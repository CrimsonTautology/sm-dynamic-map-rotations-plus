methodmap MapGroups < DMRKeyValues
{
    public MapGroups(const char[] name="map_groups", const char[] firstKey="", const char[] firstValue="")
    {
        return view_as<MapGroups>(new DMRKeyValues(name, .firstKey=firstKey, .firstValue=firstValue));
    }

    public bool GetRandomMapFromGroup(const char[] group, char[] map, int length, StringMap cache=null, MapHistory history=null)
    {
        // we only need to do a randomization once, see if we have a cached value
        if (cache != null && cache.GetString(group, map, length)) return true;

        char testmap[MAX_KEY_LENGTH];
        int rand, count=0, history_count=0;
        bool found = false, using_history = false;

        this.Rewind();

        if (this.JumpToKey(group))
        {
            this.GotoFirstSubKey();

            // use reservoir sampling to get a random map from group
            // NOTE: We maintain two seperate reservoirs to prevent previously
            // played maps from being randomly selected. We assume first that
            // they are all recently played and use the first resevoir but once
            // we find one that is not recently played we switch over to the
            // second resevoir. Also note that we use two seperate counts to
            // maintain equal distribution for our random selection.
            do
            {
                // test each map in this group
                this.GetSectionName(testmap, sizeof(testmap));

                // first we assume that all maps in this group are recently
                // played so we ignore history sample
                if (!using_history)
                {
                    count +=1;

                    if (count == 1) {
                        // allways at least return the first map
                        this.GetSectionName(map, length);

                    }
                    else
                    {
                        rand = GetRandomInt(0, count - 1);

                        if (rand == count - 1)
                        {
                            this.GetSectionName(map, length);
                        }
                    }
                }

                // if we find that the map we are testing was not recently
                // played then we can switch to history mode and ignore the
                // other sample.
                if (history != null && !history.WasMapRecentlyPlayed(testmap))
                {
                    using_history = true;  // switch to history mode
                    history_count += 1;

                    if (history_count == 1)
                    {
                        this.GetSectionName(map, length);
                    }
                    else
                    {
                        rand = GetRandomInt(0, history_count - 1);

                        if (rand == history_count - 1) {
                            this.GetSectionName(map, length);
                        }
                    }
                }

            } while(this.GotoNextKey());

            // cache the selected map
            if(cache != null) cache.SetString(group, map);

            found = true;
        }

        return found;
    }

    // validate the map groups file
    public void Validate()
    {
        char group[MAX_KEY_LENGTH], map[MAX_KEY_LENGTH];

        this.Rewind();
        if(this.GotoFirstSubKey())
        {
            // iterate every group in file
            do
            {
                this.GetSectionName(group, sizeof(group));

                if(this.GotoFirstSubKey())
                {
                    // iterate every map in group
                    do
                    {
                        this.GetSectionName(map, sizeof(map));

                        // test that this map is valid
                        if(!IsMapValid(map))
                        {
                            LogMessage("[map_groups_file] map \"%s\" in the group \"%s\" does not exist on this server.", map, group);
                        }

                    } while(this.GotoNextKey());
                }

                this.GoBack();
            } while(this.GotoNextKey());
        }
    }

}
