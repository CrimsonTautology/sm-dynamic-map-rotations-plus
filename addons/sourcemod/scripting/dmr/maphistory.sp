methodmap MapHistory < ArrayList
{
    public MapHistory()
    {
        return view_as<MapHistory>(
                new ArrayList(ByteCountToCells(MAX_KEY_LENGTH))
                );
    }

    // TODO:  I don't know how sourcemod arrays are implemented and
    // FindStringInArray may be O(n).  It may be better to maintain a separate
    // existence trie to check against to be more efficient.
    public bool WasMapRecentlyPlayed(const char[] map)
    {
        return this.FindString(map) >= 0;
    }

    public void PushMap(const char[] map, int limit)
    {
        this.PushString(map);

        if (this.Length > limit)
        {
            this.Erase(0);
        }	
    }
}
