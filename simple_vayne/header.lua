return {
    id = 'SimpleVayne';
    name = 'Simple Vayne';
    riot = true;
    load = function()
     	return player.charName == "Vayne"
    end;
    type = "Champion";
}