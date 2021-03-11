char DAYS_OF_WEEK[]= {'\0', 'm', 't', 'w', 'r', 'f', 's', 'u'};

int GetPlayerCount(bool is_admin=false)
{
    int count = 0;

    for(int i=1; i<=MaxClients; i++)
    {
        if (!IsClientInGame(i)) continue;
        if (IsFakeClient(i)) continue;
        if (is_admin && GetUserAdmin(i) == INVALID_ADMIN_ID) continue;

        count++;
    }

    return count;
}

int GetAdminCount()
{
    return GetPlayerCount(.is_admin=true);
}

/**
  Return  1 if given time is after current time
  0 if given time same as now
  -1 if given time is before current time
 */
int CompareTimeFromString(const char[] time)
{
    char tmp[2][8];

    ExplodeString(time, ":", tmp, 2, 8);
    int hour = StringToInt(tmp[0]);
    int minute = StringToInt(tmp[1]);

    return CompareTime(hour, minute);
}

/**
  Return  1 if given time is after current time
  0 if given time same as now
  -1 if given time is before current time
 */
int CompareTime(int hour, int minute)
{
    char tmp[16];

    FormatTime(tmp, sizeof(tmp), "%H");
    int hour_now = StringToInt(tmp);

    FormatTime(tmp, sizeof(tmp), "%M");
    int minute_now = StringToInt(tmp);

    if (hour > hour_now)
    {
        return 1;
    }else if (hour < hour_now)
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
bool CompareDayOfWeek(const char[] days)
{
    char tmp[16];

    FormatTime(tmp, sizeof(tmp), "%u");
    int day = StringToInt(tmp);
    Format(tmp, sizeof(tmp), "%s", DAYS_OF_WEEK[day]);

    return day > 0 && day < sizeof(DAYS_OF_WEEK) && StrContains(days, tmp) >= 0;
}
