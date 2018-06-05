local orb = module.internal("orb");
local evade = module.internal("evade");
local pred = module.internal("pred");
local ts = module.internal('TS');

-------------------
-- Menu creation --
-------------------

local menu = menu("simplevayne", "Simple Vayne");

menu:menu("q", "Q Settings");
	menu.q:boolean("stacks", "Only roll at two stacks", true);
	menu.q:boolean("range", "Roll to get in aa range", true)

menu:menu("e", "E Settings");
	menu.e:keybind("aa", "Condemn on next AA", nil, "T")
	menu.e:boolean("gapclose", "Prevent enemy gapclosing", true)
	menu.e:boolean("interrupt", "Interrupt dangerous spells", true)
	menu.e:boolean("auto", "Automatically condemn when possible", true)
	menu.e:slider('range', "Max range", 350, 0, 500, 5);
	menu.e:slider('accuracy', "Accuracy checks", 5, 1, 50, 1);

menu:keybind("poke", "Use AA>Q>AA>E Combo", nil, "G")

ts.load_to_menu();

----------------
-- Spell data --
----------------

local spells = {};

-- q data for pred input

spells.q = {
	delay = 0.25;
	radius = player.attackRange;
	speed = math.huge;
	dashRadius = 300;
	boundingRadiusModSource = 1;
    boundingRadiusModTarget = 1;
}

-- e data for pred input

spells.e = { 
	delay = 0.25; 
	radius = player.attackRange;
	speed = 2200; 
	dashRadius = 0;
	boundingRadiusModSource = 1;
    boundingRadiusModTarget = 1;
}

--------------------
-- Auto interrupt --
--------------------

spells.interrupt = {}

spells.interrupt.names = { -- names of dangerous spells
	"glacialstorm";
	"caitlynaceinthehole";
	"ezrealtrueshotbarrage";
	"drain";
	"crowstorm";
	"gragasw";
	"reapthewhirlwind";
	"karthusfallenone";
	"katarinar";
	"lucianr";
	"luxmalicecannon";
	"malzaharr";
	"meditate";
	"missfortunebullettime";
	"absolutezero";
	"pantheonrjump";
	"shenr";
	"gate";
	"varusq";
	"warwickr";
	"xerathlocusofpower2";
}

spells.interrupt.times = {6, 1, 1, 5, 1.5, 0.75, 3, 3, 2.5, 2, 0.5, 2.5, 4, 3, 3, 2, 3, 1.5, 4, 1.5, 3}; -- channel times of dangerous spells

-- On spell hook, used for interrupting

local interrupt_data = {};
local function on_spell(spell)
	if not menu.e.interrupt:get() then return end
	if not spell or not spell.name or not spell.owner then return end
	if spell.owner.isDead then return end
	if spell.owner.team == player.team then return end
	if player.pos:dist(spell.owner.pos) > player.attackRange + (player.boundingRadius + spell.owner.boundingRadius) then return end	

	for i = 0, #spells.interrupt.names do
		if (spells.interrupt.names[i] == string.lower(spell.name)) then
			interrupt_data.start = os.clock();
			interrupt_data.channel = spells.interrupt.times[i];
			interrupt_data.owner = spell.owner;
		end
	end
end

-- Interrupt stored dangerous spells w/ delay

local function interrupt()
	if not menu.e.interrupt:get() then return end
	if not interrupt_data.owner then return end
	if player.pos:dist(interrupt_data.owner.pos) > player.attackRange + (player.boundingRadius + interrupt_data.owner.boundingRadius) then return end
	
	if os.clock() - interrupt_data.channel >= interrupt_data.start then
		interrupt_data.owner = false;
		return
	end

	if os.clock() - 0.35 >= interrupt_data.start then
		player:castSpell("obj", 2, interrupt_data.owner);
		interrupt_data.owner = false;
	end
end

-------------------------------
-- Target selector functions --
-------------------------------

-- Used by target selector, without pred

local function select_target(res, obj, dist)
	if dist > 1000 then return end
	
	res.obj = obj
	return true
end

-- Used by target selector, with q data pred

local function q_pred(res, obj, dist)
	if dist > 1000 then return end
	if pred.present.get_prediction(spells.q, obj) then
      	res.obj = obj
      	return true
    end
end

-- Used by target selector, with e data pred

local function e_pred(res, obj, dist)
	if dist > 1000 then return end
	if pred.present.get_prediction(spells.e, obj) then
      	res.obj = obj
      	return true
    end
end

-- Get target selector result

local function get_target()
	return ts.get_result(select_target).obj
end

---------------------
-- Combo functions --
---------------------

local e_pos = nil; -- E position store, gets updated once condemn is called
local e_target = nil; -- E target store, used to check if player is still visible
local last_e = os.clock(); -- Last E time store, updated every time E is casted

-- Return W stacks

local function get_stacks(unit)
	local stacks = 0;
	if unit.buff["vaynesilvereddebuff"] then
		stacks = unit.buff["vaynesilvereddebuff"].stacks
	end
	return stacks;
end

-- Condemn cast and logic

local function condemn(unit)
	if player:spellSlot(2).state ~= 0 then return end

	local obj = ts.get_result(e_pred).obj;
	local checks = menu.e.accuracy:get();
	local dist_check = menu.e.range:get() / checks;
	local range = player.attackRange + (player.boundingRadius + unit.boundingRadius)

	if not obj then return end

	e_target = obj
	local p = pred.present.get_source_pos(obj)
	local unitPos = vec3(p.x, obj.y, p.y);
	
	if player.pos:dist(unitPos) <= range then
		for k = 1, 5, 1 do
			e_pos = unitPos + (dist_check*k) * (unitPos - player.pos):norm()
			last_e = os.clock();
			if navmesh.isWall(e_pos) then
				player:castSpell("obj", 2, unit)
			end
		end
	else
		e_pos = nil
	end
end

-- Condemn on next AA toggle

local function condemn_next_aa(unit)
	if not menu.e.aa:get() then return end 
	if player:spellSlot(2).state ~= 0 then return end

	if orb.combat.target and orb.core.can_attack() then
		player:castSpell("obj", 2, unit)
  	end
end

-- Condemn on enemy gapclose

local function gapclose()
	if not menu.e.gapclose:get() then return end
	if player:spellSlot(2).state ~= 0 then return end

	local obj = ts.get_result(e_pred).obj;
	if not obj or not obj.path.isActive or not obj.path.isDashing then return end

	local range = player.attackRange + (player.boundingRadius + obj.boundingRadius)
	if player.pos:dist(obj.pos) > range then return end
	
	local pred_pos = pred.core.lerp(obj.path, network.latency + spells.e.delay, obj.path.dashSpeed)
	if not pred_pos then return end

	if pred_pos:dist(player.pos2D) <= range then
		player:castSpell("obj", 2, obj)
	end
end

-- Roll cast with range & stack check

local function roll()
	local target = get_target();
	if not target then return end

	local range = player.attackRange + (player.boundingRadius + target.boundingRadius)

	if orb.combat.target then
			
		if menu.poke:get() and get_stacks(target) == 1 and player:spellSlot(0).state ~= 0 then
			if player:spellSlot(2).state ~= 0 then return end
			player:castSpell("obj", 2, target)
		end

		if player:spellSlot(0).state ~= 0 then return end

		if player.pos:dist(target.pos) < range then
			if menu.q.stacks:get() and (get_stacks(target) ~= 2 and not menu.poke:get()) then return end
			if menu.poke:get() and get_stacks(target) ~= 1 then return end
			player:castSpell("pos", 0, game.mousePos)
			orb.core.reset()
			orb.combat.set_invoke_after_attack(false)
		end
	end
end

-- Roll cast when target steps out of aa range

local function out_of_aa()
	if not orb.combat.is_active() then return end
	if not menu.q.range:get() then return end
	if menu.poke:get() then return end

	local obj = ts.get_result(q_pred).obj
    if obj then
    	local range = 300 + player.attackRange + (player.boundingRadius + obj.boundingRadius)
		if obj.pos:dist(player.pos) <= range then
			local p = pred.present.get_source_pos(obj)
			local dashpos = game.mousePos; 
			if evade.core.is_action_safe(dashpos, math.huge, 0.25) then
				player:castSpell("pos", 0, dashpos)
			end
		end
	end
end

-- Combo function to call each cast

local function combo()
	local target = get_target();
	if not target then return end

	if not menu.e.auto:get() and not orb.combat.is_active() then return end

	condemn_next_aa(target);
	condemn(target);
end

-----------
-- Hooks --
-----------

-- Called pre tick

local function ontick()
	interrupt();
	gapclose();
	combo();
end

-- Draw hook, only used to draw predicted e position

local function ondraw()

	if player.isOnScreen then
		local pos = graphics.world_to_screen(player.pos);
		if menu.e.aa:get() then
			graphics.draw_text_2D("Condemn on next AA", 14, pos.x, pos.y, graphics.argb(255,255,255,255))
		elseif menu.poke:get() then
			graphics.draw_text_2D("Use AA>Q>AA>E Combo", 14, pos.x, pos.y, graphics.argb(255,255,255,255))
		end
	end

	if e_pos and last_e > os.clock() - 3 and player.isOnScreen then
		if e_target and not e_target.isOnScreen then return end
		graphics.draw_circle(e_pos, 30, 5, graphics.argb(255, 192, 57, 43), 70)
	end
end

-- Cast spell hook, for toggling poke combo off

local function cast_spell(slot, vec3, vec3, networkID)
	if slot == 2 then
		if menu.poke:get() then
			menu.poke:set("toggleValue", false)
		end

		if menu.e.aa:get() then
			menu.e.aa:set("toggleValue", false)
		end
	end
end

cb.add(cb.draw, ondraw)
cb.add(cb.spell, on_spell)
cb.add(cb.castspell, cast_spell)

orb.combat.register_f_pre_tick(ontick)
orb.combat.register_f_after_attack(roll)
orb.combat.register_f_out_of_range(out_of_aa)