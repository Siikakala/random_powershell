# MQTT shenanigans
I want locally control my main PC thru MQTT. You can find scripts for that here.

They depend on MQTTX cli client, which you can download from [MQTTX cli website](https://mqttx.app/cli#download)

## mqtt-handler.ps1
Utility running on my main computer running Windows 10. There's several parts:
* Main thread
* MQTT listener
* MQTT Sender
* Voicemeeter Potato handler
* Process Watcher

Main thread handles the script output and thread lifecycling
MQTT Listener parses whatever mqttx client spits out and reacts to the messages as needed
MQTT Sender sends updates to topics listened by SmartThings virtual devices
Voicemeeter Potato handler is handling all the Voicemeeter API calls and informs sender if user changed something (A1 volume or device)
Process watcher triggers actions in SmartThings (utilising LAN Triggers) and Voicemeeter (changing MacroButtons button states) whenever watched process is running and stops

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
It achieves several things:

* Automating light scenes
  * Uses LAN Triggers as Process Watcher is using this mainly
    * Separate triggers when prcess is detected running and when it stops
    * Also saves up device count - one LAN Trigger device in SmartThings can handle 19 different triggers, so, 9 on-off triggers with one spare trigger
  * When OBS is running, certain scene triggers so there's enough light to my face
  * When I'm using PS Remote Play, another scene triggers so there's minimal reflections to my display
    * PS5 is connected to my monitor, so, no speakers. I'm actually using that input in display while controller input is going through remote play
* Automating PC audio
  * Enforcing maximum volume level between 21:30 - 08:00.
    * SmartThings gets info about A1 level and output device with MQTT.
      * Output level is numeric device without unit information for easier parsing (message is in form "<numeric value> <unit>")
        * Receives and sends information with different topics. If update came from MQTT, won't send updates about the changes -> loop protected
      * Output device in SmartThings is just switch - on means speakers, off means headphones
        * Changes can happen from ST, causing change on PC; or on PC, causing update to device state
    * If volume is higher than -24dB and output is through speakers, lower it to -24dB.
    * -24dB is low enough that I cannot hear the speakers to other room with door open.
    * This has already helped me to not blast music too loudly as I switch between headphones and speakers with Voicemeeter macro buttons, which are loading certain configurations. Speaker configuration has default A1 volume of -9dB which is perfect during daytime.
  * Handling speaker power
    * I have active speakers, which are connected to smart outlet and if I'm listening with headphones, the power will be turned off. And back on when output is switched to speakers
  * Triggering MacroButtons
    * MQTT message can switch between headphones and speakers by triggering macrobutton loading correct Voicemeeter configuration
    * Process watcher can lower music level when I'm playing

### Plans
I want to implement these in some point:
* Put PC to sleep with MQTT trigger
  * Might require some shenanigans, depends on if it needs admin privileges or not
* Send information if user is idle or not
* Send information if there's active wake lock preventing PC to sleep

These needs some love:
* Voicemeeter thread might not initialize properly if the thread has died once - grafefully or not
  * Prevents audio automations
  * Also requires to kill the whole process, with it's pane/console window to get working again
* Harmonize data payload structures - voicemeeter returns data in different form than what it receives.