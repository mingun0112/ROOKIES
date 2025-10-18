import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'dart:async';
import 'models/wifi_network.dart';

class WiFiSetupTab extends StatefulWidget {
  final BluetoothDevice device;
  final BluetoothCharacteristic? scanChar;
  final BluetoothCharacteristic? ssidChar;
  final BluetoothCharacteristic? passChar;
  final BluetoothCharacteristic? statusChar;

  WiFiSetupTab({
    required this.device,
    this.scanChar,
    this.ssidChar,
    this.passChar,
    this.statusChar,
  });

  @override
  _WiFiSetupTabState createState() => _WiFiSetupTabState();
}

class _WiFiSetupTabState extends State<WiFiSetupTab> {
  final TextEditingController passwordController = TextEditingController();

  List<WiFiNetwork> wifiNetworks = [];
  WiFiNetwork? selectedNetwork;

  String statusMessage = '';
  bool isScanning = false;
  bool isConnecting = false;

  StreamSubscription? scanSubscription;
  StreamSubscription? statusSubscription;

  @override
  void initState() {
    super.initState();
    resetWiFiOnConnect(); // Retain this if needed
    setupNotifications();
    // Removed the automatic call to startWiFiScan
  }

  Future<void> resetWiFiOnConnect() async {
    if (widget.scanChar != null) {
      try {
        await widget.scanChar!.write(
          utf8.encode('RESET'),
          withoutResponse: false,
        );
        print('WiFi reset command sent to ESP32');
      } catch (e) {
        print('Failed to send WiFi reset command: $e');
      }
    }
  }

  // Removed the automatic scan from setupNotifications
  Future<void> setupNotifications() async {
    if (widget.scanChar != null) {
      await widget.scanChar!.setNotifyValue(true);
      scanSubscription = widget.scanChar!.lastValueStream.listen((value) {
        String data = utf8.decode(value);
        print('Scan result: $data');

        if (data == "SCANNING") {
          setState(() {
            isScanning = true;
            statusMessage = '스캔 중...';
          });
        } else if (data == "NONE") {
          setState(() {
            isScanning = false;
            statusMessage = 'WiFi를 찾을 수 없습니다';
            wifiNetworks = [];
          });
        } else {
          parseWiFiList(data);
        }
      });
    }

    if (widget.statusChar != null) {
      await widget.statusChar!.setNotifyValue(true);
      statusSubscription = widget.statusChar!.lastValueStream.listen((value) {
        String status = utf8.decode(value);
        print('WiFi Status: $status');

        setState(() {
          if (status.startsWith('CONNECTED:')) {
            String ip = status.split(':')[1];
            statusMessage = '✅ WiFi 연결 성공!\nIP: $ip';
            isConnecting = false;
          } else if (status == 'CONNECTING') {
            statusMessage = '🔄 WiFi 연결 중...';
          } else if (status == 'FAILED') {
            statusMessage = '❌ WiFi 연결 실패\n비밀번호를 확인하세요';
            isConnecting = false;
          }
        });
      });
    }
  }

  void parseWiFiList(String data) {
    List<WiFiNetwork> networks = [];

    List<String> lines = data.split(';');
    for (String line in lines) {
      if (line.trim().isEmpty) continue;

      List<String> parts = line.split('|');
      if (parts.length >= 3) {
        networks.add(
          WiFiNetwork(
            ssid: parts[0],
            rssi: int.tryParse(parts[1]) ?? 0,
            encrypted: parts[2] == '1',
          ),
        );
      }
    }

    networks.sort((a, b) => b.rssi.compareTo(a.rssi));

    setState(() {
      wifiNetworks = networks;
      isScanning = false;
      statusMessage = '${networks.length}개의 WiFi 발견';
    });
  }

  Future<void> startWiFiScan() async {
    if (widget.scanChar == null) return;

    setState(() {
      isScanning = true;
      wifiNetworks = [];
      statusMessage = 'WiFi 검색 중...';
    });

    try {
      await widget.scanChar!.write(utf8.encode('SCAN'), withoutResponse: false);
      print('Scan request sent');
    } catch (e) {
      print('Scan error: $e');
      setState(() {
        statusMessage = '스캔 실패: $e';
        isScanning = false;
      });
    }
  }

  Future<void> connectToWiFi() async {
    if (selectedNetwork == null || passwordController.text.isEmpty) {
      setState(() {
        statusMessage = '⚠️ WiFi와 비밀번호를 입력하세요';
      });
      return;
    }

    if (widget.ssidChar == null || widget.passChar == null) {
      setState(() {
        statusMessage = '❌ ESP32와 통신할 수 없습니다';
      });
      return;
    }

    setState(() {
      isConnecting = true;
      statusMessage = '📤 WiFi 정보 전송 중...';
    });

    try {
      await widget.ssidChar!.write(
        utf8.encode(selectedNetwork!.ssid),
        withoutResponse: false,
      );
      print('SSID sent: ${selectedNetwork!.ssid}');

      await Future.delayed(Duration(milliseconds: 100));

      await widget.passChar!.write(
        utf8.encode(passwordController.text),
        withoutResponse: false,
      );
      print('Password sent');

      setState(() {
        statusMessage = '✅ WiFi 정보 전송 완료!\nESP32가 연결 시도 중...';
      });
    } catch (e) {
      print('Send error: $e');
      setState(() {
        statusMessage = '❌ 전송 실패: $e';
        isConnecting = false;
      });
    }
  }

  @override
  void dispose() {
    // Removed WiFi reset logic to prevent disconnection when switching tabs
    scanSubscription?.cancel();
    statusSubscription?.cancel();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 2,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.bluetooth_connected, color: Colors.blue, size: 32),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ESP32 연결됨',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          widget.device.platformName.isEmpty
                              ? widget.device.remoteId.toString()
                              : widget.device.platformName,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh),
                    onPressed: isScanning ? null : startWiFiScan,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 24),
          if (isScanning)
            Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('WiFi 검색 중...'),
                ],
              ),
            )
          else if (wifiNetworks.isEmpty)
            Center(
              child: Column(
                children: [
                  Icon(Icons.wifi_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'WiFi를 검색하세요',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: startWiFiScan,
                    icon: Icon(Icons.search),
                    label: Text('WiFi 검색'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WiFi 선택',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    itemCount: wifiNetworks.length,
                    separatorBuilder: (context, index) => Divider(height: 1),
                    itemBuilder: (context, index) {
                      final network = wifiNetworks[index];
                      final isSelected = selectedNetwork == network;

                      return ListTile(
                        leading: Icon(
                          network.encrypted ? Icons.wifi_lock : Icons.wifi,
                          color: isSelected ? Colors.blue : Colors.grey,
                        ),
                        title: Text(
                          network.ssid,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text('신호: ${network.rssi} dBm'),
                        trailing: isSelected
                            ? Icon(Icons.check_circle, color: Colors.blue)
                            : null,
                        selected: isSelected,
                        selectedTileColor: Colors.blue[50],
                        onTap: () {
                          setState(() {
                            selectedNetwork = network;
                            passwordController.clear();
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          if (selectedNetwork != null) ...[
            SizedBox(height: 24),
            TextField(
              controller: passwordController,
              decoration: InputDecoration(
                labelText: 'WiFi 비밀번호',
                hintText: '${selectedNetwork!.ssid} 비밀번호',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              obscureText: true,
              enabled: !isConnecting,
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: isConnecting ? null : connectToWiFi,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isConnecting) ...[
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(width: 12),
                  ],
                  Text(
                    isConnecting ? '연결 중...' : 'WiFi 연결하기',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 24),
          if (statusMessage.isNotEmpty)
            Card(
              elevation: 2,
              color: _getStatusColor(),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    _getStatusIcon(),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        statusMessage,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    if (statusMessage.contains('성공')) {
      return Colors.green[50]!;
    } else if (statusMessage.contains('실패') || statusMessage.contains('에러')) {
      return Colors.red[50]!;
    } else {
      return Colors.blue[50]!;
    }
  }

  Widget _getStatusIcon() {
    if (statusMessage.contains('성공')) {
      return Icon(Icons.check_circle, color: Colors.green, size: 28);
    } else if (statusMessage.contains('실패') || statusMessage.contains('에러')) {
      return Icon(Icons.error, color: Colors.red, size: 28);
    } else {
      return Icon(Icons.info, color: Colors.blue, size: 28);
    }
  }
}
