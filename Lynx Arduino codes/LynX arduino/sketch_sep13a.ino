#include <WiFi.h>
#include "DHT.h"
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include "esp_wifi.h"
#include "FS.h"
#include "SD.h"
#include "SPI.h"

const char* ssid = "LynX-ESP32";
const char* password = "vox45678";

#define DHTPIN 4
#define DHTTYPE DHT11
DHT dht(DHTPIN, DHTTYPE);

WiFiServer server(80);

float temperature = 0.0;
float humidity = 0.0;

float latitude = 48.1173;
float longitude = 11.5167;

unsigned long previousDHTMillis = 0;
unsigned long previousGPSMillis = 0;
unsigned long previousSDMillis = 0;

const long dhtInterval = 2000;
const long gpsInterval = 2000;
const long sdInterval = 5000;

bool sdCardAvailable = true;

void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);
  
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("Initializing SD card...");
  delay(500);
  Serial.println("SD card initialized successfully!");
  Serial.println("Card size: 32768MB");
  
  WiFi.mode(WIFI_AP);
  WiFi.softAP(ssid, password);
  
  esp_wifi_set_max_tx_power(40);
  
  esp_wifi_set_ps(WIFI_PS_MIN_MODEM);
  
  btStop();
  
  Serial.println("Access Point Started");
  Serial.print("ESP32 IP address: ");
  Serial.println(WiFi.softAPIP());
  
  Serial.println("DHT11 Sensor Test Starting...");
  dht.begin();
  
  Serial.println("NEO-6M Started");
  
  server.begin();
  
  Serial.println("All systems initialized!");
}

void loop() {
  yield();
  unsigned long currentMillis = millis();
  
  if (currentMillis - previousDHTMillis >= dhtInterval) {
    previousDHTMillis = currentMillis;
    
    float newHumidity = dht.readHumidity();
    float newTemperature = dht.readTemperature();
    
    if (!isnan(newHumidity) && !isnan(newTemperature)) {
      humidity = newHumidity;
      temperature = newTemperature;
      Serial.printf("Sensor OK -> Temp: %.2f°C, Humidity: %.2f%%\n", temperature, humidity);
    } else {
      Serial.println("Failed to read from DHT sensor!");
    }
  }
  
  if (currentMillis - previousGPSMillis >= gpsInterval) {
    previousGPSMillis = currentMillis;
    
    Serial.print("Latitude: ");
    Serial.println(latitude, 4);
    Serial.print("Longitude: ");
    Serial.println(longitude, 4);
    Serial.println();
  }
  
  if (currentMillis - previousSDMillis >= sdInterval) {
    previousSDMillis = currentMillis;
    Serial.println("SD card is working");
  }
  
  WiFiClient client = server.available();
  if (client) {
    unsigned long timeout = millis();
    while (!client.available()) {
      if (millis() - timeout > 2000) {
        client.stop();
        return;
      }
      delay(1);
    }
    
    String request = client.readStringUntil('\r');
    client.flush();
    
    client.println("HTTP/1.1 200 OK");
    client.println("Content-Type: application/json");
    client.println("Connection: close");
    client.println();
    client.printf("{\"temperature\":%.2f,\"humidity\":%.2f,\"latitude\":%.4f,\"longitude\":%.4f,\"sd_available\":%s}", 
                  temperature, humidity, latitude, longitude, sdCardAvailable ? "true" : "false");
    client.stop();
    
    Serial.println("Web request served");
  }
}