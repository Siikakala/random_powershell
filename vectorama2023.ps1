[CmdletBinding()]
param(
    $TargetFPS = 13,
    $FPSSmoothingFactor = 0.4,
    $FPSDigits = 2,
    $AnimationSeconds = 12,
    [switch]
    $InfiniteLoop
)
do {
    if ($host.UI.RawUI.WindowSize.Width -lt 324 -or $host.UI.RawUI.WindowSize.Height -lt 70) {
        if ($null -ne $env:WT_SESSION) {
            # Windows Terminal - don't want to touch
            Write-Error "Detected Windows Terminal session and too small window!"
            Write-Host "`nOutput requires at least 324x75 characters window, please resize it manually. Your current window is: $($host.UI.RawUI.WindowSize.Width)x$($host.UI.RawUI.WindowSize.Height)`n`nRecommended method: Alt-enter to full screen, then zoom out with ctrl-minus until output fits"
            exit
        }
        else {
            try {
                $newsize = New-Object -TypeName System.Management.Automation.Host.Size -ArgumentList (324, 70)
                $host.UI.RawUI.BufferSize = $newsize
                $host.UI.RawUI.WindowSize = $newsize
            }
            catch {}
        }
    }
    if ($host.UI.RawUI.WindowSize.Width -lt 324 -or $host.UI.RawUI.WindowSize.Height -lt 70) {
        Write-Error "Failed to resize window to minimum size of 324x75 characters!"
        exit
    }


    Clear-Host

    Function Write-Debug {
        param($Message)
        $old = $host.ui.RawUI.CursorPosition
        $host.ui.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(200, 1)
        Write-Host $Message -NoNewline
        $host.ui.RawUI.CursorPosition = $old
    }
    Write-Debug "Loading art-file and parsing contents"
    $art = (Get-Content -Raw ./vecto2023_artfile.ans) -split "--::--"
    $vectoslices = $art[0] -split "`n"
    $logoslices = $art[1] -split "`n"
    $nakkiveneslices = $art[2] -split "`n"
    $timeslices = $art[3] -split "`n"
    $cpslices = $art[4] -split "`n"
    $reminderslices = $art[5] -split "`n"
    $nyancatframes = $art[6] -split "::"

    $globaloffsetX = [System.Math]::Floor(($host.ui.RawUI.WindowSize.Width - 324) / 2)
    $globaloffsetY = [System.Math]::Floor(($host.ui.RawUI.WindowSize.Height - 106) / 2) + 1
    Foreach ($slice in $vectoslices) {
        $host.ui.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new($globaloffsetX, ($vectoslices.indexOf($slice) + $globaloffsetY + 15 ))
        Write-Host $slice -NoNewline
    }
    foreach ($slice in $logoslices) {
        $host.ui.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(($globaloffsetX + 1), ($logoslices.indexOf($slice) + $globaloffsetY ))
        Write-Host $slice -NoNewline
    }
    foreach ($slice in $timeslices) {
        $host.ui.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(($globaloffsetX + 180), ($timeslices.indexOf($slice) + $globaloffsetY + 13 ))
        Write-Host $slice -NoNewline
    }
    foreach ($slice in $cpslices) {
        $host.ui.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(($globaloffsetX + 5), ($cpslices.indexOf($slice) + $globaloffsetY + 90 ))
        Write-Host $slice -NoNewline
    }
    #Start-Sleep -Seconds 2

    $offset = 0
    $origpos = [System.Management.Automation.Host.Coordinates]::new($globaloffsetX, ($vectoslices.count + $globaloffsetY - 25))
    $nakkivenepositionoffset = 181
    $padding = -50
    $nyanpositionoffset = $nakkivenepositionoffset + $padding + 30
    $currentframe = 0
    $cumulatedframes = 0
    $currentfps = $TargetFPS
    $framesyncstopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $AnimationTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $TargetFrameTime = 1000 / $TargetFPS
    [console]::CursorVisible = $false
    while ($AnimationTimer.ElapsedMilliseconds -lt ($AnimationSeconds * 1000)) {
        $framesyncstopwatch.Restart()
        if ($currentframe -ge 12) {
            $currentframe = 0
        }
        $host.ui.RawUI.CursorPosition = $origpos

        $nyancatslices = $nyancatframes[($currentframe + $offset)] -split "`n"
        if ($currentframe -gt 6) {
            $veneoffset = 0
        }
        else {
            $veneoffset = -1
        }
        foreach ($slice in $nyancatslices) {
            $sliceindex = $nyancatslices.indexOf($slice)
            $host.ui.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(($origpos.X + $nyanpositionoffset), ($origpos.Y + $sliceindex))
            Write-Host $slice -NoNewline
            $host.ui.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(($origpos.X + $nakkivenepositionoffset), ($origpos.Y + $sliceindex - 8))
            Write-Host $nakkiveneslices[$sliceindex + $veneoffset + 1] -NoNewline
        }

        $frametime = $framesyncstopwatch.ElapsedMilliseconds
        # Rest of the computing takes time as well so compensating with 2ms
        $framesyncmillis = $TargetFrameTime - $frametime - 2
        $currentfps = ($currentfps * $FPSSmoothingFactor) + (1000 / ($frametime + $framesyncmillis) * (1 - $FPSSmoothingFactor))
        $fpsrounded = [System.Math]::Round($currentfps, $FPSDigits)
        $syncmillisrounded = [System.Math]::Round($framesyncmillis, 0)
        $elapsedSeconds = [System.Math]::Round(($AnimationTimer.Elapsed).TotalSeconds, 2)
        Write-Debug "FPS: Current: $fpsrounded ; Target $TargetFPS | Framesync delay: $syncmillisrounded ms | Timer: $elapsedSeconds s   "
        if ($syncmillisrounded -gt 0) {
            Start-Sleep -Milliseconds $syncmillisrounded
        }
        $currentframe++
        $cumulatedframes++
    }
    Clear-Host
    Start-Sleep -Milliseconds 200

    Foreach ($slice in $reminderslices) {
        $host.ui.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new($globaloffsetX + 38, ($reminderslices.indexOf($slice) + $globaloffsetY + 38 ))
        Write-Host $slice -NoNewline
    }

    Start-Sleep -Seconds $AnimationSeconds
    [console]::CursorVisible = $true
}while ($InfiniteLoop.IsPresent)