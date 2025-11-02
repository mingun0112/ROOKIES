import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp; // ⭐ alias 사용
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_manager.dart';
import 'imu_control_screen.dart';
import 'motor_control_screen.dart';

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({Key? key}) : super(key: key);

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  List<fbp.ScanResult> _scanResults = []; // ⭐ fbp. 사용
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);

    try {
      final btManager = context.read<BluetoothManager>();
      final results = await btManager.scanForDevices();

      setState(() {
        _scanResults = results;
        _isScanning = false;
      });
    } catch (e) {
      setState(() => _isScanning = false);
      _showError('Scan failed: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _connectToDevice(fbp.BluetoothDevice device) async {
    // ⭐ fbp. 사용
    final btManager = context.read<BluetoothManager>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      bool success = await btManager.connectToDevice(device);
      Navigator.pop(context);

      if (success) {
        String deviceName = device.platformName.toLowerCase();

        if (deviceName.contains('imu') || deviceName.contains('sensor')) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const IMUControlScreen()),
          );
        } else if (deviceName.contains('motor') ||
            deviceName.contains('control')) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MotorControlScreen()),
          );
        } else {
          _showError(
              'Unknown device type. Please rename ESP32 to include "IMU" or "Motor"');
        }
      } else {
        _showError('Connection failed');
      }
    } catch (e) {
      Navigator.pop(context);
      _showError('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select ESP32 Device'),
        actions: [
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _startScan,
          ),
        ],
      ),
      body: _scanResults.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bluetooth_searching,
                      size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No ESP32 devices found',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Make sure ESP32 is powered on',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _isScanning ? null : _startScan,
                    icon: const Icon(Icons.search),
                    label: const Text('Scan for Devices'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _scanResults.length,
              itemBuilder: (context, index) {
                final result = _scanResults[index];
                final device = result.device;
                final deviceName = device.platformName;

                final isIMU = deviceName.toLowerCase().contains('imu') ||
                    deviceName.toLowerCase().contains('sensor');
                final isMotor = deviceName.toLowerCase().contains('motor') ||
                    deviceName.toLowerCase().contains('control');

                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: Icon(
                      isIMU
                          ? Icons.sensors
                          : isMotor
                              ? Icons.precision_manufacturing
                              : Icons.bluetooth,
                      size: 36,
                      color: isIMU
                          ? Colors.blue
                          : isMotor
                              ? Colors.orange
                              : Colors.grey,
                    ),
                    title: Text(
                      deviceName.isEmpty ? 'Unknown Device' : deviceName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(device.remoteId.toString()),
                        Text(
                          'RSSI: ${result.rssi} dBm',
                          style: TextStyle(
                            color: result.rssi > -70
                                ? Colors.green
                                : Colors.orange,
                            fontSize: 12,
                          ),
                        ),
                        if (isIMU)
                          const Text('IMU Sensor',
                              style: TextStyle(color: Colors.blue))
                        else if (isMotor)
                          const Text('Motor Controller',
                              style: TextStyle(color: Colors.orange))
                        else
                          const Text('Unknown Type',
                              style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _connectToDevice(device),
                  ),
                );
              },
            ),
      floatingActionButton: _scanResults.isNotEmpty
          ? FloatingActionButton(
              onPressed: _isScanning ? null : _startScan,
              child: _isScanning
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.refresh),
            )
          : null,
    );
  }
}
