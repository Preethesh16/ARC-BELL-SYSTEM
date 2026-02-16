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

  Serial.println("\n=== BOOT ===");

  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, HIGH);
  Serial.println("Relay default OFF");

  // ---------- WIFI ----------
  Serial.print("Connecting WiFi → ");
  Serial.println(WIFI_SSID);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("\nWiFi CONNECTED");
  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());

  // ---------- FIREBASE ----------
  Serial.println("Initializing Firebase (Legacy Token)...");

  config.database_url = DATABASE_URL;
  config.signer.tokens.legacy_token = FIREBASE_LEGACY_TOKEN;

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  Serial.println("Firebase initialized successfully");
}

void loop() {

  if (millis() - lastCheck > 5000) {

    lastCheck = millis();

    Serial.println("\n--- Firebase Poll ---");

    // ===== Read Mode =====
    Serial.print("Reading /bellSystem/mode ... ");

    if (Firebase.RTDB.getString(&fbdo, "/bellSystem/mode")) {
      Serial.print("SUCCESS → ");
      Serial.println(fbdo.stringData());
    } 
    else {
      Serial.print("FAIL → ");
      Serial.println(fbdo.errorReason());
    }

    // ===== Read manualRing =====
    Serial.print("Reading /bellSystem/manualRing ... ");

    if (Firebase.RTDB.getBool(&fbdo, "/bellSystem/manualRing")) {

      bool flag = fbdo.boolData();

      Serial.print("SUCCESS → ");
      Serial.println(flag ? "true" : "false");

      if (flag) {

        Serial.println("ACTION: Trigger relay");

        digitalWrite(RELAY_PIN, LOW);
        Serial.println("Relay ON");

        delay(3000);

        digitalWrite(RELAY_PIN, HIGH);
        Serial.println("Relay OFF");

        Serial.print("Resetting manualRing to false... ");

        if (Firebase.RTDB.setBool(&fbdo, "/bellSystem/manualRing", false)) {
          Serial.println("WRITE SUCCESS");
        } 
        else {
          Serial.print("WRITE FAIL → ");
          Serial.println(fbdo.errorReason());
        }
      }
    } 
    else {
      Serial.print("FAIL → ");
      Serial.println(fbdo.errorReason());
    }
  }
}
