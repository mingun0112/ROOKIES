import 'package:flutter/material.dart';
import 'screen/bluetooth_scan_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 WiFi Setup',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: BluetoothScanScreen(),
    );
  }
}
