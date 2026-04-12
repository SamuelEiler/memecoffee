import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../device_model.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<DeviceModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('MeCoffee'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              Icons.circle,
              size: 12,
              color: model.connected ? Colors.greenAccent : Colors.redAccent,
            ),
          ),
        ],
      ),
      body: model.connected
          ? _Dashboard(model: model)
          : const _Scanning(),
    );
  }
}

// ---------------------------------------------------------------------------
// Scanning / disconnected state
// ---------------------------------------------------------------------------

class _Scanning extends StatelessWidget {
  const _Scanning();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text('Scanning for MeCoffee…', style: TextStyle(fontSize: 16)),
          SizedBox(height: 8),
          Text(
            'Make sure the machine is on.',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main dashboard — shown when connected
// ---------------------------------------------------------------------------

class _Dashboard extends StatelessWidget {
  final DeviceModel model;

  const _Dashboard({required this.model});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TemperatureCard(model: model),
          const SizedBox(height: 16),
          _TempChartCard(model: model),
          const SizedBox(height: 16),
          _PidCard(model: model),
          const SizedBox(height: 16),
          _ParamsCard(model: model),
          const SizedBox(height: 16),
          if (model.shot.active || model.shot.durationMs > 0)
            _ShotCard(model: model),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Temperature card — big numbers
// ---------------------------------------------------------------------------

class _TemperatureCard extends StatelessWidget {
  final DeviceModel model;

  const _TemperatureCard({required this.model});

  @override
  Widget build(BuildContext context) {
    final diff = model.temperature - model.setpoint;
    final diffColor = diff.abs() < 1.0
        ? Colors.greenAccent
        : diff > 0
            ? Colors.orangeAccent
            : Colors.blueAccent;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Boiler', style: TextStyle(color: Colors.white54)),
                Text(
                  '${model.temperature.toStringAsFixed(1)} °C',
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Setpoint', style: TextStyle(color: Colors.white54)),
                Text(
                  '${model.setpoint.toStringAsFixed(1)} °C',
                  style: const TextStyle(fontSize: 28),
                ),
                Text(
                  '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}',
                  style: TextStyle(fontSize: 14, color: diffColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Temperature chart
// ---------------------------------------------------------------------------

class _TempChartCard extends StatelessWidget {
  final DeviceModel model;

  const _TempChartCard({required this.model});

  @override
  Widget build(BuildContext context) {
    final s1 = model.historySensor1;
    final sp = model.historySetpoint;

    // Build chart spots from history
    final sensorSpots = [
      for (var i = 0; i < s1.length; i++) FlSpot(i.toDouble(), s1[i]),
    ];
    final setpointSpots = [
      for (var i = 0; i < sp.length; i++) FlSpot(i.toDouble(), sp[i]),
    ];

    final allVals = [...s1, ...sp];
    final minY = allVals.isEmpty ? 0.0 : allVals.reduce((a, b) => a < b ? a : b) - 3;
    final maxY = allVals.isEmpty ? 120.0 : allVals.reduce((a, b) => a > b ? a : b) + 3;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 12, bottom: 12),
              child: Text('Temperature', style: TextStyle(color: Colors.white54)),
            ),
            SizedBox(
              height: 180,
              child: s1.isEmpty
                  ? const Center(child: Text('Waiting for data…', style: TextStyle(color: Colors.white38)))
                  : LineChart(
                      LineChartData(
                        minY: minY,
                        maxY: maxY,
                        clipData: const FlClipData.all(),
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (v, _) => Text(
                                '${v.toInt()}°',
                                style: const TextStyle(fontSize: 10, color: Colors.white38),
                              ),
                            ),
                          ),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        lineBarsData: [
                          // Boiler temperature — cyan
                          LineChartBarData(
                            spots: sensorSpots,
                            isCurved: true,
                            color: Colors.cyanAccent,
                            barWidth: 2,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Colors.cyanAccent.withAlpha(20),
                            ),
                          ),
                          // Setpoint — dashed orange
                          LineChartBarData(
                            spots: setpointSpots,
                            isCurved: false,
                            color: Colors.orangeAccent.withAlpha(180),
                            barWidth: 1.5,
                            dashArray: [6, 4],
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _Legend(color: Colors.cyanAccent, label: 'Boiler'),
                const SizedBox(width: 16),
                _Legend(color: Colors.orangeAccent, label: 'Setpoint', dashed: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;

  const _Legend({required this.color, required this.label, this.dashed = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 16, height: 2, color: color),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// PID card — power bar + raw terms
// ---------------------------------------------------------------------------

class _PidCard extends StatelessWidget {
  final DeviceModel model;

  const _PidCard({required this.model});

  @override
  Widget build(BuildContext context) {
    final power = model.pid.power.clamp(0.0, 100.0);
    final barColor = power < 50
        ? Colors.greenAccent
        : power < 80
            ? Colors.orangeAccent
            : Colors.redAccent;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PID', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Power'),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: power / 100,
                      minHeight: 12,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(barColor),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text('${power.toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _PidTerm(label: 'P', value: model.pid.p),
                _PidTerm(label: 'I', value: model.pid.i),
                _PidTerm(label: 'D', value: model.pid.d),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PidTerm extends StatelessWidget {
  final String label;
  final int value;

  const _PidTerm({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        Text('$value', style: const TextStyle(fontFamily: 'monospace')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Parameters card
// ---------------------------------------------------------------------------

class _ParamsCard extends StatelessWidget {
  final DeviceModel model;

  const _ParamsCard({required this.model});

  static const _params = [
    ('tmpsp',  'Brew setpoint'),
    ('tmpstm', 'Steam setpoint'),
    ('pd1p',   'PID P'),
    ('pd1i',   'PID I'),
    ('pd1d',   'PID D'),
    ('tmron',  'Wake time'),
    ('tmroff', 'Sleep time'),
    ('tmrosd', 'Inactivity off'),
    ('shtmx',  'Max shot time'),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Device parameters', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 8),
            for (final (key, label) in _params)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white70)),
                    Text(
                      '${model.getParam(key) ?? '…'}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shot timer card
// ---------------------------------------------------------------------------

class _ShotCard extends StatelessWidget {
  final DeviceModel model;

  const _ShotCard({required this.model});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: model.shot.active
          ? Colors.orangeAccent.withAlpha(30)
          : Colors.greenAccent.withAlpha(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              model.shot.active ? Icons.coffee_maker : Icons.check_circle_outline,
              color: model.shot.active ? Colors.orangeAccent : Colors.greenAccent,
            ),
            const SizedBox(width: 12),
            Text(
              model.shot.active
                  ? 'Brewing…'
                  : 'Last shot: ${(model.shot.durationMs / 1000).toStringAsFixed(1)} s',
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}
