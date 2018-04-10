local orb = module.internal("orb");
local evade = module.internal("evade");
local pred = module.internal("pred");
local ts = module.internal('TS');

local minigun = false; -- is minigun active?
local left_side = vec3(396,182,462); -- Left side nexus
local right_side = vec3(14340,172,14384); -- Right side nexus

-- Set player team side --
local side = right_side;
if player.team == 200 then
	side = left_side;
end

-------------------
-- Menu creation --
-------------------

local menu = menu("simplejinx", "Simple Jinx");
menu:boolean("baseult", "Base ult", true);

ts.load_to_menu();

----------------
-- Spell data --
----------------

local spells = {};

spells.w = { 
	delay = 0.6; 
	width = 55;
	speed = 3200; 
	boundingRadiusMod = 1; 
	collision = { hero = true, minion = true }; 
	range = 1450;
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

local function get_target()
	return ts.get_result(select_target).obj
end

--------------
-- Base ult --
--------------

local recalls = {} -- Store table for tracking recalls

recalls.timers =  { -- Recall durations (thanks ryan!)
    recall = 8.0;
    odinrecall = 4.5;
   	odinrecallimproved = 4.0;
    recallimproved = 7.0;
    superrecall = 4.0;
}

-- Calculate total R damage, with every factor included (besides armor and shit)

local r_scale = {250,350,450};
local r_pct_scale = {0.25, 0.30, 0.35}
local function r_damage(unit)
	local dmg = r_scale[player:spellSlot(3).level] or 0;
	local pct_dmg = r_pct_scale[player:spellSlot(3).level] or 0;
	local mod = player.flatPhysicalDamageMod + (player.flatPhysicalDamageMod * 0.50);
	local missing_hp = unit.maxHealth - unit.health;
	local hp_mod = missing_hp * pct_dmg;
	return dmg + mod + hp_mod;
end

-- Calculate in seconds when rocket will reach nexus (fuck this was annoying) 

local function calc_hit_time()
    local dist = player.pos:dist(side)
    local speed = (dist > 1350 and (1500*1700+((dist-1350)*2200))/dist or 1700)
    return (dist / speed) + 0.7 + network.latency
end

-- Recall tracker, I would have used spell callback however I don't think 
-- it would have worked when player is not visible, I decided to just loop through
-- and store, if you think you'd know a better way let me know but this works pretty well

local function track_recall()
	if not menu.baseult:get() then return end
	for i = 0, objManager.enemies_n - 1 do
    	local nerd = objManager.enemies[i]
    	if not nerd then return end

    	if not recalls[nerd.networkID] then 
    		recalls[nerd.networkID] = {}
    	end

    	local data = recalls[nerd.networkID];

    	if nerd.isRecalling then 
    		
    		local recall_time = recalls.timers[nerd.recallName];
    		if not recall_time then return end

    		if data.recall then
    			data.time = recall_time - (os.clock() - data.start);
    			return
    		end

			data.recall = true;
			data.hp = nerd.health;
			data.time = recall_time;
			data.start = os.clock();
   		else
   			if data and data.recall then
   				data.recall = false;
   			end
   		end
   	end
end

-- Base ult, didn't really want to loop through players again as this causes fps drops
-- But it was nessicary with the way that the recall tracker works.

local function base_ult()
	if not menu.baseult:get() then return end
	if player:spellSlot(3).state ~= 0 then return end
	
	for i = 0, objManager.enemies_n - 1 do
    	local nerd = objManager.enemies[i]
    	local data = recalls[nerd.networkID];

    	local path = mathf.closest_vec_line(nerd.pos, player.pos, side)
        if path and path:dist(nerd.pos) <= (120 + nerd.boundingRadius) then return end

    	if data.recall and data.time <= calc_hit_time() then
    		if r_damage(nerd) < data.hp then return end
    		if data.time > calc_hit_time() + 0.6 then return end
    		player:castSpell("pos", 3, side); 
    		data.recall = false;
    	end
    end
end

---------------------
-- Combo functions --
---------------------

-- Minigun status

local function minigun()
	if player.buff["jinxqicon"] then
		return true;
	end
	return false;
end


-- Possible E spots! (took forever to map out lol)

local spots = {
	{9704,56,3262},{8214,52,3264},{8812,54,4266},{6882,49,4254},{6008,50,4146},{6142,51,3376},{6094,53,2200},{7532,52,2388},{10000,50,2488},{7484,53,6026},{4822,52,5974},{4646,52,6878},{3896,52,7280},{2604,58,6648},{2352,52,9144},{3518,52,8486},{5598,52,7562},{9214,53,7338},{10888,53,7606},{11600,53,8002},{10124,55,8268},{8276,51,10218},{8760,51,10638},{8658,54,11536},{8722,57,12496},{6626,55,11510},{6038,56,10426},{6582,49,4722},{11204,-13,5592},{11878,53,5146},{12528,53,5710},{12204,52,6622},{12228,53,8180},{11900,52,7166},{4884,57,12428},{5224,57,11574},{6818,55,13020},{7208,53,8956},{3568,33,9234},{3980,-15,11392},{6208,-68,9318},{8610,-50,5556},{9944,0,6324},{4820,4,8526}
};

-- Counts how many enemies are in range of the enemy, used for rockets.

local function count_nerds(unit, range)
	local nerds = 0;
	for i = 0, objManager.enemies_n - 1 do
    	local nerd = objManager.enemies[i]
    	if not nerd or nerd.isDead then continue end 
    	if nerd.pos:dist(unit.pos) <= range then
    		nerds = nerds + 1;
    	end
    end
    return nerds;
end


-- Switch back to minigun if they are in comfortable range

local function fishbones(unit)
	local nerds = count_nerds(unit, 100);
	if not minigun() then
	 	if player.pos:dist(unit.pos) <= player.attackRange and nerds == 1 then
			player:castSpell("self", 0)
		end
	else
		if nerds > 1 then
			player:castSpell("self", 0)
		end
	end
end

-- Cast Q when target steps out of aa range, and can hit with enhanced Q range

local function out_of_aa()
	if not orb.combat.is_active() then return end

	local target = get_target();
	if not target then return end

    if minigun() and player.pos:dist(target.pos) > player.attackRange then
    	player:castSpell("self", 0)
    end
end

-- Cast W with prediction (zap zap)

local function zap(unit)
	if player:spellSlot(1).state ~= 0 then return end
	if unit.pos:dist(player.pos) > spells.w.range then return end

	local wpred = pred.linear.get_prediction(spells.w, unit)
	if not wpred then return end
		
	if not pred.collision.get_prediction(spells.w, wpred, unit) then
		player:castSpell("pos", 1, vec3(wpred.endPos.x, game.mousePos.y, wpred.endPos.y))
	end
end

-- Cast chompers, only used when a stun or a slow is casted on target

local buff_time = nil; -- Store time of buff update on target
local buff_target = nil; -- Store buff update target
local function chompers()
	if player:spellSlot(2).state ~= 0 then return end
	if not buff_time or not buff_target then return end
 	if buff_target.isDead then buff_target = nil return end
 	if player.pos:dist(buff_target.pos) > 890 then buff_target = nil return end

	if os.clock() + 0.5 >= buff_time then
		player:castSpell("pos", 2, buff_target.pos);
		buff_target = nil;
	end
end


-- Cast chompers, with hand picked spots around the map

local function e_spot(unit)
	for i = 1, #spots do
		local spot_pos = vec3(spots[i][1], spots[i][2], spots[i][3]);
		if spot_pos:dist(unit.pos) < 200 and player.pos:dist(spot_pos) > 150 then
			local e_pos = unit.pos + unit.direction * 200
			player:castSpell("pos", 2, e_pos);
		end
	end
end


-- Combo function to call each cast

local function combo()

	chompers();

	local target = get_target();

	if not target then
		if not minigun() then
		 	player:castSpell("self", 0)
		end
	 	return
	end

	e_spot(target);

	if not orb.combat.is_active() then return end

	zap(target);
	fishbones(target);

end

-----------
-- Hooks --
-----------

-- Called pre tick

local function ontick()

	track_recall();
	base_ult();
	combo();

end

-- Update buff hook, used for chompers

local buffs = {29, 24, 11, 5}; -- Stuns and slows
local function update_buff(buff)
	if not buff.owner or not buff.type then return end
	if buff.owner.type ~= player.type or buff.owner.team ~= TEAM_ENEMY then return end

	for i = 0, #buffs do
		if buff.type == buffs[i] then
			buff_target = buff.owner;
			buff_time = os.clock();
		end
	end
end

-- Draw hook, only used to draw predicted e position

local function ondraw()
	local pos = graphics.world_to_screen(player.pos);
	if menu.baseult:get() then 
		graphics.draw_text_2D("Base-ult active!", 14, pos.x, pos.y, graphics.argb(255,255,255,255))
	end
end

cb.add(cb.draw, ondraw)
cb.add(cb.updatebuff, update_buff)
orb.combat.register_f_pre_tick(ontick)
orb.combat.register_f_out_of_range(out_of_aa)
