// BLE connection to the MeCoffee PID controller.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'device_model.dart';
import 'protocol.dart';

const String kServiceUuidFragment = 'ffe0';
const String kCharUuidFragment    = 'ffe1';
const String kDevicePrefix        = 'meCoffee';

// Android allows max 5 scans per 30s — keep scan+delay total well above 6s
const Duration kScanTimeout    = Duration(seconds: 8);
const Duration kReconnectDelay = Duration(seconds: 5);
const int kWriteChunk = 20; 

class BleConnection {
  final DeviceModel model;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _char;
  StreamSubscription? _notifySubscription;
  StreamSubscription? _stateSubscription;
  String _buffer = '';
  int _lineCount = 0;
  bool _running = false;
  bool _reconnecting = false; 

  BleConnection(this.model);

  void start() {
    _running = true;
    _connect();
  }

  void stop() {
    _running = false;
    _notifySubscription?.cancel();
    _stateSubscription?.cancel();
    _device?.disconnect();
  }

  Future<void> send(String data) async {
    await _send(data);
  }

  Future<void> _connect() async {
    if (_reconnecting) return;
    _reconnecting = true;

    while (_running) {
      try {
        // Wait for Bluetooth to be ON
        BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
        if (state != BluetoothAdapterState.on) {
           print('[BLE] Bluetooth is $state. Waiting...');
           if (state == BluetoothAdapterState.off && Platform.isAndroid) {
              print('[BLE] Attempting to turn on Bluetooth...');
              await FlutterBluePlus.turnOn();
           }
           await Future.delayed(const Duration(seconds: 5));
           continue;
        }

        print('[BLE] --- Attempting Connection ---');

        // 1. Check system devices (already paired/connected)
        List<BluetoothDevice> system = await FlutterBluePlus.systemDevices([]);
        BluetoothDevice? target;
        for (var d in system) {
          if (d.platformName.toLowerCase().contains('coffee')) {
            target = d;
            print('[BLE] Found in system devices: ${d.platformName}');
            break;
          }
        }

        // 2. Scan if not found
        if (target == null) {
          target = await _scan();
        }
        
        if (target == null) {
          print('[BLE] No meCoffee found. Waiting 10s to stay under scan limit...');
          await Future.delayed(kReconnectDelay);
          continue;
        }

        _device = target;
        _char = null;

        print('[BLE] Connecting to ${target.remoteId}...');
        await target.connect(autoConnect: false).timeout(const Duration(seconds: 15));

        print('[BLE] Discovering services...');
        final services = await target.discoverServices();
        for (final service in services) {
          if (service.uuid.toString().contains(kServiceUuidFragment)) {
            for (final char in service.characteristics) {
              if (char.uuid.toString().contains(kCharUuidFragment)) {
                _char = char;
              }
            }
          }
        }

        if (_char == null) {
          print('[BLE] Target characteristic $kCharUuidFragment not found.');
          await target.disconnect();
          await Future.delayed(kReconnectDelay);
          continue;
        }

        await _char!.setNotifyValue(true);
        _lineCount = 0;
        _buffer = '';
        _notifySubscription = _char!.onValueReceived.listen(_onData);

        // Corrected Handshake: leading \n for meCoffee firmware
        await Future.delayed(const Duration(milliseconds: 1500));
        await _send(cmdDump());
        await Future.delayed(const Duration(milliseconds: 500));
        await _send(cmdClockSync());

        _stateSubscription = target.connectionState.listen((state) {
          if (state == BluetoothConnectionState.disconnected) {
            model.onDisconnected();
            _notifySubscription?.cancel();
            _stateSubscription?.cancel();
            _reconnecting = false;
            if (_running) {
              Future.delayed(kReconnectDelay, _connect);
            }
          }
        });

        print('[BLE] Connection successful.');
        model.onConnected();
        _reconnecting = false;
        return; 

      } catch (e) {
        print('[BLE] Connection error: $e');
        model.onDisconnected();
        await Future.delayed(kReconnectDelay);
      }
    }
    _reconnecting = false;
  }

  Future<BluetoothDevice?> _scan() async {
    print('[BLE] Starting scan...');
    BluetoothDevice? found;
    
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(seconds: 1));
    }

    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (ScanResult r in results) {
        final name = r.advertisementData.advName;
        final pName = r.device.platformName;

        if (name.isNotEmpty || pName.isNotEmpty) {
          print('[BLE] Discovered: "$name" / "$pName" [${r.device.remoteId}]');
        }

        if (name.toLowerCase().contains('coffee') ||
            pName.toLowerCase().contains('coffee')) {
          print('[BLE] >>> meCoffee Found! <<<');
          found = r.device;
          FlutterBluePlus.stopScan(); // stop immediately — no need to scan longer
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: kScanTimeout,
        androidUsesFineLocation: true,
      );
    } catch (e) {
      print('[BLE] startScan failed: $e');
    }

    // Wait until scan stops (either device found + early stop, or timeout)
    while (FlutterBluePlus.isScanningNow) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    sub.cancel();
    return found;
  }

  void _onData(List<int> data) {
    final decoded = utf8.decode(data, allowMalformed: true);
    _buffer += decoded;
    while (_buffer.contains('\n')) {
      final idx = _buffer.indexOf('\n');
      final line = _buffer.substring(0, idx).trim();
      _buffer = _buffer.substring(idx + 1);
      if (line.isEmpty) continue;
      _lineCount++;
      _dispatch(line);
    }
  }

  void _dispatch(String line) {
    final msg = parseLine(line);
    if (msg == null) return;
    if (msg is TmpMessage) model.onTemperature(msg);
    else if (msg is PidMessage) model.onPid(msg);
    else if (msg is ParamMessage) model.onParam(msg);
    else if (msg is ShotMessage) model.onShot(msg);
  }

  Future<void> _send(String data) async {
    if (_char == null) return;
    final bytes = utf8.encode(data);
    for (var i = 0; i < bytes.length; i += kWriteChunk) {
      final chunk = bytes.sublist(i, (i + kWriteChunk).clamp(0, bytes.length));
      await _char!.write(chunk, withoutResponse: true);
      if (bytes.length > kWriteChunk) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }
}
