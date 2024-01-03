[CmdletBinding()]
param(
    $ComputerName = "tennoji"
)

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
        }
        Disconnect-Voicemeeter
    }
}
$invokes = {
    function Invoke-Listener {
        param(
            $functions,
            $ComputerName
        )
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
                    Write-Output "Message to topic $($data.topic):`n$(($payload | Format-List | Out-String).Trim())`n"
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
        $conf = Get-Content c:\mqttx\mqttx-cli-config.json -Raw | ConvertFrom-Json
        while ($true) {
            Write-Output "Sending heartbeat to MQTT"
            c:\mqttx\mqttx.exe pub -h $conf.pub.hostname -u $conf.pub.username -P $conf.pub.password -t "$ComputerName/heartbeat" -m (Get-Date).toString("yyyy-MM-dd HH:mm:ss")
            for ($i = 0; $i -lt 300; $i++) {
                # Stop-job takes freaking forever if Start-Sleep -Seconds 300 is used.
                Start-Sleep -Seconds 1
            }
        }
    }
}
$ChildJobs = @{
    Sender   = $null
    Receiver = $null
}

Write-Verbose "[$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))]   MAIN: Starting main thread"
while ($true) {
    $msgs = ""
    # Check and process child job messages
    if ($ChildJobs.Receiver.State -ne "Running") {
        Write-Verbose "[$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))]   MAIN: Starting listener thread"
        $ChildJobs.Receiver = Start-Job -Name "MQTTReceiver" -ScriptBlock { Invoke-Listener -functions $using:functions -Computername $using:ComputerName } -InitializationScript $invokes -ArgumentList $functions, $ComputerName
    }
    if ($ChildJobs.Sender.State -ne "Running") {
        Write-Verbose "[$((Get-Date).toString("yyyy-MM-dd HH:mm:ss"))]   MAIN: Starting sender thread"
        $ChildJobs.Sender = Start-Job -Name "MQTTSender" -ScriptBlock { Invoke-Sender -functions $using:functions -Computername $using:ComputerName } -InitializationScript $invokes -ArgumentList $functions, $ComputerName
    }
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
    Start-Sleep -Seconds 1
}