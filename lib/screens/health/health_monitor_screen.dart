import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/health_scan_result.dart';
import '../../services/health_scan_service.dart';

final ValueNotifier<int> healthTitleReplayTrigger = ValueNotifier<int>(0);

enum _HealthScanState { idle, scanning, connecting, reading, failed }

class _PdfLine {
  const _PdfLine(
    this.text, {
    this.fontSize = 11,
    this.bold = false,
    this.gapAfter = 0,
  });

  final String text;
  final double fontSize;
  final bool bold;
  final double gapAfter;
}

class HealthMonitorScreen extends StatefulWidget {
  const HealthMonitorScreen({super.key});

  @override
  State<HealthMonitorScreen> createState() => _HealthMonitorScreenState();
}

class _HealthMonitorScreenState extends State<HealthMonitorScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static final Guid serviceUuid = Guid('12345678-1234-1234-1234-1234567890ab');
  static final Guid characteristicUuid = Guid(
    'abcd1234-5678-90ab-cdef-1234567890ab',
  );

  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _notifySub;
  Timer? _scanTimer;

  late final AnimationController _pulseController;
  late final Stream<List<HealthScanResult>> _recentScansStream;

  _HealthScanState _scanState = _HealthScanState.idle;

  int? bpm;
  double? temperature;
  int? ir;
  bool _fingerDetected = false;
  bool _isSaving = false;
  bool _savedCurrentSession = false;

  String status = 'Ready to scan';
  DateTime? _scanStartedAt;
  int _durationSeconds = 0;

  DateTime _selectedDate = DateTime.now();

  final List<double> _bpmHistory = <double>[];
  final List<double> _tempHistory = <double>[];
  final int _maxPoints = 36;

  double? _smoothBpm;
  double? _smoothTemp;

  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color card2 = Color(0xFF20271A);
  static const Color soft = Color(0xFFB7C2A8);
  static const Color text = Colors.white;

  @override
  bool get wantKeepAlive => true;

  bool get _isScanning => _scanState == _HealthScanState.scanning;
  bool get _isConnecting => _scanState == _HealthScanState.connecting;
  bool get _isReading => _scanState == _HealthScanState.reading;

  @override
  void initState() {
    super.initState();
    _recentScansStream = HealthScanService.recentScansStream(limit: 12);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanTimer?.cancel();
    _scanSub?.cancel();
    _notifySub?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  Future<void> _startHealthScan() async {
    if (_isReading || _isScanning || _isConnecting) return;

    _resetCurrentReading(clearStatus: false);

    setState(() {
      _scanState = _HealthScanState.scanning;
      status = 'Scanning for NutriPulse ESP32...';
      _savedCurrentSession = false;
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

          if (!mounted) return;

          setState(() {
            _device = r.device;
            _scanState = _HealthScanState.connecting;
            status = 'Connecting to ESP32...';
          });

          await _connectToDevice(r.device);
          break;
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    await Future.delayed(const Duration(seconds: 8));

    if (!_isReading && mounted && _scanState == _HealthScanState.scanning) {
      setState(() {
        _scanState = _HealthScanState.failed;
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
              _startScanTimer();

              if (!mounted) return;

              setState(() {
                _scanState = _HealthScanState.reading;
                status = 'Place finger on sensor';
              });

              return;
            }
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _scanState = _HealthScanState.failed;
        status = 'Health data service not found.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _scanState = _HealthScanState.failed;
        status = 'Connection failed. Try again.';
      });
    }
  }

  void _startScanTimer() {
    _scanStartedAt = DateTime.now();
    _durationSeconds = 0;

    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _scanStartedAt == null) return;
      setState(() {
        _durationSeconds = DateTime.now().difference(_scanStartedAt!).inSeconds;
      });
    });
  }

  void _onDataReceived(List<int> value) {
    try {
      final jsonString = utf8.decode(value);
      final data = jsonDecode(jsonString);

      final rawBpm = (data['bpm'] as num?)?.toDouble();
      final rawTemp = (data['temp'] as num?)?.toDouble();
      final rawIr = data['ir'] as int?;
      final fingerDetected = data['finger'] == true;

      final now = DateTime.now();

      // 4 updates/sec max. This avoids jank on budget devices.
      if (now.difference(_lastUiUpdate).inMilliseconds < 250) return;
      _lastUiUpdate = now;

      if (!mounted) return;

      setState(() {
        ir = rawIr;
        _fingerDetected = fingerDetected;

        if (fingerDetected && rawBpm != null && rawBpm > 35 && rawBpm < 180) {
          _smoothBpm = _smoothBpm == null
              ? rawBpm
              : (_smoothBpm! * 0.78) + (rawBpm * 0.22);

          bpm = _smoothBpm!.round();
          _addPoint(_bpmHistory, _smoothBpm!);
        }

        if (fingerDetected && rawTemp != null && rawTemp > 20 && rawTemp < 45) {
          _smoothTemp = _smoothTemp == null
              ? rawTemp
              : (_smoothTemp! * 0.84) + (rawTemp * 0.16);

          temperature = _smoothTemp;
          _addPoint(_tempHistory, _smoothTemp!);
        }

        status = fingerDetected
            ? 'Reading live data'
            : 'Place finger on sensor';
      });
    } catch (_) {}
  }

  void _addPoint(List<double> list, double value) {
    list.add(value);
    if (list.length > _maxPoints) list.removeAt(0);
  }

  Future<void> _stopScan() async {
    await _notifySub?.cancel();
    await _device?.disconnect();

    _scanTimer?.cancel();

    if (!mounted) return;

    setState(() {
      _device = null;
      _characteristic = null;
      _scanState = _HealthScanState.idle;
      status = 'Disconnected';
      _fingerDetected = false;
      _scanStartedAt = null;
      _durationSeconds = 0;
    });
  }

  void _resetCurrentReading({required bool clearStatus}) {
    _scanTimer?.cancel();
    bpm = null;
    temperature = null;
    ir = null;
    _smoothBpm = null;
    _smoothTemp = null;
    _fingerDetected = false;
    _durationSeconds = 0;
    _scanStartedAt = null;
    _bpmHistory.clear();
    _tempHistory.clear();
    if (clearStatus) status = 'Ready to scan';
  }

  Future<void> _saveResult() async {
    if (_isSaving || !_canSave) return;

    setState(() => _isSaving = true);

    try {
      await HealthScanService.saveScan(
        bpm: bpm!,
        avgBpm: avgBpm,
        minBpm: minBpm,
        maxBpm: maxBpm,
        temperature: temperature ?? 0,
        status: overallStatus,
        recommendation: recommendation,
        durationSeconds: math.max(_durationSeconds, 1),
      );

      if (!mounted) return;

      setState(() {
        _savedCurrentSession = true;
        _selectedDate = DateTime.now();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Health scan saved',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
          ),
          backgroundColor: card2,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save result: $e',
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String get bpmText => bpm == null || bpm == 0 ? '--' : bpm.toString();

  String get overallStatus {
    return HealthScanService.healthStatus(bpm: bpm, temperature: temperature);
  }

  String get recommendation {
    return HealthScanService.recommendation(bpm: bpm, temperature: temperature);
  }

  bool get _canSave =>
      bpm != null && temperature != null && _bpmHistory.length >= 4;

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

  Color get _statusColor {
    switch (overallStatus) {
      case 'Normal':
        return lime;
      case 'Monitor':
        return Colors.amberAccent;
      case 'Warning':
        return Colors.redAccent;
      default:
        return soft;
    }
  }

  String get _scanTimerText {
    final minutes = (_durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  List<DateTime> get _weekDates {
    final today = DateTime.now();
    return List.generate(7, (index) {
      return DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(Duration(days: 6 - index));
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return StreamBuilder<List<HealthScanResult>>(
      stream: _recentScansStream,
      builder: (context, snapshot) {
        final recentScans = snapshot.data ?? const <HealthScanResult>[];
        final selectedKey = HealthScanService.dateKey(_selectedDate);
        final selectedScans = recentScans
            .where((s) => s.dateKey == selectedKey)
            .toList();

        return Stack(
          children: [
            CustomScrollView(
              key: const PageStorageKey<String>('health-monitor-scroll'),
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              cacheExtent: 1000,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 112,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate.fixed([
                      _topHeader(),
                      const SizedBox(height: 22),
                      RepaintBoundary(child: _dashboardHero()),
                      const SizedBox(height: 14),
                      RepaintBoundary(child: _quickMetricsRow()),
                      const SizedBox(height: 14),
                      _scanActionCard(),
                      const SizedBox(height: 14),
                      if (_isReading || _bpmHistory.isNotEmpty) ...[
                        RepaintBoundary(child: _liveScanPanel()),
                        const SizedBox(height: 14),
                      ],
                      RepaintBoundary(
                        child: _weeklyHealthTrendCard(recentScans),
                      ),
                      const SizedBox(height: 14),
                      RepaintBoundary(child: _healthReportCard(recentScans)),
                      const SizedBox(height: 14),
                      _calendarStrip(),
                      const SizedBox(height: 12),
                      _selectedDateSection(selectedScans),
                      const SizedBox(height: 14),
                      _recentHeader(),
                      const SizedBox(height: 10),
                      _recentScansList(recentScans),
                    ]),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _topHeader() {
    return ValueListenableBuilder<int>(
      valueListenable: healthTitleReplayTrigger,
      builder: (context, replaySeed, _) {
        return TweenAnimationBuilder<double>(
          key: ValueKey<String>('health-title-replay-$replaySeed'),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Transform.translate(
            offset: Offset(0, 18 * (1 - t)),
            child: Opacity(opacity: t, child: child),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Health',
                      style: GoogleFonts.outfit(
                        color: text,
                        fontSize: 36,
                        height: 0.95,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Connect ESP32 and monitor BPM, SpO₂, and temperature',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.76),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: (_isScanning || _isConnecting)
                    ? null
                    : _isReading
                    ? _stopScan
                    : _startHealthScan,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _isReading ? Colors.redAccent : lime,
                    borderRadius: BorderRadius.circular(19),
                    boxShadow: const [],
                  ),
                  child: (_isScanning || _isConnecting)
                      ? const Padding(
                          padding: EdgeInsets.all(15),
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2.4,
                          ),
                        )
                      : Icon(
                          _isReading
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.black,
                          size: 28,
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _connectionChip() {
    final active = _isReading;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? lime.withOpacity(0.16) : Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? lime : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.sensors_rounded : Icons.sensors_off_rounded,
            color: active ? lime : soft,
            size: 14,
          ),
          const SizedBox(width: 5),
          Text(
            active ? 'LIVE' : 'OFF',
            style: GoogleFonts.outfit(
              color: active ? lime : soft,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _box(glow: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final scale = _isReading
                      ? 0.98 + (_pulseController.value * 0.05)
                      : 1.0;
                  return Transform.scale(scale: scale, child: child);
                },
                child: Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: lime.withOpacity(_isReading ? 0.17 : 0.10),
                  ),
                  child: const Icon(
                    Icons.monitor_heart_rounded,
                    color: lime,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Smart Health Scan',
                      style: GoogleFonts.outfit(
                        color: text,
                        fontSize: 22,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: soft,
                        fontSize: 12.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _heroMetric(
                  title: 'Current BPM',
                  value: bpmText,
                  suffix: 'BPM',
                  color: _statusColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _heroMetric(
                  title: 'Temperature',
                  value: temperature == null
                      ? '--'
                      : temperature!.toStringAsFixed(1),
                  suffix: '°C',
                  color: _statusColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroMetric({
    required String title,
    required String value,
    required String suffix,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.040)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: GoogleFonts.outfit(
                      color: text,
                      fontSize: 30,
                      height: 0.92,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  suffix,
                  style: GoogleFonts.outfit(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickMetricsRow() {
    return Row(
      children: [
        Expanded(
          child: _smallMetricCard(
            icon: Icons.timer_rounded,
            title: 'Timer',
            value: _scanTimerText,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _smallMetricCard(
            icon: Icons.health_and_safety_rounded,
            title: 'Status',
            value: overallStatus,
            valueColor: _statusColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _smallMetricCard(
            icon: Icons.fingerprint_rounded,
            title: 'Finger',
            value: _fingerDetected ? 'Detected' : 'Waiting',
          ),
        ),
      ],
    );
  }

  Widget _smallMetricCard({
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      height: 98,
      padding: const EdgeInsets.all(12),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: lime, size: 20),
          const Spacer(),
          Text(
            title,
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 10.7,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: GoogleFonts.outfit(
                color: valueColor ?? text,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveScanPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart_rounded, color: lime, size: 22),
              const SizedBox(width: 8),
              Text(
                'Live Scan',
                style: GoogleFonts.outfit(
                  color: text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '${_bpmHistory.length}/$_maxPoints',
                style: GoogleFonts.outfit(
                  color: soft,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 158,
            width: double.infinity,
            child: _bpmHistory.length < 2
                ? Center(
                    child: Text(
                      'Place finger on sensor to view graph',
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.75),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : CustomPaint(
                    painter: _LiveGraphPainter(
                      points: List<double>.unmodifiable(_bpmHistory),
                      lineColor: lime,
                      gridColor: Colors.white.withOpacity(0.06),
                      fillColor: lime.withOpacity(0.10),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  'Average',
                  avgBpm == 0 ? '--' : '${avgBpm.toStringAsFixed(0)} BPM',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniStat(
                  'Min / Max',
                  minBpm == 0
                      ? '--'
                      : '${minBpm.toStringAsFixed(0)} / ${maxBpm.toStringAsFixed(0)}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            child: Text(
              value,
              style: GoogleFonts.outfit(
                color: text,
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _insightCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              overallStatus == 'Warning'
                  ? Icons.warning_amber_rounded
                  : Icons.health_and_safety_rounded,
              color: _statusColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  overallStatus == 'Waiting'
                      ? 'Health Insight'
                      : '$overallStatus Reading',
                  style: GoogleFonts.outfit(
                    color: text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  recommendation,
                  style: GoogleFonts.outfit(
                    color: soft,
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _healthScoreFor({
    required int? scoreBpm,
    required double? scoreTemp,
    required String scoreStatus,
    required int durationSeconds,
    required bool hasFinger,
  }) {
    if (scoreBpm == null && scoreTemp == null) return 0;

    var score = 100;

    if (scoreStatus == 'Warning') score -= 18;
    if (scoreStatus == 'Monitor') score -= 10;

    if (scoreBpm != null) {
      if (scoreBpm > 115) {
        score -= 22;
      } else if (scoreBpm > 100) {
        score -= 14;
      } else if (scoreBpm < 50) {
        score -= 18;
      } else if (scoreBpm < 60) {
        score -= 10;
      }
    }

    if (scoreTemp != null) {
      if (scoreTemp >= 38.0) {
        score -= 24;
      } else if (scoreTemp >= 37.6) {
        score -= 16;
      } else if (scoreTemp < 35.0) {
        score -= 18;
      } else if (scoreTemp < 35.5) {
        score -= 10;
      }
    }

    if (_isReading && !hasFinger) score -= 8;
    if (durationSeconds > 0 && durationSeconds < 8) score -= 4;

    return score.clamp(0, 100);
  }

  HealthScanResult? _latestSavedScan(List<HealthScanResult> scans) {
    if (scans.isEmpty) return null;
    final sorted = [...scans]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.first;
  }

  int? _effectiveBpm(List<HealthScanResult> scans) {
    if (bpm != null && bpm! > 0) return bpm;
    return _latestSavedScan(scans)?.bpm;
  }

  double? _effectiveTemperature(List<HealthScanResult> scans) {
    if (temperature != null && temperature! > 0) return temperature;
    final latest = _latestSavedScan(scans);
    if (latest == null || latest.temperature <= 0) return null;
    return latest.temperature;
  }

  String _effectiveStatus(List<HealthScanResult> scans) {
    if (bpm != null || temperature != null) return overallStatus;
    return _latestSavedScan(scans)?.status ?? 'Waiting';
  }

  int _effectiveScore(List<HealthScanResult> scans) {
    final effectiveBpm = _effectiveBpm(scans);
    final effectiveTemp = _effectiveTemperature(scans);
    return _healthScoreFor(
      scoreBpm: effectiveBpm,
      scoreTemp: effectiveTemp,
      scoreStatus: _effectiveStatus(scans),
      durationSeconds: _durationSeconds,
      hasFinger: _fingerDetected,
    );
  }

  String _scoreLabel(int score) {
    if (score == 0) return 'Scan needed';
    if (score >= 86) return 'Excellent';
    if (score >= 72) return 'Good';
    if (score >= 55) return 'Monitor';
    return 'Attention';
  }

  String _readinessLabel(int score) {
    if (score == 0) return 'Waiting';
    if (score >= 84) return 'High';
    if (score >= 65) return 'Moderate';
    return 'Low';
  }

  String _readinessMessage(int score) {
    if (score == 0) return 'Complete a scan to calculate readiness.';
    if (score >= 84) return 'Your body looks ready for normal activity today.';
    if (score >= 65) return 'Keep activity light and monitor how you feel.';
    return 'Rest first and repeat the scan before heavy activity.';
  }

  String _aiInsightText(List<HealthScanResult> scans) {
    final effectiveBpm = _effectiveBpm(scans);
    final effectiveTemp = _effectiveTemperature(scans);
    final effectiveStatus = _effectiveStatus(scans);

    if (effectiveBpm == null && effectiveTemp == null) {
      return 'Start a scan to receive a personalised health insight.';
    }

    if (effectiveStatus == 'Warning') {
      return 'Your reading needs attention. Sit still, hydrate, and repeat the scan after a short rest.';
    }

    if (effectiveStatus == 'Monitor') {
      return 'Your reading is slightly outside the comfortable range. Monitor symptoms and scan again later.';
    }

    return 'Your latest heart rate and temperature look stable. Stay hydrated and continue healthy activity.';
  }

  double get _signalQualityValue {
    if (!_isReading && !_fingerDetected && ir == null) return 0.0;
    if (!_fingerDetected) return 0.22;
    final rawIr = ir ?? 0;
    if (rawIr >= 70000) return 0.96;
    if (rawIr >= 35000) return 0.74;
    if (rawIr >= 12000) return 0.50;
    return 0.34;
  }

  String get _signalQualityLabel {
    if (!_isReading && !_fingerDetected && ir == null) return 'Idle';
    if (!_fingerDetected) return 'Place finger';
    final quality = _signalQualityValue;
    if (quality >= 0.85) return 'Excellent';
    if (quality >= 0.65) return 'Good';
    if (quality >= 0.45) return 'Fair';
    return 'Weak';
  }

  Color get _signalQualityColor {
    final quality = _signalQualityValue;
    if (quality >= 0.65) return lime;
    if (quality >= 0.40) return Colors.amberAccent;
    return Colors.redAccent;
  }

  Widget _healthAlertBanner() {
    final warning = overallStatus == 'Warning';
    final color = warning ? Colors.redAccent : Colors.amberAccent;
    final title = warning ? 'Warning Reading' : 'Monitor Reading';
    final message = warning
        ? 'Rest for 5 minutes and repeat the scan. Seek help if you feel unwell.'
        : 'Slightly outside normal range. Re-scan later for confirmation.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(Icons.warning_amber_rounded, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: text,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.82),
                    fontSize: 11.7,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _healthIntelligenceCard(List<HealthScanResult> scans) {
    final score = _effectiveScore(scans);
    final progress = score == 0 ? 0.0 : score / 100.0;
    final label = _scoreLabel(score);
    final readiness = _readinessLabel(score);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: _box(glow: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 86,
                height: 86,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 9,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.white.withOpacity(0.08),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          score >= 72
                              ? lime
                              : score >= 55
                              ? Colors.amberAccent
                              : Colors.redAccent,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          score == 0 ? '--' : '$score',
                          style: GoogleFonts.outfit(
                            color: text,
                            fontSize: 25,
                            height: 0.95,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'score',
                          style: GoogleFonts.outfit(
                            color: soft,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Health Score',
                      style: GoogleFonts.outfit(
                        color: text,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.45,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      label,
                      style: GoogleFonts.outfit(
                        color: score >= 72
                            ? lime
                            : score >= 55
                            ? Colors.amberAccent
                            : Colors.redAccent,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _aiInsightText(scans),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.82),
                        fontSize: 12.2,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: _premiumMiniInsight(
                  icon: Icons.bolt_rounded,
                  title: 'Readiness',
                  value: readiness,
                  subtitle: _readinessMessage(score),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _premiumMiniInsight(
                  icon: Icons.psychology_rounded,
                  title: 'AI Insight',
                  value: _effectiveStatus(scans),
                  subtitle: recommendation,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _premiumMiniInsight({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 116),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.045)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: lime, size: 18),
          const SizedBox(height: 9),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 10.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: text,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: soft.withOpacity(0.68),
              fontSize: 10.4,
              height: 1.15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _signalQualityCard() {
    final quality = _signalQualityValue;
    final color = _signalQualityColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.13),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.sensors_rounded, color: color, size: 26),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Signal Quality',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: text,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      _signalQualityLabel,
                      style: GoogleFonts.outfit(
                        color: color,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: quality,
                    minHeight: 7,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _fingerDetected
                      ? 'Finger detected • ${ir == null ? 'calibrating signal' : 'IR signal $ir'}'
                      : 'Place finger fully on the ESP32 sensor for best accuracy.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.72),
                    fontSize: 11.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weeklyHealthTrendCard(List<HealthScanResult> scans) {
    final sorted = [...scans]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final points = sorted.length > 7
        ? sorted.sublist(sorted.length - 7)
        : sorted;
    final hasTrend = points.length >= 2;
    final avgBpmValue = points.isEmpty
        ? 0
        : points.fold<double>(0, (sum, scan) => sum + scan.avgBpm) /
              points.length;
    final avgTempValue = points.isEmpty
        ? 0
        : points.fold<double>(0, (sum, scan) => sum + scan.temperature) /
              points.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, color: lime, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Weekly Health Trend',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${points.length}/7 scans',
                style: GoogleFonts.outfit(
                  color: soft,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          SizedBox(
            height: 138,
            width: double.infinity,
            child: hasTrend
                ? CustomPaint(
                    painter: _WeeklyHealthTrendPainter(
                      scans: points,
                      bpmColor: lime,
                      tempColor: Colors.amberAccent,
                      gridColor: Colors.white.withOpacity(0.055),
                    ),
                  )
                : Center(
                    child: Text(
                      'Save at least 2 scans to unlock trend analysis.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.78),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _trendMetricTile(
                  color: lime,
                  label: 'Avg BPM',
                  value: points.isEmpty ? '--' : avgBpmValue.toStringAsFixed(0),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _trendMetricTile(
                  color: Colors.amberAccent,
                  label: 'Avg Temp',
                  value: points.isEmpty
                      ? '--'
                      : '${avgTempValue.toStringAsFixed(1)}°C',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trendMetricTile({
    required Color color,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: soft,
                fontSize: 11.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: text,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _healthReportCard(List<HealthScanResult> scans) {
    return GestureDetector(
      onTap: () => _generateHealthReportPdf(scans),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: lime.withOpacity(0.10),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: lime.withOpacity(0.17)),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: lime,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.description_rounded,
                color: Colors.black,
                size: 25,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Health Report',
                    style: GoogleFonts.outfit(
                      color: text,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Create advanced PDF with charts and bars',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: soft.withOpacity(0.76),
                      fontSize: 11.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.picture_as_pdf_rounded,
                color: lime,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateHealthReportPdf(List<HealthScanResult> scans) async {
    final latest = _latestSavedScan(scans);
    final effectiveBpm = _effectiveBpm(scans);
    final effectiveTemp = _effectiveTemperature(scans);
    final score = _effectiveScore(scans);
    final effectiveStatus = _effectiveStatus(scans);
    final now = DateTime.now();
    final duration = math.max(_durationSeconds, latest?.durationSeconds ?? 0);

    try {
      final bytes = _buildAdvancedHealthReportPdf(
        scans: scans,
        generatedAt: now,
        bpmValue: effectiveBpm,
        temperatureValue: effectiveTemp,
        score: score,
        statusValue: effectiveStatus,
        durationSeconds: duration,
      );
      final directory = await getApplicationDocumentsDirectory();
      final filename =
          'nutripulse_health_report_${HealthScanService.dateKey(now)}_${now.millisecondsSinceEpoch}.pdf';
      final file = File('${directory.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      _showPdfCreatedSheet(file.path, filename: filename);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not create PDF: $e',
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<String> _formalAdviceLines({
    required String statusValue,
    required int? bpmValue,
    required double? temperatureValue,
    required int score,
  }) {
    if (bpmValue == null && temperatureValue == null) {
      return const [
        'Complete a full scan before using this report for daily wellness review.',
        'Place your finger firmly on the sensor and remain still during the scan.',
        'Repeat the scan if the reading appears unstable or incomplete.',
      ];
    }

    if (statusValue == 'Warning' || score > 0 && score < 55) {
      return const [
        'Rest for at least 5 minutes and repeat the scan in a calm seated position.',
        'Drink water and avoid intense exercise until the reading becomes stable.',
        'Seek medical advice urgently if you feel chest pain, dizziness, faintness, shortness of breath, or fever symptoms.',
      ];
    }

    if (statusValue == 'Monitor' || score > 0 && score < 72) {
      return const [
        'Monitor your condition and repeat the scan later for confirmation.',
        'Keep physical activity light if you feel tired, stressed, or unwell.',
        'Improve accuracy by keeping the finger steady and sensor contact consistent.',
      ];
    }

    return const [
      'Your latest reading appears stable for general wellness tracking.',
      'Maintain hydration, regular meals, enough sleep, and moderate daily activity.',
      'Continue saving scans consistently to build a more useful weekly trend.',
    ];
  }

  String _bpmInterpretation(int? value) {
    if (value == null || value <= 0) {
      return 'Heart rate interpretation: No heart rate value is available for this report.';
    }
    if (value < 50) {
      return 'Heart rate interpretation: The recorded heart rate is low. This may be normal for some trained individuals, but it should be monitored if symptoms are present.';
    }
    if (value <= 100) {
      return 'Heart rate interpretation: The recorded heart rate is within a commonly expected resting range for general wellness tracking.';
    }
    if (value <= 115) {
      return 'Heart rate interpretation: The recorded heart rate is slightly elevated. Rest and repeat the scan to confirm the reading.';
    }
    return 'Heart rate interpretation: The recorded heart rate is high. Avoid strenuous activity and consider medical advice if symptoms are present.';
  }

  String _temperatureInterpretation(double? value) {
    if (value == null || value <= 0) {
      return 'Temperature interpretation: No temperature value is available for this report.';
    }
    if (value < 35.5) {
      return 'Temperature interpretation: The recorded temperature is below the usual range. Repeat the scan and ensure correct sensor contact.';
    }
    if (value < 37.6) {
      return 'Temperature interpretation: The recorded temperature is within the expected range for general wellness tracking.';
    }
    if (value < 38.0) {
      return 'Temperature interpretation: The recorded temperature is mildly elevated. Monitor symptoms and repeat the reading later.';
    }
    return 'Temperature interpretation: The recorded temperature is elevated. Rest, hydrate, and seek medical advice if fever symptoms continue.';
  }

  String _statusInterpretation(String statusValue, int score) {
    if (score == 0) {
      return 'Overall interpretation: A complete score could not be calculated because there is not enough scan data.';
    }
    if (statusValue == 'Warning') {
      return 'Overall interpretation: The scan is marked as Warning. The user should rest and repeat the scan before continuing intense activity.';
    }
    if (statusValue == 'Monitor') {
      return 'Overall interpretation: The scan is marked as Monitor. The reading is usable, but follow-up scanning is recommended.';
    }
    return 'Overall interpretation: The scan is marked as Normal. Continue regular wellness tracking and compare with future readings.';
  }

  Future<void> _openPdfFile(String filePath) async {
    try {
      final result = await OpenFilex.open(filePath);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open PDF: ${result.message}',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open PDF: $e', style: GoogleFonts.outfit()),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Uint8List _buildAdvancedHealthReportPdf({
    required List<HealthScanResult> scans,
    required DateTime generatedAt,
    required int? bpmValue,
    required double? temperatureValue,
    required int score,
    required String statusValue,
    required int durationSeconds,
  }) {
    const pageWidth = 595.0;
    const pageHeight = 842.0;
    const margin = 40.0;
    const bottomLimit = 64.0;

    final sortedScans = [...scans]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final recentTrendScans = sortedScans.length > 7
        ? sortedScans.sublist(sortedScans.length - 7)
        : sortedScans;
    final latest = sortedScans.isEmpty ? null : sortedScans.last;
    final advice = _formalAdviceLines(
      statusValue: statusValue,
      bpmValue: bpmValue,
      temperatureValue: temperatureValue,
      score: score,
    );

    final bpmTrend = recentTrendScans
        .map((scan) => scan.avgBpm <= 0 ? scan.bpm.toDouble() : scan.avgBpm)
        .toList();
    final tempTrend = recentTrendScans.map((scan) => scan.temperature).toList();

    final pages = <String>[];
    var content = StringBuffer();
    var y = 0.0;

    String n(num value) => value.toDouble().toStringAsFixed(2);

    String esc(String value) {
      final normalized = value
          .replaceAll('•', '-')
          .replaceAll('–', '-')
          .replaceAll('—', '-')
          .replaceAll('’', "'")
          .replaceAll('“', '"')
          .replaceAll('”', '"')
          .replaceAll('°', ' deg ')
          .replaceAll('₂', '2')
          .replaceAll(RegExp(r'[^\x20-\x7E]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return normalized
          .replaceAll('\\', r'\\')
          .replaceAll('(', r'\(')
          .replaceAll(')', r'\)');
    }

    double channel(int color, int shift) =>
        ((color >> shift) & 0xFF).toDouble() / 255.0;

    void setFill(int color) {
      content.writeln(
        '${n(channel(color, 16))} ${n(channel(color, 8))} ${n(channel(color, 0))} rg',
      );
    }

    void setStroke(int color) {
      content.writeln(
        '${n(channel(color, 16))} ${n(channel(color, 8))} ${n(channel(color, 0))} RG',
      );
    }

    void rect(
      double x,
      double bottom,
      double width,
      double height, {
      int fill = 0xFFFFFF,
      int? stroke,
      double strokeWidth = 1,
    }) {
      setFill(fill);
      if (stroke != null) setStroke(stroke);
      content.writeln('${n(strokeWidth)} w');
      content.writeln('${n(x)} ${n(bottom)} ${n(width)} ${n(height)} re');
      content.writeln(stroke == null ? 'f' : 'B');
    }

    void line(
      double x1,
      double y1,
      double x2,
      double y2, {
      int color = 0xD1D5DB,
      double width = 1,
    }) {
      setStroke(color);
      content.writeln('${n(width)} w');
      content.writeln('${n(x1)} ${n(y1)} m ${n(x2)} ${n(y2)} l S');
    }

    void textAt(
      String value,
      double x,
      double baseline, {
      double size = 10,
      bool bold = false,
      int color = 0x111827,
    }) {
      if (value.trim().isEmpty) return;
      setFill(color);
      content.writeln('BT');
      content.writeln('/${bold ? 'F2' : 'F1'} ${n(size)} Tf');
      content.writeln('1 0 0 1 ${n(x)} ${n(baseline)} Tm');
      content.writeln('(${esc(value)}) Tj');
      content.writeln('ET');
    }

    List<String> wrapText(String text, double maxWidth, double fontSize) {
      final clean = esc(text);
      if (clean.isEmpty) return const <String>[];
      final maxChars = math.max(18, (maxWidth / (fontSize * 0.52)).floor());
      final words = clean.split(RegExp(r'\s+'));
      final lines = <String>[];
      var current = '';

      for (final word in words) {
        if (current.isEmpty) {
          current = word;
        } else if (current.length + word.length + 1 <= maxChars) {
          current = '$current $word';
        } else {
          lines.add(current);
          current = word;
        }
      }
      if (current.isNotEmpty) lines.add(current);
      return lines;
    }

    double paragraph(
      String text,
      double x,
      double top,
      double width, {
      double size = 10,
      double lineHeight = 14,
      bool bold = false,
      int color = 0x374151,
    }) {
      var currentY = top;
      final lines = wrapText(text, width, size);
      for (final lineText in lines) {
        textAt(lineText, x, currentY - size, size: size, bold: bold, color: color);
        currentY -= lineHeight;
      }
      return currentY;
    }

    void footer() {
      final pageNo = pages.length + 1;
      line(margin, 39, pageWidth - margin, 39, color: 0xDDE5D4, width: 0.7);
      textAt(
        'Wellness tracking report only - not a medical diagnosis',
        margin,
        24,
        size: 8.4,
        color: 0x6B7280,
      );
      textAt('Page $pageNo', pageWidth - margin - 44, 24, size: 8.4, color: 0x6B7280);
    }

    void startPage() {
      content = StringBuffer();
      rect(0, 0, pageWidth, pageHeight, fill: 0xF8FAF4);
      rect(0, pageHeight - 104, pageWidth, 104, fill: 0x0F140D);
      rect(0, pageHeight - 108, pageWidth, 4, fill: 0xD6FF60);
      textAt('NutriPulse', margin, pageHeight - 42, size: 14, bold: true, color: 0xD6FF60);
      textAt(
        'Advanced Health Monitoring Report',
        margin,
        pageHeight - 70,
        size: 22,
        bold: true,
        color: 0xFFFFFF,
      );
      textAt(
        'Generated ${HealthScanService.dateKey(generatedAt)} ${HealthScanService.formatTime(generatedAt)}',
        pageWidth - 240,
        pageHeight - 46,
        size: 9,
        color: 0xDDE7C9,
      );
      textAt('ESP32 wellness scan summary', pageWidth - 240, pageHeight - 63, size: 9, color: 0xAFC19C);
      y = pageHeight - 132;
    }

    void finishPage() {
      footer();
      pages.add(content.toString());
    }

    void ensureSpace(double neededHeight) {
      if (y - neededHeight < bottomLimit) {
        finishPage();
        startPage();
      }
    }

    int statusColor(String value) {
      if (value == 'Normal') return 0x2F855A;
      if (value == 'Warning') return 0xDC2626;
      if (value == 'Monitor') return 0xD97706;
      return 0x6B7280;
    }

    String scoreLabelForPdf(int value) {
      if (value == 0) return 'Scan needed';
      if (value >= 86) return 'Excellent';
      if (value >= 72) return 'Good';
      if (value >= 55) return 'Monitor';
      return 'Attention';
    }

    void sectionTitle(String title, {String? subtitle}) {
      ensureSpace(subtitle == null ? 32 : 50);
      textAt(title, margin, y - 14, size: 15, bold: true, color: 0x13210F);
      rect(margin, y - 21, 46, 2.2, fill: 0xD6FF60);
      y -= 28;
      if (subtitle != null) {
        y = paragraph(subtitle, margin, y + 4, pageWidth - (margin * 2), size: 9.2, lineHeight: 12.5, color: 0x64705F);
        y -= 6;
      }
    }

    void metricCard(
      double x,
      double top,
      double width,
      double height, {
      required String label,
      required String value,
      required String note,
      required int accent,
    }) {
      rect(x, top - height, width, height, fill: 0xFFFFFF, stroke: 0xE3EAD8, strokeWidth: 0.8);
      rect(x, top - height, 5, height, fill: accent);
      textAt(label, x + 15, top - 21, size: 8.8, bold: true, color: 0x65715F);
      textAt(value, x + 15, top - 49, size: 21, bold: true, color: 0x111827);
      paragraph(note, x + 15, top - 62, width - 28, size: 7.8, lineHeight: 10.3, color: 0x6B7280);
    }

    void drawDashboardCards() {
      ensureSpace(130);
      final cardWidth = (pageWidth - (margin * 2) - 24) / 4;
      final top = y;
      metricCard(
        margin,
        top,
        cardWidth,
        104,
        label: 'Health score',
        value: score == 0 ? '--' : '$score/100',
        note: scoreLabelForPdf(score),
        accent: score >= 72 ? 0x2F855A : score >= 55 ? 0xD97706 : 0xDC2626,
      );
      metricCard(
        margin + cardWidth + 8,
        top,
        cardWidth,
        104,
        label: 'Status',
        value: statusValue,
        note: statusValue == 'Waiting' ? 'No full reading yet' : 'Latest interpreted result',
        accent: statusColor(statusValue),
      );
      metricCard(
        margin + (cardWidth + 8) * 2,
        top,
        cardWidth,
        104,
        label: 'Heart rate',
        value: bpmValue == null ? '--' : '$bpmValue',
        note: bpmValue == null ? 'BPM unavailable' : 'beats per minute',
        accent: 0x84A600,
      );
      metricCard(
        margin + (cardWidth + 8) * 3,
        top,
        cardWidth,
        104,
        label: 'Temperature',
        value: temperatureValue == null ? '--' : temperatureValue.toStringAsFixed(1),
        note: temperatureValue == null ? 'Temperature unavailable' : 'degree Celsius',
        accent: 0xF59E0B,
      );
      y -= 126;
    }

    void drawExecutiveSummary() {
      ensureSpace(116);
      rect(margin, y - 108, pageWidth - margin * 2, 108, fill: 0xFFFFFF, stroke: 0xE3EAD8, strokeWidth: 0.8);
      rect(margin, y - 108, 8, 108, fill: 0xD6FF60);
      textAt('Executive Summary', margin + 20, y - 24, size: 14, bold: true, color: 0x13210F);
      final summary = '${_statusInterpretation(statusValue, score)} ${_bpmInterpretation(bpmValue)} ${_temperatureInterpretation(temperatureValue)}';
      paragraph(summary, margin + 20, y - 40, pageWidth - margin * 2 - 38, size: 9.2, lineHeight: 12.6, color: 0x374151);
      y -= 126;
    }

    List<double> scaledRange(List<double> values, double minFallback, double maxFallback) {
      if (values.isEmpty) return <double>[minFallback, maxFallback];
      var minValue = values.reduce(math.min);
      var maxValue = values.reduce(math.max);
      if ((maxValue - minValue).abs() < 0.5) {
        minValue -= 1;
        maxValue += 1;
      }
      final padding = (maxValue - minValue) * 0.18;
      return <double>[math.min(minFallback, minValue - padding), math.max(maxFallback, maxValue + padding)];
    }

    void drawMiniLineChart({
      required double x,
      required double top,
      required double width,
      required double height,
      required String title,
      required String subtitle,
      required List<double> values,
      required double minAxis,
      required double maxAxis,
      required int color,
      required String suffix,
    }) {
      rect(x, top - height, width, height, fill: 0xFFFFFF, stroke: 0xE3EAD8, strokeWidth: 0.8);
      textAt(title, x + 14, top - 20, size: 11.5, bold: true, color: 0x13210F);
      textAt(subtitle, x + 14, top - 36, size: 8.2, color: 0x6B7280);

      final plotLeft = x + 34;
      final plotRight = x + width - 16;
      final plotTop = top - 54;
      final plotBottom = top - height + 28;
      final plotWidth = plotRight - plotLeft;
      final plotHeight = plotTop - plotBottom;

      for (int i = 0; i < 4; i++) {
        final gridY = plotBottom + (plotHeight / 3) * i;
        line(plotLeft, gridY, plotRight, gridY, color: 0xE8EEDF, width: 0.7);
      }
      line(plotLeft, plotBottom, plotLeft, plotTop, color: 0xD5DEC8, width: 0.7);
      line(plotLeft, plotBottom, plotRight, plotBottom, color: 0xD5DEC8, width: 0.7);
      textAt(maxAxis.toStringAsFixed(0), x + 10, plotTop - 4, size: 7.2, color: 0x6B7280);
      textAt(minAxis.toStringAsFixed(0), x + 10, plotBottom - 2, size: 7.2, color: 0x6B7280);

      if (values.length < 2) {
        textAt('Save at least 2 scans to draw trend', plotLeft + 12, plotBottom + plotHeight / 2, size: 8.5, color: 0x6B7280);
        return;
      }

      double pointX(int index) => plotLeft + (plotWidth / (values.length - 1)) * index;
      double pointY(double value) {
        final normalized = ((value - minAxis) / (maxAxis - minAxis)).clamp(0.0, 1.0);
        return plotBottom + normalized * plotHeight;
      }

      setStroke(color);
      content.writeln('2.2 w');
      for (int i = 0; i < values.length; i++) {
        final px = pointX(i);
        final py = pointY(values[i]);
        if (i == 0) {
          content.writeln('${n(px)} ${n(py)} m');
        } else {
          content.writeln('${n(px)} ${n(py)} l');
        }
      }
      content.writeln('S');

      for (int i = 0; i < values.length; i++) {
        final px = pointX(i);
        final py = pointY(values[i]);
        rect(px - 2.2, py - 2.2, 4.4, 4.4, fill: color);
      }

      final latestValue = values.last;
      textAt('${latestValue.toStringAsFixed(suffix == 'C' ? 1 : 0)} $suffix', plotRight - 54, plotTop - 12, size: 8.4, bold: true, color: color);
    }

    void drawTrendCharts() {
      sectionTitle(
        'Trend Charts',
        subtitle: 'Last saved readings are visualised as clean line charts. More saved scans will produce a stronger weekly pattern.',
      );
      ensureSpace(182);
      final chartWidth = (pageWidth - margin * 2 - 12) / 2;
      final bpmAxis = scaledRange(bpmTrend, 50, 110);
      final tempAxis = scaledRange(tempTrend, 35, 38);
      final top = y;
      drawMiniLineChart(
        x: margin,
        top: top,
        width: chartWidth,
        height: 166,
        title: 'Heart Rate Trend',
        subtitle: '${bpmTrend.length}/7 recent scans',
        values: bpmTrend,
        minAxis: bpmAxis.first,
        maxAxis: bpmAxis.last,
        color: 0x84A600,
        suffix: 'BPM',
      );
      drawMiniLineChart(
        x: margin + chartWidth + 12,
        top: top,
        width: chartWidth,
        height: 166,
        title: 'Temperature Trend',
        subtitle: '${tempTrend.length}/7 recent scans',
        values: tempTrend,
        minAxis: tempAxis.first,
        maxAxis: tempAxis.last,
        color: 0xF59E0B,
        suffix: 'C',
      );
      y -= 188;
    }

    void rangeBar({
      required double x,
      required double top,
      required double width,
      required String label,
      required double? value,
      required double min,
      required double max,
      required double normalMin,
      required double normalMax,
      required String suffix,
      required int markerColor,
    }) {
      final barY = top - 37;
      final barH = 13.0;
      textAt(label, x, top - 12, size: 9.8, bold: true, color: 0x13210F);
      rect(x, barY, width, barH, fill: 0xE8EEDF);
      final normalX = x + ((normalMin - min) / (max - min)).clamp(0.0, 1.0) * width;
      final normalW = ((normalMax - normalMin) / (max - min)).clamp(0.0, 1.0) * width;
      rect(normalX, barY, normalW, barH, fill: 0xD6FF60);
      textAt('Normal zone', normalX, barY - 12, size: 7.2, color: 0x65715F);

      if (value != null) {
        final markerX = x + ((value - min) / (max - min)).clamp(0.0, 1.0) * width;
        rect(markerX - 2, barY - 4, 4, barH + 8, fill: markerColor);
        textAt('${value.toStringAsFixed(suffix == 'C' ? 1 : 0)} $suffix', math.min(markerX + 5, x + width - 50), barY + 22, size: 8.3, bold: true, color: markerColor);
      } else {
        textAt('No value available', x + width - 82, barY + 22, size: 8.2, color: 0x6B7280);
      }

      textAt(min.toStringAsFixed(0), x, barY - 24, size: 7.2, color: 0x6B7280);
      textAt(max.toStringAsFixed(0), x + width - 18, barY - 24, size: 7.2, color: 0x6B7280);
    }

    void drawComparisonBars() {
      sectionTitle(
        'Reference Range Bars',
        subtitle: 'Bars compare the latest reading with broad wellness reference zones. Use them as a guide, not a diagnosis.',
      );
      ensureSpace(148);
      rect(margin, y - 136, pageWidth - margin * 2, 136, fill: 0xFFFFFF, stroke: 0xE3EAD8, strokeWidth: 0.8);
      rangeBar(
        x: margin + 18,
        top: y - 18,
        width: pageWidth - margin * 2 - 36,
        label: 'Heart rate range comparison',
        value: bpmValue?.toDouble(),
        min: 40,
        max: 150,
        normalMin: 60,
        normalMax: 100,
        suffix: 'BPM',
        markerColor: statusColor(statusValue),
      );
      rangeBar(
        x: margin + 18,
        top: y - 78,
        width: pageWidth - margin * 2 - 36,
        label: 'Temperature range comparison',
        value: temperatureValue,
        min: 34,
        max: 40,
        normalMin: 35.5,
        normalMax: 37.5,
        suffix: 'C',
        markerColor: temperatureValue != null && temperatureValue >= 37.6 ? 0xD97706 : 0x2F855A,
      );
      y -= 158;
    }

    void drawRecentTable() {
      sectionTitle('Recent Scan Log');
      final rows = sortedScans.reversed.take(9).toList();
      ensureSpace(68 + math.max(rows.length, 1) * 28);
      final tableX = margin;
      final tableW = pageWidth - margin * 2;
      final rowH = 28.0;
      final headerTop = y;
      rect(tableX, headerTop - rowH, tableW, rowH, fill: 0x13210F);
      textAt('Date / Time', tableX + 12, headerTop - 18, size: 8.6, bold: true, color: 0xFFFFFF);
      textAt('BPM', tableX + 172, headerTop - 18, size: 8.6, bold: true, color: 0xFFFFFF);
      textAt('Temp', tableX + 242, headerTop - 18, size: 8.6, bold: true, color: 0xFFFFFF);
      textAt('Status', tableX + 326, headerTop - 18, size: 8.6, bold: true, color: 0xFFFFFF);
      textAt('Duration', tableX + 430, headerTop - 18, size: 8.6, bold: true, color: 0xFFFFFF);
      y -= rowH;

      if (rows.isEmpty) {
        rect(tableX, y - rowH, tableW, rowH, fill: 0xFFFFFF, stroke: 0xE3EAD8, strokeWidth: 0.8);
        textAt('No saved scans are available yet.', tableX + 12, y - 18, size: 9, color: 0x6B7280);
        y -= rowH + 12;
        return;
      }

      for (int i = 0; i < rows.length; i++) {
        final scan = rows[i];
        final rowFill = i.isEven ? 0xFFFFFF : 0xF1F6EA;
        rect(tableX, y - rowH, tableW, rowH, fill: rowFill, stroke: 0xE3EAD8, strokeWidth: 0.5);
        textAt(
          '${HealthScanService.dateKey(scan.createdAt)} ${HealthScanService.formatTime(scan.createdAt)}',
          tableX + 12,
          y - 18,
          size: 8.3,
          color: 0x374151,
        );
        textAt('${scan.bpm}', tableX + 172, y - 18, size: 8.3, bold: true, color: 0x111827);
        textAt('${scan.temperature.toStringAsFixed(1)} C', tableX + 242, y - 18, size: 8.3, color: 0x111827);
        textAt(scan.status, tableX + 326, y - 18, size: 8.3, bold: true, color: statusColor(scan.status));
        textAt('${scan.durationSeconds}s', tableX + 430, y - 18, size: 8.3, color: 0x374151);
        y -= rowH;
      }
      y -= 14;
    }

    void drawAdviceAndNotice() {
      sectionTitle('Formal Advice');
      ensureSpace(128);
      rect(margin, y - 118, pageWidth - margin * 2, 118, fill: 0xFFFFFF, stroke: 0xE3EAD8, strokeWidth: 0.8);
      var itemY = y - 18;
      for (final item in advice) {
        rect(margin + 16, itemY - 5, 5, 5, fill: 0xD6FF60);
        itemY = paragraph(item, margin + 30, itemY + 2, pageWidth - margin * 2 - 48, size: 9.0, lineHeight: 12.2, color: 0x374151);
        itemY -= 4;
      }
      y -= 136;

      ensureSpace(90);
      rect(margin, y - 78, pageWidth - margin * 2, 78, fill: 0xFFF7ED, stroke: 0xFED7AA, strokeWidth: 0.8);
      textAt('Important Notice', margin + 16, y - 21, size: 12, bold: true, color: 0x9A3412);
      paragraph(
        'This report is generated for wellness tracking only. It is not a medical diagnosis and should not replace advice from a qualified healthcare professional. Seek medical help if symptoms are severe, persistent, or worrying.',
        margin + 16,
        y - 38,
        pageWidth - margin * 2 - 32,
        size: 8.7,
        lineHeight: 11.7,
        color: 0x7C2D12,
      );
      y -= 92;
    }

    void drawReportMetadata() {
      ensureSpace(76);
      rect(margin, y - 64, pageWidth - margin * 2, 64, fill: 0xECF4E2, stroke: 0xD8E6C5, strokeWidth: 0.8);
      textAt('Report ID', margin + 14, y - 18, size: 8.4, bold: true, color: 0x65715F);
      textAt('NPH-${generatedAt.millisecondsSinceEpoch}', margin + 14, y - 38, size: 10, bold: true, color: 0x13210F);
      textAt('Latest saved scan', margin + 220, y - 18, size: 8.4, bold: true, color: 0x65715F);
      textAt(
        latest == null
            ? 'No saved scan yet'
            : '${HealthScanService.dateKey(latest.createdAt)} ${HealthScanService.formatTime(latest.createdAt)}',
        margin + 220,
        y - 38,
        size: 10,
        bold: true,
        color: 0x13210F,
      );
      textAt('Scan duration', margin + 405, y - 18, size: 8.4, bold: true, color: 0x65715F);
      textAt(durationSeconds <= 0 ? 'Not available' : '$durationSeconds seconds', margin + 405, y - 38, size: 10, bold: true, color: 0x13210F);
      y -= 84;
    }

    startPage();
    drawReportMetadata();
    drawDashboardCards();
    drawExecutiveSummary();
    drawTrendCharts();
    drawComparisonBars();
    drawRecentTable();
    drawAdviceAndNotice();
    finishPage();

    final objects = <String>[
      '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
      '',
      '3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n',
      '4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>\nendobj\n',
    ];

    final kids = <String>[];
    var nextObjectId = 5;

    for (final pageStream in pages) {
      final pageId = nextObjectId++;
      final contentId = nextObjectId++;
      kids.add('$pageId 0 R');
      final streamLength = utf8.encode(pageStream).length;

      objects.add(
        '$pageId 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> '
        '/Contents $contentId 0 R >>\nendobj\n',
      );
      objects.add(
        '$contentId 0 obj\n<< /Length $streamLength >>\nstream\n$pageStream\nendstream\nendobj\n',
      );
    }

    objects[1] =
        '2 0 obj\n<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${pages.length} >>\nendobj\n';

    final buffer = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[0];
    var currentOffset = utf8.encode(buffer.toString()).length;

    for (final obj in objects) {
      offsets.add(currentOffset);
      buffer.write(obj);
      currentOffset += utf8.encode(obj).length;
    }

    final xrefOffset = currentOffset;
    buffer.writeln('xref');
    buffer.writeln('0 ${objects.length + 1}');
    buffer.writeln('0000000000 65535 f ');
    for (int i = 1; i < offsets.length; i++) {
      buffer.writeln('${offsets[i].toString().padLeft(10, '0')} 00000 n ');
    }
    buffer.writeln('trailer');
    buffer.writeln('<< /Size ${objects.length + 1} /Root 1 0 R >>');
    buffer.writeln('startxref');
    buffer.writeln('$xrefOffset');
    buffer.writeln('%%EOF');

    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  void _showPdfCreatedSheet(String filePath, {required String filename}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: EdgeInsets.fromLTRB(
            22,
            18,
            22,
            MediaQuery.of(context).padding.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF141A11),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: lime.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: lime,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PDF Report Ready',
                          style: GoogleFonts.outfit(
                            color: text,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Charts, bars, table and advice',
                          style: GoogleFonts.outfit(
                            color: soft,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.045),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.045)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      filePath,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.82),
                        fontSize: 11.3,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.12),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: Text(
                          'Close',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _openPdfFile(filePath);
                        },
                        icon: const Icon(
                          Icons.open_in_new_rounded,
                          color: Colors.black,
                          size: 19,
                        ),
                        label: Text(
                          'Open PDF',
                          style: GoogleFonts.outfit(
                            color: Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: lime,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showHealthReportSheet(List<HealthScanResult> scans) {
    final latest = _latestSavedScan(scans);
    final effectiveBpm = _effectiveBpm(scans);
    final effectiveTemp = _effectiveTemperature(scans);
    final score = _effectiveScore(scans);
    final effectiveStatus = _effectiveStatus(scans);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: EdgeInsets.fromLTRB(
            22,
            14,
            22,
            MediaQuery.of(context).padding.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF141A11),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: soft.withOpacity(0.32),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: lime.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.medical_information_rounded,
                      color: lime,
                      size: 27,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Doctor-ready Summary',
                          style: GoogleFonts.outfit(
                            color: text,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          latest == null
                              ? 'Live reading summary'
                              : 'Last saved: ${HealthScanService.formatTime(latest.createdAt)}',
                          style: GoogleFonts.outfit(
                            color: soft,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _reportMetric(
                      'Score',
                      score == 0 ? '--' : '$score/100',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _reportMetric('Status', effectiveStatus)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _reportMetric(
                      'BPM',
                      effectiveBpm?.toString() ?? '--',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _reportMetric(
                      'Temp',
                      effectiveTemp == null
                          ? '--'
                          : '${effectiveTemp.toStringAsFixed(1)}°C',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.045),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.045)),
                ),
                child: Text(
                  _aiInsightText(scans),
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.86),
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: lime,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    'Done',
                    style: GoogleFonts.outfit(
                      color: Colors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _reportMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.045)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 10.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: text,
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanActionCard() {
    final primaryLabel = _isReading
        ? 'Stop Scan'
        : _isConnecting
        ? 'Connecting...'
        : _isScanning
        ? 'Scanning...'
        : 'Start Health Scan';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _isReading
                      ? Icons.monitor_heart_rounded
                      : Icons.play_arrow_rounded,
                  color: _statusColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isReading
                          ? 'Live scan running'
                          : 'Ready for health scan',
                      style: GoogleFonts.outfit(
                        color: text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isReading
                          ? 'Hold still and keep your finger on the sensor.'
                          : 'Press start and place your finger on the ESP32 sensor.',
                      style: GoogleFonts.outfit(
                        color: soft,
                        fontSize: 12.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (_isReading || _bpmHistory.isNotEmpty) ...[
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _canSave && !_savedCurrentSession && !_isSaving
                          ? _saveResult
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: lime,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: lime.withOpacity(0.30),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 2.4,
                              ),
                            )
                          : Text(
                              _savedCurrentSession ? 'Saved' : 'Save Result',
                              style: GoogleFonts.outfit(
                                color: Colors.black,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: (_isScanning || _isConnecting)
                        ? null
                        : _isReading
                        ? _stopScan
                        : _startHealthScan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isReading ? Colors.redAccent : lime,
                      disabledBackgroundColor: lime.withOpacity(0.35),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: (_isScanning || _isConnecting)
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            primaryLabel,
                            style: GoogleFonts.outfit(
                              color: Colors.black,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _calendarStrip() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _box(),
      child: Row(
        children: _weekDates.map((date) {
          final selected =
              HealthScanService.dateKey(date) ==
              HealthScanService.dateKey(_selectedDate);

          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedDate = date),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? lime : Colors.white.withOpacity(0.045),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: selected ? lime : Colors.white.withOpacity(0.045),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      HealthScanService.shortDay(date),
                      style: GoogleFonts.outfit(
                        color: selected ? Colors.black : soft,
                        fontSize: 9.8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${date.day}',
                      style: GoogleFonts.outfit(
                        color: selected ? Colors.black : text,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _selectedDateSection(List<HealthScanResult> scans) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selected Day',
          style: GoogleFonts.outfit(
            color: text,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        if (scans.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: _box(),
            child: Text(
              'No saved scans for this date.',
              style: GoogleFonts.outfit(
                color: soft,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          ...scans.map((scan) => _scanHistoryTile(scan, compact: true)),
      ],
    );
  }

  Widget _recentHeader() {
    return Row(
      children: [
        Text(
          'Recent Scans',
          style: GoogleFonts.outfit(
            color: text,
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
        const Spacer(),
        Text(
          'Saved results',
          style: GoogleFonts.outfit(
            color: soft,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _recentScansList(List<HealthScanResult> scans) {
    if (scans.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _box(),
        child: Text(
          'No saved health scans yet. Start a scan and save your result.',
          style: GoogleFonts.outfit(
            color: soft,
            fontSize: 13,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Column(
      children: scans.take(6).map((scan) => _scanHistoryTile(scan)).toList(),
    );
  }

  Widget _scanHistoryTile(HealthScanResult scan, {bool compact = false}) {
    final color = scan.status == 'Normal'
        ? lime
        : scan.status == 'Warning'
        ? Colors.redAccent
        : Colors.amberAccent;

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 8 : 10),
      padding: const EdgeInsets.all(13),
      decoration: _box(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.13),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.monitor_heart_rounded, color: color, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${scan.bpm} BPM • ${scan.temperature.toStringAsFixed(1)}°C',
                  style: GoogleFonts.outfit(
                    color: text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${HealthScanService.formatTime(scan.createdAt)} • ${scan.status}',
                  style: GoogleFonts.outfit(
                    color: soft,
                    fontSize: 11.7,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${scan.durationSeconds}s',
            style: GoogleFonts.outfit(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomActionBar() {
    final primaryLabel = _isReading
        ? 'Stop Scan'
        : _isConnecting
        ? 'Connecting...'
        : _isScanning
        ? 'Scanning...'
        : 'Start Health Scan';

    return Positioned(
      left: 16,
      right: 16,
      bottom: 92,
      child: Row(
        children: [
          if (_isReading || _bpmHistory.isNotEmpty) ...[
            Expanded(
              child: SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _canSave && !_savedCurrentSession && !_isSaving
                      ? _saveResult
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: lime,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: lime.withOpacity(0.30),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2.4,
                          ),
                        )
                      : Text(
                          _savedCurrentSession ? 'Saved' : 'Save Result',
                          style: GoogleFonts.outfit(
                            color: Colors.black,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: (_isScanning || _isConnecting)
                    ? null
                    : _isReading
                    ? _stopScan
                    : _startHealthScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isReading ? Colors.redAccent : lime,
                  disabledBackgroundColor: lime.withOpacity(0.35),
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: (_isScanning || _isConnecting)
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.black,
                        ),
                      )
                    : Text(
                        primaryLabel,
                        style: GoogleFonts.outfit(
                          color: Colors.black,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _box({bool glow = false}) {
    return BoxDecoration(
      color: glow ? card2.withOpacity(0.78) : card.withOpacity(0.72),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withOpacity(0.040)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(glow ? 0.20 : 0.15),
          blurRadius: glow ? 16 : 10,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

class _WeeklyHealthTrendPainter extends CustomPainter {
  _WeeklyHealthTrendPainter({
    required this.scans,
    required this.bpmColor,
    required this.tempColor,
    required this.gridColor,
  });

  final List<HealthScanResult> scans;
  final Color bpmColor;
  final Color tempColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (scans.length < 2 || size.width <= 0 || size.height <= 0) return;

    const leftPad = 8.0;
    const rightPad = 8.0;
    const topPad = 10.0;
    const bottomPad = 10.0;
    final usableWidth = size.width - leftPad - rightPad;
    final usableHeight = size.height - topPad - bottomPad;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (int i = 0; i < 4; i++) {
      final y = topPad + (usableHeight / 3) * i;
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(size.width - rightPad, y),
        gridPaint,
      );
    }

    Path makePath(List<double> values) {
      final minValue = values.reduce(math.min);
      final maxValue = values.reduce(math.max);
      final range = math.max(maxValue - minValue, 1.0);
      final path = Path();

      for (int i = 0; i < values.length; i++) {
        final x = leftPad + (usableWidth / (values.length - 1)) * i;
        final normalized = (values[i] - minValue) / range;
        final y = topPad + usableHeight - (normalized * usableHeight);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    final bpmValues = scans
        .map((scan) => scan.avgBpm <= 0 ? scan.bpm.toDouble() : scan.avgBpm)
        .toList();
    final tempValues = scans.map((scan) => scan.temperature).toList();

    void drawTrend(Path path, Color color) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withOpacity(0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final bpmPath = makePath(bpmValues);
    final tempPath = makePath(tempValues);
    drawTrend(bpmPath, bpmColor);
    drawTrend(tempPath, tempColor);

    final lastBpmX = size.width - rightPad;
    final lastBpmMin = bpmValues.reduce(math.min);
    final lastBpmMax = bpmValues.reduce(math.max);
    final lastBpmRange = math.max(lastBpmMax - lastBpmMin, 1.0);
    final lastBpmY =
        topPad +
        usableHeight -
        (((bpmValues.last - lastBpmMin) / lastBpmRange) * usableHeight);
    canvas.drawCircle(
      Offset(lastBpmX, lastBpmY),
      5.2,
      Paint()..color = bpmColor,
    );

    final lastTempMin = tempValues.reduce(math.min);
    final lastTempMax = tempValues.reduce(math.max);
    final lastTempRange = math.max(lastTempMax - lastTempMin, 1.0);
    final lastTempY =
        topPad +
        usableHeight -
        (((tempValues.last - lastTempMin) / lastTempRange) * usableHeight);
    canvas.drawCircle(
      Offset(lastBpmX, lastTempY),
      4.6,
      Paint()..color = tempColor,
    );
  }

  @override
  bool shouldRepaint(covariant _WeeklyHealthTrendPainter oldDelegate) {
    if (oldDelegate.scans.length != scans.length) return true;
    if (oldDelegate.bpmColor != bpmColor || oldDelegate.tempColor != tempColor)
      return true;
    for (int i = 0; i < scans.length; i++) {
      if (oldDelegate.scans[i].id != scans[i].id ||
          oldDelegate.scans[i].avgBpm != scans[i].avgBpm ||
          oldDelegate.scans[i].temperature != scans[i].temperature) {
        return true;
      }
    }
    return false;
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

    for (int i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final minValue = points.reduce(math.min) - 8;
    final maxValue = points.reduce(math.max) + 8;
    final range = math.max(maxValue - minValue, 1);

    final path = Path();
    final fillPath = Path();

    Offset pointAt(int index) {
      final x = index / (points.length - 1) * size.width;
      final y =
          size.height - ((points[index] - minValue) / range * size.height);
      return Offset(x, y);
    }

    final first = pointAt(0);
    path.moveTo(first.dx, first.dy);
    fillPath.moveTo(first.dx, size.height);
    fillPath.lineTo(first.dx, first.dy);

    for (int i = 1; i < points.length; i++) {
      final current = pointAt(i);
      path.lineTo(current.dx, current.dy);
      fillPath.lineTo(current.dx, current.dy);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final last = pointAt(points.length - 1);
    canvas.drawCircle(last, 5.5, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(covariant _LiveGraphPainter oldDelegate) {
    if (oldDelegate.points.length != points.length) return true;
    if (points.isEmpty || oldDelegate.points.isEmpty) return false;
    return oldDelegate.points.last != points.last;
  }
}
