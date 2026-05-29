[CmdletBinding()]
param()

Import-Module "$PSScriptRoot\powershell-yaml"
try {
    # Add SharpOSC dependency library
    Add-Type -Path "$PSScriptRoot\SharpOSC\SharpOSC.dll" -ErrorAction Stop
}
catch {
    Write-Error "Could not load OSC client library, $($_.Exception.Message)"
    exit 1
}

$TwitchApi = "https://api.twitch.tv/helix/streams"
$KaviApi = "https://luokittelu.kavi.fi/agelimit/"