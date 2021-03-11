/**
 * vim: set ts=4 :
 * =============================================================================
 * DMR Rock The Vote
 * Let's players rtv off the current map but does not call a map vote.
 * Mostly stolen from the stock rockthevote plugin with the map vote logic ripped out
 *
 * Copyright 2021 CrimsonTautology
 *
 * =============================================================================
 * SourceMod Rock The Vote Plugin
 * Creates a map vote when the required number of players have requested one.
 *
 * SourceMod (C)2004-2008 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 *
 */

#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.10.0"
#define PLUGIN_NAME "Dynamic Map Rotations: Rock The Vote"

public Plugin myinfo =
{
    name = PLUGIN_NAME,
    author = "CrimsonTautology",
    description = "Allows players to change the map",
    version = PLUGIN_VERSION,
    url = "https://github.com/CrimsonTautology/sm-dynamic-map-rotations-plus"
};

ConVar g_Cvar_Needed;
ConVar g_Cvar_MinPlayers;
ConVar g_Cvar_InitialDelay;

bool g_RTVAllowed = false;  // True if RTV is available to players. Used to delay rtv votes.
int g_Voters = 0;           // Total voters connected. Doesn't include fake clients.
int g_Votes = 0;            // Total number of "say rtv" votes
int g_VotesNeeded = 0;      // Necessary votes before map vote begins. (voters * percent_needed)
bool g_Voted[MAXPLAYERS+1] = {false, ...};

bool g_InChange = false;

public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    LoadTranslations("rockthevote.phrases");

    g_Cvar_Needed = CreateConVar("sm_rtv_needed", "0.60", "Percentage of players needed to rockthevote (Def 60%)", 0, true, 0.05, true, 1.0);
    g_Cvar_MinPlayers = CreateConVar("sm_rtv_minplayers", "0", "Number of players required before RTV will be enabled.", 0, true, 0.0, true, float(MAXPLAYERS));
    g_Cvar_InitialDelay = CreateConVar("sm_rtv_initialdelay", "30.0", "Time (in seconds) before first RTV can be held", 0, true, 0.00);

    RegConsoleCmd("sm_rtv", Command_RTV);

    AutoExecConfig(true, "rtv");

    OnMapEnd();

    /* Handle late load */
    for (int i=1; i<=MaxClients; i++)
    {
        if (IsClientConnected(i))
        {
            OnClientConnected(i);   
        }   
    }
}

public void OnMapEnd()
{
    g_RTVAllowed = false;
    g_Voters = 0;
    g_Votes = 0;
    g_VotesNeeded = 0;
    g_InChange = false;
}

public void OnConfigsExecuted()
{
    CreateTimer(g_Cvar_InitialDelay.FloatValue, Timer_DelayRTV, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientConnected(int client)
{
    if (!IsFakeClient(client))
    {
        g_Voters++;
        g_VotesNeeded = RoundToCeil(float(g_Voters) * g_Cvar_Needed.FloatValue);
    }
}

public void OnClientDisconnect(int client)
{   
    if (g_Voted[client])
    {
        g_Votes--;
        g_Voted[client] = false;
    }

    if (!IsFakeClient(client))
    {
        g_Voters--;
        g_VotesNeeded = RoundToCeil(float(g_Voters) * g_Cvar_Needed.FloatValue);
    }

    if (g_Votes && 
            g_Voters && 
            g_Votes >= g_VotesNeeded && 
            g_RTVAllowed ) 
    {

        StartRTV();
    }   
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
    if (!client || IsChatTrigger())
    {
        return;
    }

    if (strcmp(sArgs, "rtv", false) == 0 || strcmp(sArgs, "rockthevote", false) == 0)
    {
        ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);

        AttemptRTV(client);

        SetCmdReplySource(old);
    }
}

public Action Command_RTV(int client, int args)
{
    if (!client)
    {
        return Plugin_Handled;
    }

    AttemptRTV(client);

    return Plugin_Handled;
}

void AttemptRTV(int client)
{
    if (!g_RTVAllowed)
    {
        ReplyToCommand(client, "[SM] %t", "RTV Not Allowed");
        return;
    }

    if (GetClientCount(true) < g_Cvar_MinPlayers.IntValue)
    {
        ReplyToCommand(client, "[SM] %t", "Minimal Players Not Met");
        return;         
    }

    if (g_Voted[client])
    {
        ReplyToCommand(client, "[SM] %t", "Already Voted", g_Votes, g_VotesNeeded);
        return;
    }   

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));

    g_Votes++;
    g_Voted[client] = true;

    PrintToChatAll("[SM] %t", "RTV Requested", name, g_Votes, g_VotesNeeded);

    if (g_Votes >= g_VotesNeeded)
    {
        StartRTV();
    }   
}

public Action Timer_DelayRTV(Handle timer)
{
    g_RTVAllowed = true;
}

void StartRTV()
{
    if (g_InChange)
    {
        return; 
    }

    /* Change right now then */
    char map[PLATFORM_MAX_PATH];
    if (GetNextMap(map, sizeof(map)))
    {
        GetMapDisplayName(map, map, sizeof(map));

        PrintToChatAll("[SM] %t", "Changing Maps", map);
        CreateTimer(5.0, Timer_ChangeMap, _, TIMER_FLAG_NO_MAPCHANGE);
        g_InChange = true;

        ResetRTV();

        g_RTVAllowed = false;
    }
    return; 
}

void ResetRTV()
{
    g_Votes = 0;

    for (int i=1; i<=MAXPLAYERS; i++)
    {
        g_Voted[i] = false;
    }
}

public Action Timer_ChangeMap(Handle hTimer)
{
    g_InChange = false;

    LogMessage("RTV changing map manually");

    char map[PLATFORM_MAX_PATH];
    if (GetNextMap(map, sizeof(map)))
    {   
        ForceChangeLevel(map, "RTV after mapvote");
    }

    return Plugin_Stop;
}
