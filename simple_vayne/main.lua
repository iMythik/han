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
	menu.e:boolean("auto", "Automatically condemn when possible", true)
	menu.e:slider('range', "Max range", 350, 0, 500, 5);
	menu.e:slider('accuracy', "Accuracy checks", 5, 1, 50, 1);

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

	local e_target = obj
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

-- Roll cast with range & stack check

local function roll()
	local target = get_target();
	if not target then return end

	if player:spellSlot(0).state ~= 0 then return end

	local range = player.attackRange + (player.boundingRadius + target.boundingRadius)

	if orb.combat.target then
		if player.pos:dist(target.pos) < range then
			if menu.q.stacks:get() and get_stacks(target) ~= 2 then return end
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

	condemn(target);
end

-----------
-- Hooks --
-----------

-- Called pre tick

local function ontick()
	combo();
end

-- Draw hook, only used to draw predicted e position

local function ondraw()
	if e_pos and last_e > os.clock() - 3 and player.isOnScreen then

		if e_target and not e_target.isOnScreen then return end
		graphics.draw_circle(e_pos, 30, 5, graphics.argb(255, 192, 57, 43), 70)

	end
end

cb.add(cb.draw, ondraw)
orb.combat.register_f_pre_tick(ontick)
orb.combat.register_f_after_attack(roll)
orb.combat.register_f_out_of_range(out_of_aa)