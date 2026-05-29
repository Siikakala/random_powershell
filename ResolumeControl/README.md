# Resolume Arena control with OSC and MQTT
This script was born from the needs of Vectorama. There's some scheduled things, which needs
changes in Resolume Arena, namely free visiting time to ensure security has enough light in
their checkpoint.

Other usage is light alerts via MQTT messages. This is used in food orders, where the vendor
can press a button and then colored alerts in different places gets triggered, lights (via
Resolume Arena) being one of the destinations.

These two are just examples, the groundwork is now done for further integrations. Resolume
Arena has quite nice [OSC API](https://resolume.com/support/en/osc) with [lot of endpoints](https://resolume.com/download/Manual/OSC/OSC%20list.txt)

The OSC library uses .NET 3.5 which limits the script to Windows platform.

You need to be in the same directory as the script when running it. It requires no run-time parameters
as those are defined in the support files explained below. Can be ran from Task Scheduler, just remember
to set the working directory correctly. Script doesn't have gracefull shutdown for Task Scheduler but
can be shut down gracefully with CTRL-C when ran from PowerShell prompt.

Script is ran simply by:
```
.\resolume-control.ps1
```

## Configuration
There's two different files you need to edit for the script to work, config.yaml and parameters.psd1

Parameters defines runtime variables, like MQTT broker, it's credentials, log destination and naming,
and Resolume Arena IP and OSC port. Please remember to enable the OSC input in Resolume preferences!

Config defines the actual actions, which should be taken, divided under two main keys, mqtt and schedule.

### Parameters.ps1
First, remove the `example.` from the filename by making copy of the example file. The contents are PowerShell
hashtable and should looks something like this:
```
@{
    LogPath           = "C:\resolume-control-logs\"
    LogFilePrefix     = "resolume-control_"
    LogFileDateSyntax = "yyyy-MM-dd"
    LogRetentionDays  = 14
    MQTTBroker        = "mqtt.example.com"
    MqttUser          = ""
    MqttPassword      = ""
    ResolumeIP        = "127.0.0.1"
    ResolumePort      = 7000
}
```
The example assumes you run the script on the same machine as Resolume. If you want to run it on different machine,
change the ResolumeIP property, `127.0.0.1` in the example, to the IP of the Resolume machine. You can see the IP in
the OSC configuration page.

Other mandatory thing is the MQTT configuration. Please set MQTT server, username and password in plain text inside the
quotes. If username or password contains quotes, it needs to be escaped with backtick, like this: \`"

### Config.yaml
I have tried to make the YAML configuration as intuitive as possible - if you have configured any YAML files, you should
feel home right away.

First, remove the `example.` from the filename by making copy of the example file. The contents should look something
like this:
```
mqtt:
  topic1:
    - content: someword
      action: SelectClip
      layer: 42
      value: 2
    - content: someotherword
      action: SelectClip
      layer: 42
      value: 3
  topic2:
    - content: clear
      action: ClearLayer
      layer: 42
      value: 1
schedule:
  - name: "Event starts"
    time: "2026-06-03 11:00"
    actions:
      - action: ClearLayer
        layer: 67
        value: off
      - action: SelectClip
        layer: 67
        value: 2
      - action: Opacity
        layer: 67
        value: 80
  - name: "Event stops"
    time: "2026-06-03 21:00"
    actions:
      - action: ClearLayer
        layer: 67
        value: 1
```
First, the `mqtt`  key. The keys under it are topics you want to subscribe to. These in example are top-level topics
so you can also use something like `resolume/control` or similar. The topic key has different values as array. So,
whatever the actual payload of the MQTT message has. Script is assuming plain text but uses PowerShell -match internally,
which means you can also use regex here, defined in key `content`. This enables parsing JSON if you are masochist.

The keys `action`, `layer`, and `value` are common with the schedule section. These dictate what should happen in Resolume.
* `action`
  * Defines what should be done. Currently supported values:
    * `SelectClip`
      * Switches to the clip on the layer. Note: starts from 0, not 1
    * `ClearLayer`
      * Clears the current clip on the layer. Value is ignored. Resolume seems to be bit picky about this though,
        I advice to create blank clip and select it with SelectClip
    * `Opacity`
      * Layer opacity in percents
    * `TransitionTime`
      * Layer transition time in milliseconds. 0 - 10s, rounded to 100ms
    * `TriggerGroupColumn`
      * As SelectClip but trigger whole column of defined group. Group is defined in layer field
* `layer`
  * Defines the layer or group to which the action is performed to
* `value`
  * Raw value for OSC messages. Boolean-like values (on/off, true/false) are converted to integers automatically. For actions
    not requiring value, like ClearLayer, you can use `null`.

The `schedule` key is very similar to MQTT. Biggest difference is that instead of content, you define `time` in format `Get-Date`
can parse. I strongly recommend format `yyyy-MM-dd HH:mm:ss` like in the example (though seconds are omited). Schedules have
extra key called `name` which is mainly for humans to know what the heck this is. Script uses in log output to indicate which
schedule was triggered when time triggers. Schedules can have multiple actions, defined as array, which are processed sequentally.

## Technical details
This is modified version of my `mqtt-handler.ps1` found from MQTT folder in this repo. By default the script doesn't
produce any output to prompt you are running it from. You can follow the logs by copying log-reader script
`mqtt-handler-log-reader.ps1` from the `MQTT` folder of this repo into same folder as `resolume-control.ps1` and running it.
It discovers log files location from parameters file automatically.

The script is multithreaded so logging might miss or skip lines occasionally.