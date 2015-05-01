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
new Handle:g_Cvar_MapKey = INVALID_HANDLE;
new Handle:g_Cvar_ForceNextmap = INVALID_HANDLE;
new Handle:g_Cvar_Nextmap = INVALID_HANDLE;

new Handle:g_Rotation = INVALID_HANDLE;
new Handle:g_MapGroups = INVALID_HANDLE;

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

    g_Cvar_MapKey = CreateConVar(
            "dmr_map_key",
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
    decl String:file[PLATFORM_MAX_PATH], String:groups_file[PLATFORM_MAX_PATH], String:map_key[PLATFORM_MAX_PATH];
    GetConVarString(g_Cvar_File, file, sizeof(file));
    GetConVarString(g_Cvar_GroupsFile, groups_file, sizeof(groups_file));
    GetConVarString(g_Cvar_MapKey, map_key, sizeof(map_key));

    LoadDMRFile(file, map_key, g_Rotation);
    LoadDMRGroupsFile(groups_file, g_MapGroups);
}

LoadDMRFile(String:file[], String:map_key[], &Handle:rotation)
{
    decl String:path[PLATFORM_MAX_PATH], String:val[MAX_VAL_LENGTH];
    BuildPath(Path_SM, path, sizeof(path), file);
    if(rotation != INVALID_HANDLE) CloseHandle(rotation);

    rotation = CreateKeyValues("rotation");

    if(!FileToKeyValues(rotation, file))
    {
        LogError("[DMR+] Could not read map rotation file \"%s\"", file);
        SetFailState("Could not read map rotation file \"%s\"", file);
        return;
    }

    //Read the default "start" key if map_key cvar is not set or invalid
    if(!strlen(map_key) || !KvJumpToKey(rotation, map_key))
    {
        KvGetString(rotation, "start", val, sizeof(val));

        if(KvJumpToKey(rotation, val))
        {
            LogMessage("[DMR+] Reset dmr_map_key to \"%s\"", val);
            SetConVarString(g_Cvar_MapKey, val);
        }else{
            LogError("[DMR+] A valid \"start\" key was not defined in \"%s\"", file);
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
        LogError("[DMR+] Could not read map groups file \"%s\"", file);
        SetFailState("Could not read map groups file \"%s\"", file);
        return;
    }

    KvRewind(map_groups);
}

bool:GetMapFromKey(const String:map_key[], Handle:rotation, String:map[], length)
{
    if(rotation == INVALID_HANDLE) return false;

    KvRewind(rotation);
    if(KvJumpToKey(rotation, map_key))
    {
        KvGetString(rotation, "map", map, length);

        //Throw error if map is not valid
        if(!IsMapValid(map))
        {
            LogError("[DMR+] map \"%s\" in key \"%s\" is invalid.", map, map_key);
            SetFailState("Map \"%s\" in key \"%s\" is invalid.", map, map_key);
        }

        KvRewind(rotation);
        return true;
    }

    KvRewind(rotation);
    return false;
}

bool:GetNextMapKey(const String:map_key[], Handle:rotation, String:next_map_key[], length)
{
    if(rotation == INVALID_HANDLE) return false;

    KvRewind(rotation);

    if(KvJumpToKey(rotation, map_key))
    {
        KvGetString(rotation, "default_nextmap", next_map_key, length);

        KvRewind(rotation);
        return true;
    }

    KvRewind(rotation);
    LogError("[DMR+] map_key \"%s\" was not found.", map_key);
    return false;
}

bool:GetRandomMapFromGroup(const String:group[], Handle:map_groups, String:map[], length)
{
    if(map_groups == INVALID_HANDLE) return false;

    new count = 0, result, rand;
    KvRewind(map_groups);

    KvGetSectionName(map_groups, map, length);
    PrintToConsole(0, "section: %s", map);//TODO

    if(KvJumpToKey(map_groups, group))
    {
        PrintToConsole(0, "group: %s", group);//TODO
        KvGotoFirstSubKey(map_groups);

        do{
            count +=1;

            //Use reservoir sampling to get random map from group
            if(count == 1)
            {
                KvGetSectionName(map_groups, map, length);
            }else{
                rand = GetRandomInt(0, count - 1);

                if(rand == count - 1)
                {
                    KvGetSectionName(map_groups, map, length);
                }
            }

            PrintToConsole(0, "map: %s", map);//TODO
        } while(KvGotoNextKey(map_groups));

        KvRewind(map_groups);
        return true;
    }

    KvRewind(map_groups);
    return false;
}

public Action:Command_DMR(client, args)
{
    //TODO
    decl String:file[PLATFORM_MAX_PATH], String:map_key[PLATFORM_MAX_PATH], String:next_map_key[PLATFORM_MAX_PATH], String:next_map[PLATFORM_MAX_PATH];
    GetConVarString(g_Cvar_File, file, sizeof(file));
    GetConVarString(g_Cvar_MapKey, map_key, sizeof(map_key));

    GetMapFromKey(map_key, g_Rotation, next_map, sizeof(next_map));
    GetNextMapKey(map_key, g_Rotation, next_map_key, sizeof(next_map_key));
    PrintToConsole(0, "next_map: %s\nnext_map_key: %s", next_map, next_map_key);
    SetConVarString(g_Cvar_MapKey, next_map_key);

    if(client)
    {
        //TODO;
    }

    return Plugin_Handled;
}

public Action:Command_DMR2(client, args)
{
    //TODO
    decl String:group[PLATFORM_MAX_PATH], String:next_map[PLATFORM_MAX_PATH];
    GetCmdArgString(group, sizeof(group));

    GetRandomMapFromGroup(group, g_MapGroups, next_map, sizeof(next_map));

    PrintToConsole(0, "chose map: %s", next_map);

    return Plugin_Handled;
}
