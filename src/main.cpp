#include <Arduino.h>
#include "secrets.h"
#include <ESP8266WiFi.h>
#include <Firebase_ESP_Client.h>
#include <WiFiUdp.h>
#include <NTPClient.h>

#define RELAY_PIN 0
#define DEPARTMENT_ID "icbs"
#define MAX_SCHEDULE 20

// =============================
// Schedule Storage
// =============================
int scheduleTimes[MAX_SCHEDULE];
int scheduleCount = 0;
int lastTriggeredMinute = -1;
String lastLoadedMode = "";

// =============================
// Firebase
// =============================
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

// =============================
// NTP
// =============================
WiFiUDP ntpUDP;
const long utcOffsetInSeconds = 19800;
NTPClient timeClient(ntpUDP, "pool.ntp.org", utcOffsetInSeconds);

// =============================
// Timers
// =============================
unsigned long lastModePoll = 0;
unsigned long lastManualPoll = 0;
unsigned long lastTimeCheck = 0;
unsigned long lastNtpUpdate = 0;
unsigned long lastScheduleReload = 0;   // NEW

// ===================================================
// LOAD SCHEDULE FROM FIREBASE
// ===================================================
void loadSchedule(String mode) {

  scheduleCount = 0;

  String path = "/departments/";
  path += DEPARTMENT_ID;
  path += "/schedules/";
  path += mode;
  path += "/times";

  Serial.print("Loading schedule from ");
  Serial.println(path);

  if (Firebase.RTDB.getArray(&fbdo, path.c_str())) {

    FirebaseJsonArray &arr = fbdo.jsonArray();
    size_t len = arr.size();

    for (size_t i = 0; i < len && i < MAX_SCHEDULE; i++) {
      FirebaseJsonData result;
      arr.get(result, i);
      scheduleTimes[i] = result.intValue;
      scheduleCount++;
    }

    Serial.print("Loaded ");
    Serial.print(scheduleCount);
    Serial.println(" schedule entries");

  } else {
    Serial.println("Schedule load FAILED");
    Serial.println(fbdo.errorReason());
  }
}

// ===================================================
// TRIGGER BELL
// ===================================================
void triggerBell(int currentMinute) {

  Serial.println("🔔 BELL TRIGGERED");

  digitalWrite(RELAY_PIN, LOW);
  delay(5000);
  digitalWrite(RELAY_PIN, HIGH);

  lastTriggeredMinute = currentMinute;
}

// ===================================================
// SETUP
// ===================================================
void setup() {

  Serial.begin(115200);
  delay(2000);

  Serial.println("\n=== BOOT ===");

  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, HIGH);

  // WiFi
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi Connected");

  // Firebase
  config.database_url = DATABASE_URL;
  config.signer.tokens.legacy_token = FIREBASE_LEGACY_TOKEN;
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  // NTP
  timeClient.begin();
  timeClient.update();
  lastNtpUpdate = millis();

  // Load schedule at boot
  String basePath = "/departments/";
  basePath += DEPARTMENT_ID;
  String modePath = basePath + "/mode";

  if (Firebase.RTDB.getString(&fbdo, modePath.c_str())) {
    lastLoadedMode = fbdo.stringData();
    loadSchedule(lastLoadedMode);
  }

  lastScheduleReload = millis();
}

// ===================================================
// LOOP
// ===================================================
void loop() {

  // =============================================
  // TIME CHECK — every 1 second
  // =============================================
  if (millis() - lastTimeCheck > 1000) {

    lastTimeCheck = millis();

    // NTP update every 60 seconds
    if (millis() - lastNtpUpdate > 60000) {
      timeClient.update();
      lastNtpUpdate = millis();
    }

    int hours = timeClient.getHours();
    int minutes = timeClient.getMinutes();
    int currentMinute = hours * 60 + minutes;

    // Check schedule match
    for (int i = 0; i < scheduleCount; i++) {

      if (currentMinute == scheduleTimes[i] &&
          lastTriggeredMinute != currentMinute) {

        triggerBell(currentMinute);
      }
    }
  }

  // =============================================
  // MODE CHECK — every 30 sec
  // =============================================
  if (millis() - lastModePoll > 30000) {

    lastModePoll = millis();

    String basePath = "/departments/";
    basePath += DEPARTMENT_ID;
    String modePath = basePath + "/mode";

    if (Firebase.RTDB.getString(&fbdo, modePath.c_str())) {

      String currentMode = fbdo.stringData();

      if (currentMode != lastLoadedMode) {
        lastLoadedMode = currentMode;
        loadSchedule(currentMode);
      }
    }
  }

  // =============================================
  // SCHEDULE RELOAD — every 60 sec (NEW)
  // =============================================
  if (millis() - lastScheduleReload > 60000) {

    lastScheduleReload = millis();

    if (lastLoadedMode != "") {
      loadSchedule(lastLoadedMode);
    }
  }

  // =============================================
  // MANUAL CHECK — every 5 sec
  // =============================================
  if (millis() - lastManualPoll > 5000) {

    lastManualPoll = millis();

    String manualPath = "/departments/";
    manualPath += DEPARTMENT_ID;
    manualPath += "/manualRing";

    if (Firebase.RTDB.getBool(&fbdo, manualPath.c_str())) {

      if (fbdo.boolData()) {

        int hours = timeClient.getHours();
        int minutes = timeClient.getMinutes();
        int currentMinute = hours * 60 + minutes;

        triggerBell(currentMinute);

        Firebase.RTDB.setBool(&fbdo, manualPath.c_str(), false);
      }
    }
  }
}
