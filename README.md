# Dynamic Map Rotations Plus
[![Build Status](https://travis-ci.org/CrimsonTautology/sm_dynamic_map_rotations_plus.svg?branch=master)](https://travis-ci.org/CrimsonTautology/sm_dynamic_map_rotations_plus)

Rewrite of FLOOR_MASTER's [Dynamic Map Rotations plugin](https://forums.alliedmods.net/showthread.php?p=599464) for Sourcemod. Redesigned to.

##Installation
* Compile plugins with spcomp (e.g.)
> spcomp addons/sourcemod/scripting/dmr_plus.sp
> spcomp addons/sourcemod/scripting/dmr_rockthevote.sp
* Move compiled .smx files into your `"<modname>/addons/sourcemod/plugins"` directory.
* Move dmr.txt and dmr_groups.txt to your base "<modname>" directory or a custom "<modname>/custom/<customname>/" directory.

    

##Requirements
* None.  However it's probably not compatable with the stock mapchooser and rockthevote plugins so be sure to disable those.

# Dynamic Map Rotations

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

# Notes
