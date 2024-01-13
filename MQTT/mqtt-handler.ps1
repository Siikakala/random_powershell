[CmdletBinding()]
param(
    $ComputerName = "tennoji",
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
    function Invoke-GeneralControl {
        param($payload)
        switch ($payload.command) {
            default {}
        }
    }
    function Invoke-VoicemeeterControl {
        param($payload)
        Import-Module Voicemeeter
        $vmr = Connect-Voicemeeter -Kind "potato"
        $arg = $payload.args
        $return = $null
        switch ($payload.command.trim()) {
            "SwitchMode" {
                switch ($arg.Mode) {
                    "Speakers" {
                        # This MacroButton's button loads Voicemeeter configuration with my M-Track ASIO driver as A1 output device, to which my speakers are connected to
                        $vmr.button[11].state = $true
                    }
                    "Headphones" {
                        # This MacroButton's button loads Voicemeeter configuration with my Bluetooth headphones as A1 output device. In the case headphones aren't connected,
                        # Voicemeeter ends up in engine error state and lets go all wake locks for audio devices, potentially allowing computer to sleep
                        $vmr.button[10].state = $true
                    }
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
                    # Things in parenthesis before method call will be resolced first, so the string value of $arg.type will be
                    # converted to point to specific array in the API, as it's type was string. Then the index will be populated to
                    # select the object inside the array. The the FadeTo method of that object will be called with the level as first
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
                    $vmr.($arg.type)[$arg.index].FadeTo($arg.level, 200)
                }
            }
            "GetVolume" {
                if ($null -ne $arg.index -and $null -ne $arg.type) {
                    # See explanation above, though this is requesting info, not setting it. Slider value is returned in 'gain' property
                    $return = ($vmr.($arg.type)[$arg.index]).gain
                }
            }
        }
        Disconnect-Voicemeeter
        if ($null -ne $return) {
            return $return
        }
    }
}
$invokes = {
    function Invoke-Listener {
        param(
            $functions,
            $ComputerName
        )
        $threadstarted = Get-Date
        Write-Output "Connecting to MQTT"
        C:\mqttx\mqttx.exe sub --config C:\mqttx\mqttx-cli-config.json | ForEach-Object -Process {
            # The json object is pretty printed and pipe is consuming the data row-per-row so gather the whole message first
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
                    Write-Output "- Message to topic $($data.topic):`n$(($payload | Format-List | Out-String).Trim())"
                    switch ($data.topic) {
                        "$ComputerName/control" {
                            Write-Output "- Calling Invoke-GeneralControl as job"
                            Start-Job -ScriptBlock { Invoke-Expression $using:functions; Invoke-GeneralControl $using:payload } -ArgumentList $functions, $payload | Out-Null
                        }
                        "$ComputerName/control/sound" {
                            Write-Output "- Calling Invoke-VoicemeeterControl as job"
                            Start-Job -ScriptBlock { Invoke-Expression $using:functions; Invoke-VoicemeeterControl $using:payload } -ArgumentList $functions, $payload | Out-Null
                        }
                        "$ComputerName/heartbeat" {
                            Write-Output "- Heartbeat"
                        }
                    }
                }
                if (((Get-Date) - $threadstarted).TotalDays -gt 1) {
                    Write-Output "Thread age over a day - trying to quit."
                    break
                }
            }
        }
        Write-Output "Disconnected - waiting for 5s before returning to main thread"
        Start-Sleep -Seconds 5
    }
    function Invoke-Sender {
        param(
            $functions,
            $ComputerName
        )
        Invoke-Expression $functions
        $conf = Get-Content c:\mqttx\mqttx-cli-config.json -Raw | ConvertFrom-Json
        $threadstarted = Get-Date
        $stopwatch = [System.Diagnostics.Stopwatch]::new()
        $previousA1Level = -60
        :outer while ($true) {
            for ($i = 0; $i -lt 150; $i++) {
                # Extremely hack-y way of doing things in intervals but whatever, I regret nothing! x)
                # One complete while($true) loop takes 5 mintes, and these actions are taken in roughly once per two secnds. Different actions during it takes a bit of time so using
                # stopwatch and 2 second "offset" in milliseconds to adjust the sleep time at the end
                $stopwatch.Restart()
                $offset = 2000
                if ($i % 10 -eq 0) {
                    #This happens once in 20 seconds
                    Write-Output "Sending heartbeat to MQTT"
                    c:\mqttx\mqttx.exe pub -h $conf.pub.hostname -u $conf.pub.username -P $conf.pub.password -t "$ComputerName/heartbeat" -m (Get-Date).toString("yyyy-MM-dd HH:mm:ss") | Out-Null
                }

                if ($i % 30 -eq 0) {
                    # This happens once a minute
                    Write-Output "Requesting current A1 level from Voicemeeter"
                    $call = @{
                        command = "GetVolume"
                        args    = @{
                            type  = "bus"
                            index = 0
                        }
                    }

                    # Voicemeeter API is annoying in a sense that you can't re-connect to the API in the same session once you disconnect. So, starting new job every time by using child job
                    $VCCall = Start-Job -ScriptBlock { Invoke-Expression $using:functions; Invoke-VoicemeeterControl $using:call } -ArgumentList $functions, $call
                    while ($VCCall.State -eq "Running") {
                        Start-Sleep -Milliseconds 100
                    }
                    $A1Level = Receive-Job $VCCall
                    Remove-Job $VCCall
                    if ($A1Level -ne $previousA1Level) {
                        Write-Output "Sending MQTT message '$A1Level' to topic '$Computername/status/sound/A1Level'"
                        c:\mqttx\mqttx.exe pub -h $conf.pub.hostname -u $conf.pub.username -P $conf.pub.password -t "$ComputerName/status/sound/A1Level" -m $A1Level | Out-Null
                        $previousA1Level = $A1Level
                    }
                }

                # Sleep handling
                $stopwatch.Stop()
                $offset -= $stopwatch.ElapsedMilliseconds
                if (((Get-Date) - $threadstarted).TotalDays -gt 1) {
                    Write-Output "Thread age over a day - breaking out to free resources."
                    break outer
                }
                else {
                    Write-Debug "  [$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))]   SEND: loop $i, sleeping ${offset}ms"
                    if ($offset -gt 0) {
                        Start-Sleep -Milliseconds $offset
                    }
                }
            }
        }
    }
}
$ChildJobs = @{
    Sender   = $null
    Receiver = $null
}

Write-Verbose "[$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))]   MAIN: Starting main thread"
$ctrlc = $false
while ($true) {
    if ([console]::KeyAvailable) {
        $key = [system.console]::readkey($true)
        if (($key.modifiers -band [consolemodifiers]"control") -and ($key.key -eq "C")) {
            Write-Verbose "[$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))]   MAIN: Ctrl-C pressed, starting clean-up"
            $ctrlc = $true
            Write-Verbose "[$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))]   MAIN: Stopping child jobs"
            Stop-Job $ChildJobs.Receiver
            Stop-Job $ChildJobs.Sender
            Write-Verbose "[$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))]   MAIN: Receiving child job outputs for the last time"
        }
    }
    $msgs = ""
    # Check and process child job messages
    if ($ChildJobs.Receiver.HasMoreData) {
        $msgs = ($ChildJobs.Receiver | Receive-Job) -split "`n"
        foreach ($msg in $msgs) {
            Write-Verbose "[$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))] LISTEN: $msg"
        }
    }
    if ($ChildJobs.Sender.HasMoreData) {
        $msgs = ($ChildJobs.Sender | Receive-Job) -split "`n"
        foreach ($msg in $msgs) {
            Write-Verbose "[$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))]   SEND: $msg"
        }
    }

    if ($ChildJobs.Receiver.State -ne "Running" -and $ctrlc -eq $false) {
        if($null -ne $ChildJobs.Receiver){
            Write-Verbose "[$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))]   MAIN: Cleaning up previous listener thread"
            $ChildJobs.Receiver | Remove-Job
        }
        Write-Verbose "[$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))]   MAIN: Starting listener thread"
        $ChildJobs.Receiver = Start-Job -Name "MQTTReceiver" -ScriptBlock { $DebugPreference = $using:DebugPreference; Invoke-Listener -functions $using:functions -Computername $using:ComputerName } -InitializationScript $invokes -ArgumentList $functions, $ComputerName, $DebugPreference
    }
    if ($ChildJobs.Sender.State -ne "Running" -and $ctrlc -eq $false) {
        if($null -ne $ChildJobs.Sender){
            Write-Verbose "[$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))]   MAIN: Cleaning up previous sender thread"
            $ChildJobs.Sender | Remove-Job
        }
        Write-Verbose "[$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))]   MAIN: Starting sender thread"
        $ChildJobs.Sender = Start-Job -Name "MQTTSender" -ScriptBlock { $DebugPreference = $using:DebugPreference; Invoke-Sender -functions $using:functions -Computername $using:ComputerName } -InitializationScript $invokes -ArgumentList $functions, $ComputerName, $DebugPreference
    }


    if ($ctrlc -and ($ChildJobs.Receiver.State -eq "Stopped" -and $ChildJobs.Receiver.HasMoreData -eq $false) -and ($ChildJobs.Sender.State -eq "Stopped" -and $ChildJobs.Sender.HasMoreData -eq $false)) {
        Write-Verbose "[$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))]   MAIN: Removing child jobs and breaking main thread"
        Get-Job -Name MQTTReceiver | Remove-Job
        Get-Job -Name MQTTSender | Remove-Job
        break
    }
    # Rather tight loop for ctrl-c handling
    Start-Sleep -Milliseconds 100
}
Write-Verbose "[$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))]   MAIN: Clean-up complete, exit."
exit 0