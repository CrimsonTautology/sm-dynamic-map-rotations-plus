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

new DAYS_OF_WEEK[]= {'\0', 'm', 't', 'w', 'r', 'f', 's', 'u'};

new Handle:g_Cvar_File = INVALID_HANDLE;
new Handle:g_Cvar_GroupsFile = INVALID_HANDLE;
new Handle:g_Cvar_NodeKey = INVALID_HANDLE;
new Handle:g_Cvar_ExcludeMaps = INVALID_HANDLE;

new Handle:g_Rotation = INVALID_HANDLE;
new Handle:g_MapGroups = INVALID_HANDLE;

new bool:g_ForceNextMap = false;

new String:g_CachedNextNodeKey[PLATFORM_MAX_PATH];
new Handle:g_CachedRandomMapTrie = INVALID_HANDLE;
new Handle:g_MapHistoryArray = INVALID_HANDLE;

public OnPluginStart()
{
    LoadTranslations("common.phrases");

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

    g_Cvar_ExcludeMaps = CreateConVar(
            "dmr_exclude",
            "5",
            "Specifies how many past maps to exclude when randomly selecting a map from a group.",
            _,
            true,
            0.0);

    RegConsoleCmd("sm_nextmaps", Command_Nextmaps, "Print next maps in rotation");
    RegConsoleCmd("sm_nextnodes", Command_Nextnodes, "Print dmr nodes in rotation");

    RegAdminCmd("sm_setnextmap", Command_SetNextmap, ADMFLAG_CHANGEMAP, "Force the next map and prevent DMR from running for the duration of this map");
    RegAdminCmd("sm_unsetnextmap", Command_UnsetNextmap, ADMFLAG_CHANGEMAP, "Unset a forced next map and have DMR resume");
    RegAdminCmd("sm_nextmapnow", Command_NextmapNow, ADMFLAG_CHANGEMAP, "Force a mapchange to the determined next map right now");

    RegAdminCmd("sm_validatedmr", Command_ValidateDMR, ADMFLAG_CHANGEMAP, "Validate the DMR files");

    g_MapHistoryArray = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
    g_CachedRandomMapTrie = CreateTrie();
}

public OnMapStart()
{
    decl String:file[PLATFORM_MAX_PATH], String:groups_file[PLATFORM_MAX_PATH], String:node_key[PLATFORM_MAX_PATH], String:group[PLATFORM_MAX_PATH];
    GetConVarString(g_Cvar_File, file, sizeof(file));
    GetConVarString(g_Cvar_GroupsFile, groups_file, sizeof(groups_file));
    GetConVarString(g_Cvar_NodeKey, node_key, sizeof(node_key));

    LoadDMRFile(file, node_key, g_Rotation);
    LoadDMRGroupsFile(groups_file, g_MapGroups);

    CreateTimer(60.0, Timer_UpdateNextMap, .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

    //Remove current map group from our random map trie cache
    if(GetGroupFromKey(node_key, g_Rotation, group, sizeof(group)))
    {
        RemoveFromTrie(g_CachedRandomMapTrie, group); 
    }

    //Save this map in the map history array
    UpdateMapHistory(g_MapHistoryArray, GetConVarInt(g_Cvar_ExcludeMaps));
}

public OnConfigsExecuted()
{
    decl String:node_key[PLATFORM_MAX_PATH];
    GetConVarString(g_Cvar_NodeKey, node_key, sizeof(node_key));

    RunNodeCommands(node_key, g_Rotation);
}

public OnMapEnd()
{
    if(!ForcedNextMap())
    {
        //Update the node key to the next node key used to determine the next level
        SetConVarString(g_Cvar_NodeKey, g_CachedNextNodeKey);
    }
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

UpdateMapHistory(Handle:history, limit)
{
    decl String:map[PLATFORM_MAX_PATH];
    GetCurrentMap(map, sizeof(map));
    PushArrayString(history, map);

    if (GetArraySize(history) > limit)
    {
        RemoveFromArray(history, 0);
    }	
}

RunNodeCommands(const String:node_key[], Handle:rotation)
{
    decl String:command[MAX_VAL_LENGTH];

    KvRewind(rotation);
    if(KvJumpToKey(rotation, node_key))
    {
        if(KvExists2(rotation, "command", command, sizeof(command)))
        {
            ServerCommand(command);
        }
    }

    KvRewind(rotation);

}

//Validate that our dmr nodes and dmr map groups are valid
ValidateDMR(Handle:rotation, Handle:groups)
{
    ValidateNodeList(rotation, groups);
    ValidateMapGroups(groups);
}

//Test each node in the dmr file
ValidateNodeList(Handle:rotation, Handle:groups)
{
    decl String:val[MAX_VAL_LENGTH], String:key[MAX_KEY_LENGTH], String:section[MAX_KEY_LENGTH];
    new Handle:nodes;

    //Test that a "start" key exists in the dmr file
    if( !KvExists(rotation, "start") )
    {
        PrintToServer("[DMR] DMR File is missing a \"start\" key.");
    }

    KvRewind(rotation);
    nodes = CreateKeyValues("rotation");
    KvCopySubkeys(rotation, nodes);
    if(KvGotoFirstSubKey(rotation))
    {
        do
        {
            KvGetSectionName(rotation, section, sizeof(section));

            //Test that it has either a "map" or a "group" key
            if( !(KvExists(rotation, "map") || KvExists(rotation, "group")) )
            {
                PrintToServer("[DMR] DMR Node \"%s\" is missing either a \"map\" or \"group\" key.", section);
            }

            //Test that it does not have both a "map" and "group" key
            if( (KvExists(rotation, "map") && KvExists(rotation, "group")) )
            {
                PrintToServer("[DMR] DMR Node \"%s\" has both a \"map\" or \"group\" key.  It only needs one.", section);
            }

            //If a map; test that the map is valid
            if( KvExists2(rotation, "map", val, sizeof(val)) && !IsMapValid(val) )
            {
                PrintToServer("[DMR] DMR Node \"%s\" has an invalid map \"%s\" in the \"map\" key.", section, val);
            }

            //If a group; test that the group is valid
            KvRewind(groups);
            if( KvExists2(rotation, "group", val, sizeof(val)) && !KvJumpToKey(groups, val) )
            {
                PrintToServer("[DMR] DMR Node \"%s\" has an invalid group \"%s\" in the \"group\" key.", section, val);
            }

            //Test that a "default_nextnode" key exists in the dmr file
            if( !KvExists(rotation, "default_nextnode") )
            {
                PrintToServer("[DMR] DMR Node \"%s\" is missing a \"default_nextnode\" key");
            }

            //Test that the "default_nextnode" node is an actual node in the dmr file
            KvGetString(rotation, "default_nextnode", val, sizeof(val));
            KvRewind(nodes);
            if( !(KvJumpToKey(nodes, val)) )
            {
                PrintToServer("[DMR] The DMR Node \"%s\" in the \"default_nextnode\" key for node \"%s\" does not exist", val, section);
            }

            //For each additional node branch test that it is a valid node
            if(KvGotoFirstSubKey(rotation))
            {
                do
                {
                    KvGetSectionName(rotation, key, sizeof(key));

                    //Test that the "default_nextnode" node is an actual node in the dmr file
                    KvRewind(nodes);
                    if( !(KvJumpToKey(nodes, key)) )
                    {
                        PrintToServer("[DMR] The DMR Node \"%s\" for node \"%s\" does not exist", key, section);
                    }

                } while(KvGotoNextKey(rotation));
            }
            KvGoBack(rotation);


        }while(KvGotoNextKey(rotation));
    }
    CloseHandle(nodes);
}

//Validate the map groups file
ValidateMapGroups(Handle:groups)
{
    decl String:key[MAX_KEY_LENGTH], String:section[MAX_KEY_LENGTH];

    KvRewind(groups);
    if(KvGotoFirstSubKey(groups))
    {
        do
        {
            KvGetSectionName(groups, section, sizeof(section));

            //For each map in the group
            if(KvGotoFirstSubKey(groups))
            {
                do
                {
                    KvGetSectionName(groups, key, sizeof(key));
                    //Test that this map is valid
                    if(!IsMapValid(key))
                    {
                        PrintToServer("[DMR] The map \"%s\" in the map group \"%s\" is invalid.", key, section);
                    }

                } while(KvGotoNextKey(groups));
            }
            KvGoBack(groups);


        }while(KvGotoNextKey(groups));
    }
}

public Action:Command_Nextmaps(client, args)
{
    decl String:nextmaps[256], String:node_key[PLATFORM_MAX_PATH];
    decl String:map[PLATFORM_MAX_PATH];

    GetConVarString(g_Cvar_NodeKey, node_key, sizeof(node_key));
    new Handle:maps = GetNextMaps(node_key, 7);

    Format(nextmaps, sizeof(nextmaps), "Next Maps:");
    new count = GetArraySize(maps);
    for (new i = 0; i < count; i++)
    {
        GetArrayString(maps, i, map, sizeof(map));
        if (i > 0)
        {
            Format(nextmaps, sizeof(nextmaps), "%s, %s", nextmaps, map);
        }
        else
        {
            Format(nextmaps, sizeof(nextmaps), "%s %s", nextmaps, map);
        }
    }
    CloseHandle(maps);

    PrintToChatAll(nextmaps);
    PrintToConsole(0, nextmaps);
}

public Action:Command_Nextnodes(client, args)
{
    decl String:nextmaps[256], String:node_key[PLATFORM_MAX_PATH];
    decl String:map[PLATFORM_MAX_PATH];

    GetConVarString(g_Cvar_NodeKey, node_key, sizeof(node_key));
    new Handle:maps = GetNextMaps(node_key, 15, true);

    Format(nextmaps, sizeof(nextmaps), "Next Nodes:");
    new count = GetArraySize(maps);
    for (new i = 0; i < count; i++)
    {
        GetArrayString(maps, i, map, sizeof(map));
        if (i > 0)
        {
            Format(nextmaps, sizeof(nextmaps), "%s, %s", nextmaps, map);
        }
        else
        {
            Format(nextmaps, sizeof(nextmaps), "%s %s", nextmaps, map);
        }
    }
    CloseHandle(maps);

    PrintToChatAll(nextmaps);
    PrintToConsole(0, nextmaps);
}

public Action:Command_SetNextmap(client, args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "[DMR] Usage: sm_setnextmap <map>");
        return Plugin_Handled;
    }

    decl String:map[PLATFORM_MAX_PATH];
    GetCmdArg(1, map, sizeof(map));

    if (!IsMapValid(map))
    {
        ReplyToCommand(client, "[DMR] %t", "Map was not found", map);
        return Plugin_Handled;
    }

    ShowActivity(client, "%t", "Cvar changed", "sm_nextmap", map);

    g_ForceNextMap = true;
    SetNextMap(map);

    return Plugin_Handled;
}

public Action:Command_UnsetNextmap(client, args)
{
    if(!ForcedNextMap())
    {
        ReplyToCommand(client, "[DMR] There was no forced nextmap to unset");
    }else{
        g_ForceNextMap = false;
        UpdateNextMap();
        ReplyToCommand(client, "[DMR] Forced nextmap unset");
    }

    return Plugin_Handled;
}

public Action:Command_NextmapNow(client, args)
{
    decl String:map[PLATFORM_MAX_PATH];
    GetNextMap(map, sizeof(map));
    ForceChangeLevel(map, "sm_nextmapnow Command");

    return Plugin_Handled;
}

public Action:Command_ValidateDMR(client, args)
{
    ValidateDMR(g_Rotation, g_MapGroups);

    return Plugin_Handled;
}

public Action:Timer_UpdateNextMap(Handle:timer)
{
    //Skip this we have forced the next map
    if(ForcedNextMap()) return Plugin_Continue;

    UpdateNextMap();

    return Plugin_Continue;
}

UpdateNextMap()
{
    decl String:node_key[MAX_KEY_LENGTH], String:nextmap[MAX_KEY_LENGTH];

    GetConVarString(g_Cvar_NodeKey, node_key, sizeof(node_key));

    GetNextNodeKey(node_key, g_Rotation, g_CachedNextNodeKey, sizeof(g_CachedNextNodeKey));
    GetMapFromKey(g_CachedNextNodeKey, g_Rotation, g_MapGroups, nextmap, sizeof(nextmap));

    SetNextMap(nextmap);
}

//Tests if a key value exists and puts the value into val
stock bool:KvExists(Handle:kv, const String:key[])
{
    return KvGetDataType(kv, key) != KvData_None;
}

//Same as KvExists but also save val
stock bool:KvExists2(Handle:kv, const String:key[], String:val[], length)
{
    return KvGetString(kv, key, val, length, "") && strlen(val) > 0;
}

stock bool:ForcedNextMap()
{
    return g_ForceNextMap;
}

//TODO:  I don't know how sourcemod arrays are implemented and
//FindStringInArray may be O(n).  It may be better to maintain a seperate
//existance trie to check against to be more efficient.
stock bool:MapWasRecentlyPlayed(String:map[])
{
    return FindStringInArray(g_MapHistoryArray, map) >= 0;
}


stock bool:GetMapFromKey(const String:node_key[], Handle:rotation, Handle:map_groups, String:map[], length)
{
    if(rotation == INVALID_HANDLE) return false;
    if(map_groups == INVALID_HANDLE) return false;

    decl String:group[PLATFORM_MAX_PATH];
    new bool:found=false;

    KvRewind(rotation);
    if(KvJumpToKey(rotation, node_key))
    {
        if(KvExists2(rotation, "map", map, length))
        {
            //First check for "map" key
            //Throw error if map is not valid
            if(!IsMapValid(map))
            {
                LogError("map \"%s\" in key \"%s\" is invalid.", map, node_key);
                SetFailState("Map \"%s\" in key \"%s\" is invalid.", map, node_key);
            }

            found = true;

        }else if(KvExists2(rotation, "group", group, length))
        {
            //Then check for "group" key
            //Throw error if group is not valid
            if(!GetRandomMapFromGroup(group, map_groups, map, length))
            {
                LogError("group \"%s\" in key \"%s\" is invalid.", group, node_key);
                SetFailState("Group \"%s\" in key \"%s\" is invalid.", group, node_key);
            }


            found = true;
        }

    }

    KvRewind(rotation);
    return found;
}

stock bool:GetGroupFromKey(const String:node_key[], Handle:rotation, String:group[], length)
{
    if(rotation == INVALID_HANDLE) return false;

    new bool:found = false;

    KvRewind(rotation);
    if(KvJumpToKey(rotation, node_key))
    {
        found = KvExists2(rotation, "group", group, length);
    }

    KvRewind(rotation);
    return found;
}

stock bool:GetNextNodeKey(const String:node_key[], Handle:rotation, String:next_node_key[], length)
{
    if(rotation == INVALID_HANDLE) return false;

    KvRewind(rotation);

    if(!KvJumpToKey(rotation, node_key))
    {
        LogError("node_key \"%s\" was not found.", node_key);
        return false;
    }

    //First get the default map
    KvGetString(rotation, "default_nextnode", next_node_key, length);

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

stock bool:GetRandomMapFromGroup(const String:group[], Handle:map_groups, String:map[], length, &count=0, &history_count=0, &bool:use_history=false)
{
    if(map_groups == INVALID_HANDLE) return false;

    //We only need to do a randomization once, see if we have a cached value
    if(GetTrieString(g_CachedRandomMapTrie, group, map, length)) return true;

    new String:section[PLATFORM_MAX_PATH];
    new rand;
    new bool:found = false;

    KvRewind(map_groups);
    KvGetSectionName(map_groups, map, length);

    if(KvJumpToKey(map_groups, group))
    {
        KvGotoFirstSubKey(map_groups);

        //Use reservoir sampling to get random map from group
        //NOTE: We maintain two seperate reservoirs to prevent previously played maps from being
        //randomly selected. We assume first that they are all recently played and use the first
        //resevoir but once we find one that is not recently played we switch over to the second
        //resevoir. Also note that we use two seperate counts to maintain equal distribution
        //for our random selection.
        do
        {
            KvGetSectionName(map_groups, section, sizeof(section));

            //First we assume that all maps in this group are recently played so we ignore history
            if(!use_history)
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
            }

            //If the section map was not recently played we proceed to ignore all 
            if(!MapWasRecentlyPlayed(section))
            {
                use_history = true;
                history_count += 1;

                if(history_count == 1){
                    KvGetSectionName(map_groups, map, length);
                }else{
                    rand = GetRandomInt(0, history_count - 1);

                    if(rand == history_count - 1) {
                        KvGetSectionName(map_groups, map, length);
                    }
                }
            }

        } while(KvGotoNextKey(map_groups));

        //Cache the selected map
        SetTrieString(g_CachedRandomMapTrie, group, map);
        found= true;
    }

    KvRewind(map_groups);
    return found;
}

stock Handle:GetNextMaps(const String:node_key[], ammount, bool:keys=false)
{
    new Handle:maps = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
    new Handle:visited_groups = CreateTrie();
    new junk;
    decl String:current_key[MAX_KEY_LENGTH], String:next_key[MAX_KEY_LENGTH], String:map[PLATFORM_MAX_PATH];

    //Start with node_key
    strcopy(current_key, sizeof(current_key), node_key);

    //Traverse the dmr graph getting the map that would be selected with current server conditions
    for(new i = 0; i < ammount; i++)
    {
        GetNextNodeKey(current_key, g_Rotation, next_key, sizeof(next_key));

        //NOTE:  This is to handle the case where multiple of the same map group
        //appear in a row.  We cache the randomized result so it is impossible 
        //to know what the random map will be past the first iteration.  Instead
        //we simply display the map group past the first iteration.
        if(GetGroupFromKey(next_key, g_Rotation, map, sizeof(map)))
        {
            if(!GetTrieValue(visited_groups, map, junk))
            {
                //We've never visted this group so we're good to get the map name and cache it
                SetTrieValue(visited_groups, map, 1);
                GetMapFromKey(next_key, g_Rotation, g_MapGroups, map, sizeof(map));
            }
        }else{
            GetMapFromKey(next_key, g_Rotation, g_MapGroups, map, sizeof(map));
        }
        strcopy(current_key, sizeof(current_key), next_key);

        //Push the current_key if we're only returning keys; else push the map name
        PushArrayString(maps, keys ? current_key : map);
    }

    CloseHandle(visited_groups);

    return maps;
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

/**
  Return  1 if given time is after current time
  0 if given time same as now
  -1 if given time is before current time
 */
stock CompareTimeFromString(const String:time[])
{
    decl String:tmp[2][8];

    ExplodeString(time, ":", tmp, 2, 8);
    new hour   = StringToInt(tmp[0]);
    new minute = StringToInt(tmp[1]);

    return CompareTime(hour, minute);
}

/**
  Return  1 if given time is after current time
  0 if given time same as now
  -1 if given time is before current time
 */
stock CompareTime(hour, minute)
{
    decl String:tmp[16];

    FormatTime(tmp, sizeof(tmp), "%H");
    new hour_now = StringToInt(tmp);

    FormatTime(tmp, sizeof(tmp), "%M");
    new minute_now = StringToInt(tmp);

    if(hour > hour_now)
    {
        return 1;
    }else if(hour < hour_now)
    {
        return -1;
    }else if (minute > minute_now)
    {
        return 1;
    }else if (minute < minute_now)
    {
        return -1;
    }

    return 0;
}

/**
  Return true if today is included in days
 */
stock bool:CompareDayOfWeek(const String:days[])
{
    decl String:tmp[16];

    FormatTime(tmp, sizeof(tmp), "%u");
    new day = StringToInt(tmp);
    Format(tmp, sizeof(tmp), "%s", DAYS_OF_WEEK[day]);

    return day > 0 && day < sizeof(DAYS_OF_WEEK) && StrContains(days, tmp) >= 0;
}

stock bool:MapConditionsAreMet(Handle:conditions)
{
    decl String:val[MAX_VAL_LENGTH];
    new count;

    if(KvExists(conditions, "players_lte"))
    {
        count = KvGetNum(conditions, "players_lte");
        if(!(GetPlayerCount() <= count)) return false;
    }

    if(KvExists(conditions, "players_gte"))
    {
        count = KvGetNum(conditions, "players_gte");
        if(!(GetPlayerCount() >= count)) return false;
    }

    if(KvExists(conditions, "admins_lte"))
    {
        count = KvGetNum(conditions, "admins_lte");
        if(!(GetPlayerCount() <= count)) return false;
    }

    if(KvExists(conditions, "admins_gte"))
    {
        count = KvGetNum(conditions, "admins_gte");
        if(!(GetPlayerCount() >= count)) return false;
    }

    if(KvExists2(conditions, "time_lte", val, sizeof(val)))
    {
        if(CompareTimeFromString(val) > 0 ) return false;
    }

    if(KvExists2(conditions, "time_gte", val, sizeof(val)))
    {
        if(CompareTimeFromString(val) < 0 ) return false;
    }

    if(KvExists2(conditions, "day_eq", val, sizeof(val)))
    {
        if(!CompareDayOfWeek(val)) return false;
    }

    if(KvExists2(conditions, "day_neq", val, sizeof(val)))
    {
        if(CompareDayOfWeek(val)) return false;
    }

    return true;
}
