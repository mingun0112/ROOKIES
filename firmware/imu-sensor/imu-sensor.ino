#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <Wire.h>

// ───────── BLE UUID 정의 ─────────
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define WIFI_SCAN_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a7"
#define WIFI_SSID_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define WIFI_PASS_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define WIFI_STATUS_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26aa"
#define SENSOR_DATA_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26ab"
#define IMU_CONTROL_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26ac"  // 새로 추가!

// ───────── MPU6050 설정 ─────────
#define MPU_ADDR 0x68

// ───────── MQTT 설정 ─────────
const char* mqtt_server = "211.107.16.45";
const int mqtt_port = 51883;
const char* mqtt_topic = "degree/";

// ───────── BLE 객체 ─────────
BLEServer* pServer = NULL;
BLECharacteristic* pScanChar = NULL;
BLECharacteristic* pSSIDChar = NULL;
BLECharacteristic* pPasswordChar = NULL;
BLECharacteristic* pStatusChar = NULL;
BLECharacteristic* pSensorChar = NULL;
BLECharacteristic* pIMUControlChar = NULL;  // 새로 추가!

// ───────── WiFi & MQTT 객체 ─────────
WiFiClient espClient;
PubSubClient client(espClient);

// ───────── 상태 변수 ─────────
bool deviceConnected = false;
bool imuEnabled = false;  // IMU 활성화 상태
String wifiSSID = "";
String wifiPassword = "";
bool needToConnect = false;
bool needToScan = false;
bool wifiConnected = false;

// ───────── MPU6050 변수 ─────────
int16_t AcX, AcY, AcZ, GyX, GyY, GyZ;
float accel_angle_x, accel_angle_y;
float gyro_x, gyro_y;
float elbow = 0.0f;   // pitch
float wrist = 0.0f;   // roll

// ───────── 시간 계산 ─────────
unsigned long prev_time = 0;
unsigned long last_mqtt_send = 0;
unsigned long last_ble_send = 0;
float dt;

// ───────── 상보필터 계수 ─────────
const float ALPHA = 0.96f;
const unsigned long MQTT_INTERVAL = 100; // 100ms마다 전송
const unsigned long BLE_INTERVAL = 100;   // 100ms마다 BLE 전송

// ───────── 함수 프로토타입 (앞으로 이동) ─────────
void calibrateSensors();  // <-- 추가: IMUControlCallbacks에서 사용되므로 클래스 정의 전에 선언

// ═══════════════════════════════════════════════════════
// BLE 콜백 클래스
// ═══════════════════════════════════════════════════════
class ServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("📱 BLE Connected");
  }
  
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("📱 BLE Disconnected");
    delay(500);
    BLEDevice::startAdvertising();
  }
};

class ScanCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    String val = pChar->getValue().c_str();
    if (val == "SCAN") {
      Serial.println("🔍 WiFi Scan requested");
      needToScan = true;
    }
  }
};

class SSIDCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    wifiSSID = pChar->getValue().c_str();
    Serial.print("📶 SSID: ");
    Serial.println(wifiSSID);
  }
};

class PassCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    wifiPassword = pChar->getValue().c_str();
    Serial.print("🔑 Password: ");
    Serial.println(wifiPassword);
    
    if (wifiSSID.length() > 0 && wifiPassword.length() > 0) {
      needToConnect = true;
    }
  }
};

class IMUControlCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) {
    String command = pChar->getValue().c_str();
    Serial.print("IMU Control Command: ");
    Serial.println(command);

    if (command == "ENABLED") {
      imuEnabled = true;
      Serial.println("IMU Enabled");
      if (deviceConnected) {
        pIMUControlChar->setValue("ENABLED");
        pIMUControlChar->notify();
      }
    } else if (command == "DISABLED") {
      imuEnabled = false;
      Serial.println("IMU Disabled");
      if (deviceConnected) {
        pIMUControlChar->setValue("DISABLED");
        pIMUControlChar->notify();
      }
    } else if (command == "CALIBRATE") {
      if (imuEnabled) {  // 보정은 IMU가 활성화된 상태에서만 수행
        Serial.println("IMU Calibration Requested");
        calibrateSensors();
        if (deviceConnected) {
          pIMUControlChar->setValue("CALIBRATED");
          pIMUControlChar->notify();
        }
      } else {
        Serial.println("IMU is disabled. Calibration skipped.");
      }
    }
  }
};

// ═══════════════════════════════════════════════════════
// 함수 선언
// ═══════════════════════════════════════════════════════
float mapFloat(float x, float in_min, float in_max, float out_min, float out_max);
void initBLE();
void initMPU6050();
void scanWiFi();
void tryConnect();
void reconnectMQTT();
void readAccelGyro();
void updateDeltaTime();
void computeAngles();
void printAngles();
void sendMQTT();
void sendBLE();  // 새로 추가!

// ═══════════════════════════════════════════════════════
// SETUP
// ═══════════════════════════════════════════════════════
void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("🚀 Starting BLE WiFi Setup + MPU6050 + MQTT");

  // BLE 초기화
  initBLE();

  // MPU6050 초기화
  Wire.begin(21, 22);
  Wire.setClock(400000);
  initMPU6050();
  calibrateSensors();
  
  prev_time = micros();

  // MQTT 서버 설정
  client.setServer(mqtt_server, mqtt_port);

  Serial.println("✅ System Ready!");
  Serial.println("📱 Waiting for BLE connection to setup WiFi...");
}

// ═══════════════════════════════════════════════════════
// LOOP
// ═══════════════════════════════════════════════════════
void loop() {
  unsigned long now = millis();

  // BLE WiFi 설정 처리
  if (needToScan) {
    needToScan = false;
    scanWiFi();
  }
  
  if (needToConnect) {
    needToConnect = false;
    tryConnect();
  }

  // IMU 활성화 상태에서만 센서 읽기 및 처리
  if (imuEnabled) {
    readAccelGyro();
    updateDeltaTime();
    computeAngles();
    printAngles();

    // BLE로 센서 데이터 전송 (BLE 연결 시)
    if (deviceConnected && (now - last_ble_send >= BLE_INTERVAL)) {
      last_ble_send = now;
      sendBLE();
    }
  }

  // WiFi 연결되었을 때만 MQTT 동작
  if (wifiConnected) {
    if (!client.connected()) {
      reconnectMQTT();
    }
    client.loop();

    // MQTT 전송
    if (now - last_mqtt_send >= MQTT_INTERVAL) {
      last_mqtt_send = now;
      sendMQTT();
    }
  }

  delay(10);
}

// ═══════════════════════════════════════════════════════
// BLE 초기화
// ═══════════════════════════════════════════════════════
void initBLE() {
  BLEDevice::init("Rookies WiFi Setup");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());
  
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  // Scan characteristic
  pScanChar = pService->createCharacteristic(
    WIFI_SCAN_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY
  );
  pScanChar->setCallbacks(new ScanCallbacks());
  pScanChar->addDescriptor(new BLE2902());
  
  // SSID characteristic
  pSSIDChar = pService->createCharacteristic(
    WIFI_SSID_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pSSIDChar->setCallbacks(new SSIDCallbacks());
  
  // Password characteristic
  pPasswordChar = pService->createCharacteristic(
    WIFI_PASS_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pPasswordChar->setCallbacks(new PassCallbacks());
  
  // Status characteristic
  pStatusChar = pService->createCharacteristic(
    WIFI_STATUS_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pStatusChar->addDescriptor(new BLE2902());
  
  // 센서 데이터 characteristic (새로 추가!)
  pSensorChar = pService->createCharacteristic(
    SENSOR_DATA_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pSensorChar->addDescriptor(new BLE2902());

  // IMU Control characteristic (새로 추가!)
  pIMUControlChar = pService->createCharacteristic(
    IMU_CONTROL_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY
  );
  pIMUControlChar->setCallbacks(new IMUControlCallbacks());
  pIMUControlChar->addDescriptor(new BLE2902());
  
  pService->start();
  
  BLEAdvertising *pAd = BLEDevice::getAdvertising();
  pAd->addServiceUUID(SERVICE_UUID);
  pAd->setScanResponse(true);
  BLEDevice::startAdvertising();
  
  Serial.println("✅ BLE Ready");
}

// ═══════════════════════════════════════════════════════
// WiFi 스캔
// ═══════════════════════════════════════════════════════
void scanWiFi() {
  Serial.println("🔍 Scanning WiFi...");
  
  if (deviceConnected) {
    pScanChar->setValue("SCANNING");
    pScanChar->notify();
  }
  
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);
  
  int n = WiFi.scanNetworks();
  Serial.print("Found: ");
  Serial.println(n);
  
  if (n == 0) {
    if (deviceConnected) {
      pScanChar->setValue("NONE");
      pScanChar->notify();
    }
  } else {
    String result = "";
    int count = 0;
    
    for (int i = 0; i < n && count < 20; i++) {
      String ssid = WiFi.SSID(i);
      int rssi = WiFi.RSSI(i);
      bool encrypted = (WiFi.encryptionType(i) != WIFI_AUTH_OPEN);
      
      String line = ssid + "|" + String(rssi) + "|" + String(encrypted ? "1" : "0") + ";";
      
      if (result.length() + line.length() < 500) {
        result += line;
        count++;
      } else {
        break;
      }
    }
    
    Serial.println("Sending list:");
    Serial.println(result);
    
    if (deviceConnected) {
      pScanChar->setValue(result.c_str());
      pScanChar->notify();
    }
  }
  
  WiFi.scanDelete();
}

// ═══════════════════════════════════════════════════════
// WiFi 연결 시도
// ═══════════════════════════════════════════════════════
void tryConnect() {
  Serial.println("📶 Connecting WiFi...");
  
  WiFi.disconnect(true);
  delay(100);
  
  if (deviceConnected) {
    pStatusChar->setValue("CONNECTING");
    pStatusChar->notify();
  }
  
  WiFi.mode(WIFI_STA);
  WiFi.begin(wifiSSID.c_str(), wifiPassword.c_str());
  
  int cnt = 0;
  while (WiFi.status() != WL_CONNECTED && cnt < 60) {
    delay(500);
    Serial.print(".");
    cnt++;
  }
  Serial.println();
  
  if (WiFi.status() == WL_CONNECTED) {
    wifiConnected = true;
    Serial.println("✅ WiFi Connected!");
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());
    
    if (deviceConnected) {
      String msg = "CONNECTED:" + WiFi.localIP().toString();
      pStatusChar->setValue(msg.c_str());
      pStatusChar->notify();
    }
  } else {
    wifiConnected = false;
    Serial.println("❌ WiFi Failed!");
    
    if (deviceConnected) {
      pStatusChar->setValue("FAILED");
      pStatusChar->notify();
    }
    
    WiFi.disconnect(true);
  }
  
  wifiSSID = "";
  wifiPassword = "";
}

// ═══════════════════════════════════════════════════════
// MQTT 재연결
// ═══════════════════════════════════════════════════════
void reconnectMQTT() {
  if (!wifiConnected) return;
  
  static unsigned long lastAttempt = 0;
  unsigned long now = millis();
  
  // 5초마다 재연결 시도
  if (now - lastAttempt < 5000) return;
  lastAttempt = now;
  
  Serial.print("🔄 Connecting to MQTT...");
  
  String clientId = "ESP32Client-";
  clientId += String(random(0xffff), HEX);
  
  if (client.connect(clientId.c_str())) {
    Serial.println(" ✅ MQTT Connected!");
  } else {
    Serial.print(" ❌ Failed, rc=");
    Serial.println(client.state());
  }
}

// ═══════════════════════════════════════════════════════
// MQTT 데이터 전송
// ═══════════════════════════════════════════════════════
void sendMQTT() {
  if (!client.connected()) return;
  
  float pitch_corrected = elbow + 90.0f;
  float p = pitch_corrected;
  float weight_factor = 1.0f;

  // pitch 범위별 선형 보간
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

  float display_roll = wrist * weight_factor;

  // JSON 형식으로 데이터 구성
  String payload = "{\"elbow\":" + String(pitch_corrected, 2) + 
                   ",\"wrist\":" + String(display_roll, 2) + "}";
  
  // MQTT 전송
  if (client.publish(mqtt_topic, payload.c_str())) {
    Serial.print("📤 MQTT: ");
    Serial.println(payload);
  }
}

// ═══════════════════════════════════════════════════════
// BLE 센서 데이터 전송 (새로 추가!)
// ═══════════════════════════════════════════════════════
void sendBLE() {
  if (!deviceConnected) return;
  
  float pitch_corrected = elbow + 90.0f;
  float p = pitch_corrected;
  float weight_factor = 1.0f;

  // pitch 범위별 선형 보간
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

  float display_roll = wrist * weight_factor;

  // JSON 형식으로 데이터 구성
  String payload = "{\"elbow\":" + String(pitch_corrected, 2) + 
                   ",\"wrist\":" + String(display_roll, 2) + "}";
  
  // BLE로 전송
  pSensorChar->setValue(payload.c_str());
  pSensorChar->notify();
}

// ═══════════════════════════════════════════════════════
// MPU6050 초기화
// ═══════════════════════════════════════════════════════
void initMPU6050() {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B);
  Wire.write(0);
  Wire.endTransmission(true);
  Serial.println("✅ MPU6050 initialized");
}

// ═══════════════════════════════════════════════════════
// 자이로 오프셋 보정
// ═══════════════════════════════════════════════════════
void calibrateSensors() {
  const int N = 200;
  long sumGyX = 0, sumGyY = 0;

  Serial.println("🔧 Gyro calibration...");
  for (int i = 0; i < N; i++) {
    readAccelGyro();
    sumGyX += GyX;
    sumGyY += GyY;
    delay(5);
  }

  GyX -= sumGyX / N;
  GyY -= sumGyY / N;

  Serial.println("✅ Calibration done");
}

// ═══════════════════════════════════════════════════════
// 시간 갱신
// ═══════════════════════════════════════════════════════
void updateDeltaTime() {
  unsigned long now = micros();
  dt = (now - prev_time) / 1000000.0f;
  prev_time = now;
}

// ═══════════════════════════════════════════════════════
// 센서 읽기
// ═══════════════════════════════════════════════════════
void readAccelGyro() {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, 14, true);

  AcX = Wire.read() << 8 | Wire.read();
  AcY = Wire.read() << 8 | Wire.read();
  AcZ = Wire.read() << 8 | Wire.read();
  Wire.read(); Wire.read(); // 온도 버림
  GyX = Wire.read() << 8 | Wire.read();
  GyY = Wire.read() << 8 | Wire.read();
  GyZ = Wire.read() << 8 | Wire.read();
}

// ═══════════════════════════════════════════════════════
// 각도 계산
// ═══════════════════════════════════════════════════════
void computeAngles() {
  float ax = AcX / 16384.0f;
  float ay = AcY / 16384.0f;
  float az = AcZ / 16384.0f;

  accel_angle_x = atan2(ay, sqrt(ax * ax + az * az)) * 180.0f / M_PI;
  accel_angle_y = atan2(-ax, sqrt(ay * ay + az * az)) * 180.0f / M_PI;

  gyro_x = GyX / 131.0f;
  gyro_y = GyY / 131.0f;

  float tmp_angle_x = elbow + gyro_x * dt;
  float tmp_angle_y = wrist + gyro_y * dt;

  elbow = ALPHA * tmp_angle_x + (1.0f - ALPHA) * accel_angle_x;
  wrist = ALPHA * tmp_angle_y + (1.0f - ALPHA) * accel_angle_y;
}

// ═══════════════════════════════════════════════════════
// 각도 출력
// ═══════════════════════════════════════════════════════
void printAngles() {
  float pitch_corrected = elbow + 90.0f;
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

  float display_roll = wrist * weight_factor;

  Serial.print("Roll: ");
  Serial.print(display_roll, 2);
  Serial.print("°, Pitch: ");
  Serial.print(pitch_corrected, 2);
  Serial.println("°");
}

// ═══════════════════════════════════════════════════════
// 선형 보간 함수
// ═══════════════════════════════════════════════════════
float mapFloat(float x, float in_min, float in_max, float out_min, float out_max) {
  return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}