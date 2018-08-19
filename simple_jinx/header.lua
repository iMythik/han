return {
    id = 'SimpleJinx';
    name = 'Simple Jinx';
    riot = true;
    type = "Champion";
    load = function()
     	return player.charName == "Jinx"
    end;
}