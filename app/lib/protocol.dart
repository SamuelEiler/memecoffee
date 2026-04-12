// MeCoffee protocol parser.
//
// The device communicates over BLE UART using plain ASCII lines:
//   tmp [ts] [setpoint*100] [s1*100] [s2*100] OK
//   pid [p] [i] [d] [a] OK
//   cmd get [param] [raw_value] OK
//   cmd set s_[param] [raw_value] OK
//   sht [ts] [duration_ms] OK

// ---------------------------------------------------------------------------
// Parsed message types
// ---------------------------------------------------------------------------

class TmpMessage {
  final int timestamp; // ms since device boot
  final double setpoint; // °C
  final double sensor1; // °C — primary boiler
  final double sensor2; // °C — secondary

  TmpMessage({
    required this.timestamp,
    required this.setpoint,
    required this.sensor1,
    required this.sensor2,
  });
}

class PidMessage {
  final int p, i, d, a;

  PidMessage({required this.p, required this.i, required this.d, required this.a});

  /// Heater power as a percentage 0–100 (can briefly exceed 100 during heat-up).
  double get power => (p + i + d + a) / 655.35;
}

class ParamMessage {
  final String name;
  final String rawValue;

  ParamMessage({required this.name, required this.rawValue});
}

class ShotMessage {
  final int timestamp;
  final int durationMs; // 0 = shot started, >0 = shot ended with this duration

  ShotMessage({required this.timestamp, required this.durationMs});
}

// ---------------------------------------------------------------------------
// Scale factors: raw device integer / scale = human-readable value
// ---------------------------------------------------------------------------

const Map<String, double> kScales = {
  'tmpsp': 100.0,
  'tmpstm': 100.0,
  'pd1i': 100.0,
  'pd1imx': 655.36,
  'pistrt': 1000.0,
  'piprd': 1000.0,
};

// Parameters stored as seconds-since-midnight, displayed as "HH:MM"
const Set<String> kTimeParams = {'tmron', 'tmroff'};

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

/// Parse one line from the device. Returns a typed message or null.
Object? parseLine(String line) {
  line = line.trim();
  if (line.isEmpty) return null;

  final parts = line.split(' ');
  if (parts.isEmpty) return null;

  switch (parts[0]) {
    case 'tmp':
      if (parts.length < 5) return null;
      return TmpMessage(
        timestamp: int.parse(parts[1]),
        setpoint: int.parse(parts[2]) / 100.0,
        sensor1: int.parse(parts[3]) / 100.0,
        sensor2: int.parse(parts[4]) / 100.0,
      );

    case 'pid':
      if (parts.length < 5) return null;
      return PidMessage(
        p: int.parse(parts[1]),
        i: int.parse(parts[2]),
        d: int.parse(parts[3]),
        a: int.parse(parts[4]),
      );

    case 'cmd':
      if (parts.length < 3) return null;
      if (parts[1] == 'get' && parts.length >= 4) {
        return ParamMessage(name: parts[2], rawValue: parts[3]);
      }
      if (parts[1] == 'set' && parts.length >= 4) {
        final name = parts[2].startsWith('s_') ? parts[2].substring(2) : parts[2];
        return ParamMessage(name: name, rawValue: parts[3]);
      }
      return null;

    case 'sht':
      if (parts.length < 3) return null;
      return ShotMessage(
        timestamp: int.parse(parts[1]),
        durationMs: int.parse(parts[2]),
      );
  }

  return null;
}

// ---------------------------------------------------------------------------
// Scaling helpers
// ---------------------------------------------------------------------------

/// Convert a raw parameter value string to a human-readable value.
/// Returns a double for most params, or an "HH:MM" String for time params.
dynamic scaleParam(String name, String raw) {
  if (kTimeParams.contains(name)) {
    final secs = int.tryParse(raw) ?? 0;
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  final rawInt = int.tryParse(raw);
  if (rawInt == null) return raw;

  final scale = kScales[name];
  if (scale != null) return rawInt / scale;

  return rawInt;
}

// ---------------------------------------------------------------------------
// Command builders
// ---------------------------------------------------------------------------

String cmdDump() => '\ncmd dump OK\r\n';

String cmdClockSync() {
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day);
  final secs = now.difference(midnight).inSeconds;
  return '\ncmd clock set $secs OK\r\n';
}

String cmdSet(String param, dynamic value) {
  var rawValue = value;

  if (value is bool) {
    rawValue = value ? 1 : 0;
  }

  if (kTimeParams.contains(param)) {
    // "HH:MM" -> seconds since midnight
    final parts = value.toString().split(':');
    rawValue = int.parse(parts[0]) * 3600 + int.parse(parts[1]) * 60;
  } else {
    final scale = kScales[param];
    if (scale != null) {
      rawValue = (double.parse(value.toString()) * scale).round();
    }
  }

  return '\ncmd set $param $rawValue OK\r\n';
}
