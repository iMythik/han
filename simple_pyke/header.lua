return {
    id = 'SimplePyke';
    name = 'Simple Pyke';
    type = "Champion";
    load = function()
     	return player.charName == "Pyke"
    end;
}