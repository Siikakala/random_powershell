<#
.SYNOPSIS
Keep account of Harptos calendar. Mainly helper script for Touch Portal

.DESCRIPTION
I wrote the script for my own use, to get the Faerûn calendar info visible to Touch Portal.

When changing or setting date, script doesn't produce any output as that's the intended invocation from touch portal.
Instead it will write the info to text file, of which is defined in the parameters. It can handle fancier Waterdeep styled
output, or more straightforward, standard way.

.PARAMETER Date
Set initial date with this - it assumes sortable digits, yyyy-mm-dd hh:mm. Time is optional. For special days like Midsummer, use syntax yyyy <day name> hh:mm - again, time is optional

.PARAMETER Day
Change current day by adding or reducind days - positive integer walks time forward, negative backwards

.PARAMETER Month
Like Day, but for months

.PARAMETER Year
Like Day, but for years

.PARAMETER Hour
Like Day, but for hours

.PARAMETER Minute
Like Day, but for minutes

.PARAMETER Path
In which directory the data files resides. Defaults to C:\DnDCalendar

.PARAMETER FileName
Into which file in the directory defined in Path the actual data will be stored

.PARAMETER YearNames
For added flare, names of all the years in the calendar, which have names. JSON-file, place it in the directory defined in Path

.PARAMETER WaterdeepFlavour
Enable the more elaborate text output with this switch! It will also add info about Waterdeep major festivals to the output

.PARAMETER PassThru
Useful when debugging without Touch Portal. Will output the file contents to prompt as well.

.PARAMETER Current
Just get the current date. Supports WaterdeepFlavour - so you can easily see the difference

.EXAMPLE
.\FaerunCalendarTracker.ps1 -Current
Get the current date info

.EXAMPLE
.\FaerunCalendarTracker.ps1 -Date "1337-7-30 23:59" -WaterdeepFlavour -PassThru
Set date to 30th Flamerule 1337 DR, one minute to midnight. Will also output the generated text:

It's Nightfall. The day of love (10th, Sune) of third tenday of Flamerule of the year of the Wandering Maiden.
::
Nightfall (23:59).
30th Flamerule 1337 DR
::::1337-7-30 23:59

.EXAMPLE
.\FaerunCalendarTracker.ps1 -minute "+1" -WaterdeepFlavour
Add one minute to the current date, and write the output elaboratively. Note: Script will not produce any output to the screen!

.EXAMPLE
.\FaerunCalendarTracker.ps1 -day "+1"
Add one day to the current date. Note: Script will not produce any output to the screen!
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Set")]
    [ValidatePattern("(?<Date>(?<Year>[-]?\d{1,4})(-(?<Month>[012]{0,1}\d{1})-(?<Day>[0123]{0,1}\d{1})|([ ]?(?<SpecialDay>[[:alpha:][:punct:][:space:]]*))))[ ]?(?<Time>(?<Hour>[0123]{0,1}\d):(?<Minute>[0-5]\d))?")]
    [String]
    $Date,
    [Parameter(Mandatory = $false, ParameterSetName = "Adjust")]
    [ValidatePattern("^(([+-]\d+)|([0123]?\d)|([[:alpha:][:punct:][:space:]]*))$")]
    [String]
    $Day = $null,
    [Parameter(Mandatory = $false, ParameterSetName = "Adjust")]
    [ValidatePattern("^(([+-]\d+)|([012]?\d)|(Hammer|Alturiak|Ches|Tarsakh|Mirtul|Kythorn|Flamerule|Eleasis|Eleint|Marpenoth|Uktar|Nightal))$")]
    [String]
    $Month = $null,
    [Parameter(Mandatory = $false, ParameterSetName = "Adjust")]
    [ValidatePattern("[+-]?\d+")]
    [String]
    $Year = $null,
    [Parameter(Mandatory = $false, ParameterSetName = "Adjust")]
    [ValidatePattern("[+-]?\d+")]
    [String]
    $Hour = $null,
    [Parameter(Mandatory = $false, ParameterSetName = "Adjust")]
    [ValidatePattern("[+-]?\d+")]
    [String]
    $Minute = $null,
    [ValidateScript({ Test-Path $_ })]
    [String]
    $Path = "C:\DnDCalendar",
    [ValidateNotNullOrEmpty()]
    [String]
    $FileName = "Calendar.txt",
    [ValidateNotNullOrEmpty()]
    [String]
    $YearNames = "FaerunRollOfYears.json",
    [Switch]
    $WaterdeepFlavour,
    [Switch]
    $PassThru,
    [Parameter(Mandatory = $true, ParameterSetName = "Get")]
    [Switch]
    $Current
)

Write-Verbose "Loading year names from json file '$Path\$YearNames' and generating hashtable"
if (Test-Path -Path "$Path\$YearNames") {
    $RollOfYears = (Get-Content "$Path\$YearNames" | ConvertFrom-Json) | ForEach-Object { @(@{$_.year = $_.name }) }
}
else {
    Write-Warning "Couldn't load year names, outputs might be incorrect!"
}

Write-Verbose "Initializing variables"

# Used as [ref]
$test = $false

# There's no 0th month, so setting it empty
$MonthArray = @("", "Hammer", "Alturiak", "Ches", "Tarsakh", "Mirtul", "Kythorn", "Flamerule", "Eleasis", "Eleint", "Marpenoth", "Uktar", "Nightal")

# These days happen between months. Shieldmeet is leap day, next day after midsummer.
$SpecialDays = @{
    "Midwinter"         = @{Day = 31; After = 1 }
    "Greengrass"        = @{Day = 122; After = 4 }
    "Midsummer"         = @{Day = 213; After = 7 }
    "Shieldmeet"        = @{Day = 214; After = 7 }
    "Highharvestide"    = @{Day = 275; After = 9 }
    "Feast Of The Moon" = @{Day = 335; After = 11 }
}

Write-Verbose "Initializing functions"

Function New-FaerunDateHash {
    param(
        [String]
        $Date,
        [Switch]
        $WaterdeepFlavour
    )
    Write-Verbose "FUNC: Initialising variables"
    # As all 4 equinoxes have set days, defining now. Notation: month-day
    $equinoxes = @{
        "3-19"  = "Spring Equinox"
        "6-20"  = "Summer Solstice"
        "9-21"  = "Autumn Equinox"
        "12-20" = "Winter Solstice"
    }

    # Prepare the Waterdeep flavouring
    $WaterdeepWeekdayNames = @("", "sun", "moon", "mysteries", "justice", "the wild", "the book", "grain", "strife", "the dead", "love")
    $WaterdeepWeekdayGods = @("", "Lathander", "Selune", "Mystra", "Tyr", "Silvanus", "Oghma", "Chauntea", "Tempus", "Kelemvor", "Sune")
    # ..In addition to special days, equinoxes have different names. Date ranges as arrays with all individual days. Notation: month-day
    # Source: https://cityofsplendorsdungeonofmadness.obsidianportal.com/wikis/festivals-of-waterdeep
    $WaterdeepFestivals = @{
        "Wintershield"            = "1-1"
        "The Grand Revel"         = "2-14"
        "Fey Day"                 = "3-19"
        "Fleetswake"              = @("3-21", "3-22", "3-23", "3-24", "3-25", "3-26", "3-27", "3-28", "3-29", "3-30")
        "Waukeentide"             = @("4-1", "4-2", "4-3", "4-4", "4-5", "4-6", "4-7", "4-8", "4-9", "4-10")
        "The Plowing and Running" = @("5-6", "5-7", "5-8", "5-9")
        "Trolltide"               = "6-1"
        "Guildhall Day"           = "6-14"
        "Dragondown"              = "6-20"
        "Founders Day"            = "7-1"
        "Sornyn"                  = @("7-3", "7-4", "7-5")
        "Lliira's Night"          = "7-7"
        "Ahghairon's Day"         = "8-1"
        "Brightswords"            = "9-21"
        "Day of Wonders"          = "10-3"
        "Stoneshar"               = "10-7"
        "Reign of Misrule"        = "10-10"
        "Gods' Day"               = "10-15"
        "Liars' Night"            = "10-30"
        "Last Sheaf"              = "11-20"
        "Howldown"                = "12-11"
        "Simril"                  = "12-20"
    }

    Write-Verbose "FUNC: Preparing regex pattern"
    if ($WaterdeepFlavour.IsPresent) {
        $ValueArray = $WaterdeepFestivals.Keys + $SpecialDays.Keys
    }
    else {
        $ValueArray = $equinoxes.Values + $SpecialDays.Keys
    }
    $RegexSpecialDays = $ValueArray -join "|"

    Write-Verbose "FUNC: Parsing date with Regex"
    # Utilizing automatic $Matches variable. Setting output to null as this regex is identical to the ValidatePattern. I'm using "week", whereas Faerûnian would call it tenday
    $Date -match "(?<Date>(?<Year>[-]?\d{1,4})(-(?<Month>[012]{0,1}\d{1})-(?<Day>[0123]{0,1}\d{1})|([ ]?(?<SpecialDay>$($RegexSpecialDays)))))[ ]?(?<Time>(?<Hour>[0123]?\d):(?<Minute>[0-5]?\d))?" | Out-Null
    Write-Debug "Matches:`n$($Matches | Out-String)"
    if ($null -ne $Matches.Date) {
        Write-Verbose "FUNC: Found date '$($Matches.Date)', parsing data"
        Write-Verbose "FUNC: Converting year to positive integer for leap year checking"
        $intyear = $false
        if ([System.Int32]::TryParse($Matches.Year, [ref]$intyear)) {
            if ($intyear -lt 0) {
                Write-Verbose "      Negative year, converting"
                $intyear = $intyear * -1
            }
        }
        if ($intyear -eq 0) {
            Write-Verbose "      Year 0, setting leap year to false"
            $LeapYear = $false
        }
        else {
            $LeapYear = [DateTime]::IsLeapYear($intyear)
        }
        if ($null -ne $Matches.SpecialDay) {
            $Special = $true
            $Day = (Get-Culture).TextInfo.ToTitleCase($Matches.SpecialDay)
            if ($Matches.SpecialDay -eq "Shieldmeet" -and $LeapYear -eq $false) {
                Write-Error "Year $($Matches.Year) isn't leap year, cannot set date to Shieldmeet!" -ErrorAction Stop
                exit
            }
        }
        elseif ($null -ne $Matches.Day) {
            $Special = $false
            $Day = $Matches.Day
        }
        else {
            $Special = $false
            $Day = $null
        }
        if ($WaterdeepFlavour.IsPresent) {
            # Bit hack-y way of dropping the preceding zeros but..
            $CurrentFestival = ($WaterdeepFestivals.GetEnumerator() | Where-Object { $_.Value -contains "$([int]$Matches.Month)-$([int]$Matches.Day)" }).Name
        }
        else {
            $CurrentFestival = $equinoxes.$("$([int]$Matches.Month)-$([int]$Matches.Day)")
        }
        $DateHash = @{
            Day        = $Day
            Special    = $Special
            Month      = $null
            Year       = $Matches.Year
            LeapYear   = $LeapYear
            Week       = $null
            Weekday    = $null
            MonthName  = $null
            Hour       = $null
            Minute     = $null
            TimeOfDay  = $null
            Festival   = $CurrentFestival
            LongDate   = $null
            ShortDate  = $null
            Normalized = $null
        }

        if ($null -ne $Matches.Time) {
            Write-Verbose "FUNC: Found time '$($Matches.Time)'"
            $DateHash.Hour = $Matches.Hour
            $DateHash.Minute = "0$($Matches.Minute)".Substring($Matches.Minute.Length - 1, 2)
        }
        else {
            Write-Verbose "FUNC: No time found, defaulting to 0:00"
            $DateHash.Hour = "0"
            $DateHash.Minute = "00"
        }
        $TimeOfDay = switch ([int]$Matches.Hour) {
            0 { "Deepnight" }
            1 { "Thuldark" }
            2 { "Thuldark" }
            3 { "Thuldark" }
            4 { "Moondark" }
            5 { "Godswake" }
            6 { "Sunrise" }
            7 { "Harbright" }
            8 { "Mornbright" }
            9 { "Elsun" }
            10 { "Midmorn" }
            11 { "Highmorn" }
            12 { "Highsun" }
            13 { "Thulsun" }
            14 { "Thulsun, Waterclock time" }
            15 { "Tharsun" }
            16 { "Tharsun" }
            17 { "Tharsun" }
            18 { "Sunset" }
            19 { "Eventide" }
            20 { "Nightfall" }
            21 { "Nightfall, Candleglass time" }
            22 { "Nightfall" }
            23 { "Nightfall" }
        }
        $DateHash.TimeOfDay = $TimeOfDay

        Write-Verbose "FUNC: Populating hashtable"
        if (-not $Special) {
            $DateHash.Month = $Matches.Month
            $DateHash.Week = [System.Math]::Floor($Matches.Day / 10) + 1
            $DateHash.Weekday = $Matches.Day % 10
            if ($DateHash.Weekday -eq 0) {
                $DateHash.Weekday = 10
                $DateHash.Week--
            }
            $DateHash.MonthName = $MonthArray[$Matches.Month]
            $DateHash.ShortDate = "$(if($null -ne $DateHash.TimeOfDay){"$($DateHash.TimeOfDay) ($($DateHash.Hour):$($DateHash.Minute))`n"})$($DateHash.Day)$(switch($DateHash.Day){1 {"st"} 2 {"nd"} 3 {"rd"} default {"th"}}) $($DateHash.MonthName) $($DateHash.Year) DR$(if($null -ne $DateHash.Festival){"`n$($DateHash.Festival)"})"
            if ($WaterdeepFlavour.IsPresent) {
                # ..Yeah, inline madness, should be somewhat readable still though.
                $DateHash.LongDate = "$(if($null -ne $DateHash.TimeOfDay){"It's $($DateHash.TimeOfDay). "})The day of $($WaterdeepWeekdayNames[$DateHash.WeekDay]) ($($DateHash.WeekDay)$(switch($DateHash.Weekday){1 {"st"} 2 {"nd"} 3 {"rd"} default {"th"}}), $($WaterdeepWeekdayGods[$DateHash.WeekDay])) of $(switch($DateHash.Week){1 {"first"} 2 {"second"} 3 {"third"}}) tenday of $($DateHash.MonthName) of the year of $($RollOfYears.($DateHash.Year)).$(if($null -ne $DateHash.Festival){" It is $($DateHash.Festival) festival."})"
            }
            else {
                $DateHash.LongDate = "$(if($null -ne $DateHash.TimeOfDay){"It's $($DateHash.TimeOfDay). "})The $($DateHash.WeekDay)$(switch($DateHash.Weekday){1 {"st"} 2 {"nd"} 3 {"rd"} default {"th"}}) day of $(switch($DateHash.Week){1 {"first"} 2 {"second"} 3 {"third"}}) tenday of $($DateHash.MonthName) of the year of $($RollOfYears.($DateHash.Year)).$(if($null -ne $DateHash.Festival){" It is $($DateHash.Festival)."})"
            }
            $DateHash.Normalized = "$($DateHash.Year)-$($DateHash.Month)-$($DateHash.Day) $($DateHash.Hour):$($DateHash.Minute)"
        }
        else {
            $DateHash.LongDate = "$(if($null -ne $DateHash.TimeOfDay){"It's $($DateHash.TimeOfDay). "})The $($DateHash.Day) of the year of $($RollOfYears.($DateHash.Year))."
            $DateHash.ShortDate = "$(if($null -ne $DateHash.TimeOfDay){"$($DateHash.TimeOfDay) ($($DateHash.Hour):$($DateHash.Minute))`n"})The $($DateHash.Day) $($DateHash.Year) DR"
            $DateHash.Normalized = "$($DateHash.Year) $($DateHash.Day) $($DateHash.Hour):$($DateHash.Minute)"
        }
        Write-Verbose "FUNC: Parsed date:`nLong date:`n  $($DateHash.LongDate)`nShort date:`n  $($DateHash.ShortDate)"
    }
    if ($null -ne $DateHash) {
        Write-Verbose "FUNC: Date parsed, returning hashtable"
    }
    else {
        Write-Error "Parsing date was unsuccesful, please check the date you entered! (You entered: '$Date')" -ErrorAction Stop
        exit
    }
    return $DateHash
}


if ($Path.Substring($Path.Length - 1) -eq "\") {
    Write-Verbose "Found trailing \ from path, removing"
    $Path = $Path.Substring(0, $Path.Length - 1)
}

if (Test-Path -Path "$Path\$FileName") {
    $Mode = "Adjust"
    try {
        Write-Verbose "Trying to fetch datafile '$Path\$FileName' contents"
        $AllData = Get-Content -Path "$Path\$FileName" -Raw
    }
    catch {
        $err = $_
        Write-Error -Message "Couldn't get data file contents from path '$Path\$Filename'. Original error below." -ErrorAction Continue
        Write-Output ""
        throw $err
        exit
    }
}
else {
    $Mode = "Set"
    if (Test-Path -Path $Path) {
        Write-Verbose "Path '$Path' exists, but no datafile ($FileName) found. Going to write new datafile."
    }
    else {
        Write-Verbose "Path '$Path' doesn't exist, creating now. Also going to write new datafile."
        try {
            New-Item -Path $Path -ItemType Directory
        }
        catch {
            $err = $_
            Write-Error -Message "Couldn't create datapath '$Path'. Original error below." -ErrorAction Continue
            Write-Output ""
            throw $err
            exit
        }
    }
}

Write-Verbose "Mode: $Mode - ParameterSet: $($PSCmdlet.ParameterSetName)"

if ($PSCmdlet.ParameterSetName -eq "Get") {
    $Split = $AllData -split "::::"
    $DateHash = New-FaerunDateHash -Date $Split[1].trim() -WaterdeepFlavour:$WaterdeepFlavour.IsPresent
    Write-Host "$($DateHash.LongDate)`n::`n$($DateHash.ShortDate)`n::::$($DateHash.Normalized)"
}


if ($PSCmdlet.ParameterSetName -eq "Set") {
    Write-Verbose "Calling 'New-FaerunDateHash -Date $Date -WaterdeepFlavour:$($WaterdeepFlavour.IsPresent)'"
    $DateHash = New-FaerunDateHash -Date $Date -WaterdeepFlavour:$WaterdeepFlavour.IsPresent
    $Content = "$($DateHash.LongDate)`n::`n$($DateHash.ShortDate)`n::::$($DateHash.Normalized)"
    Write-Verbose "Writing content"
    Set-Content -Path "$Path\$FileName" -Value $Content -Force | Out-Null
}

if ($PSCmdlet.ParameterSetName -eq "Adjust") {
    if ($Mode -eq "Adjust") {
        $Split = $AllData -split "::::"
        Write-Verbose "Normalized data found from file: $($Split[1].trim())"
        Write-Debug "Human-readable: $($Split[0].trim())"
        Write-Verbose "Calling 'New-FaerunDateHash -Date $($Split[1].trim()) -WaterdeepFlavour:$($WaterdeepFlavour.IsPresent)'"
        $DateHash = New-FaerunDateHash -Date $Split[1].trim() -WaterdeepFlavour:$WaterdeepFlavour.IsPresent
    }
    if ($Mode -eq "Set") {
        if ($null -eq $Day -and ([System.Int32]::TryParse($Day, [ref]$test) -eq $true -and $null -eq $Month) -and $null -eq $Year) {
            Write-Error -Message "No previus data and mandatory parameters for setting date are missing. Please use -Date" -ErrorAction Stop
            exit
        }
        if ($null -eq $Hour) {
            Write-Verbose "Setting date in adjust mode - Hour null, defaulting to 0"
            $Hour = 0
        }
        if ($null -eq $Minute) {
            Write-Verbose "Setting date in adjust mode - Minute null, defaulting to 0"
            $Minute = 0
        }
        if ([System.Int32]::TryParse($Day, [ref]$test)) {
            $QueryDate = "$Year-$Month-$Day ${Hour}:$Minute"
        }
        else {
            $QueryDate = "$Year $Day ${Hour}:$Minute"
        }
        Write-Verbose "Calling 'New-FaerunDateHash -Date $QueryDate -WaterdeepFlavour:$($WaterdeepFlavour.IsPresent)'"
        $DateHash = New-FaerunDateHash -Date $QueryDate -WaterdeepFlavour:$WaterdeepFlavour.IsPresent
    }

    # Use current, our time date as reference point - setting the time to easier handling of days
    # Relative amount of time is the interesting part and I much rather use ready-made library than try to handle it by hand!
    $reference = Get-Date -Hour $DateHash.Hour -Minute $DateHash.Minute -Second 0 -Millisecond 0
    $referenceDayOfYear = $reference.DayOfYear
    $minuteDateDifference = 0
    if (-not [System.String]::IsNullOrEmpty($Minute)) {
        Write-Verbose "Adding $Minute minutes"
        $reference = $reference.AddMinutes($Minute)
        $minuteDateDifference += $reference.DayOfYear - $referenceDayOfYear
    }
    if (-not [System.String]::IsNullOrEmpty($Hour)) {
        Write-Verbose "Adding $Hour hours"
        $reference = $reference.AddHours($Hour)
        $minuteDateDifference += $reference.DayOfYear - $referenceDayOfYear
    }
    if (-not [System.String]::IsNullOrEmpty($Day)) {
        Write-Verbose "Adding $Day days"
        $reference = $reference.AddDays($Day)
    }
    if (-not [System.String]::IsNullOrEmpty($Month)) {
        Write-Verbose "Adding $Month months"
        # As all months are 30 days, and we are interested in relative change & handling special days separately, this is the way to go
        $intmonth = $false
        if ([System.Int32]::TryParse($Month, [ref]$intmonth)) {
            $reference = $reference.AddDays($intmonth * 30)
        }
    }
    if (-not [System.String]::IsNullOrEmpty($Year)) {
        Write-Verbose "Adding $Year years"
        $intyear = $false
        if ([System.Int32]::TryParse($Year, [ref]$intyear)) {
            $reference = $reference.AddDays($intyear * 365)
        }
    }

    # Calculate the relative change
    $TimeDifference = New-TimeSpan (Get-Date -Hour $DateHash.Hour -Minute $DateHash.Minute -Second 0 -Millisecond 0) $reference
    Write-Verbose "Time difference $($TimeDifference.TotalDays) days. Calculating day of the year."

    # Calculate the day in year in the Harptos calendar
    $DaysInPastMonths = ($DateHash.Month - 1) * 30
    if ($DateHash.Day -match "\d+") {
        $PreliminaryDayInYear = $DaysInPastMonths + $DateHash.Day
        Write-Verbose "Calculated day: $PreliminaryDayInYear - Calculating past special days"
        $SpecialDays.Keys | ForEach-Object {
            if ($Specialdays.$_.After -lt $DateHash.Month) {
                if ($_ -eq "Shieldmeet" -and $DateHash.LeapYear -ne $true) {
                    Write-Verbose "Not a leap year, ignoring Shieldmeet"
                }
                else {
                    Write-Verbose "$_ has past, adding a day"
                    $PreliminaryDayInYear++
                }
            }
        }
    }
    else {
        Write-Verbose "Current day is special day, getting known value"
        $PreliminaryDayInYear = $SpecialDays.($DateHash.Day).Day
    }
    Write-Verbose "Day of the year (before): $PreliminaryDayInYear"
    # Set the new time
    $NewMinute = $reference.Minute
    $NewHour = $reference.Hour
    # Add (or subtract) the day difference
    $PreliminaryDayInYear += $TimeDifference.Days
    $PreliminaryDayInYear += $minuteDateDifference
    Write-Verbose "Day of the year (after): $PreliminaryDayInYear"
    Write-Verbose "Checking if the year changed"
    # Check if the year changed
    $NewYear = $DateHash.Year
    while ($PreliminaryDayInYear -gt 365) {
        Write-Verbose "Current day more than 365."
        $intyear = $false
        if ([System.Int32]::TryParse($NewYear, [ref]$intyear)) {
            if ($intyear -lt 0) {
                Write-Verbose "  Negative year, converting"
                $intyear = $intyear * -1
            }
        }
        if ($intyear -eq 0) {
            Write-Verbose "  Year 0, setting leap year to false"
            $LeapYear = $false
        }
        else {
            $LeapYear = [DateTime]::IsLeapYear($intyear)
        }
        if ($PreliminaryDayInYear -eq 366 -and $LeapYear -eq $true) {
            Write-Verbose "366 days on a leap year - breaking the loop."
            break
        }
        else {
            Write-Verbose "Reducing 365 days and adding one year"
            $PreliminaryDayInYear -= 365
            $NewYear = [int]$NewYear + 1
            Write-Verbose "Current day: $PreliminaryDayInYear - Year: $NewYear"
        }
    }
    while ($PreliminaryDayInYear -lt 1) {
        Write-Verbose "Current day less than 1. Handling leap year check"
        $intyear = $false
        if ([System.Int32]::TryParse($NewYear, [ref]$intyear)) {
            if ($intyear -lt 0) {
                Write-Verbose "  Negative year, converting"
                $intyear = $intyear * -1
            }
        }
        if ($intyear -eq 0) {
            Write-Verbose "  Year 0, setting leap year to false"
            $LeapYear = $false
        }
        else {
            Write-Verbose "Checking if $intyear is leap year"
            $LeapYear = [DateTime]::IsLeapYear($intyear)
        }
        if ($PreliminaryDayInYear -eq 366 -and $LeapYear -eq $true) {
            Write-Verbose "366 days on a leap year - breaking the loop."
            break
        }
        else {
            Write-Verbose "Adding 365 days and reducing one year"
            $PreliminaryDayInYear += 365
            $NewYear = [int]$NewYear - 1
            Write-Verbose "Current day: $PreliminaryDayInYear - Year: $NewYear"
        }
    }

    $intyear = $false
    if ([System.Int32]::TryParse($NewYear, [ref]$intyear)) {
        if ($intyear -lt 0) {
            Write-Verbose "Negative year, converting leap year variable"
            $intyear = $intyear * -1
        }
    }
    if ($intyear -eq 0) {
        Write-Verbose "Year 0, setting leap year to false"
        $LeapYear = $false
    }
    else {
        Write-Verbose "Checking if $intyear is leap year and setting LeapYear variable"
        $LeapYear = [DateTime]::IsLeapYear($intyear)
    }

    # Did we land on special day?
    $WasSpecialDay = $false
    if ($SpecialDays.values.day -contains $PreliminaryDayInYear) {
        if ($SpecialDays.Shieldmeet.day -eq $PreliminaryDayInYear -and $LeapYear -eq $false) {
            Write-Verbose "Shieldmeet but not a leap year, continuing."
        }
        else {
            $NewDay = $SpecialDays.Keys | Where-Object { $SpecialDays.$_.Day -eq $PreliminaryDayInYear }
            $WasSpecialDay = $true
            Write-Verbose "Landed on special day, $NewDay"
        }
    }
    if (-not $WasSpecialDay) {
        Write-Verbose "Calculating date from the day of the year"
        # No, then handle the special cases.
        $SpecialDays.Keys | ForEach-Object {
            # Because of that damn leap day, each day shifts by one after Midsummer if it's not leap year. That's why less or equal
            if ($Specialdays.$_.Day -le $PreliminaryDayInYear) {
                if ($_ -eq "Shieldmeet" -and $LeapYear -ne $true) {
                    Write-Verbose "Not a leap year, ignoring Shieldmeet"
                }
                else {
                    Write-Verbose "$_ has past, removing a day"
                    $PreliminaryDayInYear--
                }
            }
        }

        # And finally calculate the new date!
        Write-Verbose "Calculating the date"
        $NewMonth = [System.Math]::Floor($PreliminaryDayInYear / 30) + 1
        $NewDay = $PreliminaryDayInYear % 30
        if ($NewDay -eq 0) {
            $NewDay = 30
            $NewMonth--
        }
        Write-Verbose "Day: $NewDay, Month: $NewMonth"
    }
    if ([System.Int32]::TryParse($NewDay, [ref]$test)) {
        $QueryDate = "$NewYear-$NewMonth-$NewDay ${NewHour}:$NewMinute"
    }
    else {
        $QueryDate = "$NewYear $NewDay ${NewHour}:$NewMinute"
    }
    Write-Verbose "Calling 'New-FaerunDateHash -Date $QueryDate -WaterdeepFlavour:$($WaterdeepFlavour.IsPresent)'"
    $NewDateHash = New-FaerunDateHash -Date $QueryDate -WaterdeepFlavour:$WaterdeepFlavour.IsPresent
    $Content = "$($NewDateHash.LongDate)`n::`n$($NewDateHash.ShortDate)`n::::$($NewDateHash.Normalized)"
    Set-Content -Path "$Path\$FileName" -Value $Content -Force | Out-Null
}
if ($PassThru.IsPresent) {
    Write-Host $Content
}