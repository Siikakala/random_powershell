# DM tools
Here lies scripts for easier DMing
## FaerunCalendarTracker
You can keep track of time with this script. It's mainly meant to be companion script for TouchPortal, hence, it doesn't produce output without `-Passthru`
It can handle more fancy Waterdeep-flavoured output too. Please see `Get-Help .\FaerunCalendarTracker.ps -Detailed` for details but as an example:
```
  -------------------------- EXAMPLE 2 --------------------------

    PS C:\>.\FaerunCalendarTracker.ps1 -Date "1337-7-30 23:59" -WaterdeepFlavour -PassThru

    Set date to 30th Flamerule 1337 DR, one minute to midnight. Will also output the generated text:

    It's Nightfall. The day of love (10th, Sune) of third tenday of Flamerule of the year of the Wandering Maiden.
    ::
    Nightfall (23:59).
    30th Flamerule 1337 DR
    ::::1337-7-30 23:59
```