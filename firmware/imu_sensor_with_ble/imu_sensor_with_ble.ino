#include <WiFi.h>
#include <PubSubClient.h>
#include <Wire.h>
#include <ArduinoJson.h>
#include <BluetoothSerial.h>
#include <Preferences.h>

#define MPU_ADDR 0x68

// ───────── Bluetooth ─────────
BluetoothSerial SerialBT;
Preferences preferences;

// ───────── WiFi & MQTT 설정 ─────────
String ssid = "";
String password = "";
const char* mqtt_server = "211.107.16.45";
const int   mqtt_port   = 51883;
const char* topic_pub   = "degree/mpu";  // ⭐ MPU 전용 토픽

WiFiClient espClient;
PubSubClient client(espClient);

// ───────── 센서 원시값 ─────────
int16_t AcX, AcY, AcZ, GyX, GyY, GyZ;

// ───────── 필터 결과 ─────────
float accel_angle_x, accel_angle_y;
float gyro_x, gyro_y;
float filtered_angle_x = 0.0f;   // pitch (elbow)
float filtered_angle_y = 0.0f;   // roll  (wrist)

// ───────── Calibration Offsets ─────────
int16_t gyro_offset_x = 0;
int16_t gyro_offset_y = 0;
int16_t gyro_offset_z = 0;

// ───────── 시간 계산 ─────────
unsigned long prev_time = 0;
float dt;

// ───────── 상보필터 계수 ─────────
const float ALPHA = 0.96f;

// ───────── 상태 관리 ─────────
bool wifi_configured = false;
bool is_running = false;

// ───────── 함수 선언 ─────────
void initMPU6050();
void calibrateSensors();
void readAccelGyro();
void updateDeltaTime();
void computeAngles();
void printAnglesAndPublish();
float mapFloat(float x, float in_min, float in_max, float out_min, float out_max);
void setup_wifi();
void reconnect();
void handleBluetoothCommands();
void loadWiFiConfig();
void saveWiFiConfig();
void saveCalibration();
void loadCalibration();

// ───────── SETUP ─────────
void setup() {
  Serial.begin(115200);
  delay(1000);

  // Preferences 초기화
  preferences.begin("imu-config", false);
  
  // Bluetooth 시작
  SerialBT.begin("IMU_Sensor_ESP32");
  Serial.println("🔵 Bluetooth Started: IMU_Sensor_ESP32");

  // WiFi 설정 로드
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
    Serial.println("⚠️ WiFi not configured. Use Bluetooth to setup.");
  }
}

// ───────── LOOP ─────────
void loop() {
  // Bluetooth 명령 처리
  handleBluetoothCommands();

  if (is_running) {
    if (!client.connected()) reconnect();
    client.loop();

    readAccelGyro();
    updateDeltaTime();
    computeAngles();
    printAnglesAndPublish();

    delay(10);  // 약 100Hz
  } else {
    delay(100);
  }
}

// ───────── Bluetooth 명령 처리 ─────────
void handleBluetoothCommands() {
  if (SerialBT.available()) {
    String command = SerialBT.readStringUntil('\n');
    command.trim();
    
    Serial.println("BT Command: " + command);
    
    StaticJsonDocument<256> doc;
    DeserializationError error = deserializeJson(doc, command);
    
    if (error) {
      SerialBT.println("{\"status\":\"error\",\"message\":\"Invalid JSON\"}");
      return;
    }
    
    String cmd = doc["cmd"].as<String>();
    
    // WiFi 설정
    if (cmd == "set_wifi") {
      ssid = doc["ssid"].as<String>();
      password = doc["password"].as<String>();
      
      saveWiFiConfig();
      
      SerialBT.println("{\"status\":\"success\",\"message\":\"WiFi config saved\"}");
      
      // WiFi 연결 시도
      setup_wifi();
      if (WiFi.status() == WL_CONNECTED) {
        client.setServer(mqtt_server, mqtt_port);
        wifi_configured = true;
        is_running = true;
        prev_time = micros();
        SerialBT.println("{\"status\":\"success\",\"message\":\"WiFi connected\"}");
      } else {
        SerialBT.println("{\"status\":\"error\",\"message\":\"WiFi connection failed\"}");
      }
    }
    
    // Calibration 시작
    else if (cmd == "calibrate") {
      SerialBT.println("{\"status\":\"info\",\"message\":\"Calibration started\"}");
      calibrateSensors();
      saveCalibration();
      SerialBT.println("{\"status\":\"success\",\"message\":\"Calibration completed\"}");
    }
    
    // 시작/중지
    else if (cmd == "start") {
      if (wifi_configured) {
        is_running = true;
        prev_time = micros();
        SerialBT.println("{\"status\":\"success\",\"message\":\"Sensor started\"}");
      } else {
        SerialBT.println("{\"status\":\"error\",\"message\":\"WiFi not configured\"}");
      }
    }
    else if (cmd == "stop") {
      is_running = false;
      SerialBT.println("{\"status\":\"success\",\"message\":\"Sensor stopped\"}");
    }
    
    // 상태 조회
    else if (cmd == "status") {
      StaticJsonDocument<256> response;
      response["wifi_configured"] = wifi_configured;
      response["is_running"] = is_running;
      response["wifi_connected"] = (WiFi.status() == WL_CONNECTED);
      response["mqtt_connected"] = client.connected();
      response["ssid"] = ssid;
      
      String output;
      serializeJson(response, output);
      SerialBT.println(output);
    }
    
    // WiFi 재연결
    else if (cmd == "reconnect_wifi") {
      setup_wifi();
      if (WiFi.status() == WL_CONNECTED) {
        SerialBT.println("{\"status\":\"success\",\"message\":\"WiFi reconnected\"}");
      } else {
        SerialBT.println("{\"status\":\"error\",\"message\":\"WiFi reconnection failed\"}");
      }
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
  Wire.read(); Wire.read(); // 온도 버림
  GyX = (Wire.read() << 8 | Wire.read()) - gyro_offset_x;
  GyY = (Wire.read() << 8 | Wire.read()) - gyro_offset_y;
  GyZ = (Wire.read() << 8 | Wire.read()) - gyro_offset_z;
}

// ───────── 각도 계산 ─────────
void computeAngles() {
  float ax = AcX / 16384.0f;
  float ay = AcY / 16384.0f;
  float az = AcZ / 16384.0f;

  accel_angle_x = atan2(ay, sqrt(ax * ax + az * az)) * 180.0f / M_PI; // pitch
  accel_angle_y = atan2(-ax, sqrt(ay * ay + az * az)) * 180.0f / M_PI; // roll

  gyro_x = GyX / 131.0f;
  gyro_y = GyY / 131.0f;

  float tmp_angle_x = filtered_angle_x + gyro_x * dt;
  float tmp_angle_y = filtered_angle_y + gyro_y * dt;

  filtered_angle_x = ALPHA * tmp_angle_x + (1.0f - ALPHA) * accel_angle_x;
  filtered_angle_y = ALPHA * tmp_angle_y + (1.0f - ALPHA) * accel_angle_y;
}

// ───────── 출력 + MQTT 발행 ─────────
void printAnglesAndPublish() {
  float pitch_corrected = filtered_angle_x + 90.0f;  // Elbow
  float p = pitch_corrected;
  float weight_factor = 1.0f;

  //--- pitch 범위별 선형 보간 ---
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

  // --- roll에 가중치 적용 ---
  float display_roll = filtered_angle_y * weight_factor;

  // --- pitch/roll 범위 제한 ---
  if (pitch_corrected > 90.0f) pitch_corrected = 90.0f;
  if (pitch_corrected < 25.0f)  pitch_corrected = 25.0f;
  if (display_roll   < 0.0f)    display_roll   = 0.0f;
  if (display_roll   > 95.0f)   display_roll   = 95.0f;

  // --- MQTT 발행 (MPU 전용 토픽) ---
  StaticJsonDocument<128> doc;
  doc["elbow"] = pitch_corrected;
  doc["wrist"] = display_roll;
  char buffer[128];
  serializeJson(doc, buffer);
  client.publish(topic_pub, buffer);  // ⭐ degree/mpu로 발행

  // --- 시리얼 출력 ---
  Serial.printf("→ [MPU] Elbow: %.2f°, Wrist: %.2f°\n", pitch_corrected, display_roll);
}

float mapFloat(float x, float in_min, float in_max, float out_min, float out_max) {
  return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}
