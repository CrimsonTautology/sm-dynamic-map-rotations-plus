methodmap Rotation < DMRKeyValues
{
    public Rotation(const char[] name="rotation", const char[] firstKey="", const char[] firstValue="")
    {
        return view_as<Rotation>(new DMRKeyValues(name, .firstKey=firstKey, .firstValue=firstValue));
    }

    public bool NextNodeConditionsAreMet()
    {
        char val[MAX_KEY_LENGTH];
        int count;

        if (this.KeyExists("players_lte"))
        {
            count = this.GetNum("players_lte");
            if (!(GetPlayerCount() <= count)) return false;
        }

        if (this.KeyExists("players_gte"))
        {
            count = this.GetNum("players_gte");
            if (!(GetPlayerCount() >= count)) return false;
        }

        if (this.KeyExists("admins_lte"))
        {
            count = this.GetNum("admins_lte");
            if (!(GetAdminCount() <= count)) return false;
        }

        if (this.KeyExists("admins_gte"))
        {
            count = this.GetNum("admins_gte");
            if (!(GetAdminCount() >= count)) return false;
        }

        if (this.KeyExistsAndCopy("time_lte", val, sizeof(val)))
        {
            if (CompareTimeFromString(val) <= 0 ) return false;
        }

        if (this.KeyExistsAndCopy("time_gte", val, sizeof(val)))
        {
            if (CompareTimeFromString(val) >= 0 ) return false;
        }

        if (this.KeyExistsAndCopy("day_eq", val, sizeof(val)))
        {
            if (!CompareDayOfWeek(val)) return false;
        }

        if (this.KeyExistsAndCopy("day_neq", val, sizeof(val)))
        {
            if (CompareDayOfWeek(val)) return false;
        }

        return true;
    }

    public bool GetValueOfKeyOfNode(const char[] node, const char[] key, char[] value, int length)
    {
        this.Rewind();

        return this.JumpToKey(node) &&
            this.KeyExistsAndCopy(key, value, length);
    }

    // get the title of the given node if it exists
    // return false if node does not have a title or if node does not exist
    public bool GetTitle(const char[] node, char[] value, int length)
    {
        return this.GetValueOfKeyOfNode(node, "title", value, length);
    }

    // get the map of the given node if it exists
    // return false if node does not have a map or if node does not exist
    public bool GetMap(const char[] node, char[] value, int length)
    {
        return this.GetValueOfKeyOfNode(node, "map", value, length);
    }

    // get the group of the given node if it exists
    // return false if node does not have a group or if node does not exist
    public bool GetGroup(const char[] node, char[] value, int length)
    {
        return this.GetValueOfKeyOfNode(node, "group", value, length);
    }

    // execute the value of a given command_key as if it were a server command
    // return false if node does not have the given command_key or if node does
    // not exist
    // * key "command": intended to be called from OnAutoConfigsBuffered
    // * key "pre_command": intended to be called from OnMapStart
    public bool RunNodeCommand(const char[] node, const char[] command_key="command")
    {
        char command[MAX_KEY_LENGTH];
        bool found = this.GetValueOfKeyOfNode(node, command_key, command, sizeof(command));

        if (found) ServerCommand(command);

        return found;
    }

    public bool RunNodePreCommand(const char[] node)
    {
        return this.RunNodeCommand(node, "pre_command");
    }

    // get the starting node of the graph;  return true if it exists
    public bool GetStartNode(char[] startnode, int length)
    {
        this.Rewind();
        this.GetString("start", startnode, length);

        return this.JumpToKey(startnode);
    }

    // given a node, determine the nextnode in the rotation we should jump to
    // return false if the current node does not have a nextnode
    public bool DetermineNextNode(const char[] node, char[] nextnode, int length)
    {
        // save a copy of node in case we overwrite it
        char currentnode[MAX_KEY_LENGTH];
        strcopy(currentnode, sizeof(currentnode), node);

        this.Rewind();

        if (!this.JumpToKey(currentnode))
        {
            LogError("node \"%s\" was not found in rotation.", node);
            return false;
        }

        // assume the default_nextnode as a fallback
        this.GetString("default_nextnode", nextnode, length);

        // go through remaining subkeys, with the key name being the next group
        // and the body being a list of custom rules
        this.Rewind();
        this.JumpToKey(currentnode);
        if (this.GotoFirstSubKey())
        {
            do
            {
                if (this.NextNodeConditionsAreMet())
                {
                    this.GetSectionName(nextnode, length);
                }
            } while(this.GotoNextKey());
        }

        return true;
    }

    // given a node, determine the map that is to be played.  This can either
    // be an actual map in the "map" key or it may be a random map from a map
    // group specified by the "group" key
    // return false if a map cannot be determined
    public bool DetermineMap(const char[] node, char[] map, int length, MapGroups groups=null,
            StringMap cache=null, MapHistory history=null)
    {
        // simply return the map value if it exists
        if (this.GetMap(node, map, length))
        {
            return true;
        }

        // if group key exists and given a MapGroups structure get a random map
        // from the map group
        char group[MAX_KEY_LENGTH];
        bool found = this.GetValueOfKeyOfNode(node, "group", group, sizeof(group));
        if (found && groups != null && groups.GetRandomMapFromGroup(
                    group, map, length, cache, history))
        {
            return true;
        }

        return false;
    }

    // perform an iteration from node to it's next node while return the new
    // map and updating the corresponding MapHistory
    // updates the node and map fields to the nextnode and nextmap
    // return false if we are unable to iterate
    public bool Iterate(char[] node, int nlength, char[] map, int mlength, MapGroups groups=null,
            StringMap cache=null, MapHistory history=null)
    {
        if (!this.DetermineNextNode(node, node, nlength)) return false;
        if (!this.DetermineMap(node, map, mlength, groups, cache, history)) return false;

        return true;
    }

    // from the given node iterate through the rotation a given number of time
    // and return a list of maps
    public ArrayList GetNextItems(const char[] node, int amount, MapGroups groups,
            StringMap cache, bool as_nodes=false, bool show_title=true)
    {
        ArrayList items = new ArrayList(ByteCountToCells(MAX_KEY_LENGTH));
        StringMap visited_groups = new StringMap();

        char currentnode[MAX_KEY_LENGTH], currentitem[MAX_KEY_LENGTH], group[MAX_KEY_LENGTH];
        char title[MAX_KEY_LENGTH];
        bool has_group;
        int junk;

        // iterate over a copy of node so we do not modify it
        strcopy(currentnode, sizeof(currentnode), node);

        // traverse the dmr graph getting the map that would be selected with
        // current server conditions
        for(int i = 0; i < amount; i++)
        {
            this.Iterate(currentnode, sizeof(currentnode), currentitem,
                    sizeof(currentitem), groups, cache);

            // NOTE:  This is to handle the case where multiple of the same map
            // group appear in a row.  We cache the randomized result so it is
            // impossible to know what the random map will be past the first
            // iteration.  Instead we simply display the map group past the
            // first iteration.
            has_group = this.GetGroup(currentnode, group, sizeof(group));
            if (has_group)
            {
                if (visited_groups.GetValue(group, junk))
                {
                    // we have seen and cached this group; display group name
                    // instead of map
                    strcopy(currentitem, sizeof(currentitem), group);

                }
                else
                {
                    // this is a new group, record that we have visited this
                    // group and display the cached map name
                    visited_groups.SetValue(group, 1);
                }
            }

            // use node id instead of map if requested
            if (as_nodes)
            {
                strcopy(currentitem, sizeof(currentitem), currentnode);
            }

            // append the title if it is requested and exists
            if (show_title && this.GetTitle(currentnode, title, sizeof(title)))
            {
                Format(currentitem, sizeof(currentitem), "%s (%s)", currentitem, title);
            }

            // add to return array
            items.PushString(currentitem);
        }

        delete visited_groups;

        return items;
    }

    public void Validate(MapGroups groups)
    {
        char val[MAX_KEY_LENGTH], key[MAX_KEY_LENGTH], section[MAX_KEY_LENGTH];

        // test that a "start" key exists in the dmr file
        if(!this.GetStartNode(val, sizeof(val)))
        {
            PrintToServer("[rotation_file] missing a \"start\" key.");
        }

        KeyValues tester = new KeyValues("rotation");

        this.Rewind();
        tester.Import(this);

        if(this.GotoFirstSubKey())
        {
            do
            {
                this.GetSectionName(section, sizeof(section));

                // test that it has either a "map" or a "group" key
                if(!(this.KeyExists("map") || this.KeyExists("group")))
                {
                    LogMessage("[rotation_file] node \"%s\" is missing either a \"map\" or \"group\" key.", section);
                }

                // test that it does not have both a "map" and "group" key
                if(this.KeyExists("map") && this.KeyExists("group"))
                {
                    LogMessage("[rotation_file] node \"%s\" has both a \"map\" and \"group\" key.  It only needs one.", section);
                }

                // if a map; test that the map is valid
                if(this.KeyExistsAndCopy("map", val, sizeof(val)) && !IsMapValid(val))
                {
                    LogMessage("[rotation_file] node \"%s\" has a \"map\" key that points to a map that does not exist on the server. (\"%s\")", section, val);
                }

                // if a group; test that the group is valid
                groups.Rewind();
                if(this.KeyExistsAndCopy("group", val, sizeof(val)) && !groups.JumpToKey(val))
                {
                    LogMessage("[rotation_file] node \"%s\" has a \"group\" key that points to a map group that does not exist. (\"%s\")", section, val);
                }

                // test that a "default_nextnode" key exists in the dmr file
                if(!this.KeyExists("default_nextnode"))
                {
                    LogMessage("[rotation_file] node \"%s\" is missing a \"default_nextnode\" key.", section);
                }

                // test that the "default_nextnode" node is an actual node in
                // the dmr file
                this.GetString("default_nextnode", val, sizeof(val));
                tester.Rewind();
                if(!(tester.JumpToKey(val)))
                {
                    LogMessage("[rotation_file] node \"%s\" has a \"default_nextnode\" key that points to a node that does not exist. (\"%s\")", val, section);
                }

                // for each additional node branch test that it is a valid node
                if(this.GotoFirstSubKey())
                {
                    do
                    {
                        this.GetSectionName(key, sizeof(key));

                        // test that the "default_nextnode" node is an actual
                        // node in the dmr file
                        tester.Rewind();
                        if( !(tester.JumpToKey(key)) )
                        {
                            LogMessage("[rotation_file] node \"%s\" has a conditional branching node that does not exist. (\"%s\")", key, section);
                        }

                    } while(this.GotoNextKey());
                }
                this.GoBack();

            } while(this.GotoNextKey());
        }

        delete tester;
    }
}
