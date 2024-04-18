[console]::TreatControlCAsInput = $true
$params = Import-PowerShellDataFile .\parameters.psd1
$LogPath = (Get-Item $params.LogPath).Target[0]
$StaticLogFile = $LogPath + "\" + $params.LogFilePrefix
$ctrlc = $false
while(-not $ctrlc){
    $date = Get-Date
    $reader = Start-Job -ScriptBlock {
        param($FilePrefix,$DateSyntax)
        Get-Content "$FilePrefix$((Get-Date).tostring($DateSyntax)).log" -Wait
    } -ArgumentList $StaticLogFile, $params.LogFileDateSyntax
    while((Get-Date).day -eq $date.day){
        if ([console]::KeyAvailable) {
            $key = [system.console]::readkey($true)
            if (($key.modifiers -band [consolemodifiers]"control") -and ($key.key -eq "C")) {
                $ctrlc = $true
                break
            }
        }
        Receive-Job $reader
        Start-Sleep -Milliseconds 50
    }
    $reader | Stop-Job | Remove-Job
    if(-not $ctrlc){
        Write-Host "Day changed, reloading reader"
    }
}