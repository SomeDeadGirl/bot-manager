#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

// Define the "Pool" of slots using explicit names to avoid ID confusion
enum {
    IDX_Scout = 0,
    IDX_Sniper,
    IDX_Soldier,
    IDX_Demoman,
    IDX_Medic,
    IDX_Heavy,
    IDX_Pyro,
    IDX_Spy,
    IDX_Engineer,
    IDX_Count
}

// Queue system
ArrayList g_hBotQueue;
Handle g_hSpawnTimer = null;
Handle g_hHeartbeatTimer = null; // Timer for continuous re-checks

// Global state for the manager
bool g_bManagerEnabled = true;
bool g_bHasStarted = false; // Tracks if the first player has spawned

// ConVar Handles
ConVar g_cvDebug;
ConVar g_cvTeamSizeLimit;
ConVar g_cvLimitScout;
ConVar g_cvLimitSniper;
ConVar g_cvLimitSoldier;
ConVar g_cvLimitDemoman;
ConVar g_cvLimitMedic;
ConVar g_cvLimitHeavy;
ConVar g_cvLimitPyro;
ConVar g_cvLimitSpy;
ConVar g_cvLimitEngineer;

// Enable Debug Mode (Set to false to disable console spam)
bool DEBUG_MODE = true;

public Plugin myinfo = {
    name = "Drop-in Drop-out AI",
    author = "gloom",
    description = "Bots fill empty slots when real players are absent and automatically leave when players join.",
    version = "13.0",
    url = ""
};

public void OnPluginStart() {
    g_hBotQueue = new ArrayList();
    
    // Create ConVars
    g_cvDebug = CreateConVar("sm_bot_manager_debug", "1", "Enable debug logging (1 = On, 0 = Off)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvTeamSizeLimit = CreateConVar("sm_bot_manager_team_size", "11", "Maximum team size (Human + Bot). Default: 11 (leaves 1 slot open for new players)", FCVAR_NOTIFY, true, 1.0, true, 24.0);
    g_cvLimitScout = CreateConVar("sm_bot_manager_limit_scout", "1", "Max players (Human + Bot) for Scout", FCVAR_NOTIFY);
    g_cvLimitSniper = CreateConVar("sm_bot_manager_limit_sniper", "1", "Max players (Human + Bot) for Sniper", FCVAR_NOTIFY);
    g_cvLimitSoldier = CreateConVar("sm_bot_manager_limit_soldier", "2", "Max players (Human + Bot) for Soldier", FCVAR_NOTIFY);
    g_cvLimitDemoman = CreateConVar("sm_bot_manager_limit_demoman", "2", "Max players (Human + Bot) for Demoman", FCVAR_NOTIFY);
    g_cvLimitMedic = CreateConVar("sm_bot_manager_limit_medic", "1", "Max players (Human + Bot) for Medic", FCVAR_NOTIFY);
    g_cvLimitHeavy = CreateConVar("sm_bot_manager_limit_heavy", "1", "Max players (Human + Bot) for Heavy", FCVAR_NOTIFY);
    g_cvLimitPyro = CreateConVar("sm_bot_manager_limit_pyro", "1", "Max players (Human + Bot) for Pyro", FCVAR_NOTIFY);
    g_cvLimitSpy = CreateConVar("sm_bot_manager_limit_spy", "1", "Max players (Human + Bot) for Spy", FCVAR_NOTIFY);
    g_cvLimitEngineer = CreateConVar("sm_bot_manager_limit_engineer", "1", "Max players (Human + Bot) for Engineer", FCVAR_NOTIFY);
    
    // Auto-generate config file
    AutoExecConfig(true, "plugin.dropin_drop_out");
    
    // Register Admin Commands ONLY
    RegAdminCmd("sm_bots", Command_ToggleBots, ADMFLAG_GENERIC, "Toggle the Drop-in/Drop-out bot manager");
    
    // Hook Class Change
    HookEvent("player_changeclass", Event_PlayerChangeClass, EventHookMode_Post);
    HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post); // Hook spawn event
}

public void OnConfigsExecuted() {
    // Update debug mode from CVar
    DEBUG_MODE = g_cvDebug.BoolValue;
}

public void OnMapStart() {
    g_hBotQueue.Clear();
    g_bManagerEnabled = true;
    g_bHasStarted = false; // Reset start flag on map change
    ServerCommand("tf_bot_kick all");
    
    // Start the heartbeat timer
    if (g_hHeartbeatTimer != null) delete g_hHeartbeatTimer;
    g_hHeartbeatTimer = CreateTimer(10.0, Timer_Heartbeat, _, TIMER_REPEAT);
    // NO INITIAL FILL. We wait for a player to spawn.
}

public void OnPluginEnd() {
    delete g_hBotQueue;
    delete g_hHeartbeatTimer;
}

// Console Command to toggle
public Action Command_ToggleBots(int client, int args) {
    ToggleManager(client);
    return Plugin_Handled;
}

void ToggleManager(int client) {
    g_bManagerEnabled = !g_bManagerEnabled;
    char sName[MAX_NAME_LENGTH];
    if (client > 0) GetClientName(client, sName, sizeof(sName));
    else strcopy(sName, sizeof(sName), "Console");
    
    if (g_bManagerEnabled) {
        ReplyToCommand(client, "[Server] Bots are Enabled.");
        PrintToChatAll("[Server] Enabled by %s. Waiting for player spawn...", sName);
        // If we enable manually, we don't force fill. We wait for spawn logic.
    } else {
        ReplyToCommand(client, "[Server] Bots are Disabled.");
        PrintToChatAll("[Server] Disabled by %s. Kicking all bots...", sName);
        g_hBotQueue.Clear();
        ServerCommand("tf_bot_kick all");
    }
}

// Hook player spawn to trigger the initial fill
public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    // Only trigger if the game hasn't started yet
    if (!g_bHasStarted && g_bManagerEnabled) {
        int userid = event.GetInt("userid");
        int client = GetClientOfUserId(userid);
        
        // Check if it's a valid human player on Red team
        if (IsValidPlayer(client) && GetClientTeam(client) == view_as<int>(TFTeam_Red)) {
            g_bHasStarted = true;
            if (DEBUG_MODE) PrintToServer("[Bot Manager] First player spawned! Starting bot fill...");
            // Trigger the update immediately
            UpdateTeamComposition();
        }
    }
}

// Hook changeclass
public void Event_PlayerChangeClass(Event event, const char[] name, bool dontBroadcast) {
    // If the game hasn't started, this event might fire before spawn.
    // We rely on PlayerSpawn for the initial trigger.
    // If the game HAS started, we use this to update the team composition.
    if (g_bHasStarted && g_bManagerEnabled) {
        int userid = event.GetInt("userid");
        int client = GetClientOfUserId(userid);
        if (IsValidPlayer(client) && GetClientTeam(client) == view_as<int>(TFTeam_Red)) {
            CreateTimer(0.5, Timer_Update, _, TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
    if (g_bHasStarted && g_bManagerEnabled) {
        CreateTimer(0.5, Timer_Update, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_Heartbeat(Handle timer) {
    if (g_bManagerEnabled && g_bHasStarted) {
        UpdateTeamComposition();
    }
    return Plugin_Continue;
}

public Action Timer_Update(Handle timer) {
    if (g_bHasStarted && g_bManagerEnabled) {
        UpdateTeamComposition();
    }
    return Plugin_Stop;
}

void UpdateTeamComposition() {
    // Get the current team size limit from the cvar
    int TEAM_SIZE_LIMIT = g_cvTeamSizeLimit.IntValue;
    
    // If manager is disabled, do nothing (or ensure bots are gone)
    if (!g_bManagerEnabled) {
        g_hBotQueue.Clear();
        return;
    }
    
    // CRITICAL FIX: Clear the queue every time we recalculate.
    // This prevents old spawn requests from executing after the team is full.
    g_hBotQueue.Clear();
    
    // CHECK: If there are NO human players in the server, kick all bots
    bool bHumansInServer = false;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i)) {
            bHumansInServer = true;
            break;
        }
    }
    
    if (!bHumansInServer) {
        // Clear queue and kick all bots
        g_hBotQueue.Clear();
        ServerCommand("tf_bot_kick all");
        // If everyone leaves, reset the "Started" flag so we wait for a spawn again
        if (g_bHasStarted) {
            g_bHasStarted = false;
            if (DEBUG_MODE) PrintToServer("[Bot Manager] All humans left. Resetting to 'Wait for Spawn' mode.");
        }
        return;
    }
    
    // ------------------------------------------------------------------
    // GLOBAL POINT SYSTEM
    // ------------------------------------------------------------------
    // 1. Calculate Total Points (Humans + Bots)
    int currentPoints = 0;
    int humansInClass[IDX_Count];
    int botsInClass[IDX_Count];
    
    // Initialize arrays
    for (int i = 0; i < IDX_Count; i++) {
        humansInClass[i] = 0;
        botsInClass[i] = 0;
    }
    
    // Count everyone on Red Team
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && GetClientTeam(i) == view_as<int>(TFTeam_Red)) {
            int idx = GetClassIndexFromTFClass(TF2_GetPlayerClass(i));
            if (idx != -1) {
                if (IsFakeClient(i)) {
                    botsInClass[idx]++;
                    currentPoints++;
                } else {
                    humansInClass[idx]++;
                    currentPoints++;
                }
            }
        }
    }
    
    // DEBUG OUTPUT
    if (DEBUG_MODE) {
        PrintToServer("--------------------------------------------------");
        PrintToServer("[Bot Manager] UPDATE TRIGGERED");
        PrintToServer("[Bot Manager] Total Players: %d / %d", currentPoints, TEAM_SIZE_LIMIT);
        char sClassName[32];
        for (int i = 0; i < IDX_Count; i++) {
            GetClassNameFromIndex(i, sClassName, sizeof(sClassName));
            PrintToServer("[Bot Manager] %s: %d Humans | %d Bots | Limit: %d", sClassName, humansInClass[i], botsInClass[i], GetClassLimit(i));
        }
    }
    
    // 2. HARD LIMIT CHECK
    // If we are already at or over the limit, DO NOT SPAWN ANYTHING.
    // Only kick bots to bring us down.
    if (currentPoints >= TEAM_SIZE_LIMIT) {
        if (DEBUG_MODE) PrintToServer("[Bot Manager] ACTION: Team is FULL/OVERFULL. Kicking bots...");
        
        // Calculate how many bots we have in classes where (Humans + Bots) > Limit
        int excessBots = 0;
        for (int i = 0; i < IDX_Count; i++) {
            int totalInClass = humansInClass[i] + botsInClass[i];
            int limit = GetClassLimit(i);
            
            // Check if TOTAL is greater than Limit
            if (totalInClass > limit) {
                // How many bots are excess?
                int classExcess = totalInClass - limit;
                if (classExcess > botsInClass[i]) classExcess = botsInClass[i];
                excessBots += classExcess;
                
                char sClassName[32];
                GetClassNameFromIndex(i, sClassName, sizeof(sClassName));
                if (DEBUG_MODE) PrintToServer("[Bot Manager] Excess detected in %s. Total: %d, Limit: %d. Excess Bots: %d", sClassName, totalInClass, limit, classExcess);
            }
        }
        
        if (DEBUG_MODE) PrintToServer("[Bot Manager] Total Excess Bots to kick: %d", excessBots);
        
        // Kick the excess bots
        for (int k = 0; k < excessBots; k++) {
            // Priority 1: Kick a bot from a class where (Humans + Bots) > Limit
            bool kicked = false;
            for (int i = 0; i < IDX_Count; i++) {
                int totalInClass = humansInClass[i] + botsInClass[i];
                int limit = GetClassLimit(i);
                
                if (totalInClass > limit && botsInClass[i] > 0) {
                    // Kick a bot from this class
                    if (KickBotByIndex(i)) {
                        botsInClass[i]--;
                        currentPoints--;
                        kicked = true;
                        if (DEBUG_MODE) PrintToServer("[Bot Manager] Kicked bot from class index %d", i);
                        break;
                    }
                }
            }
            
            // Priority 2: Kick any bot if the above didn't work (Safety Net)
            if (!kicked) {
                if (KickAnyBot()) {
                    currentPoints--;
                    if (DEBUG_MODE) PrintToServer("[Bot Manager] Kicked ANY bot (Fallback)");
                }
            }
        }
        
        return; // EXIT FUNCTION. We do not spawn anything if we were full.
    }
    
    // 3. SPAWNING PHASE (Only if we have room)
    if (DEBUG_MODE) PrintToServer("[Bot Manager] ACTION: Team has room. Spawning bots...");
    
    // Calculate how many bots we can add: Limit - Current
    int roomAvailable = TEAM_SIZE_LIMIT - currentPoints;
    if (DEBUG_MODE) PrintToServer("[Bot Manager] Room Available: %d", roomAvailable);
    
    if (roomAvailable > 0) {
        // SMART SPAWNING: Two passes
        // Pass 1: Fill classes with 0 Humans and 0 Bots (Empty Classes)
        // Pass 2: Fill classes that have room but are not empty (Secondary slots)
        int needed = roomAvailable;
        
        // --- PASS 1: PRIORITY - FILL EMPTY CLASSES ---
        for (int i = 0; i < IDX_Count; i++) {
            if (needed <= 0) break;
            
            int limit = GetClassLimit(i);
            int humans = humansInClass[i];
            int bots = botsInClass[i];
            int totalInClass = humans + bots;
            int availableSlots = limit - totalInClass;
            
            // Check if class is completely empty (0 Humans, 0 Bots)
            if (humans == 0 && bots == 0 && availableSlots > 0) {
                int toSpawn = availableSlots;
                if (toSpawn > needed) toSpawn = needed;
                
                if (toSpawn > 0) {
                    char sClassName[32];
                    GetClassNameFromIndex(i, sClassName, sizeof(sClassName));
                    if (DEBUG_MODE) PrintToServer("[Bot Manager] [P1] Queueing %d bots for %s (Empty Class)", toSpawn, sClassName);
                    
                    for (int k = 0; k < toSpawn; k++) {
                        g_hBotQueue.Push(i);
                    }
                    needed -= toSpawn;
                }
            }
        }
        
        // --- PASS 2: FILL REMAINING SLOTS ---
        for (int i = 0; i < IDX_Count; i++) {
            if (needed <= 0) break;
            
            int limit = GetClassLimit(i);
            int humans = humansInClass[i];
            int bots = botsInClass[i];
            int totalInClass = humans + bots;
            int availableSlots = limit - totalInClass;
            
            // If we have room for more in this class
            if (availableSlots > 0) {
                int toSpawn = availableSlots;
                if (toSpawn > needed) toSpawn = needed;
                
                if (toSpawn > 0) {
                    char sClassName[32];
                    GetClassNameFromIndex(i, sClassName, sizeof(sClassName));
                    if (DEBUG_MODE) PrintToServer("[Bot Manager] [P2] Queueing %d bots for %s (Secondary)", toSpawn, sClassName);
                    
                    for (int k = 0; k < toSpawn; k++) {
                        g_hBotQueue.Push(i);
                    }
                    needed -= toSpawn;
                }
            }
        }
    }
    
    if (g_hSpawnTimer == null && g_hBotQueue.Length > 0) {
        g_hSpawnTimer = CreateTimer(2.5, Timer_ProcessQueue, _, TIMER_REPEAT);
    }
}

// Helper to get the limit for a specific class index
int GetClassLimit(int index) {
    // Fallback defaults if CVar is invalid
    int defaultLimits[IDX_Count] = {1, 1, 2, 2, 1, 1, 1, 1, 1};
    
    switch (index) {
        case IDX_Scout: return g_cvLimitScout.IntValue;
        case IDX_Sniper: return g_cvLimitSniper.IntValue;
        case IDX_Soldier: return g_cvLimitSoldier.IntValue;
        case IDX_Demoman: return g_cvLimitDemoman.IntValue;
        case IDX_Medic: return g_cvLimitMedic.IntValue;
        case IDX_Heavy: return g_cvLimitHeavy.IntValue;
        case IDX_Pyro: return g_cvLimitPyro.IntValue;
        case IDX_Spy: return g_cvLimitSpy.IntValue;
        case IDX_Engineer: return g_cvLimitEngineer.IntValue;
        default: return defaultLimits[index];
    }
}

// Helper to map TFClassType enum to our explicit index
int GetClassIndexFromTFClass(TFClassType classType) {
    switch (classType) {
        case TFClass_Scout: return IDX_Scout;
        case TFClass_Sniper: return IDX_Sniper;
        case TFClass_Soldier: return IDX_Soldier;
        case TFClass_DemoMan: return IDX_Demoman;
        case TFClass_Medic: return IDX_Medic;
        case TFClass_Heavy: return IDX_Heavy;
        case TFClass_Pyro: return IDX_Pyro;
        case TFClass_Spy: return IDX_Spy;
        case TFClass_Engineer: return IDX_Engineer;
    }
    return -1;
}

// Helper to get class name from our explicit index
void GetClassNameFromIndex(int index, char[] buffer, int maxlen) {
    switch (index) {
        case IDX_Scout: strcopy(buffer, maxlen, "scout");
        case IDX_Sniper: strcopy(buffer, maxlen, "sniper");
        case IDX_Soldier: strcopy(buffer, maxlen, "soldier");
        case IDX_Demoman: strcopy(buffer, maxlen, "demoman");
        case IDX_Medic: strcopy(buffer, maxlen, "medic");
        case IDX_Heavy: strcopy(buffer, maxlen, "heavyweapons");
        case IDX_Pyro: strcopy(buffer, maxlen, "pyro");
        case IDX_Spy: strcopy(buffer, maxlen, "spy");
        case IDX_Engineer: strcopy(buffer, maxlen, "engineer");
        default: strcopy(buffer, maxlen, "scout");
    }
}

public Action Timer_ProcessQueue(Handle timer) {
    if (g_hBotQueue.Length == 0) {
        g_hSpawnTimer = null;
        return Plugin_Stop;
    }
    
    // If manager was disabled while queue is processing, stop
    if (!g_bManagerEnabled) {
        g_hBotQueue.Clear();
        g_hSpawnTimer = null;
        return Plugin_Stop;
    }
    
    // SAFETY CHECK: Count current team size before spawning
    int currentCount = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && GetClientTeam(i) == view_as<int>(TFTeam_Red)) {
            currentCount++;
        }
    }
    
    // Get the current team size limit from the cvar
    int TEAM_SIZE_LIMIT = g_cvTeamSizeLimit.IntValue;
    
    // If the team is full, clear the queue and stop.
    if (currentCount >= TEAM_SIZE_LIMIT) {
        if (DEBUG_MODE) PrintToServer("[Bot Manager] SPAWN CANCELLED: Team is full (%d/%d)", currentCount, TEAM_SIZE_LIMIT);
        g_hBotQueue.Clear();
        g_hSpawnTimer = null;
        return Plugin_Stop;
    }
    
    int classIndex = g_hBotQueue.Get(0);
    g_hBotQueue.Erase(0);
    SpawnBot(classIndex);
    
    return Plugin_Continue;
}

void SpawnBot(int index) {
    char className[32];
    GetClassNameFromIndex(index, className, sizeof(className));
    char command[128];
    Format(command, sizeof(command), "tf_bot_add 1 noquota TFBOT_SEX_HAVER %s Expert red", className);
    ServerCommand(command);
}

// Returns true if a bot was kicked, false otherwise
bool KickBotByIndex(int index) {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) == view_as<int>(TFTeam_Red)) {
            int idx = GetClassIndexFromTFClass(TF2_GetPlayerClass(i));
            if (idx == index) {
                KickClient(i, "Slot taken by player");
                return true;
            }
        }
    }
    return false;
}

// Returns true if a bot was kicked, false otherwise
bool KickAnyBot() {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) == view_as<int>(TFTeam_Red)) {
            KickClient(i, "Making room for players");
            return true;
        }
    }
    return false;
}

bool IsValidPlayer(int client) {
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}