import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/device_list_screen.dart';
import 'services/bluetooth_manager.dart'; // ⭐ 이름 변경

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BluetoothManager(), // ⭐ 이름 변경
      child: MaterialApp(
        title: 'Robotic Arm Controller',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: const DeviceListScreen(),
      ),
    );
  }
}
