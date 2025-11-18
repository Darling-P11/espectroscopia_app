import 'dart:async';
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class OnlineSpectroScreen extends StatefulWidget {
  const OnlineSpectroScreen({super.key});

  @override
  State<OnlineSpectroScreen> createState() => _OnlineSpectroScreenState();
}

class _OnlineSpectroScreenState extends State<OnlineSpectroScreen> {
  static const deviceId = 'esp32-as7265x-sd-01'; // IGUAL que en Arduino
  final DatabaseReference _ref = FirebaseDatabase.instance.ref(
    'readings/$deviceId',
  );

  final List<FlSpot> _o2Spots = <FlSpot>[];
  final List<FlSpot> _ndviSpots = <FlSpot>[];

  double? _oxygenPct;
  double? _ndvi;

  // Estadísticas O2
  double? _o2Min;
  double? _o2Max;
  double? _o2Avg;

  static const int maxPoints = 60;
  static const double minY = 18.0;
  static const double maxY = 23.0;

  StreamSubscription<DatabaseEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _ref.limitToLast(maxPoints).onChildAdded.listen(_onNewNode);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onNewNode(DatabaseEvent event) {
    final dataNode = event.snapshot.child('data').value;
    if (dataNode is! Map) return;

    final o2ai = double.tryParse(dataNode['O2_AI']?.toString() ?? '') ?? 0.0;
    final oxygenPct = 20.9 + (o2ai * 2.0);

    double ndvi;
    if (dataNode['NDVI'] != null) {
      ndvi = double.tryParse(dataNode['NDVI'].toString()) ?? 0.0;
    } else {
      final nir =
          _asDouble(dataNode['V_810nm']) ??
          _asDouble(dataNode['W_860nm']) ??
          0.0;
      final red =
          _asDouble(dataNode['J_645nm']) ??
          _asDouble(dataNode['K_680nm']) ??
          0.0;
      final denom = nir + red;
      ndvi = (denom.abs() > 1e-9) ? (nir - red) / denom : 0.0;
    }

    final ndviVisualY =
        minY + (ndvi.clamp(-1.0, 1.0) + 1.0) * ((maxY - minY) / 2.0);

    setState(() {
      _oxygenPct = oxygenPct;
      _ndvi = ndvi;

      final nextX = _o2Spots.isEmpty ? 0.0 : _o2Spots.last.x + 1.0;
      _o2Spots.add(FlSpot(nextX, oxygenPct));
      _ndviSpots.add(FlSpot(nextX, ndviVisualY));

      if (_o2Spots.length > maxPoints) _o2Spots.removeAt(0);
      if (_ndviSpots.length > maxPoints) _ndviSpots.removeAt(0);

      for (int i = 0; i < _o2Spots.length; i++) {
        _o2Spots[i] = FlSpot(i.toDouble(), _o2Spots[i].y);
        _ndviSpots[i] = FlSpot(i.toDouble(), _ndviSpots[i].y);
      }

      _recalculateStats();
    });
  }

  double? _asDouble(dynamic v) =>
      v == null ? null : double.tryParse(v.toString());

  void _recalculateStats() {
    if (_o2Spots.isEmpty) {
      _o2Min = _o2Max = _o2Avg = null;
      return;
    }
    final ys = _o2Spots.map((s) => s.y).toList();
    _o2Min = ys.reduce(min);
    _o2Max = ys.reduce(max);
    _o2Avg = ys.reduce((a, b) => a + b) / ys.length;
  }

  Future<void> _confirmAndReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resetear valores'),
        content: const Text(
          'Se eliminarán todos los registros en:\n'
          '/readings/esp8266-as7265x-01.\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              foregroundColor: Colors.red.shade800,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _ref.remove();
      setState(() {
        _o2Spots.clear();
        _ndviSpots.clear();
        _oxygenPct = null;
        _ndvi = null;
        _o2Min = _o2Max = _o2Avg = null;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos eliminados correctamente')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
      }
    }
  }

  // ---------- UI helpers ----------

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.wifi, color: Colors.orange, size: 28),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Datos en tiempo real',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Lecturas en vivo desde Firebase (ESP8266).',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required IconData icon,
    Color accent = Colors.orange,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, double? value) {
    return Chip(
      label: Text(
        value == null ? '$label: ---' : '$label: ${value.toStringAsFixed(2)} %',
        style: const TextStyle(fontSize: 12),
      ),
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(color: Colors.grey.shade300),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.black54)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final chartCard = Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 300,
            child: _o2Spots.isEmpty
                ? const Center(
                    child: Text(
                      'Esperando datos desde Firebase...',
                      style: TextStyle(color: Colors.black54),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minY: minY,
                      maxY: maxY,
                      backgroundColor: Colors.transparent,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 0.5,
                        getDrawingHorizontalLine: (_) =>
                            FlLine(color: Colors.black12, strokeWidth: 0.8),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 44,
                            getTitlesWidget: (v, __) => Text(
                              '${v.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      extraLinesData: ExtraLinesData(
                        horizontalLines: [
                          HorizontalLine(
                            y: 20.95,
                            color: Colors.redAccent,
                            strokeWidth: 1.2,
                            dashArray: [4, 4],
                            label: HorizontalLineLabel(
                              show: true,
                              alignment: Alignment.topRight,
                              labelResolver: (_) => '20.95% ref.',
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _o2Spots,
                          isCurved: true,
                          color: Colors.orange,
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [
                                Colors.orange.withOpacity(0.18),
                                Colors.transparent,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                        LineChartBarData(
                          spots: _ndviSpots,
                          isCurved: true,
                          color: Colors.teal,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: FlDotData(show: false),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(Colors.orange, 'Oxígeno (%)'),
              const SizedBox(width: 18),
              _legendDot(Colors.teal, 'NDVI (escala visual)'),
            ],
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            icon: const Icon(Icons.delete_forever),
            label: const Text('Resetear valores (Firebase)'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _o2Spots.isEmpty && _ndviSpots.isEmpty
                ? null
                : _confirmAndReset,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          children: [
            _header(),
            const SizedBox(height: 16),
            Row(
              children: [
                _kpiCard(
                  title: 'Nivel de oxígeno',
                  value: _oxygenPct == null
                      ? '---'
                      : '${_oxygenPct!.toStringAsFixed(2)} %',
                  icon: Icons.air,
                  accent: Colors.orange,
                ),
                const SizedBox(width: 12),
                _kpiCard(
                  title: 'NDVI',
                  value: _ndvi == null ? '---' : _ndvi!.toStringAsFixed(4),
                  icon: Icons.grass,
                  accent: Colors.teal,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _statChip('O₂ min', _o2Min),
                _statChip('O₂ max', _o2Max),
                _statChip('O₂ prom', _o2Avg),
              ],
            ),
            const SizedBox(height: 18),
            chartCard,
            const SizedBox(height: 18),
            Center(
              child: Text(
                _oxygenPct == null
                    ? 'Esperando datos...'
                    : '💨  Nivel de oxígeno: ${_oxygenPct!.toStringAsFixed(2)} %',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
