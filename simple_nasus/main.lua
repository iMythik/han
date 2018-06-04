local orb = module.internal("orb");
local evade = module.internal("evade");
local pred = module.internal("pred");
local ts = module.internal('TS');

-------------------
-- Menu creation --
-------------------

local menu = menu("simplenasus", "Simple Nasus");
menu:boolean("r", "Use ult in combo", true)

ts.load_to_menu();

-------------------------------
-- Target selector functions --
-------------------------------

-- Used by target selector, without pred

local function select_target(res, obj, dist)
	if dist > 1000 then return end
	
	res.obj = obj
	return true
end

-- Get target selector result

local function get_target(func)
	return ts.get_result(func).obj
end

---------------------
-- Combo functions --
---------------------

local q_dmg = {30, 50, 70, 90, 110};
local function siphon_dmg()
	if not player.buff["nasusqstacks"] then return 0 end
	local base = q_dmg[player:spellSlot(0).level];
	local stack = player.buff["nasusqstacks"].stacks2;
	return player.baseAttackDamage + player.flatPhysicalDamageMod + base + stack
end


-- Cast siphon, checks if player can attack

local function siphon()
	if not orb.combat.is_active() then return end
	if player:spellSlot(0).state ~= 0 then return end

	if orb.combat.target then
		player:castSpell("self", 0)
		orb.core.reset()
		orb.combat.set_invoke_after_attack(false)
	end
end

-- Use wither, called when target steps out of aa range

local function wither()
	if not orb.combat.is_active() then return end

	local target = get_target(select_target);
	if not target then return end

	if player:spellSlot(1).state ~= 0 then return end
	if player.pos:dist(target.pos) > 600 then return end

	player:castSpell("obj", 1, target)
end

-- Cast spirit fire

local function fire(unit)
	if player:spellSlot(2).state ~= 0 then return end
	if player.pos:dist(unit.pos) > 500 then return end

	player:castSpell("pos", 2, unit.pos)
end

-- Cast ult

local function fury(unit)
	if not menu.r:get() then return end
	if player:spellSlot(3).state ~= 0 then return end
	if player.pos:dist(unit.pos) > player.attackRange then return end

	player:castSpell("self", 3)
end

-- Combo function to call each cast

local function combo()
	if not orb.combat.is_active() then return end

	local target = get_target(select_target);

	if not target then return end

	fire(target);
	fury(target);
end

-- Last hit minions with Q, kinda messy looking I know.. needs to be worked on

local function last_hit()
	if orb.menu.lane_clear.key:get() or orb.menu.last_hit.key:get() then
		for i = 0, objManager.minions.size[TEAM_ENEMY] - 1 do
			local minion = objManager.minions[TEAM_ENEMY][i]
    		if minion and not minion.isDead and minion.pos:dist(player.pos) <= player.attackRange and orb.core.can_attack() then
    			if siphon_dmg() >= orb.farm.predict_hp(minion, 0.25, true) then
    				player:castSpell("self", 0);
    				player:attack(minion);
    			end
    		end
    	end
    end
end

-----------
-- Hooks --
-----------

-- Called pre tick

local function ontick()
	combo();
	last_hit();
end

orb.combat.register_f_pre_tick(ontick)
orb.combat.register_f_after_attack(siphon)
orb.combat.register_f_out_of_range(wither)