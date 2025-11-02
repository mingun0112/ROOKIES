#include <WiFi.h>
#include <PubSubClient.h>
#include "esp_rom_sys.h"
#include <ArduinoJson.h>
#include <AccelStepper.h>

// ───────── WiFi & MQTT 설정 ─────────
const char* ssid = "We";
const char* password = "01025825352";
const char* mqtt_server = "211.107.16.45";
const int   mqtt_port   = 51883;
const char* topic_sub   = "degree/1";

WiFiClient espClient;
PubSubClient client(espClient);

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
#define STEPS_PER_DEGREE_W 100.0   // 실측 기준 1° ≈ 100 steps

float current_angle_wrist = 0.0;
float target_angle_wrist  = 0.0;
bool dirW = true;

// ───────── MQTT 함수 선언 ─────────
void setup_wifi();
void reconnect();
void callback(char* topic, byte* payload, unsigned int length);

// ───────── 제어 함수 ─────────
void controlElbow();
void controlWrist();

// ───────── Wi-Fi 연결 ─────────
void setup_wifi() {
  Serial.println("Connecting to WiFi...");
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\n✅ WiFi Connected");
  Serial.print("IP: "); Serial.println(WiFi.localIP());
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

  Serial.printf("🎯 MQTT Target → Elbow: %.1f°, Wrist: %.1f°\n",
                target_angle_elbow, target_angle_wrist);
}

// ───────── MQTT 재연결 ─────────
void reconnect() {
  while (!client.connected()) {
    Serial.print("MQTT Connecting...");
    if (client.connect("ESP32_Motor_Client")) {
      Serial.println("✅ Connected");
      client.subscribe(topic_sub);
    } else {
      Serial.printf("Retry in 3s (rc=%d)\n", client.state());
      delay(3000);
    }
  }
}

// ───────── 초기화 ─────────
void setup() {
  Serial.begin(115200);
  delay(300);

  setup_wifi();
  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(callback);

  // 엘보
  pinMode(EN_ELBOW, OUTPUT);
  pinMode(STEP_ELBOW, OUTPUT);
  pinMode(DIR_ELBOW, OUTPUT);
  digitalWrite(EN_ELBOW, LOW);

  // 손목
  stepper.setMaxSpeed(3000.0);
  stepper.setAcceleration(1500.0);
  stepper.setSpeed(1200.0);
  stepper.setCurrentPosition(0);

  Serial.println("✅ ESP32 Dual Motor Control Ready");
}

// ───────── 메인 루프 ─────────
void loop() {
  if (!client.connected()) reconnect();
  client.loop();

  controlElbow();
  controlWrist();
  stepper.run();  // run은 반드시 매 loop마다 호출
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

    current_angle_wrist += dirW ? 1.0f : -1.0f;  // 1도씩 반영
  }
}