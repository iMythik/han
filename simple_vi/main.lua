local orb = module.internal("orb");
local evade = module.internal("evade");
local pred = module.internal("pred");
local ts = module.internal('TS');

-------------------
-- Menu creation --
-------------------

local menu = menu("simplevi", "Simple Vi");

menu:menu("e", "E Settings")
	menu.e:boolean("aa", "AA > E only", true)

menu:menu("r", "R Settings")
	menu.r:boolean("use", "Use R in combo if R + E killable", true)

ts.load_to_menu();

----------------
-- Spell data --
----------------

local spells = {};
spells.q = { 
	time = 0.62;
	pred = {
		delay = 0; 
		width = 55;
		speed = 1400;
		boundingRadiusMod = 1; 
		collision = { hero = true, minion = false };
	}
}

spells.q.speed = {
	min = 1250;
	max = 1400;
}

spells.q.range = {
	min = 250;
	max = 725;
}

-----------------------
-- Calculation funcs --
-----------------------

local q_is_active = false;
local last_q_time = 0;

-- R Damage calculation

local r_ratio = {150, 300, 450};
local function r_damage()
	local base = r_ratio[player:spellSlot(3).level] or 0;
	local mod = player.flatPhysicalDamageMod + (player.flatPhysicalDamageMod * 0.40);
	return math.ceil(base + mod);
end

-- E Damage calculation

local e_ratio = {10, 30, 50, 70, 90};
local function e_damage()
	local base = e_ratio[player:spellSlot(2).level] or 0;
	local ad = player.flatPhysicalDamageMod + player.baseAttackDamage;
	local admod = ad + (ad * 0.15);
	local apmod = player.flatMagicDamageMod * 0.7;
	return math.ceil(base + admod + apmod);
end

-- Q range calculation

local function q_range()
 	local t = os.clock() - last_q_time;
 	local range = (spells.q.range.min + t/.125 * 47.5);
 	
 	if range > spells.q.range.max then
 		return spells.q.range.max
 	end

  	return range
end

-- Q speed calculation (for prediction)

local function q_speed()
 	local t = os.clock() - last_q_time;
 	local speed = (spells.q.speed.min + t/.125 * 15);
 	
 	if speed > spells.q.speed.max then
 		return spells.q.speed.max
 	end

  	return speed
end

---------------------
-- Combo functions --
---------------------

-- Target selector function

local function select_target(res, obj, dist)
	if dist > 1000 then return end
	
	res.obj = obj
	return true
end

-- Return current target

local function get_target()
	return ts.get_result(select_target).obj
end

-- Cast Q and update speed for prediction

local function cast_q(unit)
	spells.q.pred.speed = q_speed();
	if(unit.pos:dist(player.pos) < q_range())then
		if(q_is_active) then
			local qpred = pred.linear.get_prediction(spells.q.pred, unit)
			if qpred then
				if not pred.collision.get_prediction(spells.q.pred, qpred, unit) then
					player:castSpell("release", 0, vec3(qpred.endPos.x, game.mousePos.y, qpred.endPos.y))
				end
			end
		end
	end
end

-- Cast E when in melee range (not after AA)

local function cast_e()
	if menu.e.aa:get() then return end
	if not player:spellSlot(2).state == 0 then return end

	if orb.combat.target and orb.core.can_attack() then
		player:castSpell("self", 2)
  	end
end

-- Cast R (is called when r + e is killable)

local function cast_r(unit)
	if not menu.r.use:get() then return end
	if not player:spellSlot(3).state == 0 then return end

	if e_damage() + r_damage() > unit.health then
		if orb.combat.target and orb.core.can_attack() then
			player:castSpell("obj", 3, unit)
  		end
  	end
end

-- Cast E (is called after every AA)

local function after_aa()
	if not menu.e.aa:get() then return end
	if not orb.combat.is_active() then return end
	if not player:spellSlot(2).state == 0 then return end

	if orb.combat.target then
		player:castSpell("self", 2)
  	end
end

-- Combo function to call all casts

local function combo()
	local target = get_target();
	if not target then return end

	if not orb.combat.is_active() then return end

	cast_q(target);

	cast_e();

	cast_r(target);
end

-----------
-- Hooks --
-----------

-- Draw hook

local function ondraw()
	local pos = graphics.world_to_screen(player.pos)
	graphics.draw_circle(player.pos, q_range(), 2, graphics.argb(255, 192, 57, 43), 70)
end

-- Tick hook

local function ontick()
	combo();
end

-- Buff hook (only used to toggle q boolean & get last q time)

local function onbuff(buff)
	if (buff.name == "ViQLaunch") then
		q_is_active = true;
		last_q_time = os.clock();
	end
	if buff.name == "ViQDash" then
		q_is_active = false
	end
end

cb.add(cb.draw, ondraw)
cb.add(cb.updatebuff, onbuff)

orb.combat.register_f_pre_tick(ontick)
orb.combat.register_f_after_attack(after_aa)