return {
    id = 'SimpleJinx';
    name = 'Simple Jinx';
    type = "Champion";
    load = function()
     	return player.charName == "Jinx"
    end;
}