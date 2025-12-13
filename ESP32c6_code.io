/*
 * ESP32-C6 Plant Moisture Monitoring System
 * Board: Seeed Studio XIAO ESP32C6
 * * FIXES:
 * 1. Fixed "empty character constant" error by securing the HTML string.
 * 2. ArduinoJson v7 compatible.
 * 3. Correct Pinout for XIAO C6.
 * * ENHANCEMENTS:
 * 1. Historical data tracking (30-min intervals, 48 data points)
 * 2. Automatic watering scheduler with configurable interval/duration
 * 3. Manual watering with duration control and countdown
 * 4. UI improvements with graphs and countdown displays
 */

#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <Preferences.h>

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

// Preferences for persistent storage
Preferences preferences;

// Historical data structure
struct HistoricalData {
  unsigned long timestamp;
  float temperature;
  float humidity;
  float avgMoisture;
};

const int MAX_HISTORY = 48; // 48 points = 24 hours at 30-min intervals
HistoricalData history[MAX_HISTORY];
int historyCount = 0;
int historyIndex = 0;
unsigned long lastHistorySave = 0;
const unsigned long HISTORY_INTERVAL = 30UL * 60UL * 1000UL; // 30 minutes

// Automatic watering configuration
int autoWaterIntervalHours = 12;
int autoWaterDurationSeconds = 20;
unsigned long lastAutoWaterTime = 0;
unsigned long nextAutoWaterTime = 0;

// Manual watering state
bool manualWateringActive = false;
unsigned long manualWateringEndTime = 0;
int manualWateringDuration = 0;

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
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
  <style>
    body { font-family: monospace; background: #000; color: #0f0; padding: 20px; text-align: center; max-width: 800px; margin: 0 auto; }
    h1 { color: #0f0; margin-bottom: 10px; }
    h2 { color: #0f0; margin: 10px 0; font-size: 18px; }
    .section { border: 2px solid #0f0; padding: 15px; margin: 20px 0; background: #001100; }
    .sensor { margin: 8px 0; padding: 8px; border: 1px solid #0f0; background: #000; }
    .btn { background: #000; color: #0f0; border: 2px solid #0f0; padding: 12px 20px; font-size: 16px; cursor: pointer; margin: 5px; font-family: monospace; }
    .btn:hover { background: #0f0; color: #000; }
    .btn-active { background: #0f0; color: #000; }
    .env { font-size: 20px; margin: 10px 0; }
    input[type=number] { background: #000; color: #0f0; border: 2px solid #0f0; padding: 8px; font-family: monospace; width: 80px; font-size: 16px; }
    .countdown { font-size: 18px; color: #ff0; margin: 10px 0; }
    .chart-container { position: relative; height: 200px; margin: 15px 0; }
    canvas { max-height: 200px; }
    .inline-group { display: flex; align-items: center; justify-content: center; gap: 10px; margin: 10px 0; flex-wrap: wrap; }
    .setting-row { display: flex; align-items: center; justify-content: center; gap: 10px; margin: 8px 0; }
    label { color: #0f0; }
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
    <h2>Historical Data</h2>
    <div class="chart-container"><canvas id="tempChart"></canvas></div>
    <div class="chart-container"><canvas id="humidityChart"></canvas></div>
    <div class="chart-container"><canvas id="moistureChart"></canvas></div>
  </div>
  
  <div class="section">
    <h2>Manual Watering</h2>
    <div class="inline-group">
      <label>Duration (sec):</label>
      <input type="number" id="manualDuration" value="20" min="1" max="300">
      <button class="btn" onclick="startManualWatering()">Start Watering</button>
    </div>
    <div id="manualCountdown" class="countdown"></div>
  </div>
  
  <div class="section">
    <h2>Automatic Watering</h2>
    <div class="setting-row">
      <label>Interval (hours):</label>
      <input type="number" id="autoInterval" value="12" min="1" max="48">
    </div>
    <div class="setting-row">
      <label>Duration (sec):</label>
      <input type="number" id="autoDuration" value="20" min="1" max="300">
    </div>
    <button class="btn" onclick="saveAutoSettings()">Save Settings</button>
    <div id="autoCountdown" class="countdown"></div>
  </div>
  
  <script>
    let tempChart, humidityChart, moistureChart;
    
    function initCharts() {
      const chartConfig = (label, color) => ({
        type: 'line',
        data: {
          labels: [],
          datasets: [{
            label: label,
            data: [],
            borderColor: color,
            backgroundColor: 'rgba(0, 255, 0, 0.1)',
            tension: 0.3,
            pointRadius: 3
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          scales: {
            x: { ticks: { color: '#0f0', maxTicksLimit: 6 }, grid: { color: '#003300' } },
            y: { ticks: { color: '#0f0' }, grid: { color: '#003300' } }
          },
          plugins: {
            legend: { labels: { color: '#0f0', font: { family: 'monospace' } } }
          }
        }
      });
      
      tempChart = new Chart(document.getElementById('tempChart'), chartConfig('Temperature (°C)', '#0f0'));
      humidityChart = new Chart(document.getElementById('humidityChart'), chartConfig('Humidity (%)', '#0f0'));
      moistureChart = new Chart(document.getElementById('moistureChart'), chartConfig('Avg Moisture (%)', '#0f0'));
    }
    
    function updateCharts(history) {
      if (!history || history.length === 0) return;
      
      const labels = history.map(d => {
        const date = new Date(d.timestamp * 1000);
        return date.getHours() + ':' + String(date.getMinutes()).padStart(2, '0');
      });
      
      tempChart.data.labels = labels;
      tempChart.data.datasets[0].data = history.map(d => d.temperature);
      tempChart.update();
      
      humidityChart.data.labels = labels;
      humidityChart.data.datasets[0].data = history.map(d => d.humidity);
      humidityChart.update();
      
      moistureChart.data.labels = labels;
      moistureChart.data.datasets[0].data = history.map(d => d.avgMoisture);
      moistureChart.update();
    }
    
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
          
          // Manual watering countdown
          if (data.manualWateringActive) {
            document.getElementById('manualCountdown').innerHTML = 
              '⏱️ Watering: ' + data.manualWateringRemaining + 's remaining';
          } else {
            document.getElementById('manualCountdown').innerHTML = '';
          }
          
          // Auto watering countdown
          if (data.nextAutoWaterIn > 0) {
            const hours = Math.floor(data.nextAutoWaterIn / 3600);
            const mins = Math.floor((data.nextAutoWaterIn % 3600) / 60);
            document.getElementById('autoCountdown').innerHTML = 
              '⏰ Next auto-water in: ' + hours + 'h ' + mins + 'm';
          } else {
            document.getElementById('autoCountdown').innerHTML = '⏰ Auto-watering scheduled';
          }
        });
    }
    
    function loadHistory() {
      fetch('/api/history')
        .then(res => res.json())
        .then(data => {
          if (data.history) {
            updateCharts(data.history);
          }
        });
    }
    
    function loadAutoSettings() {
      fetch('/api/auto-water')
        .then(res => res.json())
        .then(data => {
          document.getElementById('autoInterval').value = data.intervalHours;
          document.getElementById('autoDuration').value = data.durationSeconds;
        });
    }
    
    function startManualWatering() {
      const duration = parseInt(document.getElementById('manualDuration').value);
      fetch('/api/manual-water', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({duration: duration})
      }).then(() => setTimeout(loadData, 200));
    }
    
    function saveAutoSettings() {
      const interval = parseInt(document.getElementById('autoInterval').value);
      const duration = parseInt(document.getElementById('autoDuration').value);
      fetch('/api/auto-water', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({intervalHours: interval, durationSeconds: duration})
      }).then(() => {
        alert('Settings saved!');
        loadAutoSettings();
      });
    }
    
    initCharts();
    loadData();
    loadHistory();
    loadAutoSettings();
    setInterval(loadData, 2000);
    setInterval(loadHistory, 60000);
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
void handleGetHistory();
void handleGetAutoWater();
void handlePostAutoWater();
void handlePostManualWater();
String getUptimeString();
void saveHistoricalData();
float getAverageMoisture();
void loadPreferences();
void saveAutoWaterSettings();
void checkAutoWatering();
void checkManualWatering();
void startWatering(int durationSeconds, bool isManual);

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
  
  // Load preferences
  loadPreferences();
  
  dht.begin();
  setupWiFi();
  setupServer();
  server.begin();
  
  startTime = millis();
  readSensors();
  readDHT();
  
  // Initialize auto-watering schedule
  nextAutoWaterTime = millis() + (autoWaterIntervalHours * 3600UL * 1000UL);
  Serial.print("Auto-watering scheduled in ");
  Serial.print(autoWaterIntervalHours);
  Serial.println(" hours");
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
  
  // Check if it's time to save historical data
  if (millis() - lastHistorySave >= HISTORY_INTERVAL) {
    saveHistoricalData();
    lastHistorySave = millis();
  }
  
  // Check automatic watering schedule
  checkAutoWatering();
  
  // Check manual watering countdown
  checkManualWatering();
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
  server.on("/api/history", HTTP_GET, handleGetHistory);
  server.on("/api/auto-water", HTTP_GET, handleGetAutoWater);
  server.on("/api/auto-water", HTTP_POST, handlePostAutoWater);
  server.on("/api/manual-water", HTTP_POST, handlePostManualWater);
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
  
  // Manual watering status
  doc["manualWateringActive"] = manualWateringActive;
  if (manualWateringActive) {
    long remaining = (long)(manualWateringEndTime - millis()) / 1000;
    doc["manualWateringRemaining"] = max(0L, remaining);
  } else {
    doc["manualWateringRemaining"] = 0;
  }
  
  // Auto watering status
  long nextAutoSecs = (long)(nextAutoWaterTime - millis()) / 1000;
  doc["nextAutoWaterIn"] = max(0L, nextAutoSecs);
  
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

void loadPreferences() {
  preferences.begin("plant-monitor", false);
  
  autoWaterIntervalHours = preferences.getInt("autoInterval", 12);
  autoWaterDurationSeconds = preferences.getInt("autoDuration", 20);
  
  // Check if data was stored recently (within 24 hours)
  unsigned long lastSaveTime = preferences.getULong("lastSaveTime", 0);
  unsigned long currentTime = millis() / 1000; // Current time in seconds since boot
  
  // If last save time exists and was recent, try to restore historical data
  if (lastSaveTime > 0) {
    historyCount = preferences.getInt("historyCount", 0);
    if (historyCount > 0 && historyCount <= MAX_HISTORY) {
      for (int i = 0; i < historyCount; i++) {
        String key = "h" + String(i);
        size_t len = preferences.getBytesLength(key.c_str());
        if (len == sizeof(HistoricalData)) {
          preferences.getBytes(key.c_str(), &history[i], sizeof(HistoricalData));
        }
      }
      historyIndex = historyCount % MAX_HISTORY;
      Serial.print("Restored ");
      Serial.print(historyCount);
      Serial.println(" historical data points");
    }
  }
  
  preferences.end();
  
  Serial.print("Loaded auto-water settings: ");
  Serial.print(autoWaterIntervalHours);
  Serial.print("h interval, ");
  Serial.print(autoWaterDurationSeconds);
  Serial.println("s duration");
}

void saveAutoWaterSettings() {
  preferences.begin("plant-monitor", false);
  preferences.putInt("autoInterval", autoWaterIntervalHours);
  preferences.putInt("autoDuration", autoWaterDurationSeconds);
  preferences.end();
  Serial.println("Auto-water settings saved");
}

void saveHistoricalData() {
  if (!dhtConnected) {
    Serial.println("Skipping historical save - DHT disconnected");
    return;
  }
  
  float avgMoisture = getAverageMoisture();
  if (avgMoisture < 0) {
    Serial.println("Skipping historical save - no moisture sensors connected");
    return;
  }
  
  // Add new data point
  history[historyIndex].timestamp = millis() / 1000;
  history[historyIndex].temperature = temperature;
  history[historyIndex].humidity = humidity;
  history[historyIndex].avgMoisture = avgMoisture;
  
  historyIndex = (historyIndex + 1) % MAX_HISTORY;
  if (historyCount < MAX_HISTORY) {
    historyCount++;
  }
  
  // Save to preferences
  preferences.begin("plant-monitor", false);
  preferences.putInt("historyCount", historyCount);
  preferences.putULong("lastSaveTime", millis() / 1000);
  
  // Save recent history points to persistent storage (save all to be safe)
  for (int i = 0; i < historyCount; i++) {
    String key = "h" + String(i);
    preferences.putBytes(key.c_str(), &history[i], sizeof(HistoricalData));
  }
  
  preferences.end();
  
  Serial.print("Historical data saved: T=");
  Serial.print(temperature);
  Serial.print("C H=");
  Serial.print(humidity);
  Serial.print("% M=");
  Serial.print(avgMoisture);
  Serial.println("%");
}

float getAverageMoisture() {
  float sum = 0;
  int count = 0;
  
  for (int i = 0; i < NUM_SENSORS; i++) {
    if (sensorConnected[i]) {
      sum += moisturePercentages[i];
      count++;
    }
  }
  
  if (count == 0) return -1;
  return sum / count;
}

void handleGetHistory() {
  JsonDocument doc;
  JsonArray historyArray = doc.createNestedArray("history");
  
  // Return data in chronological order
  int startIdx = (historyCount < MAX_HISTORY) ? 0 : historyIndex;
  for (int i = 0; i < historyCount; i++) {
    int idx = (startIdx + i) % MAX_HISTORY;
    JsonObject point = historyArray.createNestedObject();
    point["timestamp"] = history[idx].timestamp;
    point["temperature"] = round(history[idx].temperature * 10) / 10.0;
    point["humidity"] = round(history[idx].humidity * 10) / 10.0;
    point["avgMoisture"] = round(history[idx].avgMoisture * 10) / 10.0;
  }
  
  String response;
  serializeJson(doc, response);
  server.send(200, "application/json", response);
}

void handleGetAutoWater() {
  JsonDocument doc;
  doc["intervalHours"] = autoWaterIntervalHours;
  doc["durationSeconds"] = autoWaterDurationSeconds;
  
  String response;
  serializeJson(doc, response);
  server.send(200, "application/json", response);
}

void handlePostAutoWater() {
  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, server.arg("plain"));
  
  if (error) {
    server.send(400, "application/json", "{\"error\":\"Invalid JSON\"}");
    return;
  }
  
  if (doc.containsKey("intervalHours")) {
    autoWaterIntervalHours = doc["intervalHours"];
    autoWaterIntervalHours = constrain(autoWaterIntervalHours, 1, 48);
  }
  
  if (doc.containsKey("durationSeconds")) {
    autoWaterDurationSeconds = doc["durationSeconds"];
    autoWaterDurationSeconds = constrain(autoWaterDurationSeconds, 1, 300);
  }
  
  saveAutoWaterSettings();
  
  // Reschedule next auto-water
  nextAutoWaterTime = millis() + (autoWaterIntervalHours * 3600UL * 1000UL);
  
  JsonDocument response;
  response["success"] = true;
  response["intervalHours"] = autoWaterIntervalHours;
  response["durationSeconds"] = autoWaterDurationSeconds;
  
  String responseStr;
  serializeJson(response, responseStr);
  server.send(200, "application/json", responseStr);
}

void handlePostManualWater() {
  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, server.arg("plain"));
  
  if (error) {
    server.send(400, "application/json", "{\"error\":\"Invalid JSON\"}");
    return;
  }
  
  int duration = doc["duration"] | 20;
  duration = constrain(duration, 1, 300);
  
  startWatering(duration, true);
  
  JsonDocument response;
  response["success"] = true;
  response["duration"] = duration;
  
  String responseStr;
  serializeJson(response, responseStr);
  server.send(200, "application/json", responseStr);
}

void startWatering(int durationSeconds, bool isManual) {
  if (isManual) {
    manualWateringActive = true;
    manualWateringDuration = durationSeconds;
    manualWateringEndTime = millis() + (durationSeconds * 1000UL);
    
    Serial.print("Starting manual watering for ");
    Serial.print(durationSeconds);
    Serial.println(" seconds");
  } else {
    Serial.print("Starting automatic watering for ");
    Serial.print(durationSeconds);
    Serial.println(" seconds");
    
    // Schedule next auto-water
    lastAutoWaterTime = millis();
    nextAutoWaterTime = millis() + (autoWaterIntervalHours * 3600UL * 1000UL);
    
    // Use the manual watering mechanism for timing
    manualWateringActive = true;
    manualWateringDuration = durationSeconds;
    manualWateringEndTime = millis() + (durationSeconds * 1000UL);
  }
  
  // Turn on relay
  relayState = true;
  digitalWrite(RELAY_PIN, HIGH);
}

void checkAutoWatering() {
  // Don't start auto-watering if manual watering is active
  if (manualWateringActive) return;
  
  // Check if it's time for auto-watering
  if (millis() >= nextAutoWaterTime) {
    startWatering(autoWaterDurationSeconds, false);
  }
}

void checkManualWatering() {
  if (manualWateringActive) {
    if (millis() >= manualWateringEndTime) {
      // Turn off relay
      relayState = false;
      digitalWrite(RELAY_PIN, LOW);
      manualWateringActive = false;
      
      Serial.println("Watering completed");
    }
  }
}
