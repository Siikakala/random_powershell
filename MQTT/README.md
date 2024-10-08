<!-- omit from toc -->
# MQTT shenanigans
I want locally control my main PC thru MQTT. You can find scripts for that here.

They depend on MQTTX cli client, which you can download from [MQTTX cli website](https://mqttx.app/cli#download)

- [mqtt-handler.ps1](#mqtt-handlerps1)
  - [Demo video](#demo-video)
  - [What they do?](#what-they-do)
  - [Threads? Really?](#threads-really)
  - [Ok, but what does it _do_?](#ok-but-what-does-it-do)
  - [Plans](#plans)
- [mqtt-handler-log-reader.ps1](#mqtt-handler-log-readerps1)

## mqtt-handler.ps1
Utility running on my main computer running Windows 10. There's several parts:
* Main thread
* MQTT listener
* MQTT Sender
* Voicemeeter Potato handler
* Process Watcher

### Demo video
!! Contains "Hey Google, switch to speakers" !!

[![Demo](demo_preview.jpg)](https://1drv.ms/v/s!AtrhTUkXQvo3jLYy0zr72UuOfBoUGw?e=xVfv7I)
(click to open)

### What they do?
- Main thread handles the script output and thread lifecycling
- MQTT Listener parses whatever mqttx client spits out and reacts to the messages as needed
- MQTT Sender sends updates to topics listened by SmartThings virtual devices
- Voicemeeter Potato handler is handling all the Voicemeeter API calls and informs sender if user changed something (A1 volume or device)
- Process watcher triggers actions in SmartThings (utilising LAN Triggers) and Voicemeeter (changing MacroButtons button states) whenever watched process is running and stops

This is close integration with SmartThings and uses several utilities Todd Austin has programmed:
* [LAN Trigger](https://github.com/toddaustin07/lantrigger)
* [Edgebridge](https://github.com/toddaustin07/edgebridge)
* [MQTTDevices](https://github.com/toddaustin07/MQTTDevices)

Edgebridge and other half of LAN Trigger is running on my local raspberry pi. The rpi is also running [mosquitto](https://mosquitto.org/)

### Threads? Really?
Yes, mqttx client is literally just piping the output to data processor, which dictated it's own thread anyway to achieve any sensible two-way communications. This was inspiration to
dive deep into the threading as I haven't done it much - just to see how to do it if I ever need it at work. It also turned out that Voicemeeter API is slightly annoying, and threading
made that part slightly easier. First iteration used just jobs, but as those are invoking their own processes, that complicated the communications a little bit, making child jobs essentially
read-only and I wanted bi-directional communications between the threads. So, took one step deeper into .NET runspaces, thread-safe queues and synced hashtables. I'm avoiding the synced hashtable
in actual communications on purpose, as I also wanted to know how to handle single queue in multi-threaded environment.

### Ok, but what does it _do_?
First of all, only one thing relies on cloud, due to bad purchase. Everything else is handled locally and doesn't require internet.

It achieves several things:

* Suspend machine with MQTT message
* Automating light scenes
  * Uses LAN Triggers as Process Watcher is using this mainly
    * Separate triggers when process is detected running and when it stops
    * Also saves up device count - one LAN Trigger device in SmartThings can handle 19 different triggers, so, 19 scenes (selected by script so it could be really elaborate actually) or 9 on-off triggers with one spare trigger
      * Currently 2 scenes and 1 on-off trigger pair (for speakers)
  * When OBS is running, certain scene triggers so there's enough light to my face
  * When I'm using PS Remote Play or Geforce NOW, another scene triggers so there's minimal reflections to my display. Unless OBS is running, which blocks the triggers.
  * When (all) app(s) have stopped, trigger fancier scene.
* Automating PC audio
  * Handling speaker power
    * I have active speakers, which are connected to smart outlet and if I'm listening with headphones, the power will be turned off. And back on when output is switched to speakers
    * The only integration requiring cloud and it's rather ":D" - MQTT changes virtual switch state, SmartThings hub syncs the state to cloud, Google notices the change and changes Tuya socket state accordingly, Tuya sends push message to outlets.
      * So: MQTT -> SmartThings Cloud -> Google Cloud -> Tuya Cloud -> Socket
      * The delay is around 2-3 seconds. Thanks Tuya for integrating with only Amazon and Google with this particular product 😩
      * Despite of that it's surprisingly robust, very rare state change misses.
  * Triggering MacroButtons
    * MQTT message can switch between headphones and speakers by triggering macrobutton loading correct Voicemeeter configuration
    * The state and/or gate trigger of a button can be enabled or disabled (enabled state = pushed, latching)
    * Process watcher can lower music level when I'm playing and disable other triggers touching the level
    * Can handle multiple buttons with one payload (using array)
  * Enforcing maximum volume level between 21:30 - 08:00.
    * SmartThings gets info about A1 level and output device with MQTT.
      * Both these virtual devices receives and sends information with different topics. If update came from MQTT, won't send updates about the changes -> loop protected
      * Changes can happen from SmartThings, causing change on PC; or on PC, causing update to device state in SmartThings
      * Output level is numeric device without unit information for easier parsing (message is in form `<numeric value> <unit>`)
      * Output device in SmartThings is just switch - on means speakers, off means headphones. Message payload uses strings "Speakers" and "Headphones" however - those are just mapped to switch states both sending and receiving.
    * If volume is higher than -24dB and output is through speakers, lower it to -24dB (=low enough during night, I live in flat aparment)
    * Switch between headphones and speakers with Voicemeeter macro buttons are loading certain configurations. Speaker configuration has default A1 volume of -9dB which is perfect during daytime.
      * The speaker power handling has noticeable delay (MQTT->Cloud->Cloud->Cloud->Socket, see speaker power above), so the order of operations and threading has usually changed volume already when the speakers actually get power. Though as it is a race - most of the time SmartThings has ordered the lower volume already before Tuya has turned the socket on.

### Plans
I want to implement these in some point:
* ~~Send information if there's active wake lock preventing PC to sleep~~ way too much hassle. Found some [examples](https://github.com/diversenok/Powercfg) but it still requires admin permissions and I don't want to run this script as admin.

These needs some love:
* Voicemeeter thread ~~might~~ does not initialize properly if the thread has died once - gracefully or not
  * Prevents audio automations
  * Currently not killing threads every 24 hours, which seems to help. ~~Restart counter could also work, so that the script triggers ctrl-c internally if restart count of any thread is over, let's say, 20. I planned to run the script as a service in the first place so that would handle the process cycling and solve the problem - though it's not exactly elegant way of doing it. MQTT heartbeats are also noted by SmartThings so it's possible to give alert to my phone if my computer is answering to ping but the script hasn't send heartbeat in 5 minutes or something.~~ Did exactly that, ~~time tells if it helped~~ which did the trick. Time to convert the script as service. The counter could be even less than 20.

## mqtt-handler-log-reader.ps1
Quick'n'dirty reader for the mqtt-handler.ps1 logs

As the logs are rotated by day and the day is part of the filename, you need to restart `get-content -wait` each time day changes. I don't want to do that so wrote little something which is doing that for me :DD It actually reads log location and date syntax from the parameters file and the parameter file name is only hardcoding it contains. It even kills the listener job when you press ctrl-c. Yay, even more threading ":D". And because of that, the output of the logfile is bit stuttery if you are reading the log during the day as the reader loop has 50ms sleep in the end of each iteration.