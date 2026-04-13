/*
  ESP32-C6 Aquarium Light Relay
  ─────────────────────────────
  • Connects to WiFi + MQTT broker
  • Syncs time via NTP (falls back to internal clock on WiFi loss)
  • Schedule stored in NVS — survives reboot AND WiFi outage
  • MQTT topics (all under house/relay1/):
      house/relay1/set              → "ON" / "OFF"  (manual override)
      house/relay1/schedule/set     → {"on":"08:00","off":"22:00"}
      house/relay1/status           ← publishes "ON"/"OFF" every 30s
      house/relay1/schedule/get     → triggers schedule publish
      house/relay1/schedule/current ← publishes current schedule
*/

#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <Preferences.h>
#include <time.h>

#define WIFI_SSID        "The Cottage"
#define WIFI_PASS        "spruces209"
#define MQTT_HOST        "192.168.0.32"
#define MQTT_PORT        1883
#define MQTT_CLIENT_ID   "esp32c6-relay1"

#define RELAY_PIN        0
#define RELAY_ACTIVE_LOW false

#define NTP_SERVER       "pool.ntp.org"
#define TZ_OFFSET_SEC    (-5 * 3600)
#define DST_OFFSET_SEC   3600

const char* TOPIC_SET       = "house/relay1/set";
const char* TOPIC_STATUS    = "house/relay1/status";
const char* TOPIC_SCHED_SET = "house/relay1/schedule/set";
const char* TOPIC_SCHED_GET = "house/relay1/schedule/get";
const char* TOPIC_SCHED_PUB = "house/relay1/schedule/current";

WiFiClient   wifiClient;
PubSubClient mqtt(wifiClient);
Preferences  prefs;

int schedOnH  = 8,  schedOnM  = 0;
int schedOffH = 22, schedOffM = 0;
bool schedEnabled = true;
bool relayState = false;

void relayWrite(bool on) {
  relayState = on;
  int lvl = on ? HIGH : LOW;
  if (RELAY_ACTIVE_LOW) lvl = !lvl;
  digitalWrite(RELAY_PIN, lvl);
}

void saveSchedule() {
  prefs.begin("relay", false);
  prefs.putInt("onH",  schedOnH);
  prefs.putInt("onM",  schedOnM);
  prefs.putInt("offH", schedOffH);
  prefs.putInt("offM", schedOffM);
  prefs.putBool("en",  schedEnabled);
  prefs.end();
  Serial.printf("[NVS] Saved %02d:%02d → %02d:%02d\n", schedOnH, schedOnM, schedOffH, schedOffM);
}

void loadSchedule() {
  prefs.begin("relay", true);
  schedOnH     = prefs.getInt("onH",  8);
  schedOnM     = prefs.getInt("onM",  0);
  schedOffH    = prefs.getInt("offH", 22);
  schedOffM    = prefs.getInt("offM", 0);
  schedEnabled = prefs.getBool("en",  true);
  prefs.end();
  Serial.printf("[NVS] Loaded %02d:%02d → %02d:%02d\n", schedOnH, schedOnM, schedOffH, schedOffM);
}

void applySchedule() {
  if (!schedEnabled) return;
  struct tm t;
  if (!getLocalTime(&t)) return;
  int nowMin = t.tm_hour * 60 + t.tm_min;
  int onMin  = schedOnH  * 60 + schedOnM;
  int offMin = schedOffH * 60 + schedOffM;
  bool shouldBeOn = (onMin < offMin)
    ? (nowMin >= onMin && nowMin < offMin)
    : (nowMin >= onMin || nowMin < offMin);
  if (shouldBeOn != relayState) {
    relayWrite(shouldBeOn);
    Serial.printf("[Schedule] Relay → %s at %02d:%02d\n",
                  shouldBeOn ? "ON" : "OFF", t.tm_hour, t.tm_min);
  }
}

void publishStatus()   { mqtt.publish(TOPIC_STATUS, relayState ? "ON" : "OFF", true); }
void publishSchedule() {
  char buf[40];
  snprintf(buf, sizeof(buf), "{\"on\":\"%02d:%02d\",\"off\":\"%02d:%02d\"}",
           schedOnH, schedOnM, schedOffH, schedOffM);
  mqtt.publish(TOPIC_SCHED_PUB, buf, true);
}

void mqttCallback(char* topic, byte* payload, unsigned int len) {
  char msg[64] = {0};
  memcpy(msg, payload, min(len, (unsigned int)63));
  Serial.printf("[MQTT] %s → %s\n", topic, msg);

  if (strcmp(topic, TOPIC_SET) == 0) {
    if (strcmp(msg, "ON") == 0)  { relayWrite(true);  publishStatus(); }
    if (strcmp(msg, "OFF") == 0) { relayWrite(false); publishStatus(); }
    return;
  }
  if (strcmp(topic, TOPIC_SCHED_SET) == 0) {
    int oH, oM, fH, fM;
    if (sscanf(msg, "{\"on\":\"%d:%d\",\"off\":\"%d:%d\"}", &oH, &oM, &fH, &fM) == 4) {
      schedOnH = oH; schedOnM = oM; schedOffH = fH; schedOffM = fM;
      saveSchedule(); publishSchedule();
    } else Serial.println("[MQTT] Bad schedule format");
    return;
  }
  if (strcmp(topic, TOPIC_SCHED_GET) == 0) publishSchedule();
}

void connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;
  Serial.printf("[WiFi] Connecting to %s", WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  uint8_t tries = 0;
  while (WiFi.status() != WL_CONNECTED && tries < 20) { delay(500); Serial.print('.'); tries++; }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\n[WiFi] IP: %s\n", WiFi.localIP().toString().c_str());
    configTime(TZ_OFFSET_SEC, DST_OFFSET_SEC, NTP_SERVER);
  } else Serial.println("\n[WiFi] Failed — running from NVS");
}

void connectMQTT() {
  if (mqtt.connected()) return;
  Serial.printf("[MQTT] Connecting to %s:%d\n", MQTT_HOST, MQTT_PORT);
  if (mqtt.connect(MQTT_CLIENT_ID, nullptr, nullptr, TOPIC_STATUS, 0, true, "OFFLINE")) {
    Serial.println("[MQTT] Connected");
    mqtt.subscribe(TOPIC_SET);
    mqtt.subscribe(TOPIC_SCHED_SET);
    mqtt.subscribe(TOPIC_SCHED_GET);
    publishStatus(); publishSchedule();
  } else Serial.printf("[MQTT] Failed rc=%d\n", mqtt.state());
}

uint32_t lastScheduleCheck = 0;
uint32_t lastStatusPub     = 0;
uint32_t lastReconnect     = 0;

void setup() {
  Serial.begin(115200);
  delay(1500);
  Serial.println("\n=== Aquarium Relay Boot ===");
  pinMode(RELAY_PIN, OUTPUT);
  relayWrite(false);
  loadSchedule();
  connectWiFi();
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  for (int i = 0; i < 3 && !mqtt.connected(); i++) { connectMQTT(); if (!mqtt.connected()) delay(2000); }
  applySchedule();
}

void loop() {
  uint32_t now = millis();
  if (now - lastReconnect > 30000)     { lastReconnect = now; connectWiFi(); connectMQTT(); }
  mqtt.loop();
  if (now - lastScheduleCheck > 30000) { lastScheduleCheck = now; applySchedule(); }
  if (now - lastStatusPub > 30000)     { lastStatusPub = now; if (mqtt.connected()) publishStatus(); }
  delay(10);
}
