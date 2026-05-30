<#
.SYNOPSIS
Remote control Resolume Arena with OSC messages

.DESCRIPTION
Multifaceted and multithreaded script which can control Resolume Arena
with OSC messages. Receives commands via MQTT and YAML. MQTT delivers
just triggers, which are defined in YAML. MQTT can be disabled in configuration

YAML Syntax:
The syntax should be somewhat intuitive. There's common keys for both mqtt messages and schedules:
* action
    Defines what should be done. Currently supported values:
    * SelectClip
        Switches to the clip on the layer. Note: starts from 0, not 1
    * ClearLayer
        Clears the current clip on the layer. Value is ignored. Resolume seems to be bit picky about this though,
        I advice to create blank clip and select it with SelectClip
    * Opacity
        Layer opacity in percents
    * TransitionTime
        Layer transition time in milliseconds. 0 - 10s, rounded to 100ms
    * TriggerGroupColumn
        As SelectClip but trigger whole column of defined group. Group is defined in layer field
* layer
    Defines the layer or group to which the action is performed to
* value
    Raw value for OSC messages. Boolean-like values (on/off, true/false) are converted to integers automatically

MQTT triggers in YAML:
    Each topic is defined as key under main key mqtt. Different values for the topic are defined as array. Each
    array entry mush contain the 3 common keys, in addition of content-key, which is plain text content of the message,
    defining which entry of the array should be triggered. Multiple actions can be defined with multiple entries of same
    content-key.

Schedules in YAML:
    Simple array under main key schedule. Each entry has following keys in addition to the common ones:
    * name
        Free-text key for people. Not used in processing - just as a comment for what this trigger is for
    * time
        Timestamp recognized as Get-Date. Format is free as long as Get-Date can parse it. yyyy-MM-dd HH:mm:ss is strongly recommended.

Internal queue message:
[PSCustomObject]@{
    To      = <Thread name>
    From    = <current thread>
    Payload = @{
        command = <case for thread's switch>
        args    = @{
            <hashtable containing information for the specific command>
        }
    }
}

#>
[CmdletBinding()]
param(
    [ValidateScript({ Test-Path $_ })]
    [string]
    $ParametersFile = ".\parameters.psd1",
    [ValidateScript({ Test-Path $_ })]
    [string]
    $YamlFile = ".\config.yaml",
    [int]
    $ThreadMaxStarts = 5,
    [pscredential]
    $MqttCredential = $null,
    [switch]
    $Confirm
)
#region Init
$esc = "$([char]0x1b)"
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
[console]::TreatControlCAsInput = $true
if ($DebugPreference -eq "Inquire" -and -not $Confirm.IsPresent) {
    # -Debug present but -Confirm is not, suppress debug confirmations
    $DebugPreference = "Continue"
}

try {
    # Add M2Mqtt dependency library
    Add-Type -Path "$PSScriptRoot\M2MQTT\M2Mqtt.Net.dll" -ErrorAction Stop

    # Import custom formatting
    Update-FormatData -AppendPath "$PSScriptRoot\M2MQTT\PSMQTT.Format.ps1xml" -ErrorAction Stop
}
catch {
    Write-Error "Could not load MQTT client library, $($_.Exception.Message)"
    exit 1
}
try {
    # Add SharpOSC dependency library
    Add-Type -Path "$PSScriptRoot\SharpOSC\SharpOSC.dll" -ErrorAction Stop
}
catch {
    Write-Error "Could not load OSC client library, $($_.Exception.Message)"
    exit 1
}

Import-Module "$PSScriptRoot\powershell-yaml"

if ($ThreadMaxStarts -isnot [int]) {
    $ThreadMaxStarts = 10
}

$paramkeys = "LogPath", "LogFilePrefix", "LogFileDateSyntax", "LogRetentionDays", "MQTTEnabled", "MQTTBroker", "MqttUser", "MqttPassword", "ResolumeIP", "ResolumePort"
$params = Import-PowerShellDataFile $ParametersFile
if ($paramkeys | Where-Object { $_ -notin $params.keys }) {
    Write-Error "Parameter file doesn't have all required keys ($($paramkeys -join ", "))"
    exit 2
}
if (-not (Test-Path $params.LogPath -PathType Container)) {
    Write-Error "Log path '$($params.LogPath)' does not exist or access is denied!"
    exit 3
}
if ($null -eq $MqttCredential) {
    $MqttCredential = New-Object System.Management.Automation.PSCredential($params.MqttUser, (
            ConvertTo-SecureString $params.MqttPassword -AsPlainText -Force
        )
    )
}
$params.Add("MqttCredential", $MqttCredential)
# Initialize log rotating - this ensures it happens when script starts.
$LatestLogRotate = Get-Date -Date 0
# Yeaaaah, there's other ways to detect and remove possible trailing slash but I find this most elegant. It also verifies the path second time.
$LogPath = (Get-Item $params.LogPath).Target[0]
if ($null -eq $LogPath) {
    Write-Error "Logpath null, please check"
    exit 4
}
try {
    $yaml = ConvertFrom-Yaml (Get-Content $YamlFile -Raw -ErrorAction Stop) -ErrorAction Stop
}
catch {
    Write-Error "Could not load configuration YAML file, $($_.Exception.Message)"
    exit 5
}
if ($null -eq $yaml.mqtt -or $null -eq $yaml.schedule) {
    Write-Error "YAML file '$YamlFile' is missing main keys mqtt or schedule, please check"
    exit 6
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
        $params,
        $yaml
    )
    <# HELPERS #>
    #region MQTT functions
    function Connect-MQTTBroker {
        [CmdletBinding(DefaultParameterSetName = 'Anon')]
        param(
            [Parameter(Mandatory)]
            [string]
            $Hostname,
            [int]
            $Port,
            [Parameter(Mandatory, ParameterSetName = 'Auth')]
            [pscredential]
            $Credential,
            [switch]
            $TLS
        )
        # Use default ports if none are specified
        if (-not $PSBoundParameters['Port']) {
            if ($TLS) {
                $Port = 1884
            }
            else {
                $Port = 1883
            }
        }

        $MqttClient = New-Object -TypeName uPLibrary.Networking.M2Mqtt.MqttClient -ArgumentList $Hostname, $Port, $TLS, $null, $null, 'None'

        try {
            switch ($PSCmdlet.ParameterSetName) {
                'Anon' {
                    $MqttClient.Connect([guid]::NewGuid()) | Out-Null
                }
                'Auth' {
                    $MqttClient.Connect([guid]::NewGuid(), $Credential.Username, ($Credential.GetNetworkCredential().Password)) | Out-Null
                }
            }
        }
        catch {
            Write-Information "Couldn't connect to MQTT server: $($_.Exception.Message)"
        }
        return $MqttClient
    }

    function Disconnect-MQTTBroker {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [uPLibrary.Networking.M2Mqtt.MqttClient]
            $Session
        )
        $Session.Disconnect()
    }

    function Send-MQTTMessage {
        [cmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [uPLibrary.Networking.M2Mqtt.MqttClient]
            $Session,
            [Parameter(Mandatory)]
            [string]
            $Topic,
            [string]
            $Payload
        )

        try {
            # Publish message to MQTTBroker
            $Session.Publish($Topic, [System.Text.Encoding]::UTF8.GetBytes($Payload)) | Out-Null
        }
        catch {
            Write-Information "Couldn't send MQTT message: $($_.Exception.Message)"
        }
    }

    function Receive-MQTTMessage {
        param($EventObject)
        # This is callback handler
        $y = $global:yaml
        $q = $global:queue
        $data = @{
            topic   = $EventObject.SourceEventArgs.Topic
            payload = [System.Text.Encoding]::ASCII.GetString($EventObject.SourceEventArgs.Message)
        }

        $payload = $false
        try {
            $payload = $data.payload | ConvertFrom-Json -ErrorAction Stop
        }
        catch {}
        if ($payload -eq $false) {
            $payload = $data.payload
        }
        if (-not [string]::IsNullOrWhiteSpace($payload)) {
            $topic = $data.topic
            Write-Information "Message to topic $($topic):`n$(($payload | Format-List | Out-String).Trim())"
            $actions = $y.mqtt.$topic | Where-Object { $payload.Trim() -match $_.content }
            if ($null -ne $actions) {
                foreach ($action in $actions) {
                    $q.TryAdd([PSCustomObject]@{
                            To      = "ResolumeControl"
                            From    = "MQTTClient"
                            Payload = @{
                                command = "MQTT"
                                args    = @{
                                    Action = $action.action
                                    Layer  = $action.layer
                                    Value  = $action.value
                                }
                            }
                        })
                }
                $global:config.ResolumeControl.DataWaiting = $true
            }
        }
    }
    #endregion
    function Find-OSCAction {
        param (
            $action
        )
        switch ($action) {
            "SelectClip" { return "/composition/layers/{0}/connectspecificclip" }
            "ClearLayer" { return "/composition/layers/{0}/clear" }
            "Opacity" { return "/composition/layers/{0}/video/opacity" }
            "TransitionTime" { return "/composition/layers/{0}/transition/duration" }
            "TriggerGroupColumn" { return "/composition/groups/{0}/connectspecificcolumn" }
        }
    }

    <# THREAD FUNCTIONS #>
    #region Schedule watcher
    function Invoke-ScheduleWatcher {
        #$parameters = $global:params
        $y = $global:yaml
        $q = $global:queue
        $threadconf = ($global:config).($global:thread)
        $message = $null
        Write-Information "Loaded $($y.schedule.Count) scheduled tasks"
        while ($threadconf.Enabled) {
            if ($threadconf.DataWaiting -and $q.TryDequeue([ref]$message)) {
                # Not really used to anything yet but just to be consistent
                if ($message.To -ne "ScheduleWatcher") {
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
            foreach ($time in $y.schedule) {
                $ScheduleCheck = New-TimeSpan (Get-Date $time.time) (Get-Date)
                if (($null -eq $time.triggered -or $time.triggered -ne $true) -and ($ScheduleCheck.TotalMinutes -gt 0 -and $ScheduleCheck.TotalMinutes -lt 5)) {
                    # Scheduled time is here, hasn't been triggered yet and has past in less than 5 minutes ago - in case of script restarts or something
                    Write-Information "Triggering schedule '$($time.name)'"
                    foreach ($action in $time.actions) {
                        $q.TryAdd([PSCustomObject]@{
                                To      = "ResolumeControl"
                                From    = "ScheduleWatcher"
                                Payload = @{
                                    command = "Schedule"
                                    args    = @{
                                        Action = $action.action
                                        Layer  = $action.layer
                                        Value  = $action.value
                                    }
                                }
                            })
                        $global:config.ResolumeControl.DataWaiting = $true
                    }
                    $time.Add("triggered", $true)
                }


            }
            # I'm still alive!
            $threadconf.Heartbeat = Get-Date
            Start-Sleep -Seconds 1
        }
        if (-not $threadconf.Enabled) {
            Write-Information "Exit requested - quiting."
        }
    }
    #endregion
    #region Resolume Control
    function Invoke-ResolumeControl {
        $parameters = $global:params
        $q = $global:queue
        $threadconf = ($global:config).($global:thread)
        $message = $null
        Write-Information "Initializing OSC Sender"
        $OSCSender = New-Object SharpOSC.UDPSender $parameters.ResolumeIP, $parameters.ResolumePort
        while ($threadconf.Enabled) {
            if ($threadconf.DataWaiting -and $q.TryDequeue([ref]$message)) {
                if ($message.To -ne "ResolumeControl") {
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
                foreach ($command in $params) {
                    Write-Information "$($command.Action) to layer/group $($command.Layer) with value $($command.Value)"
                    # Bit unorthodoxic use of string formatting. As Layer/group information is inbetween the OSC message, this is easiest way
                    # This is the only approach to abstract away the layer/group information away and make additional triggers potentially easier
                    # TODO: Consider changing layer to target in YAML
                    $OSCAction = (Find-OSCAction $command.Action) -f $command.layer
                    if ($null -ne $OSCAction) {
                        if ($command.Value -isnot [int]) {
                            $OSCValue = switch ($command.Value) {
                                "on" { 1.0; break }
                                "off" { 0.0; break }
                                "true" { 1; break }
                                "false" { 0; break }
                                "null" { $null; break }
                                $true { 1; break }
                                $false { 0; break }
                                $null { $null; break }
                                default {
                                    Write-Information "ERR: Value $($command.Value) of $($command.Action) out of bounds! Source $($message.payload.Command). Defaulting to 0"
                                    0
                                    break
                                }
                            }
                        }
                        else {
                            $OSCValue = switch ($command.Action) {
                                "Opacity" {
                                    if ($command.Value -ge 0 -or $command.Value -le 100) {
                                        # Resolume expects float between 0 and 1. Input is percents
                                        $command.Value / 100
                                    }
                                    else {
                                        Write-Information "ERR: Value $($command.Action) of $($command.Action) out of bounds! Source $($message.payload.Command). Defaulting to 0"
                                        0
                                    }
                                }
                                "TransitionTime" {
                                    if ($command.Value -ge 0 -or $command.Value -le 10000) {
                                        # Resolume expects float between 0 and 1. Input is milliseconds
                                        [Math]::Round($command.Value / 1000000, 4) * 100
                                    }
                                    else {
                                        Write-Information "ERR: Value $($command.Action) of $($command.Action) out of bounds! Source $($message.payload.Command). Defaulting to 0"
                                        0
                                    }
                                }
                                default {
                                    $command.Value
                                }
                            }
                        }
                        if ($command.Action -match "ClearLayer") {
                            $OSCValue = $null
                        }
                        if ($null -eq $OSCValue) {
                            Write-Information "Sending OSC message '$OSCAction'"
                            $OSCMessage = New-Object SharpOSC.OscMessage $OSCAction
                            $OSCSender.Send($OSCMessage)
                        }
                        else {
                            Write-Information "Sending OSC message '$OSCAction' with value '$OSCValue'"
                            $OSCMessage = New-Object SharpOSC.OscMessage $OSCAction, $OSCValue
                            $OSCSender.Send($OSCMessage)
                        }
                    }
                    else {
                        Write-Information "ERR: Invalid OSC Action $($command.Action)"
                    }
                }
            }

            # I'm still alive!
            $threadconf.Heartbeat = Get-Date
            Start-Sleep -Milliseconds 500
            if (-not $threadconf.Enabled) {
                Write-Information "Exit requested."
            }
        }
    }
    #endregion
    #region Receiver
    function Invoke-MQTTClient {
        $parameters = $global:params
        $y = $global:yaml
        $threadconf = ($global:config).($global:thread)
        $q = $global:queue
        Write-Information "Connecting to MQTT"
        while ($threadconf.Enabled) {
            try {
                $Session = Connect-MQTTBroker -Hostname $parameters.MQTTBroker -Credential $parameters.MqttCredential
                $SourceIdentifier = [guid]::NewGuid()
                Register-ObjectEvent -InputObject $Session -EventName MqttMsgPublishReceived -SourceIdentifier $SourceIdentifier

                foreach ($Topic in $y.mqtt.Keys) {
                    $Session.Subscribe($Topic, 0) | Out-Null
                }

                while ($Session.IsConnected -and (Get-EventSubscriber -SourceIdentifier $SourceIdentifier)) {
                    $message = $null
                    if ($threadconf.DataWaiting -and $q.TryDequeue([ref]$message)) {
                        if ($message.To -ne "MQTTClient") {
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
                    try {
                        # Receive and process MQTT messages - offloaded to the Receive-MQTTMessage function
                        Get-Event -SourceIdentifier $SourceIdentifier -ErrorAction Stop | ForEach-Object {
                            Receive-MQTTMessage -EventObject $PSItem -queue $global:queue -config $global:config
                            Remove-Event -EventIdentifier $PSItem.EventIdentifier
                        }
                    }
                    catch {}

                    if ($null -ne $message) {
                        # Process any messages from queue which needs to be sent to MQTT
                        # !! There's no use for this currently, leaving as an example !!
                        switch -Regex ($message.Payload.Command) {
                            "NotImplemented" {
                                #Send-MQTTMessage -Session $Session -Topic "undefined" -Payload $message.Payload.args | Out-Null
                            }
                        }
                    }


                    if (-not $threadconf.Enabled) {
                        Write-Information "Exit requested - trying to quit."
                        break
                    }
                    # I'm still alive!
                    $threadconf.Heartbeat = Get-Date
                    Start-Sleep -Milliseconds 100
                }
            }
            catch {}
            foreach ($topic in $y.mqtt.Keys) {
                $Session.Unsubscribe($Topic) | Out-Null
            }
            Unregister-Event -SourceIdentifier $SourceIdentifier
            Disconnect-MQTTBroker $Session
            Write-Information "Disconnected"
        }
        Write-Information "Exiting"
    }
    #endregion
    Write-Information "Starting $thread - loading parameters and invoking $($config.$thread.Function)"
    $config.$thread.Heartbeat = Get-Date
    Invoke-Expression $config.$thread.Function
}
#endregion
#region Variable initialization
$pool = [runspacefactory]::CreateRunspacePool(1, 3)
$pool.open()
$ChildJobs = @{
    MQTTClient      = @{
        instance = $null
        handle   = $null
    }
    ResolumeControl = @{
        instance = $null
        handle   = $null
    }
    #
    ScheduleWatcher = @{
        instance = $null
        handle   = $null
    }
}

$Config = [hashtable]::Synchronized(@{
        MQTTClient      = @{
            Enabled     = $params.MQTTEnabled
            Function    = "Invoke-MQTTClient"
            DataWaiting = $false
            Heartbeat   = $null
            Starts      = 0
        }
        ResolumeControl = @{
            Enabled     = $true
            Function    = "Invoke-ResolumeControl"
            DataWaiting = $false
            Heartbeat   = $null
            Starts      = 0
        }
        ScheduleWatcher = @{
            Enabled     = $true
            Function    = "Invoke-ScheduleWatcher"
            DataWaiting = $false
            Heartbeat   = $null
            Starts      = 0
        }
    })
$Queue = [System.Collections.Concurrent.ConcurrentQueue[psobject]]::new()
# Padding to center text into the placeholder
$Padding = @{
    MQTTClient      = @{
        Pre  = "   " #3
        Post = "  "
    }
    ResolumeControl = @{
        Pre  = "" #0
        Post = "" #1
    }
    ScheduleWatcher = @{
        Pre  = ""
        Post = ""
    }
    Main            = @{
        Pre  = "      " #6
        Post = "     "
    }
}
$Colors = @{
    MQTTClient      = 92 # Bright Green
    ResolumeControl = 96 # Bright Cyan
    ScheduleWatcher = 93 # Bright Yellow
}
$TimeStamp = { (Get-Date).toString("yyyy-MM-dd HH:mm:ss") }
$OutputTemplate = "[{0}][{1,-15}] {2}"
#$Streams = @("Debug", "Error", "Information", "Verbose", "Warning")
#endregion
#region Main loop
Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main.Pre)MAIN", " !! STARTING MAIN THREAD !!")
$ctrlc = $false
while ($true) {
    #region CTRL-C reading
    if ([console]::KeyAvailable) {
        $key = [system.console]::readkey($true)
        if (($key.modifiers -band [consolemodifiers]"control") -and ($key.key -eq "C")) {
            Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main.Pre)MAIN", "Ctrl-C pressed, requesting quit")
            $ctrlc = $true
        }
    }
    #endregion
    #region Log rotate and lifetime checks
    # Handle log rotating (roughly) once per day
    if ((Get-Date) -gt $LatestLogRotate.AddDays(1)) {
        Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main.Pre)MAIN", "Rotating logs")
        # !! NOTE: This is blocking operation !!
        Remove-OldLogs
        $LatestLogRotate = Get-Date
    }

    # This could be more elegant but it works, so, whatever
    $TooManyStarts = $Config.keys | Where-Object { $Config.$_.Starts -gt $ThreadMaxStarts }
    if ($TooManyStarts.count -gt 0) {
        Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main.Pre)MAIN", "Thread start count limit of $ThreadMaxStarts exceeded by $($TooManyStarts.count) thread$(if($TooManyStarts -ne 1){"s"}) - Requesting quit.")
        $ctrlc = $true
    }

    if ($ctrlc) {
        Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main.Pre)MAIN", "Requesting threads to stop within 5s")
        foreach ($thread in $ChildJobs.Keys) {
            $Config.$thread.Enabled = $false
        }
        Start-Sleep -Seconds 5
        Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main.Pre)MAIN", "Stopping child threads")
        $ChildJobs.Keys | ForEach-Object {
            if ($null -ne $ChildJobs.$_.instance) {
                Write-Log ("{0,38}{1}" -f "", " - $_")
                $ChildJobs.$_.instance.Stop()
            }
        }
        Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main.Pre)MAIN", "Receiving child job outputs for the last time")
    }
    #endregion
    #region Read thread output
    # Check and process child job messages and if the process had hung
    $msgs = ""
    foreach ($thread in $ChildJobs.Keys) {
        $infos = $false
        $errors = $false
        $infos = $ChildJobs.$thread.instance.Streams.Information
        $errors = $ChildJobs.$thread.instance.Streams.Error
        if ($infos) {
            $msgs = $infos -split "`n"
            foreach ($msg in $msgs) {
                Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.$thread.Pre)$esc[$($Colors.$thread)m$thread$esc[0m$($Padding.$thread.Post)", "$esc[$($Colors.$thread)m$msg$esc[0m")
            }
        }
        if ($errors) {
            $msgs = $errors -split "`n"
            foreach ($msg in $msgs) {
                Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.$thread.Pre)$esc[$($Colors.$thread)m$thread$esc[0m$($Padding.$thread.Post)", "$esc[31mERROR: $msg$esc[0m")
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
        if ($Config.$thread.Enabled -eq $true -and $null -ne $Config.$thread.Heartbeat -and $Config.$thread.Heartbeat -lt (Get-Date).AddMinutes(-1)) {
            # Thanks to MQTT heartbeat, even receiver thread will update it's heartbeat often enough - or then the broker is nonfuntional
            Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main.Pre)MAIN", "Detected hung thread $thread - latest heartbeat $([System.Math]::Round(((Get-Date) - $Config.$thread.Heartbeat).TotalMinutes, 1)) minutes ago. Disposing")
            $ChildJobs.$thread.instance.Dispose()
            $nothung = $false
        }
        if ($Config.$thread.Enabled -eq $true -and ($null -eq $ChildJobs.$thread.instance -or ($ChildJobs.$thread.instance.InvocationStateInfo.State.ToString() -ne "Running" -and $ctrlc -eq $false))) {
            if ($nothung -and $null -ne $ChildJobs.$thread.instance.InvocationStateInfo.State) {
                Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main.Pre)MAIN", "Cleaning up previous $thread thread")
                $ChildJobs.$thread.instance.Dispose()
            }
            $Config.$thread.Starts += 1
            Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main.Pre)MAIN", "Starting $thread thread (start $($Config.$thread.Starts))")
            $ChildJobs.$thread.instance = [powershell]::Create()
            $ChildJobs.$thread.instance.RunspacePool = $pool
            $ChildJobs.$thread.instance.AddScript($functions) | Out-Null
            $argslist = @{
                thread = $thread
                queue  = $queue
                config = $Config
                params = $params
                yaml   = $yaml
            }
            $ChildJobs.$thread.instance.AddParameters($argslist) | Out-Null
            $ChildJobs.$thread.handle = $ChildJobs.$thread.instance.BeginInvoke()
        }
    }
    #endregion
    if ($ctrlc) {
        Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main.Pre)MAIN", "Removing child threads and breaking main thread")
        foreach ($thread in $ChildJobs.Keys) {
            if ($null -ne $ChildJobs.$thread.instance) {
                $ChildJobs.$thread.instance.Dispose()
            }
        }
        $pool.close()
        $pool.Dispose()
        break
    }
    # Rather tight loop for ctrl-c handling
    Start-Sleep -Milliseconds 100
}
Write-Log ($OutputTemplate -f (&$TimeStamp), "$($Padding.Main.Pre)MAIN", "Clean-up complete, exit.")
#endregion
exit 0
