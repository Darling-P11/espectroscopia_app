import 'dart:convert';
import 'dart:math';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class OfflineCsvSpectroScreen extends StatefulWidget {
  const OfflineCsvSpectroScreen({super.key});

  @override
  State<OfflineCsvSpectroScreen> createState() =>
      _OfflineCsvSpectroScreenState();
}

class _OfflineCsvSpectroScreenState extends State<OfflineCsvSpectroScreen> {
  final List<FlSpot> _o2Spots = [];
  final List<FlSpot> _ndviSpots = [];

  double? _oxygenLast;
  double? _ndviLast;

  // Estadísticas
  double? _o2Min;
  double? _o2Max;
  double? _o2Avg;

  String? _fileName;

  static const double minY = 18.0;
  static const double maxY = 23.0;

  Future<void> _pickCsvAndLoad() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) return;

      final csvString = utf8.decode(bytes);

      final rows = const CsvToListConverter(
        fieldDelimiter: ',',
        eol: '\n',
        shouldParseNumbers: false,
      ).convert(csvString);

      if (rows.length <= 1) {
        _showSnack('El archivo CSV no tiene datos.');
        return;
      }

      final List<FlSpot> o2 = [];
      final List<FlSpot> ndviSpots = [];

      for (int i = 1; i < rows.length; i++) {
        final rowDynamic = rows[i];
        if (rowDynamic.isEmpty) continue;

        final row = rowDynamic.map((e) => e.toString()).toList();
        if (row.length < 5) continue;

        final x = (i - 1).toDouble();

        final o2Ai = double.tryParse(row[1]) ?? 0.0;
        final oxygenPct = 20.9 + (o2Ai * 2.0);

        final nir = double.tryParse(row[4]) ?? 0.0;

        double red = 0.0;
        if (row.length > 14) {
          red = double.tryParse(row[14]) ?? 0.0;
        } else if (row.length > 13) {
          red = double.tryParse(row[13]) ?? 0.0;
        }

        final denom = nir + red;
        final ndvi = (denom.abs() > 1e-9) ? (nir - red) / denom : 0.0;

        final ndviVisualY =
            minY + (ndvi.clamp(-1.0, 1.0) + 1.0) * ((maxY - minY) / 2.0);

        o2.add(FlSpot(x, oxygenPct));
        ndviSpots.add(FlSpot(x, ndviVisualY));
      }

      if (o2.isEmpty) {
        _showSnack('No se pudieron leer datos válidos del CSV.');
        return;
      }

      setState(() {
        _fileName = file.name;
        _o2Spots
          ..clear()
          ..addAll(o2);
        _ndviSpots
          ..clear()
          ..addAll(ndviSpots);

        _oxygenLast = _o2Spots.last.y;

        final ndviVisualLast = _ndviSpots.last.y;
        _ndviLast = (((ndviVisualLast - minY) / ((maxY - minY) / 2.0)) - 1.0)
            .clamp(-1.0, 1.0);

        _recalculateStats();
      });

      _showSnack('Archivo "${file.name}" cargado correctamente.');
    } catch (e) {
      _showSnack('Error al leer el CSV: $e');
    }
  }

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

  void _clearData() {
    setState(() {
      _o2Spots.clear();
      _ndviSpots.clear();
      _oxygenLast = null;
      _ndviLast = null;
      _fileName = null;
      _o2Min = _o2Max = _o2Avg = null;
    });
    _showSnack('Datos limpiados. Selecciona un CSV para volver a visualizar.');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------- UI helpers -------

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
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.insert_drive_file,
              color: Colors.blue,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Datos en offline',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _fileName == null
                      ? 'Selecciona un archivo CSV con registros de espectro.'
                      : 'Archivo: $_fileName',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

  Widget _chartCard() {
    if (_o2Spots.isEmpty) {
      return Container(
        height: 260,
        alignment: Alignment.center,
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
        child: const Text(
          'Aún no hay datos.\nSelecciona un archivo CSV para visualizar el espectro.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    return Container(
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
            child: LineChart(
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
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: max(1, _o2Spots.length ~/ 6).toDouble(),
                      getTitlesWidget: (value, _) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(
                          color: Colors.black45,
                          fontSize: 10,
                        ),
                      ),
                    ),
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
          const SizedBox(height: 6),
          const Text(
            'Índice de muestra',
            style: TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Seleccionar CSV'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _pickCsvAndLoad,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_sweep),
                  label: const Text('Limpiar datos'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(
                      color: Colors.redAccent.shade200,
                      width: 1.2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _o2Spots.isEmpty && _ndviSpots.isEmpty
                      ? null
                      : _clearData,
                ),
              ),
            ],
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
                  value: _oxygenLast == null
                      ? '---'
                      : '${_oxygenLast!.toStringAsFixed(2)} %',
                  icon: Icons.air,
                  accent: Colors.orange,
                ),
                const SizedBox(width: 12),
                _kpiCard(
                  title: 'NDVI',
                  value: _ndviLast == null
                      ? '---'
                      : _ndviLast!.toStringAsFixed(4),
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
            _chartCard(),
            const SizedBox(height: 18),
            Center(
              child: Text(
                _oxygenLast == null
                    ? 'Selecciona un CSV para comenzar.'
                    : '💨  Nivel de oxígeno (último dato): '
                          '${_oxygenLast!.toStringAsFixed(2)} %',
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
