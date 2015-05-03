/**
 * vim: set ts=4 :
 * =============================================================================
 * DMR Plus
 * Updated version of FLOOR_MASTER's Dynamic Map Rotations plugin
 * Dynamically alters the map rotation based on server conditions.
 *
 * Copyright 2015 CrimsonTautology
 * =============================================================================
 *
 */

#pragma semicolon 1

#include <sourcemod>

#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_NAME "Dynamic Map Rotations Plus"

public Plugin:myinfo =
{
    name = PLUGIN_NAME,
    author = "CrimsonTautology",
    description = "Dynamically alters the map rotation based on server conditions.",
    version = PLUGIN_VERSION,
    url = "https://github.com/CrimsonTautology/sm_dynamic_map_rotations_plus"
};

#define MAX_KEY_LENGTH	    32
#define MAX_VAL_LENGTH	    32

new Handle:g_Cvar_File = INVALID_HANDLE;
new Handle:g_Cvar_GroupsFile = INVALID_HANDLE;
new Handle:g_Cvar_NodeKey = INVALID_HANDLE;
new Handle:g_Cvar_ForceNextmap = INVALID_HANDLE;
new Handle:g_Cvar_Nextmap = INVALID_HANDLE;

new Handle:g_Rotation = INVALID_HANDLE;
new Handle:g_MapGroups = INVALID_HANDLE;

new String:g_CachedNextNodeKey[PLATFORM_MAX_PATH];
new Handle:g_CachedRandomMapTrie = INVALID_HANDLE;
new Handle:g_CachedMapHistoryTrie = INVALID_HANDLE;

public OnPluginStart()
{
    CreateConVar("dmr_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);

    g_Cvar_File = CreateConVar(
            "dmr_file",
            "dmr.txt",
            "Location of the rotation keyvalues file",
            FCVAR_PLUGIN);

    g_Cvar_GroupsFile = CreateConVar(
            "dmr_groups_file",
            "dmr_groups.txt",
            "Location of the map groups keyvalues file",
            FCVAR_PLUGIN);

    g_Cvar_NodeKey = CreateConVar(
            "dmr_node_key",
            "",
            "The key used to base nextmap decisions on",
            FCVAR_PLUGIN);

    g_Cvar_ForceNextmap = CreateConVar(
            "dmr_force_nextmap",
            "",
            "Override the nextmap",
            FCVAR_PLUGIN);

    g_Cvar_Nextmap = CreateConVar(
            "sm_nextmap",
            "",
            "The current nextmap",
            FCVAR_PLUGIN);


    RegConsoleCmd("sm_dmr", Command_DMR, "TODO");
    RegConsoleCmd("sm_dmr2", Command_DMR2, "TODO");

}

public OnMapStart()
{
    decl String:file[PLATFORM_MAX_PATH], String:groups_file[PLATFORM_MAX_PATH], String:node_key[PLATFORM_MAX_PATH];
    GetConVarString(g_Cvar_File, file, sizeof(file));
    GetConVarString(g_Cvar_GroupsFile, groups_file, sizeof(groups_file));
    GetConVarString(g_Cvar_NodeKey, node_key, sizeof(node_key));

    LoadDMRFile(file, node_key, g_Rotation);
    LoadDMRGroupsFile(groups_file, g_MapGroups);

    CreateTimer(60.0, Timer_UpdateNextMap, .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

    g_CachedRandomMapTrie = CreateTrie();

    CacheMapHistory(g_CachedMapHistoryTrie);
}

public OnMapEnd()
{
    //Update the node key to the next node key used to determine the next level
    SetConVarString(g_Cvar_NodeKey, g_CachedNextNodeKey);
    //LogMessage("HIT OnMapEnd, g_CachedNextNodeKey=%s", g_CachedNextNodeKey);

    if(g_CachedRandomMapTrie != INVALID_HANDLE) CloseHandle(g_CachedRandomMapTrie);
}

LoadDMRFile(String:file[], String:node_key[], &Handle:rotation)
{
    decl String:path[PLATFORM_MAX_PATH], String:val[MAX_VAL_LENGTH];
    BuildPath(Path_SM, path, sizeof(path), file);
    if(rotation != INVALID_HANDLE) CloseHandle(rotation);

    rotation = CreateKeyValues("rotation");

    if(!FileToKeyValues(rotation, file))
    {
        LogError("Could not read map rotation file \"%s\"", file);
        SetFailState("Could not read map rotation file \"%s\"", file);
        return;
    }

    //Read the default "start" key if node_key cvar is not set or invalid
    if(strlen(node_key) == 0 || !KvJumpToKey(rotation, node_key))
    {
        KvGetString(rotation, "start", val, sizeof(val));

        if(KvJumpToKey(rotation, val))
        {
            LogMessage("Reset dmr_node_key to \"%s\"", val);
            SetConVarString(g_Cvar_NodeKey, val);
        }else{
            LogError("A valid \"start\" key was not defined in \"%s\"", file);
            SetFailState("A valid \"start\" key was not defined in \"%s\"", file);
        }
    }

    KvRewind(rotation);
}

LoadDMRGroupsFile(const String:file[], &Handle:map_groups)
{
    decl String:path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), file);

    if(map_groups != INVALID_HANDLE) CloseHandle(map_groups);

    map_groups = CreateKeyValues("map_groups");

    if(!FileToKeyValues(map_groups, file))
    {
        LogError("Could not read map groups file \"%s\"", file);
        SetFailState("Could not read map groups file \"%s\"", file);
        return;
    }

    KvRewind(map_groups);
}

//Cache the most recently played maps to compare with later
CacheMapHistory(&Handle:trie)
{
    if(trie != INVALID_HANDLE) CloseHandle(trie);

    decl String:map[PLATFORM_MAX_PATH], String:junk[1], starttime;

    for(new i=0; i < GetMapHistorySize(); i++)
    {
        GetMapHistory(i, map, sizeof(map), junk, 0, starttime);
        SetTrieValue(trie, map, 1);
    }
}

public Action:Command_DMR(client, args)
{
    //TODO
    decl String:file[PLATFORM_MAX_PATH], String:node_key[PLATFORM_MAX_PATH], String:next_node_key[PLATFORM_MAX_PATH], String:nextmap[PLATFORM_MAX_PATH];
    GetConVarString(g_Cvar_File, file, sizeof(file));
    GetConVarString(g_Cvar_NodeKey, node_key, sizeof(node_key));

    GetMapFromKey(node_key, g_Rotation, g_MapGroups, nextmap, sizeof(nextmap));
    GetNextNodeKey(node_key, g_Rotation, next_node_key, sizeof(next_node_key));
    PrintToConsole(0, "nextmap: %s\nnextmap_key: %s", nextmap, next_node_key);
    SetConVarString(g_Cvar_NodeKey, next_node_key);

    if(client)
    {
        //TODO;
    }

    return Plugin_Handled;
}

public Action:Command_DMR2(client, args)
{
    //TODO
    decl String:group[PLATFORM_MAX_PATH], String:nextmap[PLATFORM_MAX_PATH];
    GetCmdArgString(group, sizeof(group));

    GetRandomMapFromGroup(group, g_MapGroups, nextmap, sizeof(nextmap));

    PrintToConsole(0, "chose map: %s", nextmap);

    return Plugin_Handled;
}

public Action:Timer_UpdateNextMap(Handle:timer)
{
    decl String:node_key[MAX_KEY_LENGTH], String:nextmap[MAX_KEY_LENGTH], String:next_node_key[MAX_KEY_LENGTH];

    GetConVarString(g_Cvar_NodeKey, node_key, sizeof(node_key));

    GetNextNodeKey(node_key, g_Rotation, g_CachedNextNodeKey, sizeof(g_CachedNextNodeKey));
    GetMapFromKey(g_CachedNextNodeKey, g_Rotation, g_MapGroups, nextmap, sizeof(nextmap));
    //LogMessage("HIT UpdateNextMap, g_Cvar_NodeKey=%s, g_CachedNextNodeKey=%s nextmap=%s", node_key, g_CachedNextNodeKey, nextmap);

    SetNextMap(nextmap);

    return Plugin_Continue;
}

bool:GetMapFromKey(const String:node_key[], Handle:rotation, Handle:map_groups, String:map[], length)
{
    if(rotation == INVALID_HANDLE) return false;
    if(map_groups == INVALID_HANDLE) return false;

    decl String:group[PLATFORM_MAX_PATH];

    KvRewind(rotation);
    if(KvJumpToKey(rotation, node_key))
    {
        if(KvGetString(rotation, "map", map, length, "") && strlen(map) > 0)
        {
            //First check for "map" key
            //Throw error if map is not valid
            if(!IsMapValid(map))
            {
                LogError("map \"%s\" in key \"%s\" is invalid.", map, node_key);
                SetFailState("Map \"%s\" in key \"%s\" is invalid.", map, node_key);
            }

            KvRewind(rotation);
            return true;

        }else if(KvGetString(rotation, "group", group, length, "") && strlen(group) > 0)
        {
            //Then check for "group" key
            //Throw error if group is not valid
            if(!GetRandomMapFromGroup(group, map_groups, map, length))
            {
                LogError("group \"%s\" in key \"%s\" is invalid.", group, node_key);
                SetFailState("Group \"%s\" in key \"%s\" is invalid.", group, node_key);
            }


            KvRewind(rotation);
            return true;
        }

    }

    KvRewind(rotation);
    return false;
}

bool:GetGroupFromKey(const String:node_key[], Handle:rotation, String:group[], length)
{
    if(rotation == INVALID_HANDLE) return false;

    KvRewind(rotation);
    if(KvJumpToKey(rotation, node_key))
    {
        KvGetString(rotation, "group", group, length);

        KvRewind(rotation);
        return true;
    }

    KvRewind(rotation);
    return false;
}

bool:GetNextNodeKey(const String:node_key[], Handle:rotation, String:next_node_key[], length)
{
    if(rotation == INVALID_HANDLE) return false;

    KvRewind(rotation);

    if(!KvJumpToKey(rotation, node_key))
    {
        LogError("node_key \"%s\" was not found.", node_key);
        return false;
    }

    //First get the default map
    KvGetString(rotation, "default_nextmap", next_node_key, length);

    //Go through remaining subkeys, where the key name being the next group and the body being a list of custom rules
    KvRewind(rotation);
    KvJumpToKey(rotation, node_key);
    if(KvGotoFirstSubKey(rotation))
    {
        do
        {
            if(MapConditionsAreMet(rotation))
            {
                KvGetSectionName(rotation, next_node_key, length);
            }
        } while(KvGotoNextKey(rotation));
    }

    KvRewind(rotation);
    return true;
}

bool:GetRandomMapFromGroup(const String:group[], Handle:map_groups, String:map[], length)
{
    if(map_groups == INVALID_HANDLE) return false;

    //We only need to do a randomization once, see if we have a cached value
    if(GetTrieString(g_CachedRandomMapTrie, group, map, length)) return true;

    new count = 0, rand;
    KvRewind(map_groups);

    KvGetSectionName(map_groups, map, length);

    if(KvJumpToKey(map_groups, group))
    {
        KvGotoFirstSubKey(map_groups);

        //Use reservoir sampling to get random map from group
        do
        {
            count +=1;

            if(count == 1) {
                KvGetSectionName(map_groups, map, length);
            }else{
                rand = GetRandomInt(0, count - 1);

                if(rand == count - 1) {
                    KvGetSectionName(map_groups, map, length);
                }
            }

        } while(KvGotoNextKey(map_groups));

        KvRewind(map_groups);

        //Cache the selected map
        SetTrieString(g_CachedRandomMapTrie, group, map);

        return true;
    }

    KvRewind(map_groups);
    return false;
}

stock GetPlayerCount()
{
    new count = 0;

    for(new i=1; i<=MaxClients; i++)
    {
        if(!IsClientInGame(i)) continue;
        if(IsFakeClient(i)) continue;

        count++;
    }

    return count;
}

stock GetAdminCount()
{
    new count = 0;

    for(new i=1; i<=MaxClients; i++)
    {
        if(!IsClientInGame(i)) continue;
        if(IsFakeClient(i)) continue;
        if(GetUserAdmin(i) == INVALID_ADMIN_ID) continue;

        count++;
    }

    return count;
}

stock bool:MapConditionsAreMet(Handle:conditions)
{
    decl String:val[MAX_VAL_LENGTH];
    new count;

    if(KvGetDataType(conditions, "players_lte") != KvData_None)
    {
        count = KvGetNum(conditions, "players_lte");
        if(!(GetPlayerCount() <= count)) return false;
    }

    if(KvGetDataType(conditions, "players_gte") != KvData_None)
    {
        count = KvGetNum(conditions, "players_gte");
        if(!(GetPlayerCount() >= count)) return false;
    }

    if(KvGetDataType(conditions, "admins_lte") != KvData_None)
    {
        count = KvGetNum(conditions, "admins_lte");
        if(!(GetPlayerCount() <= count)) return false;
    }

    if(KvGetDataType(conditions, "admins_gte") != KvData_None)
    {
        count = KvGetNum(conditions, "admins_gte");
        if(!(GetPlayerCount() >= count)) return false;
    }

    return true;
}
