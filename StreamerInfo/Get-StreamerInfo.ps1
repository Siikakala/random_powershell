[CmdletBinding()]
param(
    [ValidateScript({ Test-Path $_ })]
    [string]
    $ParametersFile = ".\parameters.psd1",
    [ValidateScript({ Test-Path $_ })]
    [string]
    $YamlFile = ".\streamers.yaml",
    $CacheFile = ".\cached_data.psd1"
)

Import-Module "$PSScriptRoot\powershell-yaml"
Import-Module "$PSScriptRoot\..\MirasMagicModule"
try {
    # Add SharpOSC dependency library
    # Add-Type -Path "$PSScriptRoot\SharpOSC\SharpOSC.dll" -ErrorAction Stop
}
catch {
    Write-Error "Could not load OSC client library, $($_.Exception.Message)"
    exit 1
}

$TwitchApi = "https://api.twitch.tv/helix/streams"
$KaviApi = "https://luokittelu.kavi.fi/agelimit/"

$params = Import-PowerShellDataFile $ParametersFile
try {
    $yaml = ConvertFrom-Yaml (Get-Content $YamlFile -Raw -ErrorAction Stop) -ErrorAction Stop
}
catch {
    Write-Error "Could not load configuration YAML file, $($_.Exception.Message)"
    exit 5
}
$cache = Import-PowerShellDataFile $CacheFile
if ($null -eq $cache) {
    $cache = @{}
}

$AuthToken = $null
if ($null -ne $cache.AuthToken) {
    Write-Information "Cached Twitch authorization token found, validating"
    try {
        $TokenValidation = Invoke-RestMethod -Uri "https://id.twitch.tv/oauth2/validate" -Authentication Bearer -Token $cache.AuthToken -ErrorAction Stop
    }
    catch {
        $TokenValidation = $_.ToString() #| ConvertFrom-Json -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    }
    if ($null -ne $TokenValidation.status -and $TokenValidation.status -eq 401) {
        Write-Information "Twitch token has expired, renewing"
    }
    else {
        Write-Information "Token valid, continuing"
        $AuthToken = ConvertTo-SecureString -AsPlainText -Force $cache.AuthToken
    }
}
if ($null -eq $AuthToken) {
    $AuthTokenInit = (New-HttpQueryUri -Uri "a" -QueryParameters @{client_id = $params.twitch_client_id; scopes = "user:read:broadcast" }).substring(10)
    $AuthTokenInitResponse = Invoke-RestMethod -Uri "https://id.twitch.tv/oauth2/device" -ContentType "application/x-www-form-urlencoded" -Method Post -Body $AuthTokenInit
    Start-Process $AuthTokenInitResponse.verification_uri
    $AuthTokenVerify = (New-HttpQueryUri -Uri "a" -QueryParameters @{client_id = $params.twitch_client_id; scopes = "user:read:broadcast"; grant_type = "urn:ietf:params:oauth:grant-type:device_code"; device_code = $AuthTokenInitResponse.device_code }).substring(10)
    do {
        Start-Sleep -Seconds 10
        try {
            $AuthTokenVerifyResponse = Invoke-RestMethod -Uri "https://id.twitch.tv/oauth2/token" -ContentType "application/x-www-form-urlencoded" -Method Post -Body $AuthTokenVerify
        }
        catch {
            $AuthTokenVerifyResponse = $_.ToString() | ConvertFrom-Json
        }
        if ($null -ne $AuthTokenVerifyResponse.status -and $AuthTokenVerifyResponse.status -eq 400) {
            if ($AuthTokenVerifyResponse.message -eq "authorization_pending") {
                Write-Information "Waiting for Twitch authorization"
            }
            else {
                Write-Error "Twitch API authorization failed!"
                exit 10
            }
        }
        if ($null -ne $AuthTokenVerifyResponse.access_token) {
            $AuthToken = ConvertTo-SecureString -AsPlainText -Force $AuthTokenVerifyResponse.access_token
            Write-Information "Twitch authorized"
        }
    }while ($null -eq $AuthToken)
    Write-Information "Updating new token to cache"
    $cache.AuthToken = $AuthTokenVerifyResponse.access_token
    $CacheContent = '@{'
    foreach ($key in $cache.Keys) {
        $CacheContent += "$key = `"$($cache.$key)`"; "
    }
    $CacheContent += "}"
    Set-Content -Path $CacheFile -Value $CacheContent
}
if ($null -ne $AuthToken) {
    $Ratings = @("Three", "Seven", "Twelve", "Sixteen", "Eighteen", "RP", "EC", "E", "E10", "T", "M", "AO", "CERO_A", "CERO_B", "CERO_C", "CERO_D", "CERO_Z", "USK_0", "USK_6", "USK_12", "USK_16", "USK_18", "GRAC_ALL", "GRAC_Twelve", "GRAC_Fifteen", "GRAC_Eighteen", "GRAC_TESTING", "CLASS_IND_L", "CLASS_IND_Ten", "CLASS_IND_Twelve", "CLASS_IND_Fourteen", "CLASS_IND_Sixteen", "CLASS_IND_Eighteen", "ACB_G", "ACB_PG", "ACB_M", "ACB_MA15", "ACB_R18", "ACB_RC")
    $RatingOrgs = @("ESRB", "PEGI", "CERO", "USK", "GRAC", "CLASS_IND", "ACB")

    foreach ($streamer in $yaml.streamers) {
        $Response = Invoke-RestMethod -Authentication Bearer -Token $AuthToken -Headers @{"Client-Id" = $params.twitch_client_id } -Uri "https://api.twitch.tv/helix/streams?user_login=$streamer"
        $Playing = $Response.data.game_name
        $StreamerName = $Response.data.user_name
        if ($null -eq $StreamerName) {
            Write-Information "Streamer '$streamer' is offline"
        }
        else {
            if ($null -eq $Playing) {
                Write-Information "Streamer '$StreamerName' is not playing anything currently"
            }
            else {
                Write-Information "Streamer '$StreamerName' is playing '$Playing'"
                if ($Playing -ne "Just Chatting") {
                    $IGDBGameSearch = Invoke-RestMethod -Authentication Bearer -Token $AuthToken -Headers @{"Client-Id" = $params.twitch_client_id } -Method Post -Body "search `"$Playing`"; fields name,age_ratings;" -Uri "https://api.igdb.com/v4/games"
                    foreach ($result in $IGDBGameSearch) {
                        foreach ($rating in $result.age_ratings) {
                            $IGDBAgeRating = Invoke-RestMethod -Authentication Bearer -Token $AuthToken -Headers @{"Client-Id" = $params.twitch_client_id } -Method Post -Body "fields organization,rating_category,rating_content_descriptions; where id = $rating;" -Uri "https://api.igdb.com/v4/age_ratings"
                            Write-Information "IGDB Age rating for game $($result.name) is $($RatingOrgs[$IGDBAgeRating.organization]) $($ratings[($IGDBAgeRating.rating_category)])"
                        }
                    }
                }
            }
        }
    }
}