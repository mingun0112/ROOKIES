import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'wifi_setup_tab.dart';
import 'imu_control_tab.dart';

class DeviceControlScreen extends StatefulWidget {
  final BluetoothDevice device;

  DeviceControlScreen({required this.device});

  @override
  _DeviceControlScreenState createState() => _DeviceControlScreenState();
}

class _DeviceControlScreenState extends State<DeviceControlScreen>
    with SingleTickerProviderStateMixin {
  static const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String WIFI_SCAN_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a7";
  static const String WIFI_SSID_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  static const String WIFI_PASS_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a9";
  static const String WIFI_STATUS_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26aa";
  static const String SENSOR_DATA_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26ab";
  static const String IMU_CONTROL_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26ac";

  late TabController _tabController;

  BluetoothCharacteristic? scanCharacteristic;
  BluetoothCharacteristic? ssidCharacteristic;
  BluetoothCharacteristic? passwordCharacteristic;
  BluetoothCharacteristic? statusCharacteristic;
  BluetoothCharacteristic? sensorDataCharacteristic;
  BluetoothCharacteristic? imuControlCharacteristic;

  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    discoverServices();
  }

  Future<void> discoverServices() async {
    try {
      print('🔍 Starting service discovery...');
      List<BluetoothService> services = await widget.device.discoverServices();
      print('📡 Found ${services.length} services');

      bool serviceFound = false;

      for (var service in services) {
        print('Service UUID: ${service.uuid.toString()}');

        if (service.uuid.toString().toLowerCase() ==
            SERVICE_UUID.toLowerCase()) {
          serviceFound = true;
          print('✅ ESP32 service found!');

          for (var characteristic in service.characteristics) {
            String charUuid = characteristic.uuid.toString().toLowerCase();
            print('  Characteristic: $charUuid');

            if (charUuid == WIFI_SCAN_UUID.toLowerCase()) {
              scanCharacteristic = characteristic;
              print('    ✓ WiFi Scan Char');
            } else if (charUuid == WIFI_SSID_UUID.toLowerCase()) {
              ssidCharacteristic = characteristic;
              print('    ✓ WiFi SSID Char');
            } else if (charUuid == WIFI_PASS_UUID.toLowerCase()) {
              passwordCharacteristic = characteristic;
              print('    ✓ WiFi Password Char');
            } else if (charUuid == WIFI_STATUS_UUID.toLowerCase()) {
              statusCharacteristic = characteristic;
              print('    ✓ WiFi Status Char');
            } else if (charUuid == SENSOR_DATA_UUID.toLowerCase()) {
              sensorDataCharacteristic = characteristic;
              print('    ✓ Sensor Data Char');
            } else if (charUuid == IMU_CONTROL_UUID.toLowerCase()) {
              imuControlCharacteristic = characteristic;
              print('    ✓ IMU Control Char');
            }
          }
          break;
        }
      }

      if (!serviceFound) {
        errorMessage = 'ESP32 서비스를 찾을 수 없습니다.\nESP32 펌웨어를 확인해주세요.';
        print('❌ ESP32 service not found!');
      } else {
        // 각 characteristic 확인
        if (imuControlCharacteristic == null) {
          print('⚠️ IMU Control Characteristic not found!');
        }
        if (sensorDataCharacteristic == null) {
          print('⚠️ Sensor Data Characteristic not found!');
        }
      }

      setState(() {
        isLoading = false;
      });

      print('✅ Service discovery completed');
    } catch (e) {
      print('❌ Service discovery error: $e');
      setState(() {
        isLoading = false;
        errorMessage = '서비스 검색 중 오류 발생: $e';
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    widget.device.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.device.platformName.isEmpty
              ? 'ESP32 제어'
              : widget.device.platformName,
        ),
        backgroundColor: Colors.blue,
        bottom: isLoading
            ? null
            : TabBar(
                controller: _tabController,
                tabs: [
                  Tab(icon: Icon(Icons.wifi), text: 'WiFi 설정'),
                  Tab(icon: Icon(Icons.sensors), text: 'IMU 제어'),
                ],
              ),
      ),
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('서비스 검색 중...'),
                ],
              ),
            )
          : errorMessage.isNotEmpty
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red),
                    SizedBox(height: 16),
                    Text(
                      errorMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.red[700]),
                    ),
                    SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          isLoading = true;
                          errorMessage = '';
                        });
                        discoverServices();
                      },
                      icon: Icon(Icons.refresh),
                      label: Text('다시 시도'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                WiFiSetupTab(
                  device: widget.device,
                  scanChar: scanCharacteristic,
                  ssidChar: ssidCharacteristic,
                  passChar: passwordCharacteristic,
                  statusChar: statusCharacteristic,
                ),
                IMUControlTab(
                  sensorDataChar: sensorDataCharacteristic,
                  imuControlChar: imuControlCharacteristic,
                ),
              ],
            ),
    );
  }
}
