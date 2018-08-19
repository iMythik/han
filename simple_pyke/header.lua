return {
    id = 'SimplePyke';
    name = 'Simple Pyke';
    riot = true;
    type = "Champion";
    load = function()
     	return player.charName == "Pyke"
    end;
}