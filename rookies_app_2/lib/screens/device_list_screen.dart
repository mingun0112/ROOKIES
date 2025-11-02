import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_service.dart';
import 'imu_control_screen.dart';
import 'motor_control_screen.dart';

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({Key? key}) : super(key: key);

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  List<BluetoothDevice> _devices = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    try {
      final btService = context.read<BluetoothService>();
      final devices = await btService.getPairedDevices();
      setState(() {
        _devices = devices;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to load devices: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    final btService = context.read<BluetoothService>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      bool success = await btService.connectToDevice(device);
      Navigator.pop(context); // Close loading dialog

      if (success) {
        // 기기 이름으로 타입 판별
        if (device.name?.contains('IMU') ?? false) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const IMUControlScreen()),
          );
        } else if (device.name?.contains('Motor') ?? false) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MotorControlScreen()),
          );
        } else {
          _showError('Unknown device type');
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
            icon: const Icon(Icons.refresh),
            onPressed: _loadDevices,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _devices.isEmpty
              ? const Center(
                  child: Text('No paired devices.\nPair ESP32 in Settings.'),
                )
              : ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    final isIMU = device.name?.contains('IMU') ?? false;
                    final isMotor = device.name?.contains('Motor') ?? false;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
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
                          device.name ?? 'Unknown Device',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${device.address}\n${isIMU ? 'IMU Sensor' : isMotor ? 'Motor Controller' : 'Unknown Type'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _connectToDevice(device),
                      ),
                    );
                  },
                ),
    );
  }
}
