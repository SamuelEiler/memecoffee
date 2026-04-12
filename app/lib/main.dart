import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ble_connection.dart';
import 'device_model.dart';
import 'screens/dashboard_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => DeviceModel(),
      child: const MeCoffeeApp(),
    ),
  );
}

class MeCoffeeApp extends StatefulWidget {
  const MeCoffeeApp({super.key});

  @override
  State<MeCoffeeApp> createState() => _MeCoffeeAppState();
}

class _MeCoffeeAppState extends State<MeCoffeeApp> {
  late BleConnection _ble;

  @override
  void initState() {
    super.initState();
    _ble = BleConnection(context.read<DeviceModel>());
    _ble.start();
  }

  @override
  void dispose() {
    _ble.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeCoffee',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB87333), // copper
          brightness: Brightness.dark,
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}
