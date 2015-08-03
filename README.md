# Dynamic Map Rotations Plus
[![Build Status](https://travis-ci.org/CrimsonTautology/sm_dynamic_map_rotations_plus.svg?branch=master)](https://travis-ci.org/CrimsonTautology/sm_dynamic_map_rotations_plus)

Rewrite of FLOOR_MASTER's [Dynamic Map Rotations plugin](https://forums.alliedmods.net/showthread.php?p=599464) for Sourcemod. 

Dynamically changes the map rotations based on current server conditions.  This allows you to determine what map to go to next based on the number of players on the server, or the current time, or the day of the week.

##Installation
* Compile plugins with spcomp (e.g.)
> spcomp addons/sourcemod/scripting/dmr_plus.sp
> spcomp addons/sourcemod/scripting/dmr_rockthevote.sp
* Move compiled .smx files into your `"<modname>/addons/sourcemod/plugins"` directory.
* Move dmr.txt and dmr_groups.txt to your base "<modname>" directory or a custom "<modname>/custom/<customname>/" directory.

    

##Requirements
* None.  However it's probably not compatable with the stock mapchooser and rockthevote plugins so be sure to disable those.

# Configuration

* `dmr_file` - (Default "dmr.txt") Location of the rotation keyvalues file off the base <modname> directory.
* `dmr_groups_file` - (Default "dmr_groups.txt") Location of the map groups keyvalues file off the base <modname> directory.
* `dmr_node_key` - The key used to base nextmap decisions on.  You shouldn't have to ever change this manually but you can change it to force the DMR to a specific node. 
* `dmr_exclude` - (Default 5) Specifies how many past maps to exclude when randomly selecting a map from a group.

# Commands

* `sm_nextmaps` - Print next maps in rotation
* `sm_nextnodes` - Print dmr nodes in rotation
* `sm_rtv` - Cast a vote to change the map.  Requires the dmr_rockthevote plugin
* `sm_nextmapnow` - (Admin) Force a mapchange to the determined next map right now
* `sm_setnextmap` - (Admin) Force the next map and prevent DMR from running for the duration of this map
* `sm_unsetnextmap` - (Admin) Unset a forced next map and have DMR resume
* `sm_reloaddmr` - (Admin) Reload the DMR files
* `sm_validatedmr` - (Admin) Validate the DMR files


# Rock the Vote
* Separate plugin to add Rock The Vote functionality to the plugin so users can vote to change maps.  Functions the same as the stock rockthevote.smx plugin.
* Type "rtv" into chat to Rock The Vote.  When enough players rock the vote the server will automatically change to the next map in the rotation.

# DMR Syntax

Dynamic map rotations are essentially keyvalues structures. I'll go through an illustrative example of how to create a simple DMR. Let's begin with a simple basic `mapcycle.txt`:

```
cp_gravelpit
cp_well
cp_dustbowl
```

Here's an equivalent `dmr.txt`:

```
"rotation"
{
    "start"    "10"
    "10"
    {
        "map"            "cp_gravelpit"
        "default_nextnode"    "20"
    }
    "20"
    {
        "map"            "cp_well"
        "default_nextnode"    "30"
    }
    "30"
    {
        "map"            "cp_dustbowl"
        "default_nextnode"    "10"
    }
}
```

There are several things to note about the DMR:
The entire keyvalues structure is called `rotation`
Every map is its own section with an arbitrary section name. In this case, the names are `10`, `20`, and `30`, but they could easily be the mapnames themselves or whatever you want.
There is a `start` keyvalue pair that indicates the first node in the rotation.
Within each section is a `map` keyvalue pair whose value is the actual name of the map.
Within each section is a `default_nextnode` keyvalue pair. The value points to the section of the nextnode. For example, notice how in section `30` (cp_dustbowl), the `default_nextnode` is section `10` (cp_gravelpit).

Now let's say we want to skip ctf_well when the number of players on the server is <= 12. The corresponding `dmr.txt` looks like:

```
"rotation"
{
    "start"    "10"
    "10"
    {
        "map"            "cp_gravelpit"
        "default_nextnode"    "20"
         "30"
        {
            "players_lte"    "12"
        }
    }
    "20"
    {
        "map"            "cp_well"
        "default_nextnode"    "30"
    }
    "30"
    {
        "map"            "cp_dustbowl"
        "default_nextnode"    "10"
    }
}
```
Notice the subsection added within section 10 (cp_dustbowl). This is called a conditional nextnode. Basically, the extra key value subsection can be read as "if the number of players is lte (less than or equal to) 12, then the nextmap is section 30 (cp_dustbowl)". If the conditional nextmap isn't true, which in this case means there are more than 12 players on the server, then the `default_nextmap` is used as the next map. You can have as many subsections as you wish and the DMR will iterate through all of them, selecting the last subsection whose conditions are true and defaulting to `default_nextnode` if none of them are true.

# Notes
