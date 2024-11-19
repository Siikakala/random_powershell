@{
    ComputerName           = "tennoji"
    LogPath                = "E:\mqtt_handler-logs\"
    LogFilePrefix          = "mqtt-handler_"
    LogFileDateSyntax      = "yyyy-MM-dd"
    LogRetentionDays       = 14
    MQTTBroker             = "mqtt.ojamo.fi"
    MQTTTopics             = @("tennoji/#")
    EdgeBridgeIP           = "172.20.1.225"
    EdgeBridgePort         = "8090"
    LanTriggers            = @{
        "obs64-start"      = @("scene", "webcam")
        "obs64-stop"       = @("scene", "candy")
        "RemotePlay-start" = @("scene", "computer")
        "RemotePlay-stop"  = @("scene", "candy")
        "GeforceNOW-start" = @("scene", "computer")
        "GeforceNOW-stop"  = @("scene", "candy")
        "Mode-Speakers"    = @("speakers", "on")
        "Mode-Headphones"  = @("speakers", "off")
    }
    AudioDevicesSpeakers   = "M-Track Quad ASIO Driver"
    AudioDevicesHeadphones = "Headphones (MOMENTUM 4 Stereo)"
    AudioDuckButtons       = @(4, 5, 14, 20, 23)
    AudioButtonActions     = @{
        "Speakers"         = @(
            @{
                Button = 11
                State  = $true
            },
            @{
                Button = 11
                State  = $false
            },
            @{
                Button = 0
                State  = $false
            }
        )
        "Headphones"       = @(
            @{
                Button = 10
                State  = $true
            },
            @{
                Button = 10
                State  = $false
            },
            @{
                Button = 0
                State  = $false
            }
        )
        "RemotePlay-start" = @{
            Button = 15 # Music to -15 dB
            State  = $true
        }
        "RemotePlay-stop"  = @{
            Button = 15
            State  = $false
        }
        "GeforceNOW-start" = @{
            Button = 25 # Music to -25 dB
            State  = $true
        }
        "GeforceNOW-stop"  = @{
            Button = 25
            State  = $false
        }
    }
    ProcessesWatcher       = @(
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
}