// BLE connection to the MeCoffee PID controller.
//
// Scans for a device whose name starts with "meCoffee", connects, subscribes
// to notifications on the HM-10 FFE1 characteristic, and feeds parsed
// protocol lines into the DeviceModel.
//
// Handles auto-discovery, line buffering, initialization handshake,
// and auto-reconnect after disconnection.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'device_model.dart';
import 'protocol.dart';

// Match by short 16-bit UUID fragment — avoids case/format sensitivity issues
const String kServiceUuidFragment = 'ffe0';
const String kCharUuidFragment    = 'ffe1';
const String kDevicePrefix        = 'meCoffee';
const Duration kScanTimeout    = Duration(seconds: 4);
const Duration kReconnectDelay = Duration(seconds: 2);
const int kWriteChunk = 20; // HM-10 max payload per BLE packet

class BleConnection {
  final DeviceModel model;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _char;
  StreamSubscription? _notifySubscription;
  StreamSubscription? _stateSubscription;
  String _buffer = '';
  int _lineCount = 0;
  bool _running = false;
  bool _reconnecting = false; // guard against multiple reconnect loops

  BleConnection(this.model);

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

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

  // -------------------------------------------------------------------------
  // Connection flow
  // -------------------------------------------------------------------------

  Future<void> _connect() async {
    if (_reconnecting) return;
    _reconnecting = true;

    while (_running) {
      try {
        // 1. First, check if we are already connected to a meCoffee device
        final connected = FlutterBluePlus.connectedDevices;
        BluetoothDevice? target;
        for (var d in connected) {
          if (d.platformName.startsWith(kDevicePrefix)) {
            target = d;
            print('[BLE] Found already connected device: ${d.platformName}');
            break;
          }
        }

        // 2. If not already connected, scan for it
        target ??= await _scan();
        
        if (target == null) {
          // No device found during scan, wait briefly before retrying
          await Future.delayed(kReconnectDelay);
          continue;
        }

        _device = target;
        _char = null;

        // On Android, explicitly setting a 10s timeout can help clear stalled attempts
        await target.connect(autoConnect: false).timeout(const Duration(seconds: 10));

        // Use the List returned by discoverServices — more reliable than
        // device.servicesList which may not be populated yet.
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
          // FFE1 not found — wrong device or firmware issue
          await target.disconnect();
          await Future.delayed(kReconnectDelay);
          continue;
        }

        // Subscribe to incoming notifications
        await _char!.setNotifyValue(true);
        _lineCount = 0;
        _buffer = '';
        _notifySubscription = _char!.onValueReceived.listen(_onData);

        // Handshake: Give the device a moment to clear its buffer of tmp lines,
        // then request dump and clock sync. Corrected leading \n logic is in protocol.dart.
        await Future.delayed(const Duration(milliseconds: 1500));
        print('[BLE] sending cmd dump');
        await _send(cmdDump());
        await Future.delayed(const Duration(milliseconds: 500));
        await _send(cmdClockSync());

        // Watch for disconnection
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

        model.onConnected();
        _reconnecting = false;
        return; // Success — loop stops while connected

      } catch (e) {
        print('[BLE] Connection error: $e');
        model.onDisconnected();
        await Future.delayed(kReconnectDelay);
      }
    }

    _reconnecting = false;
  }

  Future<BluetoothDevice?> _scan() async {
    final completer = Completer<BluetoothDevice?>();
    StreamSubscription? sub;

    // Fast-stop scan as soon as we find the target
    sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.device.platformName.startsWith(kDevicePrefix)) {
          FlutterBluePlus.stopScan();
          sub?.cancel();
          if (!completer.isCompleted) completer.complete(r.device);
          return;
        }
      }
    });

    try {
      // Shorter timeout to avoid holding the radio for too long
      await FlutterBluePlus.startScan(timeout: kScanTimeout);
    } catch (e) {
      print('[BLE] Scan error (likely throttled): $e');
      sub.cancel();
      return null;
    }

    // Fail-safe to return null if the scan completes without finding the device
    Future.delayed(kScanTimeout + const Duration(milliseconds: 500), () {
      sub?.cancel();
      if (!completer.isCompleted) completer.complete(null);
    });

    return completer.future;
  }

  // -------------------------------------------------------------------------
  // Data handling
  // -------------------------------------------------------------------------

  void _onData(List<int> data) {
    final decoded = utf8.decode(data, allowMalformed: true);
    print('[BLE] raw: ${decoded.replaceAll('\n', '\\n').replaceAll('\r', '\\r')}');
    _buffer += decoded;

    while (_buffer.contains('\n')) {
      final idx = _buffer.indexOf('\n');
      final line = _buffer.substring(0, idx).trim();
      _buffer = _buffer.substring(idx + 1);

      if (line.isEmpty) continue;

      _lineCount++;
      print('[BLE] line $_lineCount: $line');

      _dispatch(line);
    }
  }

  void _dispatch(String line) {
    final msg = parseLine(line);
    if (msg == null) {
      print('[BLE] unparsed: $line');
      return;
    }

    if (msg is TmpMessage) {
      model.onTemperature(msg);
    } else if (msg is PidMessage) {
      model.onPid(msg);
    } else if (msg is ParamMessage) {
      print('[BLE] param: ${msg.name} = ${msg.rawValue}');
      model.onParam(msg);
    } else if (msg is ShotMessage) {
      model.onShot(msg);
    }
  }

  // -------------------------------------------------------------------------
  // Writing
  // -------------------------------------------------------------------------

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
