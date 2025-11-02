import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_service.dart';

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
      final btService = context.read<BluetoothService>();
      await btService.setWiFi(
        _ssidController.text,
        _passwordController.text,
      );
      _showMessage('WiFi configured successfully');

      // 잠시 후 상태 확인
      await Future.delayed(const Duration(seconds: 2));
      await btService.getStatus();
    } catch (e) {
      _showMessage('Error: $e');
    }
  }

  Future<void> _calibrate() async {
    setState(() => _isCalibrating = true);
    try {
      final btService = context.read<BluetoothService>();
      await btService.startCalibration();
      _showMessage('Calibration started. Keep sensor still...');

      // Calibration은 약 1초 소요
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
      final btService = context.read<BluetoothService>();
      if (_isRunning) {
        await btService.stop();
        _showMessage('Sensor stopped');
      } else {
        await btService.start();
        _showMessage('Sensor started');
      }
      setState(() => _isRunning = !_isRunning);
    } catch (e) {
      _showMessage('Error: $e');
    }
  }

  Future<void> _getStatus() async {
    try {
      final btService = context.read<BluetoothService>();
      await btService.getStatus();
      _showMessage('Status requested');
    } catch (e) {
      _showMessage('Error: $e');
    }
  }

  Future<void> _reconnectWiFi() async {
    try {
      final btService = context.read<BluetoothService>();
      await btService.reconnectWiFi();
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
          Consumer<BluetoothService>(
            builder: (context, btService, _) {
              return IconButton(
                icon: Icon(
                  btService.isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                ),
                onPressed: btService.isConnected
                    ? () async {
                        await btService.disconnect();
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
            // WiFi 설정 섹션
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

            // Calibration 섹션
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

            // 제어 버튼들
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

            // 상태 표시
            Consumer<BluetoothService>(
              builder: (context, btService, _) {
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
                              btService.isConnected
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: btService.isConnected
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Connected to: ${btService.selectedDevice}',
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
