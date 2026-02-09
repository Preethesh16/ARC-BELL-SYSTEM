#include <Arduino.h>
#include "secrets.h"
#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>

#define RELAY_PIN 0   // ESP-01 relay boards usually GPIO0

ESP8266WebServer server(80);

void handleRoot() {
  String page = "<h2>ESP Bell Control</h2>";
  page += "<a href='/on'><button style='font-size:30px'>ON</button></a><br><br>";
  page += "<a href='/off'><button style='font-size:30px'>OFF</button></a>";
  server.send(200, "text/html", page);
}

void handleOn() {
  digitalWrite(RELAY_PIN, LOW);
  server.send(200, "text/html", "Relay ON");
}

void handleOff() {
  digitalWrite(RELAY_PIN, HIGH);
  server.send(200, "text/html", "Relay OFF");
}

void setup() {
  Serial.begin(115200);

  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, HIGH);

  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println();
  Serial.print("IP address: ");
  Serial.println(WiFi.localIP());

  server.on("/", handleRoot);
  server.on("/on", handleOn);
  server.on("/off", handleOff);

  server.begin();
}

void loop() {
  server.handleClient();
}
