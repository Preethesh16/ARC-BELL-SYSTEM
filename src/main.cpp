#include <Arduino.h>
#include "secrets.h"
#include <ESP8266WiFi.h>
#include <Firebase_ESP_Client.h>

#define RELAY_PIN 0

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

unsigned long lastCheck = 0;

void setup() {
  Serial.begin(115200);
  delay(2000);

  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, HIGH);

  // -------- WiFi ----------
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("WiFi connecting");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi OK");

  // -------- Firebase ----------
  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;

  // anonymous auth
  auth.user.email = "";
  auth.user.password = "";

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  Serial.println("Firebase ready");
}

void loop() {

  if (millis() - lastCheck > 5000) {
    lastCheck = millis();

    // ---- read mode ----
    if (Firebase.RTDB.getString(&fbdo, "/bellSystem/mode")) {
      Serial.print("Mode = ");
      Serial.println(fbdo.stringData());
    } else {
      Serial.print("Mode read error: ");
      Serial.println(fbdo.errorReason());
    }

    // ---- manual ring ----
    if (Firebase.RTDB.getBool(&fbdo, "/bellSystem/manualRing")) {
      if (fbdo.boolData()) {
        Serial.println("Manual ring trigger!");

        digitalWrite(RELAY_PIN, LOW);
        delay(3000);
        digitalWrite(RELAY_PIN, HIGH);

        Firebase.RTDB.setBool(&fbdo, "/bellSystem/manualRing", false);
      }
    }
  }
}
