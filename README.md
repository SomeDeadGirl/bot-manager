# What does this plugin do?
This plugin is to create a drop-in drop out system using Officerspy's MvM Defenders Bots.

Bots have a cap on what classes they can be. this can be configured in cfg/sourcemod.

Bots will be removed by two criterias:
1. Player chooses the same class as the bot and will be shuffled into a different class assuming all slots of the team size isnt taken.
2. player chooses any class it will kick a random bot to fill up a slot.

3. bots will be re added if a player leaves the server or picks a different class so as long the players didnt take the class cap.
3a. as an example the cap for soldier is 2 and scout is 1.
3b. if a new player joins as scout, it kicks the scout bot and waits till player changes classes/leaves the game.
3c. if the new player picks soldier, it will kick one soldier bot and you need another player to kick the second soldier bot out.

Yes you can stack with this plugin and it should kick the bots out to make space for the server.

REQUIREMENTS:
[MvM Defenders Bots](https://github.com/OfficerSpy/TF2-MvM-Defender-TFBots)
