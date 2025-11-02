import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class BluetoothService extends ChangeNotifier {
  BluetoothConnection? _connection;
  bool _isConnected = false;
  String _selectedDevice = '';

  bool get isConnected => _isConnected;
  String get selectedDevice => _selectedDevice;

  // 블루투스 기기 검색
  Future<List<BluetoothDevice>> getPairedDevices() async {
    try {
      List<BluetoothDevice> devices =
          await FlutterBluetoothSerial.instance.getBondedDevices();
      return devices;
    } catch (e) {
      debugPrint('Error getting devices: $e');
      return [];
    }
  }

  // 기기 연결
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      _connection = await BluetoothConnection.toAddress(device.address);
      _isConnected = true;
      _selectedDevice = device.name ?? 'Unknown';

      // 수신 데이터 리스닝
      _connection!.input!.listen((data) {
        String response = String.fromCharCodes(data);
        debugPrint('Received: $response');
        _handleResponse(response);
      }).onDone(() {
        _isConnected = false;
        _selectedDevice = '';
        notifyListeners();
      });

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Connection error: $e');
      _isConnected = false;
      notifyListeners();
      return false;
    }
  }

  // 기기 연결 해제
  Future<void> disconnect() async {
    await _connection?.close();
    _connection = null;
    _isConnected = false;
    _selectedDevice = '';
    notifyListeners();
  }

  // JSON 명령 전송
  Future<void> sendCommand(Map<String, dynamic> command) async {
    if (_connection == null || !_isConnected) {
      throw Exception('Not connected to device');
    }

    String jsonStr = jsonEncode(command);
    _connection!.output.add(utf8.encode('$jsonStr\n'));
    await _connection!.output.allSent;
    debugPrint('Sent: $jsonStr');
  }

  // WiFi 설정
  Future<void> setWiFi(String ssid, String password) async {
    await sendCommand({
      'cmd': 'set_wifi',
      'ssid': ssid,
      'password': password,
    });
  }

  // 모드 설정 (모터 ESP32만)
  Future<void> setMode(String mode) async {
    await sendCommand({
      'cmd': 'set_mode',
      'mode': mode, // 'mpu' or 'vision'
    });
  }

  // Calibration 시작 (IMU ESP32만)
  Future<void> startCalibration() async {
    await sendCommand({'cmd': 'calibrate'});
  }

  // 시작/중지
  Future<void> start() async {
    await sendCommand({'cmd': 'start'});
  }

  Future<void> stop() async {
    await sendCommand({'cmd': 'stop'});
  }

  // 상태 조회
  Future<void> getStatus() async {
    await sendCommand({'cmd': 'status'});
  }

  // WiFi 재연결
  Future<void> reconnectWiFi() async {
    await sendCommand({'cmd': 'reconnect_wifi'});
  }

  // 모터 리셋 (모터 ESP32만)
  Future<void> resetMotors() async {
    await sendCommand({'cmd': 'reset_motors'});
  }

  // 수동 각도 설정 (테스트용)
  Future<void> setAngles(double? elbow, double? wrist) async {
    Map<String, dynamic> cmd = {'cmd': 'set_angles'};
    if (elbow != null) cmd['elbow'] = elbow;
    if (wrist != null) cmd['wrist'] = wrist;
    await sendCommand(cmd);
  }

  // 응답 처리
  void _handleResponse(String response) {
    try {
      // JSON 응답 파싱
      Map<String, dynamic> json = jsonDecode(response);
      debugPrint('Response: $json');
      // 필요시 상태 업데이트
    } catch (e) {
      debugPrint('Failed to parse response: $e');
    }
  }

  @override
  void dispose() {
    _connection?.dispose();
    super.dispose();
  }
}
