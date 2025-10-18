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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    discoverServices();
  }

  Future<void> discoverServices() async {
    try {
      List<BluetoothService> services = await widget.device.discoverServices();

      for (var service in services) {
        if (service.uuid.toString().toLowerCase() ==
            SERVICE_UUID.toLowerCase()) {
          print('ESP32 service found!');

          for (var characteristic in service.characteristics) {
            String charUuid = characteristic.uuid.toString().toLowerCase();

            if (charUuid == WIFI_SCAN_UUID.toLowerCase()) {
              scanCharacteristic = characteristic;
            } else if (charUuid == WIFI_SSID_UUID.toLowerCase()) {
              ssidCharacteristic = characteristic;
            } else if (charUuid == WIFI_PASS_UUID.toLowerCase()) {
              passwordCharacteristic = characteristic;
            } else if (charUuid == WIFI_STATUS_UUID.toLowerCase()) {
              statusCharacteristic = characteristic;
            } else if (charUuid == SENSOR_DATA_UUID.toLowerCase()) {
              sensorDataCharacteristic = characteristic;
            } else if (charUuid == IMU_CONTROL_UUID.toLowerCase()) {
              imuControlCharacteristic = characteristic;
            }
          }
          break;
        }
      }

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      print('Service discovery error: $e');
      setState(() {
        isLoading = false;
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
        bottom: TabBar(
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
