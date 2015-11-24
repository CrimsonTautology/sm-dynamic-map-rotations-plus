# Dynamic Map Rotations Plus
[![Build Status](https://travis-ci.org/CrimsonTautology/sm_dynamic_map_rotations_plus.svg?branch=master)](https://travis-ci.org/CrimsonTautology/sm_dynamic_map_rotations_plus)

Rewrite of FLOOR_MASTER's [Dynamic Map Rotations plugin](https://forums.alliedmods.net/showthread.php?p=599464) for Sourcemod. 

Dynamically changes the map rotations based on current server conditions.  This allows you to determine what map to go to next based on the number of players on the server, or the current time, or the day of the week.  This had to be rewriten due to changes to the source engine as well as SourceMod.  Adds new features such as the ability to define map groups that the DMR will randomly select one of instead of having one specific map per node.

##Installation
* Compile plugins with spcomp (e.g.)
```
spcomp addons/sourcemod/scripting/dmr_plus.sp
spcomp addons/sourcemod/scripting/dmr_rockthevote.sp
```
* Move compiled .smx files into your `<modname>/addons/sourcemod/plugins` directory.
* Move dmr.txt and dmr_groups.txt to your base `<modname>` directory or a custom `<modname>/custom/<customname>/` directory.

    

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
Notice the subsection added within section 10 (cp_dustbowl). This is called a conditional nextnode. Basically, the extra key value subsection can be read as "if the number of players is lte (less than or equal to) 12, then the nextnode is section 30 (cp_dustbowl)". If the conditional nextnode isn't true, which in this case means there are more than 12 players on the server, then the `default_nextnode` is used as the next map. 

Another example. Let's add cp_badlands to the rotation and throw in a few more conditional nextnodes:

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
        "map"            "ctf_well"
        "default_nextnode"    "30"
        "10"
        {
            "players_lte"    "10"
        }
        "bdlnds"
        {
            "players_lte"    "10"
            "time_lte"    "11:00"
        }
    }
    "30"
    {
        "map"            "cp_dustbowl"
        "default_nextnode"    "10"
    }

    "bdlnds"
    {
        "map"            "cp_badlands"
        "default_nextnode"    "30"
    }
}
```

First, notice how I used the section name `bdlnds`. Remember that section names are arbitrary -- I could have just been consistent and chosen "40" or chosen anything at all.

Let's look closely at section 20 (ctf_well). There are two conditional nextnodes and a default_nextnode. The first condition reads "IF the number of players <= 10 THEN the next map is section 10 (cp_gravelpit).  The second condition reads "IF the number of players <= 10 AND the current server time is <= 11AM, THEN the next map is section bdlnds (cp_badlands)".  If none of the conditional nextmaps are true, then the nextmap is the default_nextmap: section 30 (cp_dustbowl).  You can have as many subsections as you wish and the DMR will iterate through all of them, selecting the last subsection whose conditions are true and defaulting to `default_nextnode` if none of them are true.

A new feature in this version of DMR is the concept of map groups.  Instead of specifying a specific map for each node you can instead specify your own defined mapgroup.  Take a look at this `dmr_mapgroups.txt`:

```
map_groups
{
    payload
    {
        pl_goldrush {}
        pl_badwater {}
        pl_upward {}
    }
    
    cp
    {
        cp_dustbowl {}
        cp_gravelpit {}
        cp_badlands {}
    }

    koth
    {
        koth_viaduct {}
    }
}
```

with this corresponding `dmr.txt`

```
"rotation"
{
    "start"    "10"
    "10"
    {
        "group"            "payload"
        "default_nextnode"    "20"
    }
    "20"
    {
        "group"            "cp"
        "default_nextnode"    "30"
    }
    "30"
    {
        "group"            "koth"
        "default_nextnode"    "10"
    }
}
```

This is similar to just selecting a specific map except this time a random map from a map group is chosen instead.  This DMR for example with rotatate between a radnom payload map, a random cp map, a random koth map and then back to a random pl map.  This is great if you have a huge map selection on your server but want to break off certain maps to only be played if enough people are on the server.

# Node Options
* `map` - A specific map this node will run.
* `group` - A random map from a given map group defined in `dmr_groups.txt`.
* `command` - A server command that will be called at map start when on this node
* `pre_command` - Like command but called during OnMapStart instead of OnAutoConfigsBuffered.  Used for some commands that need to be called sooner.
* `title` - A title to display next to the map name when calling !nextmaps.  Good for when you are executing a custom game mode that is different from normal.
* `default_nextnode` - The default node that will be called next if none of the custom conditions are met.

# Custom Conditions
* `players_lte` - the number of players on the server is less than or equal to the specified number
* `players_gte` - ditto, but greater than or equal to
* `admins_lte` - the number of admins on the server is less than or equal to the specified number
* `admins_gte` - ditto, but greater than or equal to
* `time_lte` - the current server time is less than or equal to the specified time, in 24-hour "h:mm" format
* `time_gte` - ditto, but greater than or equal to
* `day_eq` - the day is currently a certain day of the week, where the day is specified with m, t, w, r, f, s, and u for Monday, Tuesday, etc. You can specify multiple days. For example, "day_eq" "mwf" will be true if the day is Monday, Wednesday, or Friday. "day_eq" "u" will be true if the day is Sunday.
* `day_neq` - ditto, but if the day is NOT a certain day of the week


