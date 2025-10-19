import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'dart:async';

class IMUControlTab extends StatefulWidget {
  final BluetoothCharacteristic? sensorDataChar;
  final BluetoothCharacteristic? imuControlChar;

  IMUControlTab({this.sensorDataChar, this.imuControlChar});

  @override
  _IMUControlTabState createState() => _IMUControlTabState();
}

class _IMUControlTabState extends State<IMUControlTab> {
  bool imuEnabled = false;
  double elbow = 0.0;
  double wrist = 0.0;
  StreamSubscription? sensorSubscription;
  StreamSubscription? controlSubscription;
  bool isCalibrating = false;
  bool isInitializing = true;

  @override
  void initState() {
    super.initState();
    checkCharacteristics();
    setupNotifications();
  }

  void checkCharacteristics() {
    print('🔍 Checking characteristics...');
    print('Sensor Data Char: ${widget.sensorDataChar != null ? "✓" : "✗"}');
    print('IMU Control Char: ${widget.imuControlChar != null ? "✓" : "✗"}');

    if (widget.sensorDataChar == null || widget.imuControlChar == null) {
      setState(() {
        isInitializing = false;
      });
    }
  }

  Future<void> setupNotifications() async {
    if (widget.sensorDataChar == null || widget.imuControlChar == null) {
      print('❌ One or more characteristics are null');
      setState(() {
        isInitializing = false;
      });
      return;
    }

    try {
      // 센서 데이터 구독
      await widget.sensorDataChar!.setNotifyValue(true);
      sensorSubscription = widget.sensorDataChar!.lastValueStream.listen((
        value,
      ) {
        String data = utf8.decode(value);
        parseSensorData(data);
      });
      print('✅ Sensor data subscription set');

      // IMU 제어 상태 구독
      await widget.imuControlChar!.setNotifyValue(true);
      controlSubscription = widget.imuControlChar!.lastValueStream.listen((
        value,
      ) {
        String status = utf8.decode(value);
        print('IMU Status received: $status');

        setState(() {
          if (status == "ENABLED") {
            imuEnabled = true;
            isCalibrating = false;
          } else if (status == "DISABLED") {
            imuEnabled = false;
            isCalibrating = false;
          } else if (status == "CALIBRATED") {
            isCalibrating = false;
            showSnackBar("✅ 센서 보정이 완료되었습니다!", Colors.green);
          }
        });
      });
      print('✅ IMU control subscription set');

      // 초기 상태 확인
      await Future.delayed(Duration(milliseconds: 500));
      await checkIMUStatus();

      setState(() {
        isInitializing = false;
      });
    } catch (e) {
      print('❌ Setup notifications error: $e');
      setState(() {
        isInitializing = false;
      });
      showSnackBar("❌ 알림 설정 실패: $e", Colors.red);
    }
  }

  void parseSensorData(String data) {
    try {
      Map<String, dynamic> json = jsonDecode(data);
      setState(() {
        elbow = json['elbow']?.toDouble() ?? 0.0;
        wrist = json['wrist']?.toDouble() ?? 0.0;
      });
    } catch (e) {
      print('Parse error: $e');
    }
  }

  Future<void> checkIMUStatus() async {
    if (widget.imuControlChar == null) {
      print('❌ IMU Control Characteristic is null');
      return;
    }

    try {
      print('📤 Requesting IMU status...');
      await widget.imuControlChar!.write(utf8.encode("STATUS"));
      print('✅ IMU status request sent');
    } catch (e) {
      print('❌ Error requesting IMU status: $e');
    }
  }

  Future<void> toggleIMU() async {
    if (widget.imuControlChar == null) {
      showSnackBar("❌ IMU 제어를 사용할 수 없습니다", Colors.red);
      return;
    }

    try {
      String command = imuEnabled ? "DISABLED" : "ENABLED";
      print('📤 Sending IMU toggle command: $command');
      await widget.imuControlChar!.write(utf8.encode(command));
      print('✅ Command sent: $command');

      // 낙관적 업데이트 (ESP32 응답을 기다리지 않음)
      setState(() {
        imuEnabled = !imuEnabled;
      });

      showSnackBar(
        imuEnabled ? "✅ IMU 센서 활성화 요청" : "⏸️ IMU 센서 비활성화 요청",
        imuEnabled ? Colors.green : Colors.orange,
      );
    } catch (e) {
      print('❌ Toggle error: $e');
      showSnackBar("❌ 명령 전송 실패: $e", Colors.red);
    }
  }

  Future<void> calibrateIMU() async {
    if (widget.imuControlChar == null) {
      showSnackBar("❌ IMU 제어를 사용할 수 없습니다", Colors.red);
      return;
    }

    if (!imuEnabled) {
      showSnackBar("⚠️ IMU를 먼저 활성화해주세요", Colors.orange);
      return;
    }

    setState(() {
      isCalibrating = true;
    });

    showSnackBar("🔧 센서 보정 중... 기기를 평평한 곳에 놓아주세요!", Colors.blue);

    try {
      print('📤 Sending calibration command: CALIBRATE');
      await widget.imuControlChar!.write(utf8.encode("CALIBRATE"));
      print('✅ Calibration command sent');
    } catch (e) {
      print('❌ Calibration error: $e');
      setState(() {
        isCalibrating = false;
      });
      showSnackBar("❌ 보정 실패: $e", Colors.red);
    }
  }

  void showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    sensorSubscription?.cancel();
    controlSubscription?.cancel();
    widget.sensorDataChar?.setNotifyValue(false);
    widget.imuControlChar?.setNotifyValue(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Characteristic이 null인 경우 에러 표시
    if (widget.sensorDataChar == null || widget.imuControlChar == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bluetooth_disabled, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'IMU 제어를 사용할 수 없습니다',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red[700],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'ESP32 펌웨어에 IMU 기능이\n포함되어 있는지 확인해주세요.',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              if (widget.sensorDataChar == null)
                Text(
                  '❌ Sensor Data Characteristic',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
              if (widget.imuControlChar == null)
                Text(
                  '❌ IMU Control Characteristic',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
            ],
          ),
        ),
      );
    }

    if (isInitializing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('IMU 초기화 중...'),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // IMU 제어 카드
          Card(
            margin: EdgeInsets.all(16),
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            imuEnabled
                                ? Icons.sensors_outlined
                                : Icons.sensors_off,
                            color: imuEnabled ? Colors.green : Colors.grey,
                            size: 28,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'IMU 센서',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: imuEnabled,
                        onChanged: (value) => toggleIMU(),
                        activeColor: Colors.blue,
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: imuEnabled ? Colors.green[50] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: imuEnabled ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          imuEnabled ? '활성화' : '비활성화',
                          style: TextStyle(
                            fontSize: 14,
                            color: imuEnabled
                                ? Colors.green[700]
                                : Colors.grey[600],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 센서 데이터 표시
          if (imuEnabled) ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Elbow 데이터
                  buildSensorCard(
                    '팔꿈치 각도',
                    elbow,
                    Icons.arrow_upward,
                    Colors.blue,
                  ),
                  SizedBox(height: 16),
                  // Wrist 데이터
                  buildSensorCard(
                    '손목 각도',
                    wrist,
                    Icons.arrow_downward,
                    Colors.orange,
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
          ] else ...[
            // IMU 비활성화 상태 표시
            Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.sensors_off, size: 64, color: Colors.grey[400]),
                  SizedBox(height: 16),
                  Text(
                    'IMU 센서가 비활성화되어 있습니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '위의 스위치를 켜서 센서를 활성화하세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ],

          // 하단 버튼 (센서 보정)
          if (imuEnabled)
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: isCalibrating ? null : calibrateIMU,
                icon: isCalibrating
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(Icons.settings_backup_restore),
                label: Text(isCalibrating ? '보정 중...' : '센서 보정하기'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.all(16),
                  minimumSize: Size(double.infinity, 50),
                  backgroundColor: isCalibrating ? Colors.grey : Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildSensorCard(
    String label,
    double value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 48, color: color),
            SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 8),
            Text(
              '${value.toStringAsFixed(2)}°',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ((value + 180) / 360).clamp(0.0, 1.0),
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
