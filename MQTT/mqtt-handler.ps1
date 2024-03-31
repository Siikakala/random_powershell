[CmdletBinding()]
param(
    $ComputerName = "tennoji",
    $ThreadMaxStarts = 20,
    [switch]
    $Confirm
)
[console]::TreatControlCAsInput = $true
if ($DebugPreference -eq "Inquire" -and -not $Confirm.IsPresent) {
    # -Debug present but -Confirm is not, suppress debug confirmations
    $DebugPreference = "Continue"
}

if (-not (Test-Path C:\mqttx\mqttx.exe)) {
    Write-Error "mqttx cli client not found from path C:\mqttx\mqttx.exe. Please download from https://mqttx.app/cli#download"
    exit
}

$functions = {
    param(
        $thread,
        $config,
        $queue,
        $ComputerName
    )
    <# HELPERS #>

    function Use-LanTrigger {
        param($which)
        # This is calling Tod Austin's LanTrigger utility running on my rpi, which is triggering momentary virtual button presses in SmartThings, triggering automations
        # https://github.com/toddaustin07/lantrigger
        $uriTemplate = "http://172.20.1.225:8090/{0}/trigger"
        $uri = switch ($which) {
            "obs64-start" {
                $uriTemplate -f "tennoji_scene-webcam"
            }
            "obs64-stop" {
                $uriTemplate -f "tennoji_scene-computer"
            }
            "RemotePlay-start" {
                $uriTemplate -f "tennoji_scene-computer"
            }
            "RemotePlay-stop" {
                $uriTemplate -f "tennoji_scene-computer"
            }
            "GeforceNOW-start" {
                $uriTemplate -f "tennoji_scene-computer"
            }
            "GeforceNOW-stop" {
                $uriTemplate -f "tennoji_scene-computer"
            }
            "Mode-Speakers" {
                $uriTemplate -f "Tennoji_speakers-on"
            }
            "Mode-Headphones" {
                $uriTemplate -f "Tennoji_speakers-off"
            }
        }
        Invoke-WebRequest $uri -Method Post -DisableKeepAlive | Out-Null
    }
    function Set-VoicemeeterButton {
        param(
            $call,
            $caller,
            [switch] $HandleMusicDucking
        )
        # This is just a wrapper for easier call handling
        $VMcall = @{
            command = "SetButtonState"
            args    = @{
                Button = -1
                State  = $false
            }
        }
        $DisableDuck = @(
            @{
                Button  = 4
                Trigger = $false
            },
            @{
                Button  = 5
                Trigger = $false
            },
            @{
                Button  = 14
                Trigger = $false
            },
            @{
                Button  = 23
                Trigger = $false
            }
        )
        $EnableDuck = @(
            @{
                Button  = 4
                Trigger = $true
            },
            @{
                Button  = 5
                Trigger = $true
            },
            @{
                Button  = 14
                Trigger = $true
            },
            @{
                Button  = 23
                Trigger = $true
            }
        )
        switch ($call) {
            "RemotePlay-start" {
                $VMcall.args.Button = 15 # Music to -15 dB
                $VMcall.args.State = $true
            }
            "RemotePlay-stop" {
                $VMcall.args.Button = 15
                $VMcall.args.State = $false
            }
            "GeforceNOW-start" {
                $VMcall.args.Button = 25 # Music to -25 dB
                $VMcall.args.State = $true
            }
            "GeforceNOW-stop" {
                $VMcall.args.Button = 25
                $VMcall.args.State = $false
            }
        }
        if ($VMcall.args.Button -ne -1) {
            if ($HandleMusicDucking.IsPresent) {
                if ($call -match "^.*?-start$") {
                    $argsArray = $DisableDuck + $VMcall.args
                }
                else {
                    $argsArray = $EnableDuck + $VMcall.args
                }
                $VMcall.args = $argsArray
            }
            # Valid call, adding message to queue
            $q.TryAdd([PSCustomObject]@{
                    To      = "Voicemeeter"
                    From    = $caller
                    Payload = $VMcall
                })
            $global:config.Voicemeeter.DataWaiting = $true
        }
    }
    function Invoke-ControlMessage {
        param(
            $command
        )
        switch ($command) {
            "suspend" {
                $PowerState = [System.Windows.Forms.PowerState]::Suspend
                [System.Windows.Forms.Application]::SetSuspendState($PowerState, $false, $false) # powerstate, force, disable wake?
            }
        }
    }

    <# THREAD FUNCTIONS #>
    function Invoke-ProcessWatcher {
        $q = $global:queue
        $threadconf = ($global:config).($global:thread)
        $message = $null
        $WatcherProcesses = @(
            @{
                Process       = "obs64"
                Actions       = @("Use-LanTrigger")
                UnlessRunning = @()
            },
            @{
                Process       = "RemotePlay"
                Actions       = @(
                    "Use-LanTrigger"
                    "Set-VoicemeeterButton -HandleMusicDucking -caller ProcessWatcher -call"
                )
                UnlessRunning = @("obs64")
            },
            @{
                Process       = "GeforceNow"
                Actions       = @(
                    "Use-LanTrigger"
                    "Set-VoicemeeterButton -HandleMusicDucking -caller ProcessWatcher -call"
                )
                UnlessRunning = @("obs64")
            }
        )
        $ProcsWereRunning = @()
        $ProcsSeen = @()
        while ($threadconf.Enabled) {
            if ($threadconf.DataWaiting -and $q.TryDequeue([ref]$message)) {
                # Not really used to anything yet but just to be consistent
                if ($message.To -ne "ProcessWatcher") {
                    Write-Information "Received message for another thread, pushing back to queue"
                    $q.TryAdd($message)
                }
                else {
                    Write-Information "Received from $($message.From)"
                    if ($q.IsEmpty) {
                        $threadconf.DataWaiting = $false
                    }
                }
            }
            $ProcsRunning = @()
            foreach ($proc in $WatcherProcesses) {
                if ($null -ne (Get-Process $proc.Process -ErrorAction SilentlyContinue)) {
                    $ProcsRunning += $proc.Process
                    if ($proc.Process -notin $ProcsSeen) {
                        $ProcsSeen += $proc.Process
                    }
                    if ($proc.Process -notin $ProcsWereRunning) {
                        $blockers = $proc.UnlessRunning | Where-Object { $_ -in $ProcsWereRunning }
                        if ($blockers.count -gt 0) {
                            Write-Information "$($proc.Process) started running - found proceses running which are in UnlessRunning ($($blockers -join ", ")), SKIPPING ACTIONS"
                        }
                        else {
                            Write-Information "$($proc.Process) started running - running Actions"
                            foreach ($action in $proc.Actions) {
                                Write-Information " - Calling '$action $($proc.Process)-start'"
                                Invoke-Expression "$action $($proc.Process)-start"
                            }
                        }
                    }
                }
                else {
                    if ($proc.Process -notin $ProcsWereRunning -and $proc.Process -in $ProcsSeen) {
                        $blockers = $proc.UnlessRunning | Where-Object { $_ -in $ProcsWereRunning }
                        if ($blockers.count -gt 0) {
                            Write-Information "$($proc.Process) has stopped - found proceses running which are in UnlessRunning ($($blockers -join ", ")), SKIPPING ACTIONS"
                        }
                        else {
                            Write-Information "$($proc.Process) has stopped - running Actions"
                            foreach ($action in $proc.Actions) {
                                Write-Information " - Calling '$action $($proc.Process)-stop'"
                                Invoke-Expression "$action $($proc.Process)-stop"
                            }
                        }
                        # Removing items from array is bit annoying, so.. This is also faster if the array is big, which it isn't.
                        $ProcsSeen = $ProcsSeen | ForEach-Object { if ($_ -ne $proc.Process) { $_ } }
                        if ($null -eq $ProcsSeen) {
                            # None of the processes are running so re-initializing array
                            $ProcsSeen = @()
                        }
                    }
                }
            }
            $ProcsWereRunning = $ProcsRunning

            # I'm still alive!
            $threadconf.Heartbeat = Get-Date
            Start-Sleep -Milliseconds 250
        }
        if (-not $threadconf.Enabled) {
            Write-Information "Exit requested - quiting."
        }
    }
    function Invoke-VoicemeeterControl {
        $q = $global:queue
        $threadconf = ($global:config).($global:thread)
        $message = $null
        Import-Module Voicemeeter
        Write-Information "Connecting to Voicemeeter Potato - Thread enabled: $($threadconf.Enabled)"
        $vmr = Connect-Voicemeeter -Kind "potato"
        $previousA1Level = -60
        $previousMode = "?"
        while ($threadconf.Enabled) {
            if ($threadconf.DataWaiting -and $q.TryDequeue([ref]$message)) {
                if ($message.To -ne "Voicemeeter") {
                    Write-Information "Received message for another thread, pushing back to queue"
                    $q.TryAdd($message)
                }
                else {
                    Write-Information "Received command $($message.payload.command) from $($message.From)"
                    if ($q.IsEmpty) {
                        $threadconf.DataWaiting = $false
                    }
                }
                $params = $message.payload.args
                $return = $null
                foreach ($arg in @($params)) {
                    # Typical case is that there's only one set of payload but this way the handling is identical regardless how much there was
                    switch ($message.payload.command.trim()) {
                        "SwitchMode" {
                            # Button state API calls are latching even with push buttons, so handling the both directions at once. Also reason why this is separate command.
                            switch ($arg.Mode) {
                                "Speakers" {
                                    # This MacroButton's button loads Voicemeeter configuration with my M-Track ASIO driver as A1 output device, to which my speakers are connected to
                                    Write-Information "Setting MacroButtons id 11 state to True for 100ms"
                                    $vmr.button[11].state = $true
                                    Start-Sleep -Milliseconds 100
                                    $vmr.button[11].state = $false
                                    Write-Information "Setting MacroButtons id 0 state to False"
                                    $vmr.button[0].state = $false
                                }
                                "Headphones" {
                                    # This MacroButton's button loads Voicemeeter configuration with my Bluetooth headphones as A1 output device. In the case headphones aren't connected,
                                    # Voicemeeter ends up in engine error state and lets go all wake locks for audio devices, potentially allowing computer to sleep
                                    Write-Information "Setting MacroButtons id 10 state to True for 100ms"
                                    $vmr.button[10].state = $true
                                    Start-Sleep -Milliseconds 100
                                    $vmr.button[10].state = $false
                                    Write-Information "Setting MacroButtons id 0 state to False"
                                    $vmr.button[0].state = $false
                                }
                            }
                        }
                        "SetButtonState" {
                            # With this approach you can either change button state or if it should act on trigger - or both. Both trigger and state are boooleans
                            # !! NOTE: THIS API CALL IS LATCHING EVEN IF THE BUTTON ITSELF ISN'T! You MUST set state back to false by yourself! !!
                            if ($null -ne $arg.Button -and $null -ne $arg.State) {
                                # Setting button state according to call
                                Write-Information "Setting MacroButtons id $($arg.Button) state to $($arg.State)"
                                $vmr.button[$arg.Button].state = $arg.State
                            }
                            if ($null -ne $arg.Button -and $null -ne $arg.Trigger) {
                                # Setting button trigger state according to call
                                Write-Information "Setting MacroButtons id $($arg.Button) trigger to $($arg.Trigger)"
                                $vmr.button[$arg.Button].trigger = $arg.trigger
                            }
                        }
                        "SetVolume" {
                            if ($null -ne $arg.index -and $null -ne $arg.type -and $null -ne $arg.level) {
                                <#
                    # This looks *very* confusing, so let me break it out:
                    #
                    # $vmr = voicemeeter C API
                    # $arg.type = device type, either strip (=input) or bus (=output)
                    # $arg.index = index of the device, starting from 0. bus[0] = A1; strip[1] = second strip from the left
                    # $arg.level = level to which the method call will face to, in milliseconds defined in second parameter (=200ms)
                    #
                    # Things in parenthesis before method call will be resolved first, so the string value of $arg.type will be
                    # converted to point to specific array in the API, as it's type was string. Then the index will be populated to
                    # select the object inside the array. Then the FadeTo method of that object will be called with the level as first
                    # parameter. Yes, this is slightly abusing the Powershell engine for greated modularity. It also depends on
                    # Voicemeeter's C API input sanitization as payload is passed directly to it. But I'm the one using this,
                    # I'm not too concerned about bad input.
                    #
                    # So, this MQTT call payload:
                    # {
                    #   "command": "SetVolume",
                    #   "args": {
                    #       "type": "bus",
                    #       "index": 0,
                    #       "level": -27
                    #   }
                    # }
                    # will be converted to this call:
                    # $vmr.bus[0].FadeTo(-27, 200)
                    # #>
                                Write-Information "Calling `$vmr.$($arg.type)[$($arg.index)].FadeTo($($arg.level), 200)"
                                $vmr.($arg.type)[$arg.index].FadeTo($arg.level, 200) | Out-Null
                            }
                        }
                        "GetVolume" {
                            if ($null -ne $arg.index -and $null -ne $arg.type) {
                                # See explanation above, though this is requesting info, not setting it. Slider value is returned in 'gain' property
                                Write-Information "Calling `$vmr.$($arg.type)[$($arg.index)].gain"
                                $return = @{
                                    Trigger = "A1Level"
                                    Value   = ($vmr.($arg.type)[$arg.index]).gain
                                }
                            }
                        }
                        "GetMode" {
                            $return = switch ($vmr.bus[0].device.name) {
                                "M-Track Quad ASIO Driver" {
                                    "Speakers"
                                }
                                "Headphones (MOMENTUM 4 Stereo)" {
                                    "Headphones"
                                }
                            }
                        }
                    }
                    if ($null -ne $return) {
                        # Thanks to tue queue this works predictably even when the arguments is actual array
                        $q.TryAdd([PSCustomObject]@{
                                To      = $message.From
                                From    = "Voicemeeter"
                                Payload = $return
                            })
                        $global:config.($message.From).DataWaiting = $true
                    }
                }
            }
            else {
                if ((Get-Date).Second % 2 -eq 0) {
                    # Handle changes
                    $A1Level = $vmr.bus[0].gain
                    if ($A1Level -ne $previousA1Level -and $A1Level -ne -60) {
                        Write-Information "A1 volume changed $previousA1Level dB -> $A1Level dB - informing Sender"
                        $q.TryAdd([PSCustomObject]@{
                                To      = "Sender"
                                From    = "Voicemeeter"
                                Payload = @{
                                    Trigger = "A1Level"
                                    Value   = $A1Level
                                }
                            })
                        $global:config.Sender.DataWaiting = $true
                        $previousA1Level = $A1Level
                    }

                    $Mode = switch ($vmr.bus[0].device.name) {
                        "M-Track Quad ASIO Driver" {
                            "Speakers"
                        }
                        "Headphones (MOMENTUM 4 Stereo)" {
                            "Headphones"
                        }
                    }
                    if ($Mode -ne $previousMode) {
                        Write-Information "Mode changed $previousMode -> $Mode - informing Sender"
                        $q.TryAdd([PSCustomObject]@{
                                To      = "Sender"
                                From    = "Voicemeeter"
                                Payload = @{
                                    Trigger = "Mode"
                                    Value   = $Mode
                                }
                            })
                        $global:config.Sender.DataWaiting = $true
                        $previousMode = $Mode
                        Write-Information "Setting MacroButtons id 0 state to False"
                        $vmr.button[0].state = $false
                    }
                }
            }
            # I'm still alive!
            $threadconf.Heartbeat = Get-Date
            Start-Sleep -Milliseconds 100
        }
        Disconnect-Voicemeeter
        if (-not $threadconf.Enabled) {
            Write-Information "Exit requested."
        }
    }

    function Invoke-Listener {
        $com = $global:ComputerName
        $q = $global:queue
        $threadconf = ($global:config).($global:thread)
        $payload = $null
        Write-Information "Connecting to MQTT - Thread enabled: $($threadconf.Enabled)"
        C:\mqttx\mqttx.exe sub --config C:\mqttx\mqttx-cli-config.json | ForEach-Object -Process {
            # The json object is pretty printed and pipe is consuming the data row-by-row so gather the whole message first
            $data = $null
            $msg += $_
            if ($_ -match "^}$") {
                $data = $msg | ConvertFrom-Json
                $msg = ""
            }
            if (-not [string]::IsNullOrEmpty($data)) {
                $payload = $false
                try {
                    $payload = $data.payload | ConvertFrom-Json -ErrorAction Stop
                }
                catch {}
                if ($payload -eq $false) {
                    $payload = $data.payload
                }
                if (-not [string]::IsNullOrWhiteSpace($payload)) {
                    Write-Information "Message to topic $($data.topic):`n$(($payload | Format-List | Out-String).Trim())"
                    switch ($data.topic) {
                        "$com/control" {
                            Write-Information "- Control, calling 'Invoke-ControlMessage $payload'"
                            Invoke-ControlMessage $payload
                        }
                        "$com/control/sound" {
                            Write-Information "- Voicemeeter, queuing payload"
                            $q.TryAdd([PSCustomObject]@{
                                    To      = "Voicemeeter"
                                    From    = "Listener"
                                    Payload = $payload
                                })
                            $global:config.Voicemeeter.DataWaiting = $true
                        }
                        "$com/heartbeat" {
                            Write-Information "- Heartbeat"
                        }
                        "$com/meta/mainvolume" {
                            Write-Information "- Voicemeeter A1 volume control, queuing payload"
                            $q.TryAdd([PSCustomObject]@{
                                    To      = "Voicemeeter"
                                    From    = "Listener"
                                    Payload = @{
                                        command = "SetVolume"
                                        args    = @{
                                            type  = "bus"
                                            index = 0
                                            level = $payload
                                        }
                                    }
                                })
                            $global:config.Voicemeeter.DataWaiting = $true
                        }
                        "$com/meta/soundmode" {
                            Write-Information "- Voicemeeter mode change to $payload, queuing payload"
                            $q.TryAdd([PSCustomObject]@{
                                    To      = "Voicemeeter"
                                    From    = "Listener"
                                    Payload = @{
                                        command = "SwitchMode"
                                        args    = @{
                                            Mode = $payload
                                        }
                                    }
                                })
                            $global:config.Voicemeeter.DataWaiting = $true
                        }
                    }
                }
                else {
                    Write-Information "Got unprocessable data:`n$data"
                }
            }
            if (-not $threadconf.Enabled) {
                Write-Information "Exit requested - trying to quit."
                break
            }
            # I'm still alive!
            $threadconf.Heartbeat = Get-Date
        }
        Write-Information "Disconnected"
    }
    function Invoke-Sender {
        $com = $global:ComputerName
        $q = $global:queue
        $threadconf = ($global:config).($global:thread)
        $conf = Get-Content c:\mqttx\mqttx-cli-config.json -Raw | ConvertFrom-Json
        $stopwatch = [System.Diagnostics.Stopwatch]::new()
        $previousA1Level = -60
        Write-Information "Starting sender thread - Thread enabled: $($threadconf.Enabled)"
        :outer while ($threadconf.Enabled) {
            for ($i = 0; $i -lt 150; $i++) {
                # Extremely hack-y way of doing things in intervals but whatever, I regret nothing! x)
                # One complete while($true) loop takes 5 mintes, and these actions are taken in roughly once per two secnds. Different actions during it takes a bit of time so using
                # stopwatch and 2 second "offset" in milliseconds to adjust the sleep time at the end
                $stopwatch.Restart()
                $offset = 2000
                $message = $null
                if ($i % 10 -eq 0) {
                    #This happens once in 20 seconds
                    Write-Information "Sending heartbeat to MQTT"
                    c:\mqttx\mqttx.exe pub -h $conf.pub.hostname -u $conf.pub.username -P $conf.pub.password -t "$com/heartbeat" -m (Get-Date).toString("yyyy-MM-dd HH:mm:ss") | Out-Null
                }
                if ($threadconf.DataWaiting -and $q.TryDequeue([ref]$message)) {
                    if ($message.To -ne "Sender") {
                        Write-Information "Received message for another thread, pushing back to queue"
                        $q.TryAdd($message)
                    }
                    else {
                        Write-Information "Received message from $($message.From)"
                        if ($q.IsEmpty) {
                            $threadconf.DataWaiting = $false
                        }
                    }
                }
                if ($i % 30 -eq 0) {
                    # This happens once a minute
                    Write-Information "Requesting current A1 level from Voicemeeter"
                    $call = @{
                        command = "GetVolume"
                        args    = @{
                            type  = "bus"
                            index = 0
                        }
                    }
                    $q.TryAdd([PSCustomObject]@{
                            To      = "Voicemeeter"
                            From    = "Sender"
                            Payload = $call
                        })
                    $global:config.Voicemeeter.DataWaiting = $true
                }
                if ($null -ne $message) {
                    switch ($message.Payload.Trigger) {
                        "A1Level" {
                            if ($message.Payload.Value -ne $previousA1Level) {
                                Write-Information "Sending MQTT message '$($message.Payload.Value)' to topic '$com/status/sound/A1Level'"
                                c:\mqttx\mqttx.exe pub -h $conf.pub.hostname -u $conf.pub.username -P $conf.pub.password -t "$com/status/sound/A1Level" -m $message.Payload.Value | Out-Null
                                $previousA1Level = $message.Payload.Value
                            }
                            else {
                                Write-Information "A1 level stayed unchanged"
                            }
                        }
                        "Mode" {
                            Write-Information "Sound mode changed to '$($message.Payload.Value)' - Calling actions"
                            Write-Information " - Calling 'Use-LanTrigger Mode-$($message.Payload.Value)'"
                            Use-LanTrigger "Mode-$($message.Payload.Value)"
                            Write-Information " - Sending MQTT message '$($message.Payload.Value)' to topic '$com/status/sound/mode'"
                            c:\mqttx\mqttx.exe pub -h $conf.pub.hostname -u $conf.pub.username -P $conf.pub.password -t "$com/status/sound/mode" -m $message.Payload.Value | Out-Null
                        }
                    }
                }

                # Sleep handling
                $stopwatch.Stop()
                $offset -= $stopwatch.ElapsedMilliseconds
                Write-Debug "  [$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))]   SEND: loop $i, sleeping ${offset}ms"
                if ($offset -gt 0) {
                    Start-Sleep -Milliseconds $offset
                }

                if (-not $threadconf.Enabled) {
                    Write-Information "Exit requested - breaking outer look."
                    break outer
                }

                # I'm still alive!
                $threadconf.Heartbeat = Get-Date
            }
        }
        # There's tiiiiiny race condition - if the exit request has gone past the inner loop for the last time BUT main loop hasn't yet started new, you might drop out without output
        if (-not $threadconf.Enabled) {
            Write-Information "Exiting"
        }
    }
    Write-Information "Starting $thread - invoking $($config.$thread.Function)"
    $config.$thread.Heartbeat = Get-Date
    Invoke-Expression $config.$thread.Function
}
$pool = [runspacefactory]::CreateRunspacePool(1, 4)
$pool.open()
$ChildJobs = @{
    Sender         = @{
        instance = $null
        handle   = $null
    }
    Receiver       = @{
        instance = $null
        handle   = $null
    }
    Voicemeeter    = @{
        instance = $null
        handle   = $null
    }
    #<#
    ProcessWatcher = @{
        instance = $null
        handle   = $null
    }
    # #>
}

$Config = [hashtable]::Synchronized(@{
        Sender         = @{
            Enabled     = $true
            Function    = "Invoke-Sender"
            DataWaiting = $false
            Heartbeat   = $null
            Starts      = 0
        }
        Receiver       = @{
            Enabled     = $true
            Function    = "Invoke-Listener"
            DataWaiting = $false
            Heartbeat   = $null
            Starts      = 0
        }
        Voicemeeter    = @{
            Enabled     = $true
            Function    = "Invoke-VoicemeeterControl"
            DataWaiting = $false
            Heartbeat   = $null
            Starts      = 0
        }
        ProcessWatcher = @{
            Enabled     = $true
            Function    = "Invoke-ProcessWatcher"
            DataWaiting = $false
            Heartbeat   = $null
            Starts      = 0
        }
    })
$Queue = [System.Collections.Concurrent.ConcurrentQueue[psobject]]::new()
# Padding to center text into the placeholder
$Padding = @{
    Sender         = "    " #4
    Receiver       = "   " #3
    Voicemeeter    = " " #1
    ProcessWatcher = ""
    Main           = "     " #5
}
$TimeStamp = { (Get-Date).toString("yyyy-MM-dd HH:mm:ss") }
$OutputTemplate = "[{0}][{1,-14}] {2}"
#$Streams = @("Debug", "Error", "Information", "Verbose", "Warning")

Write-Verbose ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Starting main thread")
$ctrlc = $false
while ($true) {
    if ([console]::KeyAvailable) {
        $key = [system.console]::readkey($true)
        if (($key.modifiers -band [consolemodifiers]"control") -and ($key.key -eq "C")) {
            Write-Verbose ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Ctrl-C pressed, requesting quit")
            $ctrlc = $true
        }
    }
    # This could be more elegant but it works, so, whatever
    $TooManyStarts = $Config.keys | Where-Object{$Config.$_.Starts -gt $ThreadMaxStarts}
    if($TooManyStarts.count -gt 0){
        Write-Verbose ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Thread start count limit of $ThreadMaxStarts exceeded by $($TooManyStarts.count) thread$(if($TooManyStarts -ne 1){"s"}) - Requesting quit.")
        $ctrlc = $true
    }
    if ($ctrlc) {
        Write-Verbose ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Requesting threads to stop within 5s")
        foreach ($thread in $ChildJobs.Keys) {
            $Config.$thread.Enabled = $false
        }
        Start-Sleep -Seconds 5
        Write-Verbose ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Stopping child threads")
        $ChildJobs.Keys | ForEach-Object {
            Write-Verbose ("{0,38}{1}" -f "", " - $_")
            $ChildJobs.$_.instance.Stop()
        }
        Write-Verbose ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Receiving child job outputs for the last time")
    }
    $msgs = ""
    # Check and process child job messages and if the process had hung
    foreach ($thread in $ChildJobs.Keys) {
        $infos = $false
        $infos = $ChildJobs.$thread.instance.Streams.Information
        if ($infos) {
            $msgs = $infos -split "`n"
            foreach ($msg in $msgs) {
                Write-Verbose ($OutputTemplate -f (&$TimeStamp), "$($Padding.$thread)$thread", $msg)
            }
        }
        try {
            $ChildJobs.$thread.instance.Streams.ClearStreams()
        }
        catch {}

        if ($null -ne $Config.$thread.Heartbeat -and $Config.$thread.Heartbeat -lt (Get-Date).AddMinutes(-1)) {
            # Thanks to MQTT heartbeat, even receiver thread will update it's heartbeat often enough - or then the broker is nonfuntional
            Write-Verbose ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Detected hung thread $thread - latest heartbeat $([System.Math]::Round(((Get-Date) - $Config.$thread.Heartbeat).TotalMinutes, 1)) minutes ago. Disposing")
            $ChildJobs.$thread.instance.Dispose()
        }
    }

    foreach ($thread in $ChildJobs.Keys) {
        if ($null -eq $ChildJobs.$thread.instance -or ($ChildJobs.$thread.instance.InvocationStateInfo.State.ToString() -ne "Running" -and $ctrlc -eq $false)) {
            if ($null -ne $ChildJobs.$thread.instance.InvocationStateInfo.State) {
                Write-Verbose ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Cleaning up previous $thread thread")
                $ChildJobs.$thread.instance.Dispose()
            }
            $Config.$thread.Starts += 1
            Write-Verbose ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Starting $thread thread (start $($Config.$thread.Starts))")
            $ChildJobs.$thread.instance = [powershell]::Create()
            $ChildJobs.$thread.instance.RunspacePool = $pool
            $ChildJobs.$thread.instance.AddScript($functions) | Out-Null
            $argslist = @{
                thread       = $thread
                queue        = $queue
                config       = $Config
                ComputerName = $ComputerName
            }
            $ChildJobs.$thread.instance.AddParameters($argslist) | Out-Null
            $ChildJobs.$thread.handle = $ChildJobs.$thread.instance.BeginInvoke()
        }
    }

    if ($ctrlc) {
        Write-Verbose ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Removing child threads and breaking main thread")
        foreach ($thread in $ChildJobs.Keys) {
            $ChildJobs.$thread.instance.Dispose()
        }
        $pool.close()
        $pool.Dispose()
        break
    }
    # Rather tight loop for ctrl-c handling
    Start-Sleep -Milliseconds 100
}
Write-Verbose ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Clean-up complete, exit.")
exit 0
