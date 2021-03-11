# Dynamic Map Rotations Plus (DMR)

![Build Status](https://github.com/CrimsonTautology/sm-dynamic-map-rotations-plus/workflows/Build%20plugins/badge.svg?style=flat-square)
[![GitHub stars](https://img.shields.io/github/stars/CrimsonTautology/sm-dynamic-map-rotations-plus?style=flat-square)](https://github.com/CrimsonTautology/sm-dynamic-map-rotations-plus/stargazers)
[![GitHub issues](https://img.shields.io/github/issues/CrimsonTautology/sm-dynamic-map-rotations-plus.svg?style=flat-square&logo=github&logoColor=white)](https://github.com/CrimsonTautology/sm-dynamic-map-rotations-plus/issues)
[![GitHub pull requests](https://img.shields.io/github/issues-pr/CrimsonTautology/sm-dynamic-map-rotations-plus.svg?style=flat-square&logo=github&logoColor=white)](https://github.com/CrimsonTautology/sm-dynamic-map-rotations-plus/pulls)
[![GitHub All Releases](https://img.shields.io/github/downloads/CrimsonTautology/sm-dynamic-map-rotations-plus/total.svg?style=flat-square&logo=github&logoColor=white)](https://github.com/CrimsonTautology/sm-dynamic-map-rotations-plus/releases)

Rewrite of FLOOR_MASTER's [Dynamic Map Rotations plugin](https://forums.alliedmods.net/showthread.php?p=599464) for Sourcemod. 

Dynamically changes the map rotations based on current server conditions.  This allows you to determine what map to go to next based on the number of players on the server, or the current time, or the day of the week.  This had to be rewriten due to changes to the source engine as well as SourceMod.  Adds new features such as the ability to define map groups that the DMR will randomly select one of instead of having one specific map per node.


## Requirements
* [SourceMod](https://www.sourcemod.net/) 1.10 or later


## Installation
Make sure your server has SourceMod installed.  See [Installing SourceMod](https://wiki.alliedmods.net/Installing_SourceMod).  If you are new to managing SourceMod on a server be sure to read the '[Installing Plugins](https://wiki.alliedmods.net/Managing_your_sourcemod_installation#Installing_Plugins)' section from the official SourceMod Wiki.

Download the latest [release](https://github.com/CrimsonTautology/sm-dynamic-map-rotations-plus/releases/latest) and copy the contents of `addons` to your server's `addons` directory.  It is recommended to restart your server after installing.

To confirm the plugin is installed correctly, on your server's console type:
```
sm plugins list
```

You will also need to create map rotation and map group configuration files (by default the plugin looks for `cfg/dmr_rotation.txt` and `cfg/dmr_groups.txt`).  You can find an exmple for these under `cfg/`.

This plugin most likley conflicts with other mapchooser and rockthevote style plugins so you may need to uninstiall them before using DMR.

## Usage


### Commands
NOTE: All commands can be run from the in-game chat by replacing `sm_` with `!` or `/`.  For example `sm_rtv` can be called with `!rtv`.

| Command | Accepts | Values | SM Admin Flag | Description |
| --- | --- | --- | --- | --- |
| sm_nextmaps | None | None | None | Print next maps in rotation |
| sm_nextnodes | None | None | None | Print next DMR nodes in rotation.  Good for debugging |
| sm_currentnode | None | None | None | Print current DMR node.  Good for debugging |
| sm_setnextmap | string | map | Change Map | Force the next map and prevent DMR from running for the duration of this map |
| sm_unsetnextmap | None | None | Change Map | Unset a forced next map and have DMR resume |
| sm_nextmapnow | None | None | Change Map | Force a mapchange to the determined next map right now |
| sm_reloaddmr | string | node | Change Map | Reload the DMR files.  Accepts an optional node argument that will start the DMR at the given node instead of the `start` node |
| sm_validatedmr | None | None | Change Map | Validate the DMR files but do not reload them.  Good for testing |


### Console Variables

| Command | Accepts | Description |
| --- | --- | --- | --- |
| dmr_rotation_file | path | Location of the rotation keyvalues file (default: `cfg/dmr_rotation.txt`)|
| dmr_groups_file | path | Location of the map groups keyvalues file (default: `cfg/dmr_groups.txt`)|
| dmr_exclude | integer | Specifies how many past maps to exclude when randomly selecting a map from a group. (default: `5`)|


## Rock the Vote
* Separate plugin to add Rock The Vote functionality to the plugin so users can vote to change maps.  Functions the same as the stock rockthevote.smx plugin.
* Type "rtv" into chat to Rock The Vote.  When enough players rock the vote the server will automatically change to the next map in the rotation.


## DMR Syntax

Dynamic map rotations are essentially keyvalues structures. I'll go through an illustrative example of how to create a simple DMR. Let's begin with a simple basic `mapcycle.txt`:

```
cp_gravelpit
cp_well
cp_dustbowl
```

Here's an equivalent `cfg/dmr_rotation.txt`:

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

Now let's say we want to skip ctf_well when the number of players on the server is <= 12. The corresponding `cfg/dmr_rotation.txt` looks like:

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

A new feature in this version of DMR is the concept of map groups.  Instead of specifying a specific map for each node you can instead specify your own defined mapgroup.  Take a look at this `cfg/dmr_mapgroups.txt`:

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

with this corresponding `cfg/dmr_rotation.txt`

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

### Node Options
| Option Key | Description |
| --- | --- |
| `map` | A specific map this node will run. |
| `group` | A random map from a given map group defined in `cfg/dmr_groups.txt`. |
| `command` | A server command that will be called at map start when on this node |
| `pre_command` | Like command but called during OnMapStart instead of OnAutoConfigsBuffered.  Used for some commands that need to be called sooner. |
| `title` | A title to display next to the map name when calling !nextmaps.  Good for when you are executing a custom game mode that is different from normal. |
| `default_nextnode` | The default node that will be called next if none of the custom conditions are met. |

### Custom Conditions
| Condition Key | Description |
| --- | --- |
| `players_lte` | the number of players on the server is less than or equal to the specified number |
| `players_gte` | ditto, but greater than or equal to |
| `admins_lte` | the number of admins on the server is less than or equal to the specified number |
| `admins_gte` | ditto, but greater than or equal to |
| `time_lte` | the current server time is less than or equal to the specified time, in 24-hour "h:mm" format |
| `time_gte` | ditto, but greater than or equal to |
| `day_eq` | the day is currently a certain day of the week, where the day is specified with m, t, w, r, f, s, and u for Monday, Tuesday, etc. You can specify multiple days. For example, "day_eq" "mwf" will be true if the day is Monday, Wednesday, or Friday. "day_eq" "u" will be true if the day is Sunday. |
| `day_neq` | ditto, but if the day is NOT a certain day of the week |


## Compiling
If you are new to SourceMod development be sure to read the '[Compiling SourceMod Plugins](https://wiki.alliedmods.net/Compiling_SourceMod_Plugins)' page from the official SourceMod Wiki.

You will need the `spcomp` compiler from the latest stable release of SourceMod.  Download it from [here](https://www.sourcemod.net/downloads.php?branch=stable) and uncompress it to a folder.  The compiler `spcomp` is located in `addons/sourcemod/scripting/`;  you may wish to add this folder to your path.

Once you have SourceMod downloaded you can then compile using the included [Makefile](Makefile).

```sh
cd sm-dynamic-map-rotations-plus
make SPCOMP=/path/to/addons/sourcemod/scripting/spcomp
```

Other included Makefile targets that you may find useful for development:

```sh
# compile plugin with DEBUG enabled
make DEBUG=1

# pass additonal flags to spcomp
make SPFLAGS="-E -w207"

# install plugins and required files to local srcds install
make install SRCDS=/path/to/srcds

# uninstall plugins and required files from local srcds install
make uninstall SRCDS=/path/to/srcds
```


## Contributing

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request


## License
[GNU General Public License v3.0](https://choosealicense.com/licenses/gpl-3.0/)


## Acknowledgements

* [sm-testsuite by clugg](https://github.com/clugg/sm-testsuite)
* [FLOOR_MASTER's original Dynamic Map Rotations plugin](https://forums.alliedmods.net/showthread.php?p=599464)
* [alliedmods's original Rock the Vote plugin](https://github.com/alliedmodders/sourcemod/blob/master/plugins/rockthevote.sp)
