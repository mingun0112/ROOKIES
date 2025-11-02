// ESP32_BLE_imu_sensor.cpp
// iOS 호환 BLE 버전 - IMU Sensor

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <Wire.h>
#include <ArduinoJson.h>
#include <Preferences.h>

#define MPU_ADDR 0x68

// ───────── BLE 설정 ─────────
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define RX_CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define TX_CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a9"

BLEServer* pServer = NULL;
BLECharacteristic* pTxCharacteristic = NULL;
BLECharacteristic* pRxCharacteristic = NULL;
bool deviceConnected = false;
String receivedData = "";

// ───────── WiFi & MQTT 설정 ─────────
Preferences preferences;
String ssid = "";
String password = "";
const char* mqtt_server = "211.107.16.45";
const int   mqtt_port   = 51883;
const char* topic_pub   = "degree/mpu";

WiFiClient espClient;
PubSubClient client(espClient);

// ───────── 센서 데이터 ─────────
int16_t AcX, AcY, AcZ, GyX, GyY, GyZ;
float accel_angle_x, accel_angle_y;
float gyro_x, gyro_y;
float filtered_angle_x = 0.0f;
float filtered_angle_y = 0.0f;

int16_t gyro_offset_x = 0;
int16_t gyro_offset_y = 0;
int16_t gyro_offset_z = 0;

unsigned long prev_time = 0;
float dt;
const float ALPHA = 0.96f;

bool wifi_configured = false;
bool is_running = false;

// ───────── 함수 선언 ─────────
void initBLE();
void initMPU6050();
void calibrateSensors();
void readAccelGyro();
void updateDeltaTime();
void computeAngles();
void printAnglesAndPublish();
float mapFloat(float x, float in_min, float in_max, float out_min, float out_max);
void setup_wifi();
void reconnect();
void handleCommand(String command);
void sendBLEResponse(String message);
void loadWiFiConfig();
void saveWiFiConfig();
void loadCalibration();
void saveCalibration();

// ───────── BLE 콜백 클래스 ─────────
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("✅ BLE Device connected");
    }

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("❌ BLE Device disconnected");
      BLEDevice::startAdvertising();
    }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      std::string rxValue = pCharacteristic->getValue();
      
      if (rxValue.length() > 0) {
        receivedData += String(rxValue.c_str());
        
        if (receivedData.indexOf('\n') != -1) {
          receivedData.trim();
          Serial.println("BLE RX: " + receivedData);
          handleCommand(receivedData);
          receivedData = "";
        }
      }
    }
};

// ───────── SETUP ─────────
void setup() {
  Serial.begin(115200);
  delay(1000);

  preferences.begin("imu-config", false);
  
  initBLE();
  
  loadWiFiConfig();
  loadCalibration();

  Wire.begin(21, 22);
  Wire.setClock(400000);

  initMPU6050();
  
  if (wifi_configured) {
    setup_wifi();
    client.setServer(mqtt_server, mqtt_port);
    prev_time = micros();
    is_running = true;
    Serial.println("✅ Auto-started with saved WiFi config");
  } else {
    Serial.println("⚠️ WiFi not configured. Use BLE to setup.");
  }
}

// ───────── LOOP ─────────
void loop() {
  if (is_running) {
    if (!client.connected()) reconnect();
    client.loop();

    readAccelGyro();
    updateDeltaTime();
    computeAngles();
    printAnglesAndPublish();

    delay(10);
  } else {
    delay(100);
  }
}

// ───────── BLE 초기화 ─────────
void initBLE() {
  BLEDevice::init("IMU_Sensor_ESP32");
  
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  pTxCharacteristic = pService->createCharacteristic(
                        TX_CHARACTERISTIC_UUID,
                        BLECharacteristic::PROPERTY_NOTIFY
                      );
  pTxCharacteristic->addDescriptor(new BLE2902());
  
  pRxCharacteristic = pService->createCharacteristic(
                        RX_CHARACTERISTIC_UUID,
                        BLECharacteristic::PROPERTY_WRITE
                      );
  pRxCharacteristic->setCallbacks(new MyCallbacks());
  
  pService->start();
  
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  
  Serial.println("🔵 BLE Started: IMU_Sensor_ESP32");
}

// ───────── BLE 응답 전송 ─────────
void sendBLEResponse(String message) {
  if (deviceConnected && pTxCharacteristic != NULL) {
    pTxCharacteristic->setValue(message.c_str());
    pTxCharacteristic->notify();
    delay(10);
  }
}

// ───────── 명령 처리 ─────────
void handleCommand(String command) {
  StaticJsonDocument<256> doc;
  DeserializationError error = deserializeJson(doc, command);
  
  if (error) {
    sendBLEResponse("{\"status\":\"error\",\"message\":\"Invalid JSON\"}");
    return;
  }
  
  String cmd = doc["cmd"].as<String>();
  
  if (cmd == "set_wifi") {
    ssid = doc["ssid"].as<String>();
    password = doc["password"].as<String>();
    saveWiFiConfig();
    sendBLEResponse("{\"status\":\"success\",\"message\":\"WiFi config saved\"}");
    
    setup_wifi();
    if (WiFi.status() == WL_CONNECTED) {
      client.setServer(mqtt_server, mqtt_port);
      wifi_configured = true;
      is_running = true;
      prev_time = micros();
      sendBLEResponse("{\"status\":\"success\",\"message\":\"WiFi connected\"}");
    } else {
      sendBLEResponse("{\"status\":\"error\",\"message\":\"WiFi connection failed\"}");
    }
  }
  else if (cmd == "calibrate") {
    sendBLEResponse("{\"status\":\"info\",\"message\":\"Calibration started\"}");
    calibrateSensors();
    saveCalibration();
    sendBLEResponse("{\"status\":\"success\",\"message\":\"Calibration completed\"}");
  }
  else if (cmd == "start") {
    if (wifi_configured) {
      is_running = true;
      prev_time = micros();
      sendBLEResponse("{\"status\":\"success\",\"message\":\"Sensor started\"}");
    } else {
      sendBLEResponse("{\"status\":\"error\",\"message\":\"WiFi not configured\"}");
    }
  }
  else if (cmd == "stop") {
    is_running = false;
    sendBLEResponse("{\"status\":\"success\",\"message\":\"Sensor stopped\"}");
  }
  else if (cmd == "status") {
    StaticJsonDocument<256> response;
    response["wifi_configured"] = wifi_configured;
    response["is_running"] = is_running;
    response["wifi_connected"] = (WiFi.status() == WL_CONNECTED);
    response["mqtt_connected"] = client.connected();
    response["ssid"] = ssid;
    
    String output;
    serializeJson(response, output);
    sendBLEResponse(output);
  }
  else if (cmd == "reconnect_wifi") {
    setup_wifi();
    if (WiFi.status() == WL_CONNECTED) {
      sendBLEResponse("{\"status\":\"success\",\"message\":\"WiFi reconnected\"}");
    } else {
      sendBLEResponse("{\"status\":\"error\",\"message\":\"WiFi reconnection failed\"}");
    }
  }
}

// ───────── WiFi 설정 저장/로드 ─────────
void saveWiFiConfig() {
  preferences.putString("ssid", ssid);
  preferences.putString("password", password);
  preferences.putBool("configured", true);
}

void loadWiFiConfig() {
  wifi_configured = preferences.getBool("configured", false);
  if (wifi_configured) {
    ssid = preferences.getString("ssid", "");
    password = preferences.getString("password", "");
    Serial.println("Loaded WiFi: " + ssid);
  }
}

// ───────── Calibration 저장/로드 ─────────
void saveCalibration() {
  preferences.putShort("gyro_x_off", gyro_offset_x);
  preferences.putShort("gyro_y_off", gyro_offset_y);
  preferences.putShort("gyro_z_off", gyro_offset_z);
  Serial.println("✅ Calibration saved");
}

void loadCalibration() {
  gyro_offset_x = preferences.getShort("gyro_x_off", 0);
  gyro_offset_y = preferences.getShort("gyro_y_off", 0);
  gyro_offset_z = preferences.getShort("gyro_z_off", 0);
  if (gyro_offset_x != 0 || gyro_offset_y != 0) {
    Serial.printf("Loaded calibration: X=%d, Y=%d, Z=%d\n", 
                  gyro_offset_x, gyro_offset_y, gyro_offset_z);
  }
}

// ───────── Wi-Fi 연결 ─────────
void setup_wifi() {
  Serial.println("Connecting to WiFi: " + ssid);
  WiFi.begin(ssid.c_str(), password.c_str());
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✅ WiFi connected!");
    Serial.print("IP: "); Serial.println(WiFi.localIP());
  } else {
    Serial.println("\n❌ WiFi connection failed");
  }
}

// ───────── MQTT 재연결 ─────────
void reconnect() {
  if (!client.connected()) {
    Serial.print("MQTT Connecting...");
    if (client.connect("ESP32_MPU_Publisher")) {
      Serial.println("✅ Connected to broker");
    } else {
      Serial.printf("Failed (rc=%d)\n", client.state());
      delay(3000);
    }
  }
}

// ───────── MPU6050 초기화 ─────────
void initMPU6050() {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B);
  Wire.write(0);
  Wire.endTransmission(true);
  Serial.println("✅ MPU6050 initialized");
}

// ───────── 자이로 오프셋 보정 ─────────
void calibrateSensors() {
  const int N = 200;
  long sumGyX = 0, sumGyY = 0, sumGyZ = 0;

  Serial.println("🔧 Gyro offset calibration...");
  for (int i = 0; i < N; i++) {
    readAccelGyro();
    sumGyX += GyX;
    sumGyY += GyY;
    sumGyZ += GyZ;
    delay(5);
  }

  gyro_offset_x = sumGyX / N;
  gyro_offset_y = sumGyY / N;
  gyro_offset_z = sumGyZ / N;

  Serial.printf("✅ Calibration: X=%d, Y=%d, Z=%d\n", 
                gyro_offset_x, gyro_offset_y, gyro_offset_z);
}

// ───────── 시간 갱신 ─────────
void updateDeltaTime() {
  unsigned long now = micros();
  dt = (now - prev_time) / 1000000.0f;
  prev_time = now;
}

// ───────── 센서 읽기 ─────────
void readAccelGyro() {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, 14, true);

  AcX = Wire.read() << 8 | Wire.read();
  AcY = Wire.read() << 8 | Wire.read();
  AcZ = Wire.read() << 8 | Wire.read();
  Wire.read(); Wire.read();
  GyX = (Wire.read() << 8 | Wire.read()) - gyro_offset_x;
  GyY = (Wire.read() << 8 | Wire.read()) - gyro_offset_y;
  GyZ = (Wire.read() << 8 | Wire.read()) - gyro_offset_z;
}

// ───────── 각도 계산 ─────────
void computeAngles() {
  float ax = AcX / 16384.0f;
  float ay = AcY / 16384.0f;
  float az = AcZ / 16384.0f;

  accel_angle_x = atan2(ay, sqrt(ax * ax + az * az)) * 180.0f / M_PI;
  accel_angle_y = atan2(-ax, sqrt(ay * ay + az * az)) * 180.0f / M_PI;

  gyro_x = GyX / 131.0f;
  gyro_y = GyY / 131.0f;

  float tmp_angle_x = filtered_angle_x + gyro_x * dt;
  float tmp_angle_y = filtered_angle_y + gyro_y * dt;

  filtered_angle_x = ALPHA * tmp_angle_x + (1.0f - ALPHA) * accel_angle_x;
  filtered_angle_y = ALPHA * tmp_angle_y + (1.0f - ALPHA) * accel_angle_y;
}

// ───────── 출력 + MQTT 발행 ─────────
void printAnglesAndPublish() {
  float pitch_corrected = filtered_angle_x + 90.0f;
  float p = pitch_corrected;
  float weight_factor = 1.0f;

  if      (p >= 0 && p < 10)   weight_factor = mapFloat(p, 0, 10, 10.0f, 4.0f);
  else if (p >= 10 && p < 30)   weight_factor = mapFloat(p, 10, 30, 4.0f, 3.1f);
  else if (p >= 30 && p < 40)   weight_factor = mapFloat(p, 30, 40, 3.1f, 2.3f);
  else if (p >= 40 && p < 60)   weight_factor = mapFloat(p, 40, 60, 2.3f, 1.5f);
  else if (p >= 60 && p < 80)   weight_factor = mapFloat(p, 60, 80, 1.5f, 9.0f/8.0f);
  else if (p >= 80 && p < 100)  weight_factor = mapFloat(p, 80, 100, 9.0f/8.0f, 9.0f/8.0f);
  else if (p >= 100 && p < 120) weight_factor = mapFloat(p, 100, 120, 9.0f/8.0f, 1.5f);
  else if (p >= 120 && p < 140) weight_factor = mapFloat(p, 120, 140, 1.5f, 2.1f);
  else if (p >= 140 && p < 160) weight_factor = mapFloat(p, 140, 160, 2.1f, 5.0f);
  else                          weight_factor = 1.0f;

  float display_roll = filtered_angle_y * weight_factor;

  if (pitch_corrected > 90.0f) pitch_corrected = 90.0f;
  if (pitch_corrected < 25.0f)  pitch_corrected = 25.0f;
  if (display_roll   < 0.0f)    display_roll   = 0.0f;
  if (display_roll   > 95.0f)   display_roll   = 95.0f;

  StaticJsonDocument<128> doc;
  doc["elbow"] = pitch_corrected;
  doc["wrist"] = display_roll;
  char buffer[128];
  serializeJson(doc, buffer);
  client.publish(topic_pub, buffer);

  Serial.printf("→ [MPU] Elbow: %.2f°, Wrist: %.2f°\n", pitch_corrected, display_roll);
}

float mapFloat(float x, float in_min, float in_max, float out_min, float out_max) {
  return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}