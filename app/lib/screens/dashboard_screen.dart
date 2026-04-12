import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

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
          _ShotCard(model: model),
          const SizedBox(height: 16),
          _TemperatureCard(model: model),
          const SizedBox(height: 16),
          _TempChartCard(model: model),
          const SizedBox(height: 16),
          _PidCard(model: model),
          const SizedBox(height: 16),
          _ParamsCard(model: model),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Temperature bottom sheet — step up/down with +/- buttons
// ---------------------------------------------------------------------------

void _showTempSheet(
  BuildContext context,
  DeviceModel model, {
  required String param,
  required String label,
  required double min,
  required double max,
}) {
  // Seed from the live model value; fall back to the param store
  final rawParam = model.getParam(param);
  final initial = rawParam is double
      ? rawParam
      : rawParam is int
          ? rawParam.toDouble()
          : model.setpoint;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TempSheet(
      model: model,
      param: param,
      label: label,
      initial: initial,
      min: min,
      max: max,
    ),
  );
}

class _TempSheet extends StatefulWidget {
  final DeviceModel model;
  final String param;
  final String label;
  final double initial;
  final double min;
  final double max;

  const _TempSheet({
    required this.model,
    required this.param,
    required this.label,
    required this.initial,
    required this.min,
    required this.max,
  });

  @override
  State<_TempSheet> createState() => _TempSheetState();
}

class _TempSheetState extends State<_TempSheet> {
  late double _value;

  @override
  void initState() {
    super.initState();
    // Round to nearest 0.5 so steps stay on clean values
    _value = (widget.initial * 2).round() / 2;
  }

  void _step(double delta) {
    setState(() {
      _value = (_value + delta).clamp(widget.min, widget.max);
      _value = (_value * 2).round() / 2; // keep on 0.5 grid
    });
  }

  void _set(BuildContext ctx) {
    widget.model.sendSet(widget.param, _value);
    Navigator.pop(ctx);
  }

  @override
  Widget build(BuildContext context) {
    final changed = (_value - widget.initial).abs() > 0.01;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Text(widget.label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 24),

          // Step row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepButton(label: '−1', onTap: () => _step(-1.0)),
              const SizedBox(width: 4),
              _StepButton(label: '−½', onTap: () => _step(-0.5)),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: Text(
                  '${_value.toStringAsFixed(1)} °C',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: changed ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _StepButton(label: '+½', onTap: () => _step(0.5)),
              const SizedBox(width: 4),
              _StepButton(label: '+1', onTap: () => _step(1.0)),
            ],
          ),

          const SizedBox(height: 8),
          Text(
            '${widget.min.toStringAsFixed(0)} – ${widget.max.toStringAsFixed(0)} °C',
            style: const TextStyle(fontSize: 12, color: Colors.white38),
          ),

          const SizedBox(height: 28),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: changed ? () => _set(context) : null,
                  child: const Text('Set'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _StepButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Center(
            child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Temperature card — big numbers, setpoint tappable
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
            // Setpoint — tappable to edit
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showTempSheet(
                context, model,
                param: 'tmpsp',
                label: 'Brew setpoint',
                min: 80,
                max: 105,
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Setpoint', style: TextStyle(color: Colors.white54)),
                        const SizedBox(width: 6),
                        const Icon(Icons.edit, size: 12, color: Colors.white38),
                      ],
                    ),
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
              ),
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
    ('tmpsp',  'Brew setpoint',   'temp', '°C'),
    ('tmpstm', 'Steam setpoint',  'temp', '°C'),
    ('pd1p',   'PID P',           'edit', ''),
    ('pd1i',   'PID I',           'edit', ''),
    ('pd1d',   'PID D',           'edit', ''),
    ('tmron',  'Wake time',       'none', ''),
    ('tmroff', 'Sleep time',      'none', ''),
    ('tmrosd', 'Inactivity off',  'none', ''),
    ('shtmx',  'Max shot time',   'none', ''),
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
            for (final (key, label, mode, unit) in _params)
              _ParamRow(
                model: model,
                paramKey: key,
                label: label,
                mode: mode,
                unit: unit,
              ),
          ],
        ),
      ),
    );
  }
}

class _ParamRow extends StatelessWidget {
  final DeviceModel model;
  final String paramKey;
  final String label;
  /// 'temp' → bottom sheet stepper, 'edit' → text dialog, 'none' → read-only
  final String mode;
  final String unit;

  const _ParamRow({
    required this.model,
    required this.paramKey,
    required this.label,
    required this.mode,
    required this.unit,
  });

  void _onTap(BuildContext context) {
    if (mode == 'temp') {
      final isSteam = paramKey == 'tmpstm';
      _showTempSheet(
        context, model,
        param: paramKey,
        label: label,
        min: isSteam ? 115 : 80,
        max: isSteam ? 150 : 105,
      );
    } else if (mode == 'edit') {
      _showEditDialog(context);
    }
  }

  void _showEditDialog(BuildContext context) {
    final current = model.getParam(paramKey);
    final controller = TextEditingController(
      text: current != null ? '$current' : '',
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
          ],
          decoration: InputDecoration(suffixText: unit.isNotEmpty ? unit : null),
          onSubmitted: (_) => _submit(ctx, controller.text),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => _submit(ctx, controller.text), child: const Text('Set')),
        ],
      ),
    );
  }

  void _submit(BuildContext context, String text) {
    final value = double.tryParse(text);
    if (value != null) model.sendSet(paramKey, value);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final rawValue = model.getParam(paramKey);
    final valueText = rawValue != null ? '$rawValue' : '…';
    final editable = mode != 'none';

    return InkWell(
      onTap: editable ? () => _onTap(context) : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  unit.isNotEmpty ? '$valueText $unit' : valueText,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (editable) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.edit, size: 14, color: Colors.white38),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shot timer card — always visible, counts up, alerts at target
// ---------------------------------------------------------------------------

class _ShotCard extends StatefulWidget {
  final DeviceModel model;

  const _ShotCard({required this.model});

  @override
  State<_ShotCard> createState() => _ShotCardState();
}

class _ShotCardState extends State<_ShotCard> {
  Timer? _ticker;
  double _elapsed = 0;
  bool _alerted = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), _tick);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick(Timer _) {
    final model = widget.model;
    if (model.shot.active && model.shotStartTime != null) {
      final secs = DateTime.now().difference(model.shotStartTime!).inMilliseconds / 1000.0;
      setState(() => _elapsed = secs);

      if (!_alerted && secs >= model.shotTargetSeconds) {
        _alerted = true;
        _vibrateAlert();
      }
    } else {
      if (_alerted) _alerted = false;
    }
  }

  Future<void> _vibrateAlert() async {
    final hasVibrator = await Vibration.hasVibrator() ?? false;
    if (hasVibrator) {
      // Two strong pulses: 400 ms on, 150 ms off, 400 ms on — max amplitude
      Vibration.vibrate(pattern: [0, 400, 150, 400], intensities: [0, 255, 0, 255]);
    } else {
      // Fallback for devices without vibrator (e.g. some tablets)
      for (int i = 0; i < 3; i++) {
        await HapticFeedback.heavyImpact();
        if (i < 2) await Future.delayed(const Duration(milliseconds: 150));
      }
    }
  }

  void _editTarget(BuildContext context) {
    final controller = TextEditingController(
      text: '${widget.model.shotTargetSeconds}',
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Target shot time'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: 's'),
          onSubmitted: (_) => _submitTarget(ctx, controller.text),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => _submitTarget(ctx, controller.text), child: const Text('Set')),
        ],
      ),
    );
  }

  void _submitTarget(BuildContext context, String text) {
    final v = int.tryParse(text);
    if (v != null && v > 0) {
      setState(() => widget.model.shotTargetSeconds = v);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final target = model.shotTargetSeconds.toDouble();
    final active = model.shot.active;
    final lastSecs = model.shot.durationMs / 1000.0;

    final displaySecs = active ? _elapsed : lastSecs;
    final progress = target > 0 ? (displaySecs / target).clamp(0.0, 1.0) : 0.0;
    final overTarget = active && _elapsed >= target;

    final Color barColor;
    if (overTarget) {
      barColor = Colors.redAccent;
    } else if (active) {
      barColor = Colors.orangeAccent;
    } else {
      barColor = Colors.white24;
    }

    return Card(
      color: overTarget ? Colors.redAccent.withAlpha(25) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Shot timer', style: TextStyle(color: Colors.white54)),
                InkWell(
                  onTap: () => _editTarget(context),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Target: ${model.shotTargetSeconds} s',
                          style: const TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit, size: 12, color: Colors.white38),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Timer display + status
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  active || lastSecs > 0
                      ? displaySecs.toStringAsFixed(1)
                      : '—',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: overTarget ? Colors.redAccent : null,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    active ? 'brewing…' : (lastSecs > 0 ? 'last shot' : 'ready'),
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Progress bar toward target
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('0 s', style: TextStyle(fontSize: 10, color: Colors.white38)),
                Text('${model.shotTargetSeconds} s', style: const TextStyle(fontSize: 10, color: Colors.white38)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
