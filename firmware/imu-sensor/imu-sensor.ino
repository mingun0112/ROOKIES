#include <WiFi.h>
#include <PubSubClient.h>
#include <Wire.h>
#include <ArduinoJson.h>

#define MPU_ADDR 0x68

// ───────── WiFi & MQTT 설정 ─────────
const char* ssid = "We";
const char* password = "01025825352";
const char* mqtt_server = "211.107.16.45";
const int   mqtt_port   = 51883;
const char* topic_pub   = "degree/1";

WiFiClient espClient;
PubSubClient client(espClient);

// ───────── 센서 원시값 ─────────
int16_t AcX, AcY, AcZ, GyX, GyY, GyZ;

// ───────── 필터 결과 ─────────
float accel_angle_x, accel_angle_y;
float gyro_x, gyro_y;
float filtered_angle_x = 0.0f;   // pitch (elbow)
float filtered_angle_y = 0.0f;   // roll  (wrist)

// ───────── 시간 계산 ─────────
unsigned long prev_time = 0;
float dt;

// ───────── 상보필터 계수 ─────────
const float ALPHA = 0.96f;

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

// ───────── SETUP ─────────
void setup() {
  Serial.begin(115200);
  delay(1000);

  Wire.begin(21, 22);
  Wire.setClock(400000);

  setup_wifi();
  client.setServer(mqtt_server, mqtt_port);

  initMPU6050();
  calibrateSensors();
  prev_time = micros();

  Serial.println("✅ ESP32 + MPU6050 MQTT Publisher (Elbow/Pitch, Wrist/Roll)");
}

// ───────── LOOP ─────────
void loop() {
  if (!client.connected()) reconnect();
  client.loop();

  readAccelGyro();
  updateDeltaTime();
  computeAngles();
  printAnglesAndPublish();

  delay(10);  // 약 100Hz (필터 계산 + MQTT 발행 주기)
}

// ───────── Wi-Fi 연결 ─────────
void setup_wifi() {
  Serial.println("Connecting to WiFi...");
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected!");
  Serial.print("IP: "); Serial.println(WiFi.localIP());
}

// ───────── MQTT 재연결 ─────────
void reconnect() {
  while (!client.connected()) {
    Serial.print("MQTT Connecting...");
    if (client.connect("ESP32_MPU_Publisher")) {
      Serial.println("✅ Connected to broker");
    } else {
      Serial.printf("Retry in 3s (rc=%d)\n", client.state());
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
}

// ───────── 자이로 오프셋 보정 ─────────
void calibrateSensors() {
  const int N = 200;
  long sumGyX = 0, sumGyY = 0;

  Serial.println("🔧 Gyro offset calibration...");
  for (int i = 0; i < N; i++) {
    readAccelGyro();
    sumGyX += GyX;
    sumGyY += GyY;
    delay(5);
  }

  GyX -= sumGyX / N;
  GyY -= sumGyY / N;

  Serial.println("✅ Calibration done.");
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
  GyX = Wire.read() << 8 | Wire.read();
  GyY = Wire.read() << 8 | Wire.read();
  GyZ = Wire.read() << 8 | Wire.read();
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

  // --- MQTT 발행 ---
  StaticJsonDocument<128> doc;
  doc["elbow"] = pitch_corrected; // pitch → elbow
  doc["wrist"] = display_roll;    // roll  → wrist
  char buffer[128];
  serializeJson(doc, buffer);
  client.publish(topic_pub, buffer);

  // --- 시리얼 출력 ---
  Serial.printf("→ Elbow: %.2f°, Wrist: %.2f°\n", pitch_corrected, display_roll);
}

float mapFloat(float x, float in_min, float in_max, float out_min, float out_max) {
  return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}