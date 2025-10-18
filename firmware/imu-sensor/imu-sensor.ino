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
#define SENSOR_DATA_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26ab"  // 새로 추가!
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
BLECharacteristic* pSensorChar = NULL;  // 새로 추가!
BLECharacteristic* pIMUControlChar = NULL;  // 새로 추가!

// ───────── WiFi & MQTT 객체 ─────────
WiFiClient espClient;
PubSubClient client(espClient);

// ───────── 상태 변수 ─────────
bool deviceConnected = false;
String wifiSSID = "";
String wifiPassword = "";
bool needToConnect = false;
bool needToScan = false;
bool wifiConnected = false;
bool imuEnabled = true;  // IMU 활성화 상태

// ───────── MPU6050 변수 ─────────
int16_t AcX, AcY, AcZ, GyX, GyY, GyZ;
float accel_angle_x, accel_angle_y;
float gyro_x, gyro_y;
float elbow = 0.0f;   // pitch
float wrist = 0.0f;   // roll

// ───────── 시간 계산 ─────────
unsigned long prev_time = 0;
unsigned long last_mqtt_send = 0;
unsigned long last_ble_send = 0;  // 새로 추가!
float dt;

// ───────── 상보필터 계수 ─────────
const float ALPHA = 0.96f;
const unsigned long MQTT_INTERVAL = 100; // 100ms마다 전송
const unsigned long BLE_INTERVAL = 100;   // 100ms마다 BLE 전송

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

class IMUControlCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) {
    String command = pChar->getValue().c_str();
    Serial.print("IMU Control Command: ");
    Serial.println(command);

    if (command == "ON") {
      imuEnabled = true;
      Serial.println("IMU Enabled");
      if (deviceConnected) {
        pIMUControlChar->setValue("ON");
        pIMUControlChar->notify();
      }
    } else if (command == "OFF") {
      imuEnabled = false;
      Serial.println("IMU Disabled");
      if (deviceConnected) {
        pIMUControlChar->setValue("OFF");
        pIMUControlChar->notify();
      }
    } else if (command == "CALIBRATE") {
      Serial.println("IMU Calibration Requested");
      calibrateSensors();
      if (deviceConnected) {
        pIMUControlChar->setValue("CALIBRATED");
        pIMUControlChar->notify();
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
void calibrateSensors();
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
  // BLE WiFi 설정 처리
  if (needToScan) {
    needToScan = false;
    scanWiFi();
  }
  
  if (needToConnect) {
    needToConnect = false;
    tryConnect();
  }

  if (imuEnabled) {
    // 센서 읽기 및 처리 (IMU 활성화 상태에서만 동작)
    readAccelGyro();
    updateDeltaTime();
    computeAngles();
    printAngles();

    // BLE로 센서 데이터 전송
    unsigned long now = millis();
    if (deviceConnected && (now - last_ble_send >= BLE_INTERVAL)) {
      last_ble_send = now;
      sendBLE();
    }
  }

  // WiFi 연결되었을 때만 MQTT 동작
  if (wifiConnected) {
    // MQTT 연결 유지
    if (!client.connected()) {
      reconnectMQTT();
    }
    client.loop();

    // MQTT 전송
    unsigned long now = millis();
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

  // IMU Control characteristic
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

// ...remaining code unchanged...