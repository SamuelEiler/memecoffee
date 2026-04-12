// Device state model.
//
// A ChangeNotifier that holds all live data from the MeCoffee.
// The BLE connection layer calls update methods here; the UI listens
// via Provider and rebuilds automatically.

import 'package:flutter/foundation.dart';
import 'protocol.dart';

const int kHistorySize = 200; // rolling window for the temperature chart

class ShotState {
  final bool active;
  final int durationMs;

  const ShotState({this.active = false, this.durationMs = 0});
}

class DeviceModel extends ChangeNotifier {
  // Connection
  bool connected = false;

  // Live readings
  double temperature = 0.0; // °C, sensor 1
  double setpoint = 0.0; // °C
  double sensor2 = 0.0; // °C, sensor 2
  PidMessage pid = PidMessage(p: 0, i: 0, d: 0, a: 0);
  ShotState shot = const ShotState();

  // Stored device parameters (raw strings, keyed by parameter name)
  final Map<String, String> parameters = {};

  // Rolling history for the temperature chart
  final List<double> historySensor1 = [];
  final List<double> historySetpoint = [];

  // -------------------------------------------------------------------------
  // Called by the BLE connection layer
  // -------------------------------------------------------------------------

  void onConnected() {
    connected = true;
    notifyListeners();
  }

  void onDisconnected() {
    connected = false;
    temperature = 0.0;
    pid = PidMessage(p: 0, i: 0, d: 0, a: 0);
    notifyListeners();
  }

  void onTemperature(TmpMessage msg) {
    temperature = msg.sensor1;
    setpoint = msg.setpoint;
    sensor2 = msg.sensor2;

    _appendHistory(historySensor1, msg.sensor1);
    _appendHistory(historySetpoint, msg.setpoint);

    notifyListeners();
  }

  void onPid(PidMessage msg) {
    pid = msg;
    notifyListeners();
  }

  void onParam(ParamMessage msg) {
    parameters[msg.name] = msg.rawValue;
    notifyListeners();
  }

  void onShot(ShotMessage msg) {
    if (msg.durationMs == 0) {
      shot = const ShotState(active: true, durationMs: 0);
    } else {
      shot = ShotState(active: false, durationMs: msg.durationMs);
    }
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Return the human-readable value of a stored parameter, or null.
  dynamic getParam(String name) {
    final raw = parameters[name];
    if (raw == null) return null;
    return scaleParam(name, raw);
  }

  void _appendHistory(List<double> list, double value) {
    list.add(value);
    if (list.length > kHistorySize) list.removeAt(0);
  }
}
