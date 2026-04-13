#include <WiFi.h>
#include <HTTPClient.h>

const char* ssid = "The Cottage";
const char* password = "spruces209";
const char* sonosIP = "192.168.0.31";
const char* bridgeIP = "192.168.0.32";

const int BUTTON_PIN = 9;

const unsigned long debounceDelay = 50;
const unsigned long doubleClickGap = 400;
const unsigned long longPressTime = 1000;

bool isPlaying = true;
int buttonState;
int lastButtonState = HIGH;
unsigned long lastDebounceTime = 0;
unsigned long lastClickTime = 0;
int clickCount = 0;
bool waitingForDouble = false;

unsigned long buttonDownTime = 0;
bool longPressHandled = false;

void setup() {
  Serial.begin(115200);
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
  Serial.println("\nWiFi Connected. Big Button Ready.");
}

void sendSonosCommand(String action) {
  if (WiFi.status() != WL_CONNECTED) return;
  HTTPClient http;
  String url = "http://" + String(sonosIP) + ":1400/MediaRenderer/AVTransport/Control";
  http.begin(url);
  http.addHeader("Content-Type", "text/xml; charset=\"utf-8\"");
  http.addHeader("SOAPACTION", "urn:schemas-upnp-org:service:AVTransport:1#" + action);
  String body = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/envelope/\">"
                "<s:Body><u:" + action + " xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">"
                "<InstanceID>0</InstanceID>";
  if (action == "Play") body += "<Speed>1</Speed>";
  body += "</u:" + action + "></s:Body></s:Envelope>";
  int code = http.POST(body);
  Serial.println(code > 0 ? action + " sent!" : "Error: " + String(code));
  http.end();
}

void playPlaylist(String playlistName) {
  if (WiFi.status() != WL_CONNECTED) return;
  HTTPClient http;
  String url = "http://" + String(bridgeIP) + ":8090/playlist";
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  String body = "{\"name\":\"" + playlistName + "\"}";
  int code = http.POST(body);
  Serial.println(code > 0 ? "Playlist '" + playlistName + "' started!" : "Playlist error: " + String(code));
  http.end();
  isPlaying = true;
}

void loop() {
  int reading = digitalRead(BUTTON_PIN);

  if (reading != lastButtonState) lastDebounceTime = millis();

  if ((millis() - lastDebounceTime) > debounceDelay) {
    if (reading != buttonState) {
      buttonState = reading;
      if (buttonState == LOW) {
        buttonDownTime = millis();
        longPressHandled = false;
      }
      if (buttonState == HIGH) {
        if (!longPressHandled) {
          clickCount++;
          lastClickTime = millis();
          waitingForDouble = true;
        }
      }
    }
  }

  if (buttonState == LOW && !longPressHandled && (millis() - buttonDownTime > longPressTime)) {
    Serial.println("Long press — playing party mode");
    playPlaylist("party mode");
    longPressHandled = true;
    clickCount = 0;
    waitingForDouble = false;
  }

  if (waitingForDouble && (millis() - lastClickTime > doubleClickGap)) {
    if (clickCount == 1) {
      if (isPlaying) { sendSonosCommand("Pause"); isPlaying = false; }
      else           { sendSonosCommand("Play");  isPlaying = true;  }
    } else if (clickCount >= 2) {
      sendSonosCommand("Next");
      isPlaying = true;
    }
    clickCount = 0;
    waitingForDouble = false;
  }

  lastButtonState = reading;

  if (Serial.available() > 0) {
    String input = Serial.readStringUntil('\n');
    input.trim();
    if      (input == "pause")    { sendSonosCommand("Pause"); isPlaying = false; }
    else if (input == "play")     { sendSonosCommand("Play");  isPlaying = true;  }
    else if (input == "skip")     sendSonosCommand("Next");
    else if (input == "playlist") playPlaylist("party mode");
  }
}
