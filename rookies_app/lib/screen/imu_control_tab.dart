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

  @override
  void initState() {
    super.initState();
    setupNotifications();
  }

  Future<void> setupNotifications() async {
    // 센서 데이터 구독
    if (widget.sensorDataChar != null) {
      await widget.sensorDataChar!.setNotifyValue(true);
      sensorSubscription = widget.sensorDataChar!.lastValueStream.listen((
        value,
      ) {
        String data = utf8.decode(value);
        parseSensorData(data);
      });
    }

    // IMU 제어 상태 구독
    if (widget.imuControlChar != null) {
      await widget.imuControlChar!.setNotifyValue(true);
      controlSubscription = widget.imuControlChar!.lastValueStream.listen((
        value,
      ) {
        String status = utf8.decode(value);
        print('IMU Status: $status');

        setState(() {
          if (status == "ON") {
            imuEnabled = true;
          } else if (status == "OFF") {
            imuEnabled = false;
          } else if (status == "CALIBRATED") {
            showSnackBar("센서 보정이 완료되었습니다!");
          }
        });
      });

      // 초기 상태 확인
      checkIMUStatus();
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
    if (widget.imuControlChar != null) {
      try {
        await widget.imuControlChar!.write(utf8.encode("STATUS"));
      } catch (e) {
        print('Status check error: $e');
      }
    }
  }

  Future<void> toggleIMU() async {
    if (widget.imuControlChar != null) {
      try {
        String command = imuEnabled ? "DISABLED" : "ENABLED"; // 명령어 수정
        await widget.imuControlChar!.write(utf8.encode(command));
        print('IMU toggle command sent: $command');
        setState(() {
          imuEnabled = !imuEnabled;
        });
      } catch (e) {
        print('Toggle error: $e');
        showSnackBar("IMU 제어 실패: $e");
      }
    }
  }

  Future<void> calibrateIMU() async {
    if (imuEnabled && widget.imuControlChar != null) {
      showSnackBar("센서 보정 중... 기기를 평평한 곳에 놓아주세요!");
      try {
        await widget.imuControlChar!.write(utf8.encode("CALIBRATE"));
        print('Calibration command sent');
      } catch (e) {
        print('Calibration error: $e');
        showSnackBar("보정 실패: $e");
      }
    } else {
      showSnackBar("IMU가 비활성화 상태입니다. 활성화 후 보정하세요.");
    }
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: Duration(seconds: 2)),
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
    return SingleChildScrollView(
      // Wrap content in a scrollable view
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
                        onChanged: (value) async {
                          await toggleIMU(); // Ensure toggleIMU is awaited
                        },
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
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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

          // IMU Control Buttons
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: toggleIMU,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    backgroundColor: imuEnabled ? Colors.red : Colors.green,
                  ),
                  child: Text(
                    imuEnabled ? 'IMU 끄기' : 'IMU 켜기',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                ElevatedButton(
                  onPressed: calibrateIMU,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    backgroundColor: Colors.blue,
                  ),
                  child: Text('센서 보정', style: TextStyle(fontSize: 16)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!imuEnabled) {
                      await toggleIMU(); // IMU 활성화 명령 전송
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    backgroundColor: Colors.green,
                  ),
                  child: Text('IMU 활성화', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),

          // 하단 버튼
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
              onPressed: calibrateIMU,
              icon: Icon(Icons.settings_backup_restore),
              label: Text('센서 보정하기'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.all(16),
                minimumSize: Size(double.infinity, 50),
                backgroundColor: Colors.blue,
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
