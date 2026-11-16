// ESP-01S GPIO0 active-LOW relay module.
// One Firebase connection. No filesystem initialization required.

#include <Arduino.h>
#include "bell_support.h"
#include <ESP8266WiFi.h>
#include <Firebase_ESP_Client.h>
#include <ArduinoJson.h>
#include <Ticker.h>
#include <coredecls.h>
#include <time.h>
#include <stdarg.h>
#include "tls_roots.h"

#if __has_include("secrets.h")
#include "secrets.h"
#elif __has_include("secret.h")
#include "secret.h"
#else
#error "Copy your existing secrets.h into this sketch folder before uploading."
#endif

constexpr uint8_t RELAY_PIN = 0;

const String BASE = "/departments/icbs";

// Only ONE FirebaseData object.
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

bell::LiveFeed feed;
Ticker offTimer;

WiFiEventHandler disconnectHandler;

volatile uint8_t wifiFailureReason = 0;
volatile bool relayOn = false;
volatile bool syncPending = false;
volatile bool offNotice = false;
volatile uint32_t offAt = 0;

uint32_t pulseStart = 0;

uint32_t lastStreamAttempt = 0;
uint32_t lastConfigAttempt = 0;
uint32_t lastReconnect = 0;
uint32_t lastStatus = 0;
uint32_t lastRepair = 0;
uint32_t refreshRevision = 0;
uint32_t lastCleanup = 0;

// These names are retained from the earlier sketch.
// No Firebase streaming connection is used.
bool streamStarted = false;
bool attemptedStream = false;
bool refreshActive = false;

uint8_t refreshPhase = 0;

String pendingMode;
bell::Schedule pendingSchedule;

const char* pendingStatus = nullptr;
uint32_t resultTime = 0;
uint32_t configAppliedAt = 0;

bool configStatusPending = false;
bool ringStatusPending = false;

const char* lastRingSource = "none";
uint32_t lastRingStartedAt = 0;
uint32_t lastRingEndedAt = 0;
uint32_t lastRingDurationMs = 0;

char lastRingMode[33] = {};

// Schedule/state are held in RAM for this boot.
// No flash files are needed.
class RamStore : public bell::Store {
 public:
  bool save(const bell::State&) override {
    return true;
  }
} storage;

bell::Engine engine(storage);

uint32_t scheduledPulses = 0;
uint32_t manualPulses = 0;
uint32_t manualRejected = 0;
uint32_t lateSkipped = 0;
uint32_t reconnectAttempts = 0;
uint32_t maxServiceGap = 0;
uint32_t lastServiceMs = 0;

bool servicedBefore = false;

// --------------------------------------------------
// Simple Serial messages
// --------------------------------------------------

void logLine(
  const char* tag,
  const char* format,
  ...
) __attribute__((format(printf, 2, 3)));

void logLine(const char* tag, const char* format, ...) {
  char message[224];

  va_list args;
  va_start(args, format);
  vsnprintf(message, sizeof(message), format, args);
  va_end(args);

  // Hide routine diagnostic chatter.
  if (!strcmp(tag, "COUNTERS") ||
      !strcmp(tag, "LOOP") ||
      !strcmp(tag, "STATE") ||
      !strcmp(tag, "STORAGE") ||
      !strcmp(tag, "HELP") ||
      !strcmp(tag, "TIME") ||
      !strcmp(tag, "WIFI") ||
      !strcmp(tag, "STATUS")) {
    return;
  }

  if (!strcmp(tag, "BOOT")) {
    Serial.printf(
      "Bell starting. Guarded single-connection version. "
      "Relay OFF. Reset: %s\n",
      ESP.getResetReason().c_str()
    );
    return;
  }

  if (!strcmp(tag, "READY")) {
    Serial.println("READY. Click Manual Ring in Flutter.");
    return;
  }

  if (!strcmp(tag, "RELAY")) {
    Serial.println(message);
    return;
  }

  if (!strcmp(tag, "MANUAL")) {
    if (strstr(message, "result=started") ||
        strstr(message, "new true edge") ||
        strstr(message, "old true baseline")) {
      return;
    }

    if (strstr(message, "stale_request_cleared")) {
      Serial.println(
        "Old request cleared. Click Manual Ring again after READY."
      );
    } else if (strstr(message, "ack_failed")) {
      Serial.println(
        "Bell NOT rung: could not reset the Firebase request. "
        "Check Firebase write access/connection."
      );
    } else if (strstr(message, "read_failed")) {
      Serial.println(
        "Bell NOT rung: could not read the Firebase request."
      );
    } else if (strstr(message, "busy")) {
      Serial.println(
        "Bell NOT rung: cooldown or scheduled bell is too close. "
        "Try again in 15 seconds."
      );
    } else if (strstr(message, "expired")) {
      Serial.println(
        "Bell NOT rung: request took too long. Click again."
      );
    } else if (strstr(message, "cancelled")) {
      Serial.println(
        "Bell NOT rung: request was already cleared."
      );
    } else {
      Serial.println(
        "Bell NOT rung: device is not ready."
      );
    }

    return;
  }

  if (!strcmp(tag, "STREAM")) {
    if (strstr(message, "connecting to")) {
      return;
    }

    if (strstr(message, "snapshot received")) {
      Serial.println("Firebase connected.");
    } else {
      Serial.print("Firebase: ");
      Serial.println(message);
    }

    return;
  }

  if (!strcmp(tag, "CONFIG")) {
    if (strstr(message, "refresh") ||
        strstr(message, "applied in RAM")) {
      return;
    }

    Serial.print("Schedule: ");
    Serial.println(message);
    return;
  }

  Serial.println(message);
}

void timeText(uint32_t utc, char* output, size_t size) {
  if (utc < bell::MIN_EPOCH) {
    snprintf(output, size, "UNSYNCED");
    return;
  }

  time_t local = static_cast<time_t>(utc) + bell::OFFSET;
  struct tm fields;

  if (!gmtime_r(&local, &fields)) {
    snprintf(output, size, "INVALID");
    return;
  }

  strftime(
    output,
    size,
    "%Y-%m-%d %H:%M:%S IST",
    &fields
  );
}

const char* operatingState() {
  if (engine.fault) {
    return "STORAGE_FAULT";
  }

  if (!engine.clockOK(uint32_t(time(nullptr)), millis())) {
    return "WAITING_FOR_TIME";
  }

  if (engine.schedulePaused) {
    return "WAITING_FOR_NEW_CONFIG";
  }

  if (!engine.state.schedule.count ||
      !engine.state.schedule.days) {
    return "NO_ACTIVE_TIMES";
  }

  if (WiFi.status() != WL_CONNECTED) {
    return "CACHED_WIFI_OFFLINE";
  }

  if (!feed.baseline) {
    return "CACHED_STREAM_OFFLINE";
  }

  return "LIVE";
}

void printSchedule() {
  const auto& s = engine.state.schedule;

  logLine(
    "SCHEDULE",
    "mode='%s' count=%u daysMask=%u (Sun=1 ... Sat=64)",
    s.mode,
    unsigned(s.count),
    unsigned(s.days)
  );

  for (unsigned i = 0; i < s.count; ++i) {
    logLine(
      "SCHEDULE",
      "%02u: %02u:%02u IST; minute=%u",
      i + 1,
      unsigned(s.times[i] / 60),
      unsigned(s.times[i] % 60),
      unsigned(s.times[i])
    );
  }

  if (!s.count || !s.days) {
    logLine(
      "SCHEDULE",
      "automatic schedule is empty or disabled"
    );
  }
}

void printStatus() {
  if (WiFi.status() != WL_CONNECTED) {
    switch (wifiFailureReason) {
      case 201:
        Serial.println(
          "Wi-Fi network not found. "
          "Check the Wi-Fi name, range and 2.4 GHz network."
        );
        break;

      case 202:
        Serial.println(
          "Wi-Fi login failed. "
          "Check the password and router security settings."
        );
        break;

      case 15:
      case 204:
        Serial.println(
          "Wi-Fi handshake timed out. "
          "Check password, signal and router security settings."
        );
        break;

      default:
        Serial.printf(
          "Wi-Fi not connected. Retrying. Router reason: %u\n",
          unsigned(wifiFailureReason)
        );
        break;
    }

    return;
  }

  if (!engine.clockOK(uint32_t(time(nullptr)), millis())) {
    Serial.println(
      "Wi-Fi connected, but waiting for internet time. "
      "Firebase connection waits for this."
    );
    return;
  }

  if (!feed.baseline) {
    Serial.println(
      "Wi-Fi and time OK. Waiting for Firebase; "
      "see any Firebase error above."
    );
    return;
  }

  if (feed.configUnconfirmed) {
    Serial.println(
      "Firebase connected. Waiting for a valid schedule."
    );
    return;
  }

  Serial.printf(
    "Connected. Bell %s. Mode: %s. Schedule: %u times.\n",
    relayOn ? "ON" : "OFF",
    engine.state.schedule.mode,
    unsigned(engine.state.schedule.count)
  );
}

void serialHelp() {
  Serial.println(
    "Commands: status, schedule. Use Flutter to ring the bell."
  );
}

void serviceSerial() {
  static char line[24];
  static size_t used = 0;
  static bool tooLong = false;

  for (unsigned i = 0; i < 32 && Serial.available(); ++i) {
    int c = Serial.read();

    if (c == '\r') {
      continue;
    }

    if (c == '\n') {
      line[used] = 0;

      if (tooLong) {
        logLine("SERIAL", "command too long; send help");
      } else if (!strcmp(line, "status")) {
        printStatus();
      } else if (!strcmp(line, "schedule")) {
        printSchedule();
      } else if (!strcmp(line, "help")) {
        serialHelp();
      } else if (used) {
        logLine("SERIAL", "unknown command; send help");
      }

      used = 0;
      tooLong = false;
    } else if (c >= 32 && c < 127 && !tooLong) {
      if (used + 1 < sizeof(line)) {
        line[used++] = static_cast<char>(c);
      } else {
        tooLong = true;
      }
    }
  }
}

void logTransitions() {
  static int previousWifi = -1;
  static int previousTime = -1;
  static uint8_t previousReason = 0;

  bool connected = WiFi.status() == WL_CONNECTED;

  if (int(connected) != previousWifi) {
    if (connected) {
      Serial.println(
        "Wi-Fi connected. Getting internet time..."
      );
      wifiFailureReason = 0;
    } else {
      Serial.println("Connecting to Wi-Fi...");
    }

    previousWifi = connected;
  }

  if (!connected &&
      wifiFailureReason &&
      wifiFailureReason != previousReason) {
    printStatus();
  }

  previousReason = wifiFailureReason;

  bool valid = engine.clockOK(
    uint32_t(time(nullptr)),
    millis()
  );

  if (valid && previousTime != 1) {
    Serial.println("Time OK. Connecting to Firebase...");
  }

  previousTime = valid;
}

// --------------------------------------------------
// Relay control
// --------------------------------------------------

void relayOff() {
  digitalWrite(RELAY_PIN, HIGH);

  // Record the first OFF only.
  if (relayOn) {
    offAt = millis();
    relayOn = false;
    offNotice = true;
  }
}

void serviceRelay() {
  // Backup OFF check if the timer has not switched it off.
  if (relayOn &&
      bell::elapsed(millis(), pulseStart) >= bell::PULSE_MS) {
    relayOff();
  }

  // Explicit OFF output while idle.
  if (!relayOn) {
    digitalWrite(RELAY_PIN, HIGH);
  }

  if (offNotice) {
    offNotice = false;

    lastRingDurationMs = bell::elapsed(offAt, pulseStart);
    lastRingEndedAt =
      lastRingStartedAt + lastRingDurationMs / 1000;

    ringStatusPending = true;

    logLine(
      "RELAY",
      "Bell OFF commanded after %lums.",
      static_cast<unsigned long>(lastRingDurationMs)
    );
  }
}

void pulse(bell::Result result) {
  if (result != bell::Result::Scheduled &&
      result != bell::Result::Manual) {

    if (result == bell::Result::Late) {
      ++lateSkipped;

      logLine(
        "SKIP",
        "scheduled time exceeded 15-second grace; no late replay"
      );
    } else if (result == bell::Result::Busy) {
      logLine(
        "SKIP",
        "busy/cooldown or scheduled boundary guard"
      );
    } else if (result == bell::Result::StorageFault) {
      logLine(
        "FAULT",
        "state update failed; relay inhibited"
      );
    } else if (result == bell::Result::ClockReset) {
      logLine(
        "CLOCK",
        "time step detected; current minute will not replay"
      );
    }

    return;
  }

  // Never extend an active pulse.
  if (relayOn) {
    Serial.println(
      "Bell request ignored: a pulse is already running."
    );
    return;
  }

  serviceRelay();

  offTimer.detach();

  // Prepare OFF timer while the relay is still inactive.
  offTimer.once_ms(bell::PULSE_MS, relayOff);

  lastRingStartedAt = uint32_t(time(nullptr));

  lastRingSource =
    result == bell::Result::Manual
      ? "firebase_manual"
      : "schedule";

  strncpy(
    lastRingMode,
    engine.state.schedule.mode,
    sizeof(lastRingMode)
  );

  lastRingMode[sizeof(lastRingMode) - 1] = '\0';

  lastRingEndedAt = 0;
  lastRingDurationMs = 0;

  if (result == bell::Result::Scheduled) {
    ++scheduledPulses;
  } else {
    ++manualPulses;
  }

  pulseStart = millis();
  relayOn = true;

  digitalWrite(RELAY_PIN, LOW);

  char when[40];
  timeText(lastRingStartedAt, when, sizeof(when));

  logLine(
    "RELAY",
    "Bell ON: %s; %s; mode=%s; OFF in 5 seconds.",
    result == bell::Result::Manual
      ? "Firebase manual request"
      : "schedule",
    when,
    lastRingMode
  );
}

void serviceBell() {
  engine.schedulePaused =
    feed.baseline && feed.configUnconfirmed;

  uint32_t ms = millis();

  if (servicedBefore) {
    uint32_t gap = bell::elapsed(ms, lastServiceMs);

    if (gap > maxServiceGap) {
      maxServiceGap = gap;
    }

    if (gap > 2000) {
      logLine(
        "LOOP",
        "service gap=%lums; check network latency",
        static_cast<unsigned long>(gap)
      );
    }
  }

  servicedBefore = true;
  lastServiceMs = ms;

  if (syncPending) {
    syncPending = false;
    engine.synced(ms);
    logLine("TIME", "SNTP synchronization received");
  }

  serviceRelay();
  pulse(engine.tick(uint32_t(time(nullptr)), ms));
}

// --------------------------------------------------
// Firebase connection and manual request polling
// --------------------------------------------------

bool validMode(const String& name) {
  if (!name.length() || name.length() > 32) {
    return false;
  }

  bell::Schedule s{};
  name.toCharArray(s.mode, sizeof(s.mode));

  return bell::valid(s);
}

void report(const char* result) {
  pendingStatus = result;
  resultTime = uint32_t(time(nullptr));

  if (strcmp(result, "started")) {
    ++manualRejected;
  }

  logLine("MANUAL", "result=%s", result);
}

void loseConnection() {
  streamStarted = false;
  attemptedStream = true;
  lastStreamAttempt = millis();

  feed.disconnect();
  refreshActive = false;
}

void pollManualButton() {
  uint32_t ms = millis();

  // Normal polling: 1 second.
  // Retry after a connection failure: 3 seconds.
  uint32_t interval = streamStarted ? 1000 : 3000;

  if (attemptedStream &&
      bell::elapsed(ms, lastStreamAttempt) < interval) {
    return;
  }

  attemptedStream = true;

  bool ok = Firebase.RTDB.getBool(
    &fbdo,
    (BASE + "/manualRing").c_str()
  );

  lastStreamAttempt = millis();

  if (!ok) {
    Serial.printf(
      "Firebase read failed: %s. Retrying.\n",
      fbdo.errorReason().c_str()
    );

    loseConnection();
    return;
  }

  bool value = fbdo.boolData();

  if (!streamStarted) {
    streamStarted = true;

    // Initial true is treated as an old request.
    feed.apply(
      "put",
      "/",
      value
        ? "{\"manualRing\":true}"
        : "{\"manualRing\":false}",
      millis()
    );

    Serial.println(
      "Firebase connected (single connection)."
    );
  } else {
    feed.apply(
      "put",
      "/manualRing",
      value ? "true" : "false",
      millis()
    );
  }
}

// --------------------------------------------------
// Read mode, read schedule, verify mode, then apply
// --------------------------------------------------

void refreshConfig() {
  if (!refreshActive) {
    if (!feed.configDirty ||
        bell::elapsed(millis(), lastConfigAttempt) < 1000) {
      return;
    }

    refreshActive = true;
    refreshPhase = 0;
    refreshRevision = feed.revision;
    lastConfigAttempt = millis();

    logLine(
      "CONFIG",
      "refresh started revision=%lu",
      static_cast<unsigned long>(refreshRevision)
    );
  }

  if (refreshRevision != feed.revision) {
    refreshActive = false;

    logLine(
      "CONFIG",
      "changed during fetch; restarting refresh"
    );

    return;
  }

  if (refreshPhase == 0) {
    if (!Firebase.RTDB.getString(
          &fbdo,
          (BASE + "/mode").c_str()
        ) ||
        !validMode(fbdo.stringData())) {

      refreshActive = false;

      logLine(
        "CONFIG",
        "mode read/validation failed HTTP=%d; cache retained",
        fbdo.httpCode()
      );

      return;
    }

    pendingMode = fbdo.stringData();

    if (pendingMode != engine.state.schedule.mode) {
      feed.configUnconfirmed = true;
    }

    refreshPhase = 1;

  } else if (refreshPhase == 1) {
    String path = BASE + "/schedules/" + pendingMode;

    if (!Firebase.RTDB.getJSON(&fbdo, path.c_str()) ||
        !bell::parseSchedule(
          fbdo.payload().c_str(),
          pendingMode.c_str(),
          pendingSchedule
        )) {

      refreshActive = false;

      logLine(
        "CONFIG",
        "schedule read/validation failed HTTP=%d; cache retained",
        fbdo.httpCode()
      );

      return;
    }

    refreshPhase = 2;

  } else {
    refreshActive = false;

    if (!Firebase.RTDB.getString(
          &fbdo,
          (BASE + "/mode").c_str()
        ) ||
        fbdo.stringData() != pendingMode) {

      logLine(
        "CONFIG",
        "mode verification failed/changed; not committing stale fetch"
      );

      return;
    }

    if (engine.configure(pendingSchedule)) {
      feed.refreshed(refreshRevision);

      configAppliedAt = uint32_t(time(nullptr));
      configStatusPending = true;

      logLine(
        "CONFIG",
        "applied in RAM; mode='%s' entries=%u",
        pendingSchedule.mode,
        unsigned(pendingSchedule.count)
      );

      static bool announcedReady = false;

      if (!announcedReady) {
        logLine("READY", "ready");
        announcedReady = true;
      }

    } else {
      logLine(
        "FAULT",
        "configuration rejected; check schedule data"
      );
    }
  }
}

// --------------------------------------------------
// Acknowledge manual request before ringing
// --------------------------------------------------

struct ButtonTransport {
  String etag;

  bool read(bool& value) {
    if (!Firebase.RTDB.getBool(
          &fbdo,
          (BASE + "/manualRing").c_str()
        )) {
      return false;
    }

    value = fbdo.boolData();
    etag = fbdo.ETag();

    return true;
  }

  bool clear() {
    return etag.length() &&
      Firebase.RTDB.setBool(
        &fbdo,
        (BASE + "/manualRing").c_str(),
        false,
        etag.c_str()
      );
  }
};

void consumeButton() {
  if (!feed.pending &&
      bell::elapsed(millis(), lastCleanup) < 3000) {
    return;
  }

  lastCleanup = millis();

  ButtonTransport transport;

  auto ack = bell::acknowledgeButton(
    feed,
    transport,
    []() {
      return millis();
    }
  );

  switch (ack) {
    case bell::ButtonAck::ReadFailed:
      report("read_failed_no_ring");
      loseConnection();
      return;

    case bell::ButtonAck::WriteFailed:
      report("ack_failed_no_ring");
      loseConnection();
      return;

    case bell::ButtonAck::StaleCleared:
      report("stale_request_cleared");
      return;

    case bell::ButtonAck::Expired:
      report("expired_locally");
      return;

    case bell::ButtonAck::Cancelled:
      report("cancelled_before_ack");
      return;

    case bell::ButtonAck::Ready:
      break;

    default:
      return;
  }

  serviceBell();

  bell::Result result = engine.legacyButton(
    uint32_t(time(nullptr)),
    millis()
  );

  pulse(result);

  report(
    result == bell::Result::Manual
      ? "started"
      : result == bell::Result::Busy
        ? "busy"
        : "not_ready"
  );
}

// --------------------------------------------------
// Publish latest diagnostic information after ringing
// --------------------------------------------------

void publishStatus() {
  if (!pendingStatus &&
      !configStatusPending &&
      !ringStatusPending) {
    return;
  }

  FirebaseJson json;

  if (ringStatusPending) {
    // Software commands only, not physical relay feedback.
    json.set("lastRing/source", lastRingSource);
    json.set("lastRing/mode", lastRingMode);
    json.set("lastRing/startedAt", double(lastRingStartedAt));
    json.set("lastRing/offCommandAt", double(lastRingEndedAt));
    json.set("lastRing/durationMs", double(lastRingDurationMs));
  }

  if (pendingStatus) {
    json.set("manualResult", pendingStatus);
    json.set("manualResultAt", double(resultTime));
  }

  if (configStatusPending) {
    FirebaseJsonArray times;

    for (unsigned i = 0;
         i < engine.state.schedule.count;
         ++i) {
      times.add(engine.state.schedule.times[i]);
    }

    json.set("appliedMode", engine.state.schedule.mode);
    json.set("appliedDaysMask", engine.state.schedule.days);
    json.set("appliedTimes", times);
    json.set("configAppliedAt", double(configAppliedAt));
  }

  if (Firebase.RTDB.updateNode(
        &fbdo,
        (BASE + "/deviceStatus").c_str(),
        &json
      )) {

    pendingStatus = nullptr;
    configStatusPending = false;
    ringStatusPending = false;

    logLine("STATUS", "deviceStatus published");
  }
}

// --------------------------------------------------
// Setup
// --------------------------------------------------

void setup() {
  // Set OFF latch before configuring the output.
  digitalWrite(RELAY_PIN, HIGH);
  pinMode(RELAY_PIN, OUTPUT);

  Serial.begin(115200);

  logLine(
    "BOOT",
    "ESP-01S bell; relay OFF; reset=%s",
    ESP.getResetReason().c_str()
  );

  WiFi.persistent(false);
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);

  disconnectHandler = WiFi.onStationModeDisconnected(
    [](const WiFiEventStationModeDisconnected& event) {
      wifiFailureReason =
        static_cast<uint8_t>(event.reason);
    }
  );

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  settimeofday_cb([]() {
    syncPending = true;
  });

  // System clock remains UTC.
  // bell_support.h applies the IST offset for schedules.
  configTime(
    0,
    0,
    "pool.ntp.org",
    "time.google.com",
    "time.cloudflare.com"
  );

  config.database_url = DATABASE_URL;
  config.signer.tokens.legacy_token =
    FIREBASE_LEGACY_TOKEN;

  config.cert.data = BELL_TLS_ROOTS;

  config.timeout.socketConnection = 1500;
  config.timeout.serverResponse = 1500;

  fbdo.setBSSLBufferSize(4096, 1024);
  fbdo.setResponseSize(2048);

  Firebase.begin(&config, &auth);

  // Firebase ESP Client 4.4.17: actual TLS handshake timeout.
  fbdo.tcpClient.client()->setHandshakeTimeout(5);

  // Wi-Fi reconnection is handled explicitly below.
  Firebase.reconnectWiFi(false);
}

// --------------------------------------------------
// Main loop
// --------------------------------------------------

void loop() {
  serviceBell();

  uint32_t ms = millis();
  uint32_t utc = uint32_t(time(nullptr));

  serviceSerial();
  logTransitions();

  // Print a short status only while something is not ready.
  if (bell::elapsed(ms, lastStatus) >= 30000) {
    lastStatus = ms;

    if (WiFi.status() != WL_CONNECTED ||
        !engine.clockOK(utc, ms) ||
        !feed.baseline ||
        feed.configUnconfirmed) {
      printStatus();
    }
  }

  // Do not perform Firebase requests while the relay is ON.
  if (relayOn) {
    delay(1);
    return;
  }

  if (WiFi.status() != WL_CONNECTED ||
      !engine.clockOK(utc, ms)) {

    if (streamStarted) {
      loseConnection();
    }

    if (WiFi.status() != WL_CONNECTED &&
        bell::elapsed(ms, lastReconnect) >= 30000) {

      lastReconnect = ms;
      WiFi.reconnect();
    }

    delay(1);
    return;
  }

  if (engine.fault) {
    delay(1);
    return;
  }

  pollManualButton();
  serviceBell();

  if (relayOn || !feed.baseline || engine.fault) {
    delay(1);
    return;
  }

  if (feed.pending || feed.cleanup) {
    consumeButton();

  } else if (feed.configDirty || refreshActive) {
    refreshConfig();

  } else if (!engine.nearScheduled(uint32_t(time(nullptr)))) {

    // Schedule refresh takes priority over diagnostic uploads.
    if (bell::elapsed(ms, lastRepair) >= 15000) {
      lastRepair = ms;
      feed.configDirty = true;

    } else if (
      (pendingStatus || configStatusPending || ringStatusPending) &&
      bell::elapsed(ms, lastCleanup) >= 1000
    ) {
      lastCleanup = ms;
      publishStatus();
    }
  }

  serviceBell();
  delay(1);
}