import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'device_control_screen.dart'; // 수정된 부분

class BluetoothScanScreen extends StatefulWidget {
  @override
  _BluetoothScanScreenState createState() => _BluetoothScanScreenState();
}

class _BluetoothScanScreenState extends State<BluetoothScanScreen> {
  List<ScanResult> scanResults = [];
  List<String> pairedDeviceIds = [];
  bool isScanning = false;

  @override
  void initState() {
    super.initState();
    checkPermissions();
    loadPairedDevices();
  }

  Future<void> checkPermissions() async {
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.location.request();
    print('Permissions checked');
  }

  Future<void> loadPairedDevices() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? saved = prefs.getStringList('paired_esp32_devices');
    if (saved != null) {
      setState(() {
        pairedDeviceIds = saved;
      });
      print('Loaded paired devices: $pairedDeviceIds');
    }
  }

  Future<void> savePairedDevice(BluetoothDevice device) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!pairedDeviceIds.contains(device.remoteId.toString())) {
      pairedDeviceIds.add(device.remoteId.toString());
      await prefs.setStringList('paired_esp32_devices', pairedDeviceIds);
      setState(() {});
      print('Device saved: ${device.remoteId}');
    }
  }

  Future<void> removePairedDevice(String deviceId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    pairedDeviceIds.remove(deviceId);
    await prefs.setStringList('paired_esp32_devices', pairedDeviceIds);
    setState(() {});
    print('Device removed: $deviceId');
  }

  Future<void> startScan() async {
    if (isScanning) {
      print('Scan already in progress');
      return;
    }

    setState(() {
      isScanning = true;
      scanResults.clear();
    });

    print('Starting BLE scan...');
    FlutterBluePlus.startScan(timeout: Duration(seconds: 4));

    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        scanResults = results;
      });
      print('Scan results updated: ${results.length} devices found');
    });

    await Future.delayed(Duration(seconds: 4));
    FlutterBluePlus.stopScan();

    setState(() {
      isScanning = false;
    });
    print('BLE scan stopped');
  }

  bool isPairedDevice(BluetoothDevice device) {
    return pairedDeviceIds.contains(device.remoteId.toString());
  }

  List<ScanResult> getPairedDevices() {
    return scanResults
        .where((result) => isPairedDevice(result.device))
        .toList();
  }

  List<ScanResult> getNewDevices() {
    return scanResults
        .where(
          (result) =>
              !isPairedDevice(result.device) &&
              (result.device.platformName.toLowerCase().contains('rookies') ||
                  result.device.platformName.toLowerCase().contains('esp')),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final pairedDevices = getPairedDevices();
    final newDevices = getNewDevices();

    return Scaffold(
      appBar: AppBar(title: Text('ESP32 관리'), backgroundColor: Colors.blue),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isScanning ? null : startScan,
              icon: isScanning
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.search),
              label: Text(isScanning ? '검색 중...' : 'ESP32 검색'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (pairedDevices.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        Icon(Icons.bookmark, color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '등록된 기기',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...pairedDevices.map(
                    (result) => buildDeviceCard(result, isPaired: true),
                  ),
                  Divider(height: 32, thickness: 1),
                ],
                if (newDevices.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        Icon(Icons.devices, color: Colors.grey[600], size: 20),
                        SizedBox(width: 8),
                        Text(
                          '근처 기기',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...newDevices.map(
                    (result) => buildDeviceCard(result, isPaired: false),
                  ),
                ],
                if (scanResults.isEmpty && !isScanning)
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.bluetooth_disabled,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          '검색 버튼을 눌러\nESP32를 찾아보세요',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDeviceCard(ScanResult result, {required bool isPaired}) {
    final device = result.device;
    final deviceName = device.platformName.isEmpty
        ? '알 수 없는 기기'
        : device.platformName;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: isPaired ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPaired
            ? BorderSide(color: Colors.blue[200]!, width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isPaired ? Colors.blue[50] : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.router,
            color: isPaired ? Colors.blue : Colors.grey[600],
            size: 28,
          ),
        ),
        title: Text(
          deviceName,
          style: TextStyle(
            fontWeight: isPaired ? FontWeight.bold : FontWeight.normal,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Text(
              device.remoteId.toString(),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.signal_cellular_alt, size: 14, color: Colors.grey),
                SizedBox(width: 4),
                Text(
                  '${result.rssi} dBm',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                if (isPaired) ...[
                  SizedBox(width: 12),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '등록됨',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: isPaired
            ? PopupMenuButton(
                icon: Icon(Icons.more_vert),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    child: Row(
                      children: [
                        Icon(Icons.settings, size: 20),
                        SizedBox(width: 8),
                        Text('기기 설정'),
                      ],
                    ),
                    onTap: () {
                      Future.delayed(Duration.zero, () {
                        connectToDevice(device);
                      });
                    },
                  ),
                  PopupMenuItem(
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Colors.red),
                        SizedBox(width: 8),
                        Text('등록 해제', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                    onTap: () {
                      removePairedDevice(device.remoteId.toString());
                    },
                  ),
                ],
              )
            : Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => connectToDevice(device),
      ),
    );
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      print('Attempting to connect to device: ${device.remoteId}');
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('연결 중...'),
                ],
              ),
            ),
          ),
        ),
      );

      await device.connect(timeout: Duration(seconds: 10));
      print('Connected to device: ${device.remoteId}');
      await savePairedDevice(device);

      Navigator.pop(context);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DeviceControlScreen(device: device), // 수정된 부분
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      print('Connection failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('연결 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
