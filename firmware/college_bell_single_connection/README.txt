ESP-01S bell: single Firebase connection OOM correction

Your log confirmed Wi-Fi, internet time and Firebase connected. The previous
two-client sketch ran out of RAM when it needed another secure TLS connection.
This version removes the streaming FirebaseData object entirely. Every Firebase
read and write uses one fbdo object, sequentially. TLS certificate checking stays enabled.

SETUP
Extract this folder. Copy your existing secrets.h into it.
Open college_bell_single_connection.ino and upload using your working ESP8266 settings.
Keep both supplied headers beside the sketch. Serial Monitor: 115200 baud.
First line must say: Bell starting. Single-connection version. Relay OFF.
Wait for READY, then click Manual Ring in Flutter.

BEHAVIOR
Button checked approximately once per second (plus request/network delay).
Mode/schedule refreshed approximately every 15 seconds (plus request delay).
GPIO0 active-LOW, fixed 5-second pulse, fixed IST scheduling.
Existing Firebase paths retained. No Flutter schema changes required.
Old true at startup/reconnection is cleared without ringing: click again after READY.
10-second cooldown after each pulse; manual requests near scheduled bells may be rejected.
RAM-only schedule; a powered device can use its cached schedule during an outage,
up to 24 hours since time sync. Restart requires internet to reload/time-sync.
config/ringDurationSec and config/timezone remain unused.
One boolean is not a queue; rapid clicks can combine. No exactly-once guarantee.

This removes the overlapping TLS connections seen at the OOM failure point.
Compilation cannot prove actual peak heap use on your module: hardware retesting required.
