import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp; // ⭐ alias 사용

class BluetoothManager extends ChangeNotifier {
  fbp.BluetoothDevice? _device; // ⭐ fbp. 사용
  fbp.BluetoothCharacteristic? _txCharacteristic;
  fbp.BluetoothCharacteristic? _rxCharacteristic;

  bool _isConnected = false;
  String _selectedDevice = '';

  bool get isConnected => _isConnected;
  String get selectedDevice => _selectedDevice;

  // ESP32 BLE 서비스/특성 UUID
  static const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String RX_CHAR_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  static const String TX_CHAR_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a9";

  // 블루투스 기기 검색
  Future<List<fbp.ScanResult>> scanForDevices() async {
    // ⭐ fbp. 사용
    List<fbp.ScanResult> results = [];

    try {
      if (fbp.FlutterBluePlus.isScanningNow) {
        await fbp.FlutterBluePlus.stopScan();
      }

      await fbp.FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 5),
        androidUsesFineLocation: true,
      );

      await for (List<fbp.ScanResult> scanResults
          in fbp.FlutterBluePlus.scanResults) {
        results = scanResults;
        if (results.isNotEmpty) break;
      }

      await fbp.FlutterBluePlus.stopScan();

      return results.where((result) {
        final name = result.device.platformName.toLowerCase();
        return name.contains('esp32') ||
            name.contains('imu') ||
            name.contains('motor');
      }).toList();
    } catch (e) {
      debugPrint('Scan error: $e');
      return [];
    }
  }

  // 기기 연결
  Future<bool> connectToDevice(fbp.BluetoothDevice device) async {
    // ⭐ fbp. 사용
    try {
      _device = device;
      _selectedDevice = device.platformName;

      await device.connect(timeout: const Duration(seconds: 15));

      // ⭐ fbp. 사용 - BluetoothService는 flutter_blue_plus의 것
      List<fbp.BluetoothService> services = await device.discoverServices();

      fbp.BluetoothService? targetService;
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() ==
            SERVICE_UUID.toLowerCase()) {
          targetService = service;
          break;
        }
      }

      if (targetService == null) {
        debugPrint('Service not found');
        await device.disconnect();
        return false;
      }

      for (var characteristic in targetService.characteristics) {
        String uuid = characteristic.uuid.toString().toLowerCase();

        if (uuid == RX_CHAR_UUID.toLowerCase()) {
          _rxCharacteristic = characteristic;
          await characteristic.setNotifyValue(true);
          characteristic.lastValueStream.listen((value) {
            String response = utf8.decode(value);
            _handleResponse(response);
          });
        } else if (uuid == TX_CHAR_UUID.toLowerCase()) {
          _txCharacteristic = characteristic;
        }
      }

      if (_txCharacteristic == null || _rxCharacteristic == null) {
        debugPrint('Characteristics not found');
        await device.disconnect();
        return false;
      }

      _isConnected = true;
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
    try {
      await _device?.disconnect();
    } catch (e) {
      debugPrint('Disconnect error: $e');
    }

    _device = null;
    _txCharacteristic = null;
    _rxCharacteristic = null;
    _isConnected = false;
    _selectedDevice = '';
    notifyListeners();
  }

  // JSON 명령 전송
  Future<void> sendCommand(Map<String, dynamic> command) async {
    if (_txCharacteristic == null || !_isConnected) {
      throw Exception('Not connected to device');
    }

    try {
      String jsonStr = jsonEncode(command);
      List<int> bytes = utf8.encode('$jsonStr\n');

      const int chunkSize = 20;

      for (int i = 0; i < bytes.length; i += chunkSize) {
        int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        List<int> chunk = bytes.sublist(i, end);
        await _txCharacteristic!.write(chunk, withoutResponse: false);
        await Future.delayed(const Duration(milliseconds: 50));
      }

      debugPrint('Sent: $jsonStr');
    } catch (e) {
      debugPrint('Send error: $e');
      rethrow;
    }
  }

  // WiFi 설정
  Future<void> setWiFi(String ssid, String password) async {
    await sendCommand({
      'cmd': 'set_wifi',
      'ssid': ssid,
      'password': password,
    });
  }

  // 모드 설정
  Future<void> setMode(String mode) async {
    await sendCommand({
      'cmd': 'set_mode',
      'mode': mode,
    });
  }

  // Calibration
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

  // 모터 리셋
  Future<void> resetMotors() async {
    await sendCommand({'cmd': 'reset_motors'});
  }

  // 수동 각도 설정
  Future<void> setAngles(double? elbow, double? wrist) async {
    Map<String, dynamic> cmd = {'cmd': 'set_angles'};
    if (elbow != null) cmd['elbow'] = elbow;
    if (wrist != null) cmd['wrist'] = wrist;
    await sendCommand(cmd);
  }

  // 응답 처리
  void _handleResponse(String response) {
    try {
      Map<String, dynamic> json = jsonDecode(response);
      debugPrint('Response: $json');
    } catch (e) {
      debugPrint('Failed to parse response: $e');
    }
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
