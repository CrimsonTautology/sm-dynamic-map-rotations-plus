/**
 * vim: set ts=4 :
 * =============================================================================
 * DMR Plus
 * Updated version of FLOOR_MASTER's Dynamic Map Rotations plugin
 * Dynamically alters the map rotation based on server conditions.
 *
 * Copyright 2021 CrimsonTautology
 * =============================================================================
 *
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "1.10.1"
#define PLUGIN_NAME "Dynamic Map Rotations Plus"

public Plugin myinfo =
{
    name = PLUGIN_NAME,
    author = "CrimsonTautology",
    description = "Dynamically alters the map rotation based on server conditions.",
    version = PLUGIN_VERSION,
    url = "https://github.com/CrimsonTautology/sm-dynamic-map-rotations-plus"
};


ConVar g_RotationFileCvar;
ConVar g_GroupsFileCvar;
ConVar g_ExcludeMapsCvar;

#include "dmr/keyvalues.sp"
#include "dmr/maphistory.sp"
#include "dmr/mapgroups.sp"
#include "dmr/rotation.sp"
#include "dmr/utils.sp"

Rotation g_Rotation;
MapGroups g_MapGroups;
MapHistory g_MapHistory;
StringMap g_CachedRandomMapTrie;

bool g_NextMapIsForced = false;

char g_Node[MAX_KEY_LENGTH];

public void OnPluginStart()
{
    LoadTranslations("common.phrases");

    CreateConVar("dmr_version", PLUGIN_VERSION, PLUGIN_NAME,
            FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);

    g_RotationFileCvar = CreateConVar(
            "dmr_rotation_file",
            "cfg/dmr_rotation.txt",
            "Location of the rotation keyvalues file",
            0);

    g_GroupsFileCvar = CreateConVar(
            "dmr_groups_file",
            "cfg/dmr_groups.txt",
            "Location of the map groups keyvalues file",
            0);

    g_ExcludeMapsCvar = CreateConVar(
            "dmr_exclude",
            "5",
            "Specifies how many past maps to exclude when randomly selecting a map from a group.",
            _,
            true,
            0.0);

    RegConsoleCmd("sm_nextmaps", Command_Nextmaps, "Print next maps in rotation");
    RegConsoleCmd("sm_nextnodes", Command_Nextnodes, "Print next DMR nodes in rotation");
    RegConsoleCmd("sm_currentnode", Command_Currentnode, "Print current DMR node");

    RegAdminCmd("sm_setnextmap", Command_SetNextmap, ADMFLAG_CHANGEMAP,
            "Force the next map and prevent DMR from running for the duration of this map");
    RegAdminCmd("sm_unsetnextmap", Command_UnsetNextmap, ADMFLAG_CHANGEMAP,
            "Unset a forced next map and have DMR resume");
    RegAdminCmd("sm_nextmapnow", Command_NextmapNow, ADMFLAG_CHANGEMAP,
            "Force a mapchange to the determined next map right now");

    RegAdminCmd("sm_reloaddmr", Command_ReloadDMR, ADMFLAG_CHANGEMAP,
            "Reload the DMR files");
    RegAdminCmd("sm_validatedmr", Command_ValidateDMR, ADMFLAG_CHANGEMAP,
            "Validate the DMR files");

    InitializeDMR();
    ValidateDMR();
}

public void OnMapStart()
{
    char currentmap[MAX_KEY_LENGTH], currentgroup[MAX_KEY_LENGTH];

    if (!NextMapIsForced())
    {
        // add this map to our history
        GetCurrentMap(currentmap, sizeof(currentmap));
        g_MapHistory.PushMap(currentmap, g_ExcludeMapsCvar.IntValue);

        // if current node holds a map group;  clear it from the cache
        if (g_Rotation.GetGroup(g_Node, currentgroup, sizeof(currentgroup)))
        {
            g_CachedRandomMapTrie.Remove(currentgroup);
        }
    }

    // reset globals
    g_NextMapIsForced = false;

    // set up repeating timer
    CreateTimer(60.0, Timer_UpdateNextMap, .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

    // initialize a nextmap
    UpdateNextMap();

    // run pre-Commands
    g_Rotation.RunNodePreCommand(g_Node);
}

public void OnMapEnd()
{
    // needed for Iterate, not actually used
    char nextmap[MAX_KEY_LENGTH];

    if (!NextMapIsForced())
    {
        // iterate to the next node in our rotation
        g_Rotation.Iterate(
                g_Node, sizeof(g_Node), nextmap, sizeof(nextmap),
                g_MapGroups, g_CachedRandomMapTrie, g_MapHistory);
    }
}

public void OnAutoConfigsBuffered()
{
    g_Rotation.RunNodeCommand(g_Node);
}

// saying "nextmaps" is more intuitive than "!nextmaps" due to "nextmap" being
// registered already
public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
    if (strcmp(sArgs, "nextmaps", false) == 0)
    {
        PrintNextItems();
    }
}

Action Command_Nextmaps(int client, int args)
{
    PrintNextItems();
    return Plugin_Handled;
}

Action Command_Nextnodes(int client, int args)
{
    PrintNextItems(.amount=20, .as_nodes=true);
    return Plugin_Handled;
}

Action Command_Currentnode(int client, int args)
{
    PrintToChatAll(g_Node);
    PrintToServer(g_Node);
    return Plugin_Handled;
}

Action Command_SetNextmap(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "[DMR] Usage: sm_setnextmap <map>");
        return Plugin_Handled;
    }

    char map[MAX_KEY_LENGTH];
    GetCmdArg(1, map, sizeof(map));

    if (!IsMapValid(map))
    {
        ReplyToCommand(client, "[DMR] %t", "Map was not found", map);
        return Plugin_Handled;
    }

    ShowActivity(client, "%t", "Cvar changed", "sm_nextmap", map);

    g_NextMapIsForced = true;
    SetNextMap(map);

    return Plugin_Handled;
}

Action Command_UnsetNextmap(int client, int args)
{
    if (!NextMapIsForced())
    {
        ReplyToCommand(client, "[DMR] There was no forced nextmap to unset");

    }
    else
    {
        g_NextMapIsForced = false;
        UpdateNextMap();
        ReplyToCommand(client, "[DMR] Forced nextmap unset");
    }

    return Plugin_Handled;
}

Action Command_NextmapNow(int client, int args)
{
    char map[MAX_KEY_LENGTH];
    GetNextMap(map, sizeof(map));
    ForceChangeLevel(map, "sm_nextmapnow Command");

    return Plugin_Handled;
}

Action Command_ReloadDMR(int client, int args)
{
    char at_node[MAX_KEY_LENGTH];
    if (args >= 1)
    {
        // use the current node passed in as an argument
        GetCmdArg(1, at_node, sizeof(at_node));

    }
    else
    {
        // use the global current node
        strcopy(at_node, sizeof(at_node), g_Node);
    }

    InitializeDMR(.at_node=at_node);
    ValidateDMR();
    UpdateNextMap();

    return Plugin_Handled;
}

Action Command_ValidateDMR(int client, int args)
{
    ValidateDMR();

    return Plugin_Handled;
}

Action Timer_UpdateNextMap(Handle timer)
{
    // skip this we have forced the next map
    if (NextMapIsForced()) return Plugin_Continue;

    UpdateNextMap();

    return Plugin_Continue;
}

Rotation LoadDMRFile(const char[] file, const char[] startnode="", char[] currentnode, int length)
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), file);

    Rotation rotation = new Rotation("DMR Rotation");

    if (!rotation.ImportFromFile(file))
    {
        LogError("Could not read map rotation file \"%s\"", file);
        SetFailState("Could not read map rotation file \"%s\"", file);
        delete rotation;
        return null;
    }

    if (strlen(startnode) > 0 && rotation.JumpToKey(startnode))
    {
        // if given a manual startnode that exists, set current node to that
        strcopy(currentnode, length, startnode);
        LogMessage("Manually set dmr currentnode to \"%s\"", startnode);

    }
    else if (rotation.GetStartNode(currentnode, length))
    {
        // if not given a manual startnode, set current node to default start
        // node if it exists
        LogMessage("Default dmr currentnode to \"%s\"", startnode);
    }
    else
    {
        // we cannot set a currentnode so have the plugin fail
        LogError("A valid \"start\" key was not defined in \"%s\"", file);
        SetFailState("A valid \"start\" key was not defined in \"%s\"", file);
        delete rotation;
        return null;
    }

    return rotation;
}

MapGroups LoadDMRGroupsFile(const char[] file)
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), file);

    MapGroups map_groups = new MapGroups("DMR MapGroups");

    if (!map_groups.ImportFromFile(file))
    {
        LogError("Could not read map groups file \"%s\"", file);
        SetFailState("Could not read map groups file \"%s\"", file);
        return null;
    }

    return map_groups;
}

void InitializeDMR(const char[] at_node="")
{
    char rotation_file[PLATFORM_MAX_PATH], groups_file[PLATFORM_MAX_PATH];
    char currentmap[MAX_KEY_LENGTH];

    g_RotationFileCvar.GetString(rotation_file, sizeof(rotation_file));
    delete g_Rotation;
    g_Rotation = LoadDMRFile(rotation_file, at_node, g_Node, sizeof(g_Node));

    g_GroupsFileCvar.GetString(groups_file, sizeof(groups_file));
    delete g_MapGroups;
    g_MapGroups = LoadDMRGroupsFile(groups_file);

    delete g_MapHistory;
    g_MapHistory = new MapHistory();
    GetCurrentMap(currentmap, sizeof(currentmap));
    g_MapHistory.PushMap(currentmap, g_ExcludeMapsCvar.IntValue);

    delete g_CachedRandomMapTrie;
    g_CachedRandomMapTrie = new StringMap();
}

void ValidateDMR()
{
    // ensure that the plugin rotation and mapgroups structures are valid
    g_Rotation.Validate(g_MapGroups);
    g_MapGroups.Validate();
}

void UpdateNextMap()
{
    char nextnode[MAX_KEY_LENGTH], nextmap[MAX_KEY_LENGTH];
    strcopy(nextnode, sizeof(nextnode), g_Node);

    // iterate to the next node in our rotation with current server conditions
    // and update the nextmap
    if(g_Rotation.Iterate(
            nextnode, sizeof(nextnode), nextmap, sizeof(nextmap), g_MapGroups,
            g_CachedRandomMapTrie, g_MapHistory))
    {
        SetNextMap(nextmap);
    }
}

bool NextMapIsForced()
{
    return g_NextMapIsForced;
}

void PrintNextItems(int amount=7, bool as_nodes=false, bool show_title=true)
{
    char nextmaps[512];
    char map[MAX_KEY_LENGTH];

    ArrayList maps = g_Rotation.GetNextItems(g_Node, amount, g_MapGroups,
            g_CachedRandomMapTrie, .as_nodes=as_nodes, .show_title=show_title);

    Format(nextmaps, sizeof(nextmaps), as_nodes ? "Next Nodes:" : "Next Maps:");

    // prepend nexmap if we set a forced nextmap
    if (NextMapIsForced())
    {
        GetNextMap(map, sizeof(map));
        Format(nextmaps, sizeof(nextmaps), "%s %s", nextmaps, map);
    }

    for (int i = 0; i < maps.Length; i++)
    {
        maps.GetString(i, map, sizeof(map));
        if (i > 0 || NextMapIsForced())
        {
            Format(nextmaps, sizeof(nextmaps), "%s, %s", nextmaps, map);
        }
        else
        {
            Format(nextmaps, sizeof(nextmaps), "%s %s", nextmaps, map);
        }
    }

    delete maps;

    PrintToChatAll(nextmaps);
    PrintToServer(nextmaps);
}
