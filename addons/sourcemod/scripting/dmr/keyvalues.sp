#define MAX_KEY_LENGTH 128

/**
  Custom KeyValues class with additional functions
 */
methodmap DMRKeyValues < KeyValues
{
    public DMRKeyValues(const char[] name, const char[] firstKey="", const char[] firstValue="")
    {
        return view_as<DMRKeyValues>(new KeyValues(name, .firstKey=firstKey, .firstValue=firstValue));
    }

    // tests if a key value exists
    public bool KeyExists(const char[] key)
    {
        return this.GetDataType(key) != KvData_None;
    }

    // same as KeyExists but also copy the string value into val if it exists
    public bool KeyExistsAndCopy(const char[] key, char[] val, int length)
    {
        return this.GetString(key, val, length, "") && strlen(val) > 0;
    }

}
