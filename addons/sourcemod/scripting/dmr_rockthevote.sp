/**
 * vim: set ts=4 :
 * =============================================================================
 * DMR Rock The Vote
 * Let's players rtv off the current map but does not call a map vote.
 * Mostly stolen from the stock rockthevote plugin with the map vote logic ripped out
 *
 * Copyright 2015 CrimsonTautology
 * =============================================================================
 *
 */


#include <sourcemod>

#pragma semicolon 1

#define PLUGIN_VERSION "1.0.3"
#define PLUGIN_NAME "Dynamic Map Rotations: Rock The Vote"

public Plugin:myinfo =
{
    name = PLUGIN_NAME,
    author = "CrimsonTautology",
    description = "Allows players to change the map",
    version = PLUGIN_VERSION,
    url = "https://github.com/CrimsonTautology/sm_dynamic_map_rotations_plus"
};

new Handle:g_Cvar_Needed = INVALID_HANDLE;
new Handle:g_Cvar_MinPlayers = INVALID_HANDLE;
new Handle:g_Cvar_InitialDelay = INVALID_HANDLE;

new bool:g_CanRTV = false;		// True if RTV loaded maps and is active.
new bool:g_RTVAllowed = false;	// True if RTV is available to players. Used to delay rtv votes.
new g_Voters = 0;				// Total voters connected. Doesn't include fake clients.
new g_Votes = 0;				// Total number of "say rtv" votes
new g_VotesNeeded = 0;			// Necessary votes before map vote begins. (voters * percent_needed)
new bool:g_Voted[MAXPLAYERS+1] = {false, ...};

new bool:g_InChange = false;

public OnPluginStart()
{
    LoadTranslations("common.phrases");
    LoadTranslations("rockthevote.phrases");

    g_Cvar_Needed = CreateConVar("sm_rtv_needed", "0.60", "Percentage of players needed to rockthevote (Def 60%)", 0, true, 0.05, true, 1.0);
    g_Cvar_MinPlayers = CreateConVar("sm_rtv_minplayers", "0", "Number of players required before RTV will be enabled.", 0, true, 0.0, true, float(MAXPLAYERS));
    g_Cvar_InitialDelay = CreateConVar("sm_rtv_initialdelay", "30.0", "Time (in seconds) before first RTV can be held", 0, true, 0.00);

    RegConsoleCmd("sm_rtv", Command_RTV);

    AutoExecConfig(true, "rtv");
}

public OnMapStart()
{
    g_Voters = 0;
    g_Votes = 0;
    g_VotesNeeded = 0;
    g_InChange = false;

    /* Handle late load */
    for (new i=1; i<=MaxClients; i++)
    {
        if (IsClientConnected(i))
        {
            OnClientConnected(i);	
        }	
    }
}

public OnMapEnd()
{
    g_CanRTV = false;	
    g_RTVAllowed = false;
}

public OnConfigsExecuted()
{	
    g_CanRTV = true;
    g_RTVAllowed = false;
    CreateTimer(GetConVarFloat(g_Cvar_InitialDelay), Timer_DelayRTV, _, TIMER_FLAG_NO_MAPCHANGE);
}

public OnClientConnected(client)
{
    if(IsFakeClient(client)) return;

    g_Voted[client] = false;

    g_Voters++;
    g_VotesNeeded = RoundToFloor(float(g_Voters) * GetConVarFloat(g_Cvar_Needed));

    return;
}

public OnClientDisconnect(client)
{
    if(IsFakeClient(client)) return;

    if(g_Voted[client]) g_Votes--;

    g_Voters--;

    g_VotesNeeded = RoundToFloor(float(g_Voters) * GetConVarFloat(g_Cvar_Needed));

    if (!g_CanRTV) return;	

    if (g_Votes && 
            g_Voters && 
            g_Votes >= g_VotesNeeded && 
            g_RTVAllowed ) 
    {
        StartRTV();
    }	
}

public OnClientSayCommand_Post(client, const String:command[], const String:sArgs[])
{
    if (!g_CanRTV || !client) return;

    if (strcmp(sArgs, "rtv", false) == 0 || strcmp(sArgs, "rockthevote", false) == 0)
    {
        new ReplySource:old = SetCmdReplySource(SM_REPLY_TO_CHAT);

        AttemptRTV(client);

        SetCmdReplySource(old);
    }
}

public Action:Command_RTV(client, args)
{
    if (!g_CanRTV || !client) return Plugin_Handled;

    AttemptRTV(client);

    return Plugin_Handled;
}

AttemptRTV(client)
{
    if (!g_RTVAllowed)
    {
        ReplyToCommand(client, "[SM] %t", "RTV Not Allowed");
        return;
    }

    if (GetClientCount(true) < GetConVarInt(g_Cvar_MinPlayers))
    {
        ReplyToCommand(client, "[SM] %t", "Minimal Players Not Met");
        return;			
    }

    if (g_Voted[client])
    {
        ReplyToCommand(client, "[SM] %t", "Already Voted", g_Votes, g_VotesNeeded);
        return;
    }	

    new String:name[64];
    GetClientName(client, name, sizeof(name));

    g_Votes++;
    g_Voted[client] = true;

    PrintToChatAll("[SM] %t", "RTV Requested", name, g_Votes, g_VotesNeeded);

    if (g_Votes >= g_VotesNeeded)
    {
        StartRTV();
    }	
}

public Action:Timer_DelayRTV(Handle:timer)
{
    g_RTVAllowed = true;
}

StartRTV()
{
    if (g_InChange) return;	

    /* Change right now then */
    new String:map[65];
    if (GetNextMap(map, sizeof(map)))
    {
        PrintToChatAll("[SM] %t", "Changing Maps", map);
        CreateTimer(5.0, Timer_ChangeMap, _, TIMER_FLAG_NO_MAPCHANGE);
        g_InChange = true;

        ResetRTV();

        g_RTVAllowed = false;
    }
    return;	
}

ResetRTV()
{
    g_Votes = 0;

    for (new i=1; i<=MAXPLAYERS; i++)
    {
        g_Voted[i] = false;
    }
}

public Action:Timer_ChangeMap(Handle:hTimer)
{
    g_InChange = false;

    LogMessage("DMR RTV changing map manually");

    new String:map[65];
    if (GetNextMap(map, sizeof(map)))
    {	
        ForceChangeLevel(map, "DMR RTV");
    }

    return Plugin_Stop;
}
