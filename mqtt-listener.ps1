[CmdletBinding()]
param(
    $ComputerName = "tennoji"
)

if(-not (Test-Path C:\mqttx\mqttx.exe)){
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
                        $vmr.button[11].state = $true
                    }
                    "Headphones" {
                        $vmr.button[10].state = $true
                    }
                }
            }
            "SetVolume" {
                if ($null -ne $arg.index -and $null -ne $arg.type -and $null -ne $arg.level) {
                    if ($arg.type -eq "bus") {
                        $vmr.bus[$arg.index].FadeTo($arg.level, 200)
                    }
                    else {
                        $vmr.strip[$arg.index].FadeTo($arg.level, 200)
                    }
                }
            }
        }
        Disconnect-Voicemeeter
    }
}

while (Test-Path C:\mqttx\mqttx.exe) {
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
                Write-Verbose "$((Get-Date).toString("yyyy-MM-dd hh:mm:ss")) Message to topic $($data.topic):`n$(($payload | Format-List | Out-String).Trim())`n`n"
                switch ($data.topic) {
                    "$ComputerName/control" {
                        Write-Verbose "- Calling Invoke-GeneralControl as job"
                        Start-Job -ScriptBlock { Invoke-GeneralControl $using:payload } -InitializationScript $functions -ArgumentList $payload | Out-Null
                    }
                    "$ComputerName/control/sound" {
                        Write-Verbose "- Calling Invoke-VoicemeeterControl as job"
                        Start-Job -ScriptBlock { Invoke-VoicemeeterControl $using:payload } -InitializationScript $functions -ArgumentList $payload | Out-Null
                    }
                }
            }
        }
    }
    Start-Sleep -Seconds 5
    Write-Verbose "Reconnecting to MQTT"
}