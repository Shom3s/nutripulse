import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

class HealthMonitorScreen extends StatefulWidget {
  const HealthMonitorScreen({super.key});

  @override
  State<HealthMonitorScreen> createState() => _HealthMonitorScreenState();
}

class _HealthMonitorScreenState extends State<HealthMonitorScreen>
    with SingleTickerProviderStateMixin {
  static final Guid serviceUuid =
      Guid('12345678-1234-1234-1234-1234567890ab');
  static final Guid characteristicUuid =
      Guid('abcd1234-5678-90ab-cdef-1234567890ab');

  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _notifySub;

  late AnimationController _pulseController;

  bool _isScanning = false;
  bool _isConnected = false;
  bool _isReading = false;

  int? bpm;
  double? temperature;
  int? ir;
  String status = 'Not connected';

  final List<double> _bpmHistory = [];
  final List<double> _tempHistory = [];
  final int _maxPoints = 40;

  double? _smoothBpm;
  double? _smoothTemp;

  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color card2 = Color(0xFF22281F);
  static const Color soft = Color(0xFFB7C2A8);
  static const Color text = Colors.white;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanSub?.cancel();
    _notifySub?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  Future<void> _startHealthScan() async {
    if (_isReading || _isScanning) return;

    setState(() {
      _isScanning = true;
      status = 'Scanning for NutriPulse ESP32...';
    });

    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    await FlutterBluePlus.stopScan();

    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      for (final r in results) {
        final name = r.device.platformName;

        if (name == 'NutriPulse-ESP32') {
          await FlutterBluePlus.stopScan();
          await _scanSub?.cancel();

          setState(() {
            _device = r.device;
            status = 'Connecting to ESP32...';
          });

          await _connectToDevice(r.device);
          break;
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    await Future.delayed(const Duration(seconds: 8));

    if (!_isConnected && mounted) {
      setState(() {
        _isScanning = false;
        status = 'ESP32 not found. Make sure it is powered on.';
      });
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));

      final services = await device.discoverServices();

      for (final service in services) {
        if (service.uuid == serviceUuid) {
          for (final c in service.characteristics) {
            if (c.uuid == characteristicUuid) {
              _characteristic = c;
              await c.setNotifyValue(true);

              _notifySub = c.lastValueStream.listen(_onDataReceived);

              setState(() {
                _isConnected = true;
                _isReading = true;
                _isScanning = false;
                status = 'Live health scan running';
              });

              return;
            }
          }
        }
      }

      setState(() {
        _isScanning = false;
        status = 'Health data service not found.';
      });
    } catch (_) {
      setState(() {
        _isScanning = false;
        _isConnected = false;
        status = 'Connection failed. Try again.';
      });
    }
  }

  void _onDataReceived(List<int> value) {
    try {
      final jsonString = utf8.decode(value);
      final data = jsonDecode(jsonString);

      final rawBpm = (data['bpm'] as num?)?.toDouble();
      final rawTemp = (data['temp'] as num?)?.toDouble();
      final rawIr = data['ir'] as int?;
      final fingerDetected = data['finger'] == true;

      if (!mounted) return;

      setState(() {
        ir = rawIr;

        if (fingerDetected && rawBpm != null && rawBpm > 35 && rawBpm < 180) {
          _smoothBpm = _smoothBpm == null
              ? rawBpm
              : (_smoothBpm! * 0.75) + (rawBpm * 0.25);

          bpm = _smoothBpm!.round();
          _addPoint(_bpmHistory, _smoothBpm!);
        }

        if (fingerDetected && rawTemp != null && rawTemp > 20 && rawTemp < 45) {
          _smoothTemp = _smoothTemp == null
              ? rawTemp
              : (_smoothTemp! * 0.80) + (rawTemp * 0.20);

          temperature = _smoothTemp;
          _addPoint(_tempHistory, _smoothTemp!);
        }

        status = fingerDetected ? 'Reading live data' : 'Place finger on sensor';
      });
    } catch (_) {}
  }

  void _addPoint(List<double> list, double value) {
    list.add(value);
    if (list.length > _maxPoints) {
      list.removeAt(0);
    }
  }

  Future<void> _stopScan() async {
    await _notifySub?.cancel();
    await _device?.disconnect();

    setState(() {
      _isConnected = false;
      _isReading = false;
      _isScanning = false;
      status = 'Disconnected';
      bpm = null;
      temperature = null;
      ir = null;
      _smoothBpm = null;
      _smoothTemp = null;
      _bpmHistory.clear();
      _tempHistory.clear();
    });
  }

  String get bpmText => bpm == null || bpm == 0 ? '--' : bpm.toString();

  String get tempText =>
      temperature == null ? '--' : '${temperature!.toStringAsFixed(1)} °C';

  String get healthStatus {
    if (bpm == null) return 'Waiting';
    if (bpm! < 60) return 'Low BPM';
    if (bpm! <= 100) return 'Normal';
    return 'High BPM';
  }

  double get avgBpm {
    if (_bpmHistory.isEmpty) return 0;
    return _bpmHistory.reduce((a, b) => a + b) / _bpmHistory.length;
  }

  double get minBpm {
    if (_bpmHistory.isEmpty) return 0;
    return _bpmHistory.reduce(math.min);
  }

  double get maxBpm {
    if (_bpmHistory.isEmpty) return 0;
    return _bpmHistory.reduce(math.max);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2A3A18),
              Color(0xFF0F140D),
              Color(0xFF070907),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              children: [
                _topBar(),
                const SizedBox(height: 18),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        _mainCard(),
                        const SizedBox(height: 18),
                        _liveGraphCard(),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: _smallCard(
                                title: 'Heart Rate',
                                value: '$bpmText BPM',
                                icon: Icons.favorite_rounded,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _smallCard(
                                title: 'Body Temp',
                                value: tempText,
                                icon: Icons.thermostat_rounded,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: _statsCard(
                                title: 'Average',
                                value: avgBpm == 0
                                    ? '--'
                                    : '${avgBpm.toStringAsFixed(0)} BPM',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _statsCard(
                                title: 'Min / Max',
                                value: minBpm == 0
                                    ? '--'
                                    : '${minBpm.toStringAsFixed(0)} / ${maxBpm.toStringAsFixed(0)}',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
                _bottomButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: text),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Health Monitor',
                style: GoogleFonts.outfit(
                  color: text,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: soft,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        _connectionChip(),
      ],
    );
  }

  Widget _connectionChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _isConnected
            ? lime.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _isConnected ? lime : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Text(
        _isConnected ? 'LIVE' : 'OFF',
        style: GoogleFonts.outfit(
          color: _isConnected ? lime : soft,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _mainCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: _box(glow: true),
      child: Column(
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.06).animate(
              CurvedAnimation(
                parent: _pulseController,
                curve: Curves.easeInOut,
              ),
            ),
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: lime.withValues(alpha: _isReading ? 0.18 : 0.08),
                boxShadow: [
                  BoxShadow(
                    color: lime.withValues(alpha: _isReading ? 0.30 : 0.08),
                    blurRadius: 40,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: const Icon(
                Icons.monitor_heart_rounded,
                color: lime,
                size: 62,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '$bpmText BPM',
            style: GoogleFonts.outfit(
              color: text,
              fontSize: 46,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            healthStatus,
            style: GoogleFonts.outfit(
              color: lime,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveGraphCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart_rounded, color: lime, size: 22),
              const SizedBox(width: 8),
              Text(
                'Live BPM Graph',
                style: GoogleFonts.outfit(
                  color: text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '${_bpmHistory.length}/$_maxPoints',
                style: GoogleFonts.outfit(
                  color: soft,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 185,
            width: double.infinity,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _bpmHistory.length < 2
                  ? Center(
                      child: Text(
                        'Start scan to view live graph',
                        style: GoogleFonts.outfit(
                          color: soft.withValues(alpha: 0.75),
                          fontSize: 13,
                        ),
                      ),
                    )
                  : CustomPaint(
                      painter: _LiveGraphPainter(
                        points: _bpmHistory,
                        lineColor: lime,
                        gridColor: Colors.white.withValues(alpha: 0.08),
                        fillColor: lime.withValues(alpha: 0.13),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: lime, size: 24),
          const SizedBox(height: 14),
          Text(
            title,
            style: GoogleFonts.outfit(color: soft, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: text,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsCard({
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(color: soft, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomButton() {
    return SizedBox(
      width: double.infinity,
      height: 62,
      child: ElevatedButton(
        onPressed: _isReading ? _stopScan : _startHealthScan,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isReading ? Colors.redAccent : lime,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        child: _isScanning
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.black,
                ),
              )
            : Text(
                _isReading ? 'Stop Health Scan' : 'Start Health Scan',
                style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
      ),
    );
  }

  BoxDecoration _box({bool glow = false}) {
    return BoxDecoration(
      color: glow ? card2 : card,
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
        if (glow)
          BoxShadow(
            color: lime.withValues(alpha: 0.12),
            blurRadius: 40,
            spreadRadius: 2,
          ),
      ],
    );
  }
}

class _LiveGraphPainter extends CustomPainter {
  final List<double> points;
  final Color lineColor;
  final Color gridColor;
  final Color fillColor;

  _LiveGraphPainter({
    required this.points,
    required this.lineColor,
    required this.gridColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (int i = 1; i <= 4; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final minValue = points.reduce(math.min) - 8;
    final maxValue = points.reduce(math.max) + 8;
    final range = math.max(maxValue - minValue, 1);

    final path = Path();
    final fillPath = Path();

    Offset pointAt(int index) {
      final x = index / (points.length - 1) * size.width;
      final y = size.height - ((points[index] - minValue) / range * size.height);
      return Offset(x, y);
    }

    final first = pointAt(0);
    path.moveTo(first.dx, first.dy);
    fillPath.moveTo(first.dx, size.height);
    fillPath.lineTo(first.dx, first.dy);

    for (int i = 1; i < points.length; i++) {
      final previous = pointAt(i - 1);
      final current = pointAt(i);
      final controlX = (previous.dx + current.dx) / 2;

      path.cubicTo(
        controlX,
        previous.dy,
        controlX,
        current.dy,
        current.dx,
        current.dy,
      );

      fillPath.cubicTo(
        controlX,
        previous.dy,
        controlX,
        current.dy,
        current.dx,
        current.dy,
      );
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    final last = pointAt(points.length - 1);

    canvas.drawCircle(
      last,
      7,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.fill,
    );

    canvas.drawCircle(
      last,
      7,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _LiveGraphPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}