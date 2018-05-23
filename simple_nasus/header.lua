return {
    id = 'SimpleNasus';
    name = 'Simple Nasus';
    type = "Champion";
    load = function()
     	return player.charName == "Nasus"
    end;
}