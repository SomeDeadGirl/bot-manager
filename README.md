# What does this plugin do?  
This plugin creates a drop-in drop-out system using Officerspy's MvM Defenders Bots.   

Bots have a cap on what classes they can be, which can be configured in cfg/sourcemod.  

Bots will be removed based on two criteria: when a player chooses the same class as the bot, they will be shuffled into a different class assuming all slots of the team size aren't taken; when a player chooses any class, it will kick a random bot to fill up a slot. Bots will be re-added if a player leaves the server or picks a different class as long as the players didn't take the class cap. For example, if the cap for soldier is 2 and scout is 1, and a new player joins as scout, it kicks the scout bot and waits until the player changes classes or leaves the game. If the new player picks soldier, it will kick one soldier bot, and you need another player to kick the second soldier bot out.  

Yes, you can stack with this plugin, and it should kick the bots out to make space for the server.  

If you're an admin, you can turn off the manager by typing !bots in chat. By the way, it will sort of remain "on" - it will just kick the bots and prevent them from spawning, but it will still be keeping track of everything.  

REQUIREMENTS:  
[MvM Defenders Bots](https://github.com/OfficerSpy/TF2-MvM-Defender-TFBots)
