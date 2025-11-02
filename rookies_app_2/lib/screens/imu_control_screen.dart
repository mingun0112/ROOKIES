import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_manager.dart'; // ⭐ 이름 변경

class IMUControlScreen extends StatefulWidget {
  const IMUControlScreen({Key? key}) : super(key: key);

  @override
  State<IMUControlScreen> createState() => _IMUControlScreenState();
}

class _IMUControlScreenState extends State<IMUControlScreen> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isCalibrating = false;
  bool _isRunning = false;

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _setWiFi() async {
    if (_ssidController.text.isEmpty || _passwordController.text.isEmpty) {
      _showMessage('Please enter SSID and Password');
      return;
    }

    try {
      final btManager = context.read<BluetoothManager>(); // ⭐ 이름 변경
      await btManager.setWiFi(
        _ssidController.text,
        _passwordController.text,
      );
      _showMessage('WiFi configured successfully');

      await Future.delayed(const Duration(seconds: 2));
      await btManager.getStatus();
    } catch (e) {
      _showMessage('Error: $e');
    }
  }

  Future<void> _calibrate() async {
    setState(() => _isCalibrating = true);
    try {
      final btManager = context.read<BluetoothManager>(); // ⭐ 이름 변경
      await btManager.startCalibration();
      _showMessage('Calibration started. Keep sensor still...');

      await Future.delayed(const Duration(seconds: 2));
      _showMessage('Calibration completed');
    } catch (e) {
      _showMessage('Calibration error: $e');
    } finally {
      setState(() => _isCalibrating = false);
    }
  }

  Future<void> _toggleRunning() async {
    try {
      final btManager = context.read<BluetoothManager>(); // ⭐ 이름 변경
      if (_isRunning) {
        await btManager.stop();
        _showMessage('Sensor stopped');
      } else {
        await btManager.start();
        _showMessage('Sensor started');
      }
      setState(() => _isRunning = !_isRunning);
    } catch (e) {
      _showMessage('Error: $e');
    }
  }

  Future<void> _getStatus() async {
    try {
      final btManager = context.read<BluetoothManager>(); // ⭐ 이름 변경
      await btManager.getStatus();
      _showMessage('Status requested');
    } catch (e) {
      _showMessage('Error: $e');
    }
  }

  Future<void> _reconnectWiFi() async {
    try {
      final btManager = context.read<BluetoothManager>(); // ⭐ 이름 변경
      await btManager.reconnectWiFi();
      _showMessage('Reconnecting to WiFi...');
    } catch (e) {
      _showMessage('Error: $e');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IMU Sensor Control'),
        actions: [
          Consumer<BluetoothManager>(
            // ⭐ 이름 변경
            builder: (context, btManager, _) {
              return IconButton(
                icon: Icon(
                  btManager.isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                ),
                onPressed: btManager.isConnected
                    ? () async {
                        await btManager.disconnect();
                        Navigator.pop(context);
                      }
                    : null,
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'WiFi Configuration',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _ssidController,
                      decoration: const InputDecoration(
                        labelText: 'WiFi SSID',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.wifi),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'WiFi Password',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _setWiFi,
                      icon: const Icon(Icons.save),
                      label: const Text('Set WiFi'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sensor Calibration',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Place sensor on flat surface and keep it still during calibration.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isCalibrating ? null : _calibrate,
                      icon: _isCalibrating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.tune),
                      label: Text(
                        _isCalibrating ? 'Calibrating...' : 'Start Calibration',
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Control',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _toggleRunning,
                      icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
                      label: Text(_isRunning ? 'Stop Sensor' : 'Start Sensor'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: _isRunning ? Colors.red : Colors.green,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _getStatus,
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Get Status'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _reconnectWiFi,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reconnect WiFi'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Consumer<BluetoothManager>(
              // ⭐ 이름 변경
              builder: (context, btManager, _) {
                return Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              btManager.isConnected
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: btManager.isConnected
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Connected to: ${btManager.selectedDevice}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Status: ${_isRunning ? 'Running' : 'Stopped'}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
