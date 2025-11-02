#include <WiFi.h>
#include <PubSubClient.h>
#include "esp_rom_sys.h"
#include <ArduinoJson.h>
#include <AccelStepper.h>
#include <BluetoothSerial.h>
#include <Preferences.h>

// ───────── Bluetooth ─────────
BluetoothSerial SerialBT;
Preferences preferences;

// ───────── WiFi & MQTT 설정 ─────────
String ssid = "";
String password = "";
const char* mqtt_server = "211.107.16.45";
const int   mqtt_port   = 51883;
const char* topic_mpu   = "degree/mpu";     // ⭐ MPU 전용 토픽
const char* topic_vision = "degree/vision"; // ⭐ Vision 전용 토픽

WiFiClient espClient;
PubSubClient client(espClient);

// ───────── 모드 설정 ─────────
enum ControlMode {
  MODE_MPU,      // MPU 센서 모드 (MQTT: degree/mpu)
  MODE_VISION    // Vision 모드 (MQTT: degree/vision)
};

ControlMode current_mode = MODE_MPU;
bool wifi_configured = false;
bool is_running = false;

// ───────── 팔꿈치 모터 (Elbow) - GPIO 제어 ─────────
const int EN_ELBOW  = 15;
const int STEP_ELBOW = 0;
const int DIR_ELBOW  = 2;

#define GPIO_REG_WRITE(addr, val) (*(volatile uint32_t *)(addr) = (val))
#define GPIO_OUT_W1TS_REG 0x3FF44008
#define GPIO_OUT_W1TC_REG 0x3FF4400C
#define STEP_HIGH_E()  GPIO_REG_WRITE(GPIO_OUT_W1TS_REG, (1 << STEP_ELBOW))
#define STEP_LOW_E()   GPIO_REG_WRITE(GPIO_OUT_W1TC_REG, (1 << STEP_ELBOW))
#define DIR_HIGH_E()   GPIO_REG_WRITE(GPIO_OUT_W1TS_REG, (1 << DIR_ELBOW))
#define DIR_LOW_E()    GPIO_REG_WRITE(GPIO_OUT_W1TC_REG, (1 << DIR_ELBOW))

const int PULSE_DELAY_E = 11;
const int STEPS_PER_DEGREE_E = 3600;

float current_angle_elbow = 30.0;
float target_angle_elbow  = 30.0;
bool dirE = true;

// ───────── 손목 모터 (Wrist) - AccelStepper 제어 ─────────
AccelStepper stepper(AccelStepper::HALF4WIRE, 26, 27, 14, 12);
#define STEPS_PER_REV 544.0
#define STEPS_PER_DEGREE_W 100.0

float current_angle_wrist = 0.0;
float target_angle_wrist  = 0.0;
bool dirW = true;

// ───────── 함수 선언 ─────────
void setup_wifi();
void reconnect();
void callback(char* topic, byte* payload, unsigned int length);
void controlElbow();
void controlWrist();
void handleBluetoothCommands();
void loadWiFiConfig();
void saveWiFiConfig();
void loadModeConfig();
void saveModeConfig();

// ───────── SETUP ─────────
void setup() {
  Serial.begin(115200);
  delay(300);

  // Preferences 초기화
  preferences.begin("motor-config", false);
  
  // Bluetooth 시작
  SerialBT.begin("Motor_Control_ESP32");
  Serial.println("🔵 Bluetooth Started: Motor_Control_ESP32");

  // 설정 로드
  loadWiFiConfig();
  loadModeConfig();

  // 엘보 모터
  pinMode(EN_ELBOW, OUTPUT);
  pinMode(STEP_ELBOW, OUTPUT);
  pinMode(DIR_ELBOW, OUTPUT);
  digitalWrite(EN_ELBOW, LOW);

  // 손목 모터
  stepper.setMaxSpeed(3000.0);
  stepper.setAcceleration(1500.0);
  stepper.setSpeed(1200.0);
  stepper.setCurrentPosition(0);

  // WiFi가 설정되어 있으면 자동 연결
  if (wifi_configured) {
    setup_wifi();
    if (WiFi.status() == WL_CONNECTED) {
      client.setServer(mqtt_server, mqtt_port);
      client.setCallback(callback);
      reconnect();  // MQTT 연결 및 토픽 구독
      is_running = true;
      Serial.println("✅ Auto-started with saved WiFi config");
    }
  } else {
    Serial.println("⚠️ WiFi not configured. Use Bluetooth to setup.");
  }

  Serial.println("✅ ESP32 Dual Motor Control Ready");
}

// ───────── LOOP ─────────
void loop() {
  // Bluetooth 명령 처리
  handleBluetoothCommands();

  if (is_running) {
    if (!client.connected()) reconnect();
    client.loop();

    controlElbow();
    controlWrist();
  }
  
  stepper.run();  // 항상 호출
  delay(1);
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
        client.setCallback(callback);
        reconnect();  // MQTT 연결 및 모드별 토픽 구독
        wifi_configured = true;
        is_running = true;
        SerialBT.println("{\"status\":\"success\",\"message\":\"WiFi connected\"}");
      } else {
        SerialBT.println("{\"status\":\"error\",\"message\":\"WiFi connection failed\"}");
      }
    }
    
    // 모드 설정 (⭐ 토픽 재구독 추가)
    else if (cmd == "set_mode") {
      String mode = doc["mode"].as<String>();
      
      if (mode == "mpu") {
        current_mode = MODE_MPU;
        saveModeConfig();
        
        // MQTT 재연결하여 토픽 변경
        if (client.connected()) {
          client.disconnect();
          delay(100);
          reconnect();  // degree/mpu 구독
        }
        
        SerialBT.println("{\"status\":\"success\",\"message\":\"Mode set to MPU\"}");
        Serial.println("📡 Switched to MPU mode (degree/mpu)");
        
      } else if (mode == "vision") {
        current_mode = MODE_VISION;
        saveModeConfig();
        
        // MQTT 재연결하여 토픽 변경
        if (client.connected()) {
          client.disconnect();
          delay(100);
          reconnect();  // degree/vision 구독
        }
        
        SerialBT.println("{\"status\":\"success\",\"message\":\"Mode set to Vision\"}");
        Serial.println("📡 Switched to Vision mode (degree/vision)");
        
      } else {
        SerialBT.println("{\"status\":\"error\",\"message\":\"Invalid mode\"}");
      }
    }
    
    // 시작/중지
    else if (cmd == "start") {
      if (wifi_configured) {
        is_running = true;
        SerialBT.println("{\"status\":\"success\",\"message\":\"Motor control started\"}");
      } else {
        SerialBT.println("{\"status\":\"error\",\"message\":\"WiFi not configured\"}");
      }
    }
    else if (cmd == "stop") {
      is_running = false;
      SerialBT.println("{\"status\":\"success\",\"message\":\"Motor control stopped\"}");
    }
    
    // 상태 조회
    else if (cmd == "status") {
      StaticJsonDocument<256> response;
      response["wifi_configured"] = wifi_configured;
      response["is_running"] = is_running;
      response["wifi_connected"] = (WiFi.status() == WL_CONNECTED);
      response["mqtt_connected"] = client.connected();
      response["mode"] = (current_mode == MODE_MPU) ? "mpu" : "vision";
      response["ssid"] = ssid;
      response["elbow_angle"] = current_angle_elbow;
      response["wrist_angle"] = current_angle_wrist;
      
      String output;
      serializeJson(response, output);
      SerialBT.println(output);
    }
    
    // 모터 리셋
    else if (cmd == "reset_motors") {
      current_angle_elbow = 30.0;
      target_angle_elbow = 30.0;
      current_angle_wrist = 0.0;
      target_angle_wrist = 0.0;
      stepper.setCurrentPosition(0);
      SerialBT.println("{\"status\":\"success\",\"message\":\"Motors reset\"}");
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
    
    // 수동 모터 제어 (테스트용)
    else if (cmd == "set_angles") {
      if (doc.containsKey("elbow")) {
        target_angle_elbow = constrain((float)doc["elbow"], 0.0, 180.0);
      }
      if (doc.containsKey("wrist")) {
        target_angle_wrist = constrain((float)doc["wrist"], 0.0, 180.0);
      }
      SerialBT.println("{\"status\":\"success\",\"message\":\"Target angles set\"}");
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

// ───────── 모드 설정 저장/로드 ─────────
void saveModeConfig() {
  preferences.putUChar("mode", (uint8_t)current_mode);
  Serial.println("Mode saved: " + String((current_mode == MODE_MPU) ? "MPU" : "Vision"));
}

void loadModeConfig() {
  uint8_t mode = preferences.getUChar("mode", MODE_MPU);
  current_mode = (ControlMode)mode;
  Serial.println("Loaded mode: " + String((current_mode == MODE_MPU) ? "MPU" : "Vision"));
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
    Serial.println("\n✅ WiFi Connected");
    Serial.print("IP: "); Serial.println(WiFi.localIP());
  } else {
    Serial.println("\n❌ WiFi connection failed");
  }
}

// ───────── MQTT 콜백 ─────────
void callback(char* topic, byte* payload, unsigned int length) {
  payload[length] = '\0';
  String msg = String((char*)payload);
  StaticJsonDocument<200> doc;
  if (deserializeJson(doc, msg)) return;

  if (doc.containsKey("elbow"))
    target_angle_elbow = constrain((float)doc["elbow"], 0.0, 180.0);
  if (doc.containsKey("wrist"))
    target_angle_wrist = constrain((float)doc["wrist"], 0.0, 180.0);

  Serial.printf("🎯 [%s] Target → Elbow: %.1f°, Wrist: %.1f°\n",
                (current_mode == MODE_MPU) ? "MPU" : "Vision",
                target_angle_elbow, target_angle_wrist);
}

// ───────── MQTT 재연결 (⭐ 모드별 토픽 구독) ─────────
void reconnect() {
  if (!client.connected()) {
    Serial.print("MQTT Connecting...");
    String clientId = "ESP32_Motor_" + String((current_mode == MODE_MPU) ? "MPU" : "Vision");
    
    if (client.connect(clientId.c_str())) {
      Serial.println("✅ Connected");
      
      // ⭐ 모드에 따라 다른 토픽 구독
      if (current_mode == MODE_MPU) {
        client.subscribe(topic_mpu);
        Serial.println("📡 Subscribed to: degree/mpu");
      } else {
        client.subscribe(topic_vision);
        Serial.println("📡 Subscribed to: degree/vision");
      }
      
    } else {
      Serial.printf("Failed (rc=%d)\n", client.state());
      delay(3000);
    }
  }
}

// ───────── 엘보 제어 ─────────
void controlElbow() {
  if (abs(target_angle_elbow - current_angle_elbow) >= 1.0f) {
    float angle_diff = target_angle_elbow - current_angle_elbow;
    dirE = (angle_diff > 0);
    if (dirE) DIR_LOW_E(); else DIR_HIGH_E();

    Serial.printf("📐 Elbow: %.1f° → %.1f° (moving 1°)\n",
                  current_angle_elbow, target_angle_elbow);

    for (int i = 0; i < STEPS_PER_DEGREE_E; i++) {
      STEP_HIGH_E();
      esp_rom_delay_us(PULSE_DELAY_E);
      STEP_LOW_E();
      esp_rom_delay_us(PULSE_DELAY_E);
    }

    current_angle_elbow += dirE ? 1.0f : -1.0f;
  }
}

// ───────── 손목 제어 ─────────
void controlWrist() {
  if (abs(target_angle_wrist - current_angle_wrist) >= 0.9f) {
    dirW = (target_angle_wrist > current_angle_wrist);

    long steps_to_move = dirW ? STEPS_PER_DEGREE_W : -STEPS_PER_DEGREE_W;
    long target_pos = stepper.currentPosition() + steps_to_move;

    stepper.moveTo(target_pos);

    Serial.printf("📐 Wrist: %.1f° → %.1f° (%ld steps)\n",
                  current_angle_wrist, target_angle_wrist, steps_to_move);

    current_angle_wrist += dirW ? 1.0f : -1.0f;
  }
}
