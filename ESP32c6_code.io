/*
 * ESP32-C6 Plant Moisture Monitoring System
 * Board: Seeed Studio XIAO ESP32C6
 * * FIXES:
 * 1. Fixed "empty character constant" error by securing the HTML string.
 * 2. ArduinoJson v7 compatible.
 * 3. Correct Pinout for XIAO C6.
 */

#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>
#include <DHT.h>

// ============================================
// CONFIGURATION - CHANGE THESE FOR YOUR SETUP
// ============================================

// WiFi Configuration - CHANGE THESE!
const char* ssid = "The Cottage";          
const char* password = "spruces209";  

// Hardware Configuration - XIAO ESP32C6 Specifics
// D0=0, D1=1, D2=2, D3=23, D4=22
const int SENSOR_PINS[] = {0};  
const int NUM_SENSORS = 1;                    

// RELAY (Physical D6 = GPIO 20 on XIAO C6)
const int RELAY_PIN = 20;    

// DHT SENSOR (Physical D5 = GPIO 23 on XIAO C6)
const int DHT_PIN = 23;      
const int DHT_TYPE = DHT11;  // Change to DHT22 if using the white sensor

// Calibration values
const int DRY_VALUE = 6;      
const int WET_VALUE = 1755;      

// Sensor reading thresholds
const int SENSOR_MIN_VALID = 500;   
const int SENSOR_MAX_VALID = 4000;  

// ============================================
// END OF CONFIGURATION
// ============================================

// Web Server
WebServer server(80);

// DHT Sensor
DHT dht(DHT_PIN, DHT_TYPE);

// Global variables
bool relayState = false;
unsigned long startTime = 0;
int sensorReadings[NUM_SENSORS];
float moisturePercentages[NUM_SENSORS];
bool sensorConnected[NUM_SENSORS];
float temperature = 0.0;
float humidity = 0.0;
bool dhtConnected = false;

// HTML CODE STORAGE (Moved here to prevent syntax errors)
const char index_html[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ESP32 Plant Monitor</title>
  <style>
    body { font-family: monospace; background: #000; color: #0f0; padding: 20px; text-align: center; max-width: 600px; margin: 0 auto; }
    h1 { color: #0f0; margin-bottom: 10px; }
    .section { border: 2px solid #0f0; padding: 15px; margin: 20px 0; background: #001100; }
    .sensor { margin: 8px 0; padding: 8px; border: 1px solid #0f0; background: #000; }
    .relay-btn { background: #000; color: #0f0; border: 2px solid #0f0; padding: 15px 30px; font-size: 18px; cursor: pointer; margin: 10px; width: 200px; }
    .relay-btn:hover { background: #0f0; color: #000; }
    .relay-on { background: #0f0; color: #000; }
    .env { font-size: 20px; margin: 10px 0; }
  </style>
</head>
<body>
  <h1>🌱 ESP32 Plant Monitor</h1>
  <div class="section">
    <h2>Environment</h2>
    <div id="environment">Loading...</div>
  </div>
  <div class="section">
    <h2>Soil Moisture</h2>
    <div id="sensors">Loading...</div>
  </div>
  <div class="section">
    <h2>Watering Control</h2>
    <button class="relay-btn" id="relayBtn" onclick="toggleRelay()">Relay: ...</button>
  </div>
  <script>
    function loadData() {
      fetch('/api/sensors')
        .then(res => res.json())
        .then(data => {
          // Environment
          var envHtml = '';
          if (data.dhtConnected) {
            envHtml += '<div class="env">🌡️ ' + data.temperature.toFixed(1) + '°C</div>';
            envHtml += '<div class="env">💧 ' + data.humidity.toFixed(1) + '% Hum</div>';
          } else {
            envHtml = '<div style="color:#f00">DHT Disconnected</div>';
          }
          document.getElementById('environment').innerHTML = envHtml;
          
          // Sensors
          var html = '';
          for (var i = 0; i < data.sensors.length; i++) {
            var s = data.sensors[i];
            var status = s.connected ? (s.moisture.toFixed(1) + '%') : 'Disconnected';
            var icon = s.connected ? (s.moisture < 30 ? '🌵' : s.moisture < 60 ? '🌿' : '💧') : '❌';
            html += '<div class="sensor">' + icon + ' Sensor ' + s.id + ': ' + status + '</div>';
          }
          document.getElementById('sensors').innerHTML = html;
          
          // Relay
          var btn = document.getElementById('relayBtn');
          btn.innerText = 'Relay: ' + data.relay.toUpperCase();
          btn.className = data.relay === 'on' ? 'relay-btn relay-on' : 'relay-btn';
        });
    }
    
    function toggleRelay() {
      fetch('/api/relay', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({state: 'toggle'})
      }).then(() => setTimeout(loadData, 200));
    }
    
    setInterval(loadData, 2000);
    loadData();
  </script>
</body>
</html>
)rawliteral";

// Function prototypes
void setupWiFi();
void setupServer();
void readSensors();
void readDHT();
float convertToMoisture(int adcValue);
void handleRoot();
void handleGetSensors();
void handlePostRelay();
void handleGetStatus();
void handleNotFound();
String getUptimeString();

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n\n=== ESP32-C6 Plant Monitor ===");
  
  // Initialize relay
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);
  
  // Initialize sensors
  for (int i = 0; i < NUM_SENSORS; i++) {
    pinMode(SENSOR_PINS[i], INPUT);
  }
  
  dht.begin();
  setupWiFi();
  setupServer();
  server.begin();
  
  startTime = millis();
  readSensors();
  readDHT();
}

void loop() {
  server.handleClient();
  
  static unsigned long lastSoilReadTime = 0;
  if (millis() - lastSoilReadTime >= 2000) {
    readSensors();
    lastSoilReadTime = millis();
  }
  
  static unsigned long lastDHTReadTime = 0;
  if (millis() - lastDHTReadTime >= 5000) {
    readDHT();
    lastDHTReadTime = millis();
  }
}

void setupWiFi() {
  Serial.print("Connecting to: ");
  Serial.println(ssid);
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 40) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  Serial.println();
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("✓ Connected! IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("✗ Connection failed.");
  }
}

void setupServer() {
  server.enableCORS(true);
  server.on("/", HTTP_GET, handleRoot);
  server.on("/api/sensors", HTTP_GET, handleGetSensors);
  server.on("/api/relay", HTTP_POST, handlePostRelay);
  server.on("/api/status", HTTP_GET, handleGetStatus);
  server.onNotFound(handleNotFound);
}

void readSensors() {
  Serial.println("Reading sensors...");
  for (int i = 0; i < NUM_SENSORS; i++) {
    int total = 0;
    for (int j = 0; j < 5; j++) {
      total += analogRead(SENSOR_PINS[i]);
      delay(10);
    }
    int rawValue = total / 5;
    sensorReadings[i] = rawValue;
    
    if (rawValue < SENSOR_MIN_VALID || rawValue > SENSOR_MAX_VALID) {
      sensorConnected[i] = false;
      moisturePercentages[i] = -1;
    } else {
      sensorConnected[i] = true;
      moisturePercentages[i] = convertToMoisture(rawValue);
    }
  }
}

void readDHT() {
  float h = dht.readHumidity();
  float t = dht.readTemperature();
  if (isnan(h) || isnan(t)) {
    dhtConnected = false;
  } else {
    dhtConnected = true;
    humidity = h;
    temperature = t;
  }
}

float convertToMoisture(int adcValue) {
  if (adcValue <= DRY_VALUE) return 0.0;
  else if (adcValue >= WET_VALUE) return 100.0;
  else {
    float percentage = ((float)(adcValue - DRY_VALUE) / (float)(WET_VALUE - DRY_VALUE)) * 100.0;
    return constrain(percentage, 0.0, 100.0);
  }
}

void handleRoot() {
  server.send(200, "text/html", index_html);
}

void handleGetSensors() {
  JsonDocument doc; // ArduinoJson v7
  JsonArray sensors = doc.createNestedArray("sensors");
  
  for (int i = 0; i < NUM_SENSORS; i++) {
    JsonObject sensor = sensors.createNestedObject();
    sensor["id"] = i + 1;
    sensor["pin"] = SENSOR_PINS[i];
    sensor["connected"] = sensorConnected[i];
    sensor["raw"] = sensorReadings[i];
    if (sensorConnected[i]) {
      sensor["moisture"] = round(moisturePercentages[i] * 10) / 10.0;
    } else {
      sensor["moisture"] = nullptr;
    }
  }
  
  if (dhtConnected) {
    doc["temperature"] = round(temperature * 10) / 10.0;
    doc["humidity"] = round(humidity * 10) / 10.0;
  } else {
    doc["temperature"] = nullptr;
    doc["humidity"] = nullptr;
  }
  doc["dhtConnected"] = dhtConnected;
  doc["relay"] = relayState ? "on" : "off";
  
  String response;
  serializeJson(doc, response);
  server.send(200, "application/json", response);
}

void handlePostRelay() {
  if (server.method() == HTTP_OPTIONS) {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200);
    return;
  }
  
  JsonDocument doc; // ArduinoJson v7
  DeserializationError error = deserializeJson(doc, server.arg("plain"));
  
  if (error) {
    server.send(400, "application/json", "{\"error\":\"Invalid JSON\"}");
    return;
  }
  
  const char* stateStr = doc["state"];
  if (stateStr) {
      if (strcmp(stateStr, "on") == 0) relayState = true;
      else if (strcmp(stateStr, "off") == 0) relayState = false;
      else if (strcmp(stateStr, "toggle") == 0) relayState = !relayState;
  }
  
  digitalWrite(RELAY_PIN, relayState ? HIGH : LOW);
  
  JsonDocument response;
  response["relay"] = relayState ? "on" : "off";
  response["success"] = true;
  
  String responseStr;
  serializeJson(response, responseStr);
  server.send(200, "application/json", responseStr);
}

void handleGetStatus() {
  JsonDocument doc; // ArduinoJson v7
  doc["ip"] = WiFi.localIP().toString();
  doc["rssi"] = WiFi.RSSI();
  doc["relay"] = relayState ? "on" : "off";
  doc["uptime"] = getUptimeString();
  
  String response;
  serializeJson(doc, response);
  server.send(200, "application/json", response);
}

void handleNotFound() {
  server.send(404, "application/json", "{\"error\":\"Not found\"}");
}

String getUptimeString() {
  unsigned long uptime = millis() - startTime;
  unsigned long seconds = uptime / 1000;
  unsigned long minutes = seconds / 60;
  unsigned long hours = minutes / 60;
  unsigned long days = hours / 24;
  
  seconds %= 60;
  minutes %= 60;
  hours %= 24;
  
  String result = "";
  if (days > 0) result += String(days) + "d ";
  if (hours > 0) result += String(hours) + "h ";
  result += String(minutes) + "m " + String(seconds) + "s";
  return result;
}
