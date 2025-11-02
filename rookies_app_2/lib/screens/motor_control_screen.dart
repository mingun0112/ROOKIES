import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_service.dart';

class MotorControlScreen extends StatefulWidget {
  const MotorControlScreen({Key? key}) : super(key: key);

  @override
  State<MotorControlScreen> createState() => _MotorControlScreenState();
}

class _MotorControlScreenState extends State<MotorControlScreen> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedMode = 'mpu'; // 'mpu' or 'vision'
  bool _isRunning = false;
  double _elbowAngle = 30.0;
  double _wristAngle = 0.0;

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

      await Future.delayed(const Duration(seconds: 2));
      await btService.getStatus();
    } catch (e) {
      _showMessage('Error: $e');
    }
  }

  Future<void> _setMode(String mode) async {
    try {
      final btService = context.read<BluetoothService>();
      await btService.setMode(mode);
      setState(() => _selectedMode = mode);
      _showMessage('Mode set to ${mode.toUpperCase()}');
    } catch (e) {
      _showMessage('Error: $e');
    }
  }

  Future<void> _toggleRunning() async {
    try {
      final btService = context.read<BluetoothService>();
      if (_isRunning) {
        await btService.stop();
        _showMessage('Motor control stopped');
      } else {
        await btService.start();
        _showMessage('Motor control started');
      }
      setState(() => _isRunning = !_isRunning);
    } catch (e) {
      _showMessage('Error: $e');
    }
  }

  Future<void> _resetMotors() async {
    try {
      final btService = context.read<BluetoothService>();
      await btService.resetMotors();
      setState(() {
        _elbowAngle = 30.0;
        _wristAngle = 0.0;
      });
      _showMessage('Motors reset to initial position');
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

  Future<void> _setManualAngles() async {
    try {
      final btService = context.read<BluetoothService>();
      await btService.setAngles(_elbowAngle, _wristAngle);
      _showMessage('Manual angles set');
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
        title: const Text('Motor Control'),
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

            // 모드 선택 섹션
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Control Mode',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'mpu',
                          label: Text('MPU Mode'),
                          icon: Icon(Icons.sensors),
                        ),
                        ButtonSegment(
                          value: 'vision',
                          label: Text('Vision Mode'),
                          icon: Icon(Icons.videocam),
                        ),
                      ],
                      selected: {_selectedMode},
                      onSelectionChanged: (Set<String> selected) {
                        _setMode(selected.first);
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedMode == 'mpu'
                          ? 'Using IMU sensor data for control'
                          : 'Using vision-based control',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
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
                      label: Text(_isRunning ? 'Stop Motors' : 'Start Motors'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: _isRunning ? Colors.red : Colors.green,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _resetMotors,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reset Motors'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
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

            // 수동 제어 (테스트용)
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Manual Control (Test)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Elbow: ${_elbowAngle.toStringAsFixed(1)}°'),
                    Slider(
                      value: _elbowAngle,
                      min: 0,
                      max: 180,
                      divisions: 180,
                      label: _elbowAngle.toStringAsFixed(1),
                      onChanged: (value) {
                        setState(() => _elbowAngle = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    Text('Wrist: ${_wristAngle.toStringAsFixed(1)}°'),
                    Slider(
                      value: _wristAngle,
                      min: 0,
                      max: 180,
                      divisions: 180,
                      label: _wristAngle.toStringAsFixed(1),
                      onChanged: (value) {
                        setState(() => _wristAngle = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _setManualAngles,
                      icon: const Icon(Icons.send),
                      label: const Text('Send Manual Angles'),
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
                          'Mode: ${_selectedMode.toUpperCase()}',
                          style: const TextStyle(color: Colors.grey),
                        ),
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
