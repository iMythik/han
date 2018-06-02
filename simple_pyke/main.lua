local orb = module.internal("orb");
local evade = module.internal("evade");
local pred = module.internal("pred");
local ts = module.internal('TS');

-------------------
-- Menu creation --
-------------------

local menu = menu("simplepyke", "Simple Pyke");

menu:menu("e", "E Settings")
	menu.e:boolean("e", "Use dash in combo", true)
	menu.e:slider("range", "Only dash if range <", 400, 100, 500, 10)
	menu.e:slider("mana", "Only dash mana above %", 20, 1, 100, 1)

ts.load_to_menu();

----------------
-- Spell data --
----------------

local spells = {};

-- Pred input for Q

spells.q = { 
	delay = 0.25; 
	width = 70;
	speed = 2000;
	boundingRadiusMod = 1; 
	collision = { hero = true, minion = true };
}


-- Pred input for R

spells.r = { 
    delay = 0.325;
    radius = 50;
    speed = 1100;
    boundingRadiusMod = 1;
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

-- Get target selector result

local function get_target(func)
	return ts.get_result(func).obj
end

--------------------
-- Calc functions --
--------------------

-- Point ray-line projection intersection calculation using vectors

local function vector_point_project(v1, v2, v)
    local cx, cy, ax, ay, bx, by = v.pos.x, (v.pos.z or v.pos.y), v1.x, (v1.z or v1.y), v2.x, (v2.z or v2.y)
    local rL = ((cx - ax) * (bx - ax) + (cy - ay) * (by - ay)) / ((bx - ax) ^ 2 + (by - ay) ^ 2)
    local pointLine = { x = ax + rL * (bx - ax), y = ay + rL * (by - ay) }
    local rS = rL < 0 and 0 or (rL > 1 and 1 or rL)
    local isOnSegment = rS == rL
    local pointSegment = isOnSegment and pointLine or { x = ax + rS * (bx - ax), y = ay + rS * (by - ay) }
    return pointSegment, pointLine, isOnSegment
end

-- Q range calculation

local last_q_time = 0; -- last q time store
local function q_range()
 	local t = os.clock() - last_q_time;
 	local range = 400;

 	if t > 0.5 then
 		range = range + (t/.1 * 62);
 	end
 	
 	if range > 1050 then
 		return 1050
 	end

  	return range
end

-- Calculate R damage

local scale = {190, 240, 290, 340, 390, 440, 475, 510, 545, 580, 615, 635, 655};
local function r_damage()
	if player.levelRef < 6 then return 0 end
	local dmg = scale[player.levelRef - 5];
	local bonus = player.flatPhysicalDamageMod;
	return (dmg + (bonus * 0.6));
end

-- Get current mana in percentage

local function mana_pct()
	return player.mana / player.maxMana * 100
end

---------------------
-- Combo functions --
---------------------

-- Q Cast, with dynamic range calculation, with collision for short and long

local function spear(unit)
	if player:spellSlot(0).state ~= 0 then return end
	if (player:spellSlot(2).state == 0 and unit.pos:dist(player.pos) < menu.e.range:get()) and not player.buff['pykeq'] and menu.e.e:get() then return end
	if unit.pos:dist(player.pos) > q_range() then return end

	local qpred = pred.linear.get_prediction(spells.q, unit)
	if not qpred then return end
		
	if not pred.collision.get_prediction(spells.q, qpred, unit) or unit.pos:dist(player.pos) <= 400 then
		if player.buff["pykeq"] then
			orb.core.set_pause_attack(0.1);
			if unit.pos:dist(player.pos) + 150 < q_range() or (unit.pos:dist(player.pos) < 400 and q_range() <= 400) then
				player:castSpell("release", 0, vec3(qpred.endPos.x, game.mousePos.y, qpred.endPos.y))
			end
		else
			player:castSpell("pos", 0, player.pos)
		end
	end
end

-- Dash, with configurable range and mana

local function dash(unit)
	if not menu.e.e:get() then return end
	if player:spellSlot(2).state ~= 0 then return end
	if player.buff["pykeq"] then return end
	if unit.pos:dist(player.pos) > menu.e.range:get() then return end
	if mana_pct() < menu.e.mana:get() then return end

	player:castSpell("pos", 2, unit.pos)
end

-- Execute R, with X intersection calculation, and draw storage

local ex_data = {};
local function execute(unit)
	if player:spellSlot(3).state == 32 then return end
	if player.pos:dist(unit.pos) > 700 then return end
	if unit.isDead or not unit.isVisible and unit.isTargetable then return end
	if unit.buff and unit.buff[17] then return end

	local rpred = pred.circular.get_prediction(spells.r, unit)
	if not rpred then return end

	local pred_pos = vec3(rpred.endPos.x, unit.pos.y, rpred.endPos.y);
	if pred_pos:dist(player.pos) > 700 then return end

	local x1 = pred_pos + vec3(200,0,200);
	local x2 = pred_pos + vec3(-200,0,-200);
	local x3 = pred_pos + vec3(200,0,-200);
	local x4 = pred_pos + vec3(-200,0,200);

	ex_data[unit.networkID].draw = {x1, x2, x3, x4};

	local ps1, pl1, line1 = vector_point_project(x1, x2, unit);
	local ps2, pl2, line2 = vector_point_project(x3, x4, unit);
	local newpos = vec2(pred_pos.x, pred_pos.z);

	if (line1 and newpos:dist(ps1) < 50 + unit.boundingRadius) or (line2 and newpos:dist(ps2) < 50 + unit.boundingRadius) then
		player:castSpell("pos", 3, pred_pos)
	end
end

-- Combo function to call each cast

local function combo()
	local target = get_target(select_target);

	if not target then return end
	if not orb.combat.is_active() then return end

	spear(target);
	dash(target);
end

-----------
-- Hooks --
-----------

-- Called pre tick
-- With loop for kill stealing

local function ontick()

	for i = 0, objManager.enemies_n - 1 do
    	local nerd = objManager.enemies[i]
    	if not nerd then return end
    	if not ex_data[nerd.networkID] then ex_data[nerd.networkID] = {} end
    	ex_data[nerd.networkID].kill = false;
    	if r_damage() >= nerd.health and not nerd.isDead and nerd.isVisible then
    		ex_data[nerd.networkID].kill = true;
    		execute(nerd);
    	end
    end

	combo();
end

-- Draw hook, used for drawing X and dynamic Q range

local function ondraw()

	for i = 0, objManager.enemies_n - 1 do
    	local nerd = objManager.enemies[i]
    	if not nerd then return end

    	local data = ex_data[nerd.networkID];
    	if not data then return end

    	if data.kill and data.draw and nerd.isOnScreen then
			graphics.draw_line(data.draw[1], data.draw[2], 50, graphics.argb(100, 192, 57, 43))
			graphics.draw_line(data.draw[3], data.draw[4], 50, graphics.argb(100, 192, 57, 43))
		end
	end

	graphics.draw_circle(player.pos, q_range(), 2, graphics.argb(255, 192, 57, 43), 70)
end

-- Buff hook, used for last q time storage

local function onbuff(buff)
	if buff.name == "PykeQ" then
		last_q_time = os.clock();
	end
end

cb.add(cb.updatebuff, onbuff)
cb.add(cb.draw, ondraw)
orb.combat.register_f_pre_tick(ontick)