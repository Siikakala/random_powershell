[CmdletBinding()]
param(
    [ValidateScript({ Test-Path $_ })]
    [string]
    $ParametersFile = ".\parameters.psd1",
    [int]
    $ThreadMaxStarts = 5,
    [switch]
    $Confirm
)
#region Init
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
[console]::TreatControlCAsInput = $true
if ($DebugPreference -eq "Inquire" -and -not $Confirm.IsPresent) {
    # -Debug present but -Confirm is not, suppress debug confirmations
    $DebugPreference = "Continue"
}

try{
    # Add M2Mqtt dependency library
    Add-Type -Path "$PSScriptRoot\M2MQTT\M2Mqtt.Net.dll" -ErrorAction Stop

    # Import custom formatting
    Update-FormatData -AppendPath "$PSScriptRoot\M2MQTT\PSMQTT.Format.ps1xml" -ErrorAction Stop
}catch{
    Write-Error "Could not load MQTT client library, $($_.Exception.Message)"
    exit 1
}

class PSMQTTMessage
{
    [string]$Topic
    [string]$Payload
    [byte[]]$PayloadUTF8ByteA
    [datetime]$Timestamp
    [boolean]$DupFlag
    [int]$QosLevel
    [boolean]$Retain

    PSMQTTMessage(
        [string]$Topic,
        [string]$Payload
    )
    {
        $this.Topic = $Topic
        $this.Payload = $Payload
        $this.PayloadUTF8ByteA = [System.Text.Encoding]::UTF8.GetBytes($Payload)
        $this.Timestamp = (Get-Date)
    }

    PSMQTTMessage(
        [System.Management.Automation.PSEventArgs]$EventObject
    )
    {
        $this.Topic = $EventObject.SourceEventArgs.Topic
        $this.Payload = [System.Text.Encoding]::ASCII.GetString($EventObject.SourceEventArgs.Message)
        $this.PayloadUTF8ByteA = $EventObject.SourceEventArgs.Message
        $this.DupFlag = $EventObject.SourceEventArgs.DupFlag
        $this.QosLevel = $EventObject.SourceEventArgs.QosLevel
        $this.Retain = $EventObject.SourceEventArgs.Retain
        $this.Timestamp = $EventObject.TimeGenerated
    }

    [string] ToString ()
    {
        return ($this.Topic + ';' + $this.Payload)
    }

}

if ($ThreadMaxStarts -isnot [int]) {
    $ThreadMaxStarts = 10
}

$paramkeys = "LogPath", "LogFilePrefix", "LogFileDateSyntax", "LogRetentionDays", "EdgeBridgeIP", "EdgeBridgePort", "AudioButtonActions", "AudioDuckButtons", "ComputerName", "AudioDevicesHeadphones", "ProcessesWatcher", "AudioDevicesSpeakers", "LanTriggers"
$params = Import-PowerShellDataFile $ParametersFile
if ($paramkeys | Where-Object { $_ -notin $params.keys }) {
    Write-Error "Parameter file doesn't have all required keys ($($paramkeys -join ", "))"
    exit 2
}
if (-not (Test-Path $params.LogPath -PathType Container)) {
    Write-Error "Log path '$($params.LogPath)' does not exist or access is denied!"
    exit 3
}
# Initialize log rotating - this ensures it happens when script starts.
$LatestLogRotate = Get-Date -Date 0
# Yeaaaah, there's other ways to detect and remove possible trailing slash but I find this most elegant. It also verifies the path second time.
$LogPath = (Get-Item $params.LogPath).Target[0]
if ($null -eq $LogPath) {
    Write-Error "Logpath null, please check"
    exit 4
}
#endregion
#region Main loop only functions
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        $line
    )
    $file = $LogPath + "\" + $params.LogFilePrefix + (Get-Date).ToString($params.LogFileDateSyntax) + ".log"

    $i = 0
    do {
        $failed = $false
        try {
            Add-Content -Path $file -Value $line -ErrorAction Stop
        }
        catch {
            $failed = $true
            Start-Sleep -Milliseconds 5
        }
        $i++
    }while ($failed -and $i -lt 10)
    Write-Verbose $line
}
function Remove-OldLogs {
    # "Rotate" isn't approved verb and we are actually removing things so, Remove- it is then

    # There isn't "RemoveDays" - you add negative integer, hence this madness. This also handles bad parameter input as it will give error if it's not a number AND converts & rounds it to integer if it's not
    if ([int] $params.LogRetentionDays -gt 0) {
        $Retention = 0 - [int] $params.LogRetentionDays
    }
    else {
        $Retention = [int] $params.LogRetentionDays
    }
    $RetentionPeriod = (Get-Date).AddDays($Retention)

    # I hate that you can't use -Filter with Get-ChildItem for anything else than name.
    Write-Log "[Remove-OldLogs] Logpath: $($LogPath)"
    Get-ChildItem -Path $LogPath -File | ForEach-Object -Process {
        if ($_.LastWriteTime -lt $RetentionPeriod) {
            Write-Log "[Remove-OldLogs] Removing: $_"
            $_ | Remove-Item
        }
    }
}
#endregion
#region Threads code block
$functions = {
    param(
        $thread,
        $config,
        $queue,
        $params
    )
    <# HELPERS #>

    #region LanTrigger
    function Use-LanTrigger {
        param($which)
        $parameters = $global:params
        # This is calling Tod Austin's LanTrigger utility running on my rpi, which is triggering momentary virtual button presses in SmartThings, triggering automations
        # https://github.com/toddaustin07/lantrigger
        $uri = "http://{0}:{1}/{2}_{3}/trigger" -f $parameters.EdgeBridgeIP, $parameters.EdgeBridgePort, $parameters.ComputerName, ($parameters.LanTriggers.$which -join "-")
        Write-Information "[Use-LanTrigger] Calling 'Invoke-WebRequest $uri -Method Post -DisableKeepAlive'"
        Invoke-WebRequest $uri -Method Post -DisableKeepAlive | Out-Null
    }
    #endregion
    #region Voicemeeter buttons
    function Set-VoicemeeterButton {
        param(
            $call,
            $caller,
            [switch] $HandleMusicDucking
        )
        $parameters = $global:params
        # This is just a wrapper for easier call handling
        $VMcall = @{
            command = "SetButtonState"
            args    = foreach ($action in @($parameters.AudioButtonActions.$call)) {
                @{
                    Button  = $action.Button
                    State   = $action.State
                    Trigger = $null
                }
            }
        }
        $DisableDuck = foreach ($button in $parameters.AudioDuckButtons) {
            @{
                Button  = $button
                Trigger = $false
                State   = $null
            }
        }
        $EnableDuck = foreach ($button in $parameters.AudioDuckButtons) {
            @{
                Button  = $button
                Trigger = $true
                State   = $null
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
    #endregion
    #region Control messages
    function Invoke-ControlMessage {
        param(
            $command
        )
        switch ($command) {
            "suspend" {
                $PowerState = [System.Windows.Forms.PowerState]::Suspend
                Write-Information "[Invoke-ControlMessage] !! SUSPENDING SYSTEM !!"
                [System.Windows.Forms.Application]::SetSuspendState($PowerState, $false, $false) # powerstate, force, disable wake?
            }
        }
    }
    #endregion

    <# THREAD FUNCTIONS #>
    #region Process watcher
    function Invoke-ProcessWatcher {
        $parameters = $global:params
        $q = $global:queue
        $threadconf = ($global:config).($global:thread)
        $message = $null
        $WatcherProcesses = $parameters.ProcessesWatcher
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
    #endregion
    #region Voicemeeter
    function Invoke-VoicemeeterControl {
        $parameters = $global:params
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
                                    command = "ReturnVolume"
                                    args    = @{
                                        Trigger = "$($arg.type)$($arg.index)Level"
                                        Value   = ($vmr.($arg.type)[$arg.index]).gain
                                    }
                                }
                            }
                        }
                        "GetMode" {
                            $Mode = switch ($vmr.bus[0].device.name) {
                                ($parameters.AudioDevicesSpeakers) {
                                    "Speakers"
                                }
                                ($parameters.AudioDevicesHeadphones) {
                                    "Headphones"
                                }
                            }
                            $return = @{
                                command = "ReturnMode"
                                args    = @{
                                    Mode = $Mode
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
                    # Let's not process everything _too_ fast
                    Start-Sleep -Milliseconds 50
                }
            }

            # Handle changes - every 200ms might be bit excessive but like I care.
            $A1Level = $vmr.bus[0].gain
            if ($A1Level -ne $previousA1Level -and $A1Level -ne -60) {
                Write-Information "A1 volume changed $previousA1Level dB -> $A1Level dB - informing Sender"
                $q.TryAdd([PSCustomObject]@{
                        To      = "Sender"
                        From    = "Voicemeeter"
                        Payload = @{
                            command = "ChangedVolume"
                            args    = @{
                                Trigger = "bus0Level"
                                Value   = $A1Level
                            }
                        }
                    })
                $global:config.Sender.DataWaiting = $true
                $previousA1Level = $A1Level
            }

            $Mode = switch ($vmr.bus[0].device.name) {
                    ($parameters.AudioDevicesSpeakers) {
                    "Speakers"
                }
                    ($parameters.AudioDevicesHeadphones) {
                    "Headphones"
                }
            }
            if ($Mode -ne $previousMode) {
                Write-Information "Mode changed $previousMode -> $Mode - informing Sender"
                $q.TryAdd([PSCustomObject]@{
                        To      = "Sender"
                        From    = "Voicemeeter"
                        Payload = @{
                            command = "ChangedMode"
                            args    = @{
                                Mode = $Mode
                            }
                        }
                    })
                $global:config.Sender.DataWaiting = $true
                $previousMode = $Mode
                Write-Information "Setting MacroButtons id 0 state to False"
                $vmr.button[0].state = $false
            }

            # I'm still alive!
            $threadconf.Heartbeat = Get-Date
            Start-Sleep -Milliseconds 200
        }
        Disconnect-Voicemeeter
        if (-not $threadconf.Enabled) {
            Write-Information "Exit requested."
        }
    }
    #endregion
    #region Receiver
    function Invoke-Listener {
        $parameters = $global:params
        $com = $parameters.ComputerName
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
                            Write-Information "- Voicemeeter mode change, calling 'Set-VoicemeeterButton -call $payload -caller Receiver'"
                            Set-VoicemeeterButton -call $payload -caller Receiver
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
    #endregion
    #region Sender
    function Invoke-Sender {
        $parameters = $global:params
        $com = $parameters.ComputerName
        $q = $global:queue
        $threadconf = ($global:config).($global:thread)
        $conf = Get-Content c:\mqttx\mqttx-cli-config.json -Raw | ConvertFrom-Json
        $stopwatch = [System.Diagnostics.Stopwatch]::new()
        $previousA1Level = -60
        Write-Information "Starting sender thread - Thread enabled: $($threadconf.Enabled)"
        :outer while ($threadconf.Enabled) {
            for ($i = 0; $i -lt 300; $i++) {
                # Extremely hack-y way of doing things in intervals but whatever, I regret nothing! x)
                # One complete while($true) loop takes 5 minutes, and these actions are taken in roughly once per second. Different actions during it takes a bit of time so using
                # stopwatch and 1 second "offset" in milliseconds to adjust the sleep time at the end
                $stopwatch.Restart()
                $offset = 1000
                $message = $null
                if ($i % 20 -eq 0) {
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
                        Write-Information "Received $($message.Payload.Command) from $($message.From)"
                        if ($q.IsEmpty) {
                            $threadconf.DataWaiting = $false
                        }
                    }
                }
                if ($i % 60 -eq 0) {
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
                    switch -Regex ($message.Payload.Command) {
                        "(Changed|Return)Volume" {
                            if ($message.Payload.args.Trigger -eq "bus0Level") {
                                if ($message.Payload.args.Value -ne $previousA1Level) {
                                    Write-Information "Sending MQTT message '$($message.Payload.args.Value)' to topic '$com/status/sound/A1Level'"
                                    c:\mqttx\mqttx.exe pub -h $conf.pub.hostname -u $conf.pub.username -P $conf.pub.password -t "$com/status/sound/A1Level" -m $message.Payload.args.Value | Out-Null
                                    $previousA1Level = $message.Payload.args.Value
                                }
                                else {
                                    Write-Information "A1 level stayed unchanged"
                                }
                            }
                        }
                        "(Changed|Return)Mode" {
                            Write-Information "Sound mode changed to '$($message.Payload.args.Mode)' - Calling actions"
                            Write-Information " - Calling 'Use-LanTrigger Mode-$($message.Payload.args.Mode)'"
                            Use-LanTrigger "Mode-$($message.Payload.args.Mode)"
                            Write-Information " - Sending MQTT message '$($message.Payload.args.Mode)' to topic '$com/status/sound/mode'"
                            c:\mqttx\mqttx.exe pub -h $conf.pub.hostname -u $conf.pub.username -P $conf.pub.password -t "$com/status/sound/mode" -m $message.Payload.args.Mode | Out-Null
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
    #endregion
    Write-Information "Starting $thread - loading parameters and invoking $($config.$thread.Function)"
    $config.$thread.Heartbeat = Get-Date
    Invoke-Expression $config.$thread.Function
}
#endregion
#region Variable initialization
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
#endregion
#region Main loop
Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", " !! STARTING MAIN THREAD !!")
$ctrlc = $false
while ($true) {
    #region CTRL-C reading
    if ([console]::KeyAvailable) {
        $key = [system.console]::readkey($true)
        if (($key.modifiers -band [consolemodifiers]"control") -and ($key.key -eq "C")) {
            Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Ctrl-C pressed, requesting quit")
            $ctrlc = $true
        }
    }
    #endregion
    #region Log rotate and lifetime checks
    # Handle log rotating (roughly) once per day
    if ((Get-Date) -gt $LatestLogRotate.AddDays(1)) {
        Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Rotating logs")
        # !! NOTE: This is blocking operation !!
        Remove-OldLogs
        $LatestLogRotate = Get-Date
    }

    # This could be more elegant but it works, so, whatever
    $TooManyStarts = $Config.keys | Where-Object { $Config.$_.Starts -gt $ThreadMaxStarts }
    if ($TooManyStarts.count -gt 0) {
        Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Thread start count limit of $ThreadMaxStarts exceeded by $($TooManyStarts.count) thread$(if($TooManyStarts -ne 1){"s"}) - Requesting quit.")
        $ctrlc = $true
    }

    if ($ctrlc) {
        Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Requesting threads to stop within 5s")
        foreach ($thread in $ChildJobs.Keys) {
            $Config.$thread.Enabled = $false
        }
        Start-Sleep -Seconds 5
        Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Stopping child threads")
        $ChildJobs.Keys | ForEach-Object {
            Write-Log ("{0,38}{1}" -f "", " - $_")
            $ChildJobs.$_.instance.Stop()
        }
        Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Receiving child job outputs for the last time")
    }
    #endregion
    #region Read thread output
    # Check and process child job messages and if the process had hung
    $msgs = ""
    foreach ($thread in $ChildJobs.Keys) {
        $infos = $false
        $infos = $ChildJobs.$thread.instance.Streams.Information
        if ($infos) {
            $msgs = $infos -split "`n"
            foreach ($msg in $msgs) {
                Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.$thread)$thread", $msg)
            }
        }
        try {
            $ChildJobs.$thread.instance.Streams.ClearStreams()
        }
        catch {}
    }
    #endregion
    #region Thread starter
    foreach ($thread in $ChildJobs.Keys) {
        $nothung = $true
        if ($null -ne $Config.$thread.Heartbeat -and $Config.$thread.Heartbeat -lt (Get-Date).AddMinutes(-1)) {
            # Thanks to MQTT heartbeat, even receiver thread will update it's heartbeat often enough - or then the broker is nonfuntional
            Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Detected hung thread $thread - latest heartbeat $([System.Math]::Round(((Get-Date) - $Config.$thread.Heartbeat).TotalMinutes, 1)) minutes ago. Disposing")
            $ChildJobs.$thread.instance.Dispose()
            $nothung = $false
        }
        if ($null -eq $ChildJobs.$thread.instance -or ($ChildJobs.$thread.instance.InvocationStateInfo.State.ToString() -ne "Running" -and $ctrlc -eq $false)) {
            if ($nothung -and $null -ne $ChildJobs.$thread.instance.InvocationStateInfo.State) {
                Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Cleaning up previous $thread thread")
                $ChildJobs.$thread.instance.Dispose()
            }
            $Config.$thread.Starts += 1
            Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Starting $thread thread (start $($Config.$thread.Starts))")
            $ChildJobs.$thread.instance = [powershell]::Create()
            $ChildJobs.$thread.instance.RunspacePool = $pool
            $ChildJobs.$thread.instance.AddScript($functions) | Out-Null
            $argslist = @{
                thread = $thread
                queue  = $queue
                config = $Config
                params = $params
            }
            $ChildJobs.$thread.instance.AddParameters($argslist) | Out-Null
            $ChildJobs.$thread.handle = $ChildJobs.$thread.instance.BeginInvoke()
        }
    }
    #endregion
    if ($ctrlc) {
        Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Removing child threads and breaking main thread")
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
Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main)MAIN", "Clean-up complete, exit.")
#endregion
exit 0
