import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:sensors_plus/sensors_plus.dart';

import '../../models/activity_record.dart';
import '../../services/activity_service.dart';
import 'activity_summary_screen.dart';

enum _MapStyle { dark, light, satellite }

class LiveActivityScreen extends StatefulWidget {
  const LiveActivityScreen({super.key, required this.activityType});

  final String activityType;

  @override
  State<LiveActivityScreen> createState() => _LiveActivityScreenState();
}

class _LiveActivityScreenState extends State<LiveActivityScreen>
    with TickerProviderStateMixin {
  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color routeOrange = Color(0xFFFF5A1F);
  static const Color soft = Color(0xFFB7C2A8);
  static const Color card = Color(0xFF1A1F17);
  static const Color markerBlue = Color(0xFF2F80ED);

  // Movement filters:
  // - Prevent indoor GPS drift from becoming fake distance.
  // - Prevent calories and pace from changing when the user is not moving.
  static const double _maxRouteAccuracyMeters = 32.0;
  static const double _minRouteMoveMeters = 6.0;
  static const double _stationaryDriftMeters = 14.0;
  static const double _minMovingSpeedMps = 0.55;
  static const double _maxReasonableJumpMeters = 120.0;
  static const double _minLiveMetricDistanceKm = 0.02;
  static const int _minPaceDurationSeconds = 12;

  // Drives the radar pulse on the location marker, the LIVE dot, and the
  // breathing start button. One controller, reused everywhere for cheapness.
  late final AnimationController _pulse;

  final MapController _mapController = MapController();
  final Distance _distance = const Distance();
  final List<LatLng> _route = [];

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<MagnetometerEvent>? _magnetometerSub;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSub;
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;

  Timer? _timer;
  Timer? _watchdogTimer;
  Timer? _pollTimer;

  DateTime? _startedAt;
  DateTime? _lastLocationAt;
  DateTime? _lastAcceptedRouteAt;
  DateTime? _lastRealMovementAt;
  DateTime? _lastGyroAt;

  int _elapsedSeconds = 0;
  int _movingSeconds = 0;
  bool _tracking = false;
  bool _paused = false;
  bool _gpsReady = false;
  bool _starting = false;
  bool _finishing = false;
  bool _mapMovedOnce = false;

  double? _gpsHeadingDeg;
  double? _magnetometerHeadingDeg;
  double? _gyroHeadingDeg;
  double? _fusedHeadingDeg;
  double _phoneMotion = 0;

  String? _error;
  LatLng? _current;
  _MapStyle _mapStyle = _MapStyle.dark;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _startSensorFusion();
    _prepareGpsPreview();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _positionSub?.cancel();
    _magnetometerSub?.cancel();
    _gyroscopeSub?.cancel();
    _accelerometerSub?.cancel();
    _timer?.cancel();
    _watchdogTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startSensorFusion() {
    _magnetometerSub?.cancel();
    _gyroscopeSub?.cancel();
    _accelerometerSub?.cancel();

    _magnetometerSub = magnetometerEventStream().listen(
      (event) {
        final heading = _headingFromMagnetometer(event);
        if (heading == null) return;

        _magnetometerHeadingDeg = heading;
        _gyroHeadingDeg ??= heading;
        _updateFusedHeading();
      },
      onError: (_) {},
      cancelOnError: false,
    );

    _gyroscopeSub = gyroscopeEventStream().listen(
      (event) {
        final now = DateTime.now();
        final last = _lastGyroAt;
        _lastGyroAt = now;

        if (last == null) return;

        final dt = now.difference(last).inMicroseconds / 1000000.0;
        if (dt <= 0 || dt > 0.25) return;

        // Gyroscope z is radians/second. Convert to degrees and integrate.
        final deltaDeg = event.z * 180 / math.pi * dt;
        final base =
            _gyroHeadingDeg ??
            _fusedHeadingDeg ??
            _gpsHeadingDeg ??
            _magnetometerHeadingDeg ??
            0;
        _gyroHeadingDeg = _normalizeDegrees(base + deltaDeg);
        _updateFusedHeading();
      },
      onError: (_) {},
      cancelOnError: false,
    );

    _accelerometerSub = accelerometerEventStream().listen(
      (event) {
        final magnitude = math.sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        );

        // 9.8 is gravity. Difference gives rough movement shake/acceleration.
        _phoneMotion = (magnitude - 9.80665).abs().clamp(0.0, 12.0);
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  double? _headingFromMagnetometer(MagnetometerEvent event) {
    if (event.x == 0 && event.y == 0) return null;

    // Basic compass heading. It is not perfect indoors but helps when GPS heading is unavailable.
    final radians = math.atan2(event.y, event.x);
    final degrees = radians * 180 / math.pi;
    return _normalizeDegrees(degrees);
  }

  void _updateFusedHeading() {
    final gps = _gpsHeadingDeg;
    final mag = _magnetometerHeadingDeg;
    final gyro = _gyroHeadingDeg;

    double? target;

    // Priority: GPS course when moving, gyro for fast rotation, magnetometer when stopped.
    if (gps != null && (_averageSpeedKmh > 1.2 || _tracking)) {
      target = gps;
    } else if (gyro != null) {
      target = gyro;
    } else {
      target = mag;
    }

    if (target == null) return;

    final current = _fusedHeadingDeg ?? target;

    // More gyro weight when the phone/car is turning; more compass/GPS smoothing when stable.
    final smoothFactor = _phoneMotion > 1.8 ? 0.32 : 0.18;
    _fusedHeadingDeg = _lerpAngle(current, target, smoothFactor);

    if (mounted) setState(() {});
  }

  double _lerpAngle(double from, double to, double t) {
    final delta = ((to - from + 540) % 360) - 180;
    return _normalizeDegrees(from + delta * t);
  }

  double _normalizeDegrees(double value) {
    var out = value % 360;
    if (out < 0) out += 360;
    return out;
  }

  Future<void> _prepareGpsPreview() async {
    final allowed = await _ensureLocationPermission();
    if (!allowed || !mounted) return;

    try {
      final initial = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 12),
      );

      if (!mounted) return;

      final point = LatLng(initial.latitude, initial.longitude);
      _applyGpsHeading(initial);

      setState(() {
        _current = point;
        _gpsReady = true;
        _error = null;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _safeMoveMap(point, zoom: 16.0);
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _gpsReady = true;
        _error =
            'GPS is slow. You can still start; route will update when GPS locks.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gpsReady = true;
        _error = 'GPS preview error: $e';
      });
    }
  }

  Future<void> _startActivity() async {
    if (_starting || _tracking) return;

    setState(() {
      _starting = true;
      _error = null;
    });

    final allowed = await _ensureLocationPermission();
    if (!allowed) {
      if (mounted) setState(() => _starting = false);
      return;
    }

    await _positionSub?.cancel();
    _timer?.cancel();
    _watchdogTimer?.cancel();
    _pollTimer?.cancel();

    try {
      final initial = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 10),
      );

      if (!mounted) return;

      _route.clear();
      _startedAt = DateTime.now();
      _elapsedSeconds = 0;
      _movingSeconds = 0;
      _lastAcceptedRouteAt = null;
      _lastRealMovementAt = null;
      _paused = false;
      _tracking = true;
      _starting = false;
      _lastLocationAt = DateTime.now();

      _addPosition(initial, moveMap: true, force: true);
      _startTimer();
      _startLocationStream();
      _startWatchdog();

      if (mounted) setState(() {});
    } on TimeoutException {
      if (!mounted) return;

      _route.clear();

      if (_current != null) {
        _route.add(_current!);
      }

      _movingSeconds = 0;
      _lastAcceptedRouteAt = null;
      _lastRealMovementAt = null;

      setState(() {
        _startedAt = DateTime.now();
        _elapsedSeconds = 0;
        _paused = false;
        _tracking = true;
        _starting = false;
        _lastLocationAt = DateTime.now();
        _error = 'Started. Waiting for stronger GPS signal...';
      });

      _startTimer();
      _startLocationStream();
      _startWatchdog();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'Could not start activity: $e';
      });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_tracking || _paused) return;

      final now = DateTime.now();
      final movingRecently =
          _lastRealMovementAt != null &&
          now.difference(_lastRealMovementAt!).inSeconds <= 4;

      setState(() {
        _elapsedSeconds++;
        if (movingRecently) {
          _movingSeconds++;
        }
      });
    });
  }

  void _startLocationStream() {
    _positionSub?.cancel();

    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 1,
          ),
        ).listen(
          (pos) {
            if (!_tracking || _paused) return;
            _addPosition(pos, moveMap: true);
          },
          onError: (e) {
            if (!mounted) return;
            setState(() => _error = 'GPS stream error. Trying fallback...');
            _pollCurrentLocation();
          },
          cancelOnError: false,
        );
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _pollTimer?.cancel();

    _watchdogTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!_tracking || _paused) return;

      final last = _lastLocationAt;
      if (last == null) {
        _pollCurrentLocation();
        return;
      }

      final staleSeconds = DateTime.now().difference(last).inSeconds;
      if (staleSeconds >= 12) {
        _pollCurrentLocation();
      }
    });

    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_tracking || _paused) return;
      _pollCurrentLocation();
    });
  }

  Future<void> _pollCurrentLocation() async {
    if (!_tracking || _paused) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 6),
      );

      if (!mounted || !_tracking || _paused) return;
      _addPosition(pos, moveMap: true);
    } catch (_) {
      // Keep UI alive. Do not spam errors.
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() => _error = 'Please turn on GPS/location service.');
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      if (mounted) {
        setState(
          () =>
              _error = 'Location permission is required for activity tracking.',
        );
      }
      return false;
    }

    return true;
  }

  void _addPosition(
    Position position, {
    required bool moveMap,
    bool force = false,
  }) {
    if (!mounted) return;

    final next = LatLng(position.latitude, position.longitude);
    final now = DateTime.now();
    _applyGpsHeading(position);

    // First GPS lock/start point: place the marker, but do not count it as
    // movement. A single point cannot prove the user moved.
    if (force || _route.isEmpty) {
      setState(() {
        _current = next;
        _lastLocationAt = now;

        if (_tracking && _route.isEmpty) {
          _route.add(next);
          _lastAcceptedRouteAt = now;
        }

        _error = null;
      });

      _updateFusedHeading();
      if (moveMap) _safeMoveMap(next);
      return;
    }

    final accuracy = position.accuracy;
    if (accuracy > _maxRouteAccuracyMeters) {
      // Bad indoor GPS can jump several meters while the phone is still.
      // Keep the marker fresh, but do not add distance/calories.
      setState(() {
        _current = next;
        _lastLocationAt = now;
        _error = 'GPS accuracy is weak. Move outdoors for accurate pace.';
      });
      _updateFusedHeading();
      return;
    }

    final meters = _distance(_route.last, next);

    if (meters > _maxReasonableJumpMeters) {
      // Ignore impossible GPS jumps.
      return;
    }

    final lastAccepted = _lastAcceptedRouteAt;
    final dtSeconds = lastAccepted == null
        ? 1.0
        : now.difference(lastAccepted).inMilliseconds / 1000.0;

    final gpsSpeed = position.speed.isFinite && position.speed >= 0
        ? position.speed
        : 0.0;
    final distanceSpeed = dtSeconds > 0 ? meters / dtSeconds : 0.0;
    final bestSpeed = math.max(gpsSpeed, distanceSpeed);

    final looksLikeStationaryDrift =
        meters < _minRouteMoveMeters ||
        (bestSpeed < _minMovingSpeedMps && meters < _stationaryDriftMeters);

    if (looksLikeStationaryDrift) {
      setState(() {
        _current = next;
        _lastLocationAt = now;
        _error = null;
      });
      _updateFusedHeading();
      return;
    }

    setState(() {
      _current = next;
      _lastLocationAt = now;
      _lastAcceptedRouteAt = now;
      _lastRealMovementAt = now;

      if (_tracking) {
        _route.add(next);
      }

      _error = null;
    });

    _updateFusedHeading();

    if (moveMap) {
      _safeMoveMap(next);
    }
  }

  void _applyGpsHeading(Position position) {
    final heading = _cleanHeading(position.heading);
    if (heading == null) return;

    _gpsHeadingDeg = heading;
    _gyroHeadingDeg ??= heading;
    _fusedHeadingDeg ??= heading;
  }

  double? _cleanHeading(double heading) {
    if (heading.isNaN || heading < 0) return null;
    return _normalizeDegrees(heading);
  }

  void _safeMoveMap(LatLng point, {double? zoom}) {
    if (!mounted) return;

    try {
      final currentZoom = _mapController.camera.zoom;
      final targetZoom = zoom ?? (currentZoom < 15 ? 15.6 : currentZoom);
      _mapController.move(point, targetZoom);
      _mapMovedOnce = true;
    } catch (_) {
      if (!_mapMovedOnce) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            try {
              _mapController.move(point, zoom ?? 15.6);
              _mapMovedOnce = true;
            } catch (_) {}
          }
        });
      }
    }
  }

  void _centerOnCurrentLocation() {
    if (_current == null) {
      _prepareGpsPreview();
      return;
    }

    _safeMoveMap(_current!, zoom: 16.4);
  }

  double get _rawDistanceKm => ActivityService.routeDistanceKm(_route);

  // Do not show fake micro-distance from GPS drift as real activity.
  double get _distanceKm =>
      _rawDistanceKm < _minLiveMetricDistanceKm ? 0.0 : _rawDistanceKm;

  int get _metricDurationSeconds => _movingSeconds;

  int get _pace {
    if (_distanceKm <= 0 || _metricDurationSeconds < _minPaceDurationSeconds) {
      return 0;
    }
    return ActivityService.paceSecondsPerKm(
      _distanceKm,
      _metricDurationSeconds,
    );
  }

  double get _averageSpeedKmh {
    if (_distanceKm <= 0 || _metricDurationSeconds <= 0) return 0.0;
    return ActivityService.averageSpeedKmh(_distanceKm, _metricDurationSeconds);
  }

  int get _calories {
    if (_distanceKm <= 0 || _metricDurationSeconds <= 0) return 0;
    return ActivityService.estimateCalories(
      distanceKm: _distanceKm,
      durationSeconds: _metricDurationSeconds,
    );
  }

  int get _xp {
    if (_distanceKm <= 0 || _metricDurationSeconds <= 0) return 0;
    return ActivityService.calculateXp(_distanceKm, _metricDurationSeconds);
  }

  String get _activityLabel {
    final raw = widget.activityType.trim();
    if (raw.isEmpty) return 'Activity';
    return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
  }

  IconData get _activityIcon {
    final type = widget.activityType.toLowerCase();

    if (type.contains('walk')) return Icons.directions_walk_rounded;
    if (type.contains('jog')) return Icons.directions_run_rounded;
    if (type.contains('ride') ||
        type.contains('cycle') ||
        type.contains('bike')) {
      return Icons.directions_bike_rounded;
    }

    return Icons.directions_run_rounded;
  }

  String _duration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;

    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }

    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _paceLabel(int seconds) {
    if (seconds <= 0) return '--';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return "$m'${s.toString().padLeft(2, '0')}\"";
  }

  String get _tileUrl {
    switch (_mapStyle) {
      case _MapStyle.light:
        return 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';
      case _MapStyle.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case _MapStyle.dark:
        return 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
    }
  }

  List<String> get _tileSubdomains {
    switch (_mapStyle) {
      case _MapStyle.satellite:
        return const [];
      case _MapStyle.light:
      case _MapStyle.dark:
        return const ['a', 'b', 'c', 'd'];
    }
  }

  String get _mapStyleLabel {
    switch (_mapStyle) {
      case _MapStyle.dark:
        return 'Dark';
      case _MapStyle.light:
        return 'Light';
      case _MapStyle.satellite:
        return 'Satellite';
    }
  }

  void _togglePause() {
    if (!_tracking) return;
    setState(() => _paused = !_paused);
  }

  Future<bool> _confirmExitIfNeeded() async {
    if (!_tracking || _elapsedSeconds <= 0) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Discard activity?',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          'This activity is already running. Leaving now will discard the current session.',
          style: GoogleFonts.outfit(
            color: soft,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Stay', style: GoogleFonts.outfit(color: soft)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Discard',
              style: GoogleFonts.outfit(
                color: routeOrange,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _finish() async {
    if (!_tracking || _finishing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Finish activity?',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          'Your route, pace, distance and calories will be saved.',
          style: GoogleFonts.outfit(
            color: soft,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: soft)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Finish',
              style: GoogleFonts.outfit(
                color: routeOrange,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _finishing = true);

    await _positionSub?.cancel();
    _timer?.cancel();
    _watchdogTimer?.cancel();
    _pollTimer?.cancel();

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final ended = DateTime.now();

    // Save a compact route instead of the raw GPS stream.
    // Long raw routes make Firestore writes slow and can leave the button stuck
    // on "Saving..." on weak internet. The compact route is still enough for
    // a clean route preview and summary.
    final saveRoute = ActivityService.compactRouteForSave(
      _route,
      maxPoints: 120,
      minDistanceMeters: 5,
    );

    final record = ActivityRecord(
      id: '',
      uid: uid,
      type: widget.activityType,
      distanceKm: _distanceKm,
      durationSeconds: _elapsedSeconds,
      averagePaceSecondsPerKm: _pace,
      averageSpeedKmh: _averageSpeedKmh,
      caloriesBurned: _calories,
      xpEarned: _xp,
      route: saveRoute,
      startedAt: _startedAt ?? ended,
      endedAt: ended,
    );

    String activityId = '';

    try {
      // Queue the Firestore write and go to summary immediately.
      // This prevents the tracker from getting stuck on "Saving..." when
      // the internet is slow. Firestore will sync the pending write in the
      // background when the connection is available.
      activityId = ActivityService.queueActivitySave(record);
    } catch (e) {
      if (!mounted) return;
      setState(() => _finishing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Activity save failed: $e',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _tracking = false;
      _paused = false;
      _finishing = false;
    });

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ActivitySummaryScreen(activityId: activityId, record: record),
      ),
    );
  }

  Widget _mapLoadingOverlay() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.15,
          colors: [Color(0xFF26371A), Color(0xFF10150D), Color(0xFF050705)],
        ),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: card.withOpacity(0.88),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(color: lime, strokeWidth: 2.4),
              ),
              const SizedBox(width: 12),
              Text(
                'Locking GPS...',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fallbackCenter = _current ?? const LatLng(3.1390, 101.6869);

    return WillPopScope(
      onWillPop: _confirmExitIfNeeded,
      child: Scaffold(
        backgroundColor: bg,
        body: Stack(
          children: [
            Positioned.fill(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: fallbackCenter,
                  initialZoom: 15.2,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: _tileUrl,
                    subdomains: _tileSubdomains,
                    userAgentPackageName: 'com.example.nutripulse',
                  ),
                  if (_route.length > 1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _route,
                          strokeWidth: 6,
                          color: _paused ? Colors.orangeAccent : lime,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      if (_current != null)
                        Marker(
                          point: _current!,
                          width: 86,
                          height: 86,
                          child: _directionMarker(),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (!_gpsReady) Positioned.fill(child: _mapLoadingOverlay()),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        bg.withOpacity(
                          _mapStyle == _MapStyle.light ? 0.18 : 0.32,
                        ),
                        Colors.transparent,
                        bg.withOpacity(
                          _mapStyle == _MapStyle.light ? 0.36 : 0.55,
                        ),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _topBar(),
                  _mapTools(),
                  const Spacer(),
                  if (_error != null) _errorBox(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.06),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: _tracking
                          ? _liveHud(key: const ValueKey('live-hud'))
                          : _preStartHud(key: const ValueKey('prestart-hud')),
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

  Widget _directionMarker() {
    final heading =
        (_fusedHeadingDeg ?? _gpsHeadingDeg ?? _magnetometerHeadingDeg ?? 0) *
        math.pi /
        180.0;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = _pulse.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Radar pulse ring — expands and fades, only while live & unpaused.
            if (_tracking && !_paused)
              Opacity(
                opacity: (1.0 - t) * 0.55,
                child: Container(
                  width: 24 + t * 60,
                  height: 24 + t * 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: lime.withOpacity(0.9), width: 2),
                  ),
                ),
              ),
            child!,
          ],
        );
      },
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: markerBlue,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 5),
          boxShadow: [
            BoxShadow(
              color: markerBlue.withOpacity(0.65),
              blurRadius: 20,
              spreadRadius: 3,
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.34),
              blurRadius: 9,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Transform.rotate(
          angle: heading,
          child: const Icon(
            Icons.navigation_rounded,
            color: Colors.white,
            size: 13,
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () async {
              final canLeave = await _confirmExitIfNeeded();
              if (canLeave && mounted) Navigator.pop(context);
            },
            icon: Icon(
              _tracking
                  ? Icons.close_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          Expanded(
            child: Text(
              _tracking
                  ? '${_activityLabel.toUpperCase()} Tracker'
                  : _activityLabel,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _statusPill(),
        ],
      ),
    );
  }

  Widget _statusPill() {
    final live = _tracking && !_paused;
    final Color pillColor = !_tracking
        ? Colors.white.withOpacity(0.10)
        : (_paused ? Colors.orangeAccent : lime);
    final label = !_tracking ? 'READY' : (_paused ? 'PAUSED' : 'LIVE');
    final fg = !_tracking ? Colors.white : Colors.black;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: pillColor,
        borderRadius: BorderRadius.circular(999),
        border: !_tracking
            ? Border.all(color: Colors.white.withOpacity(0.08))
            : null,
        boxShadow: live
            ? [
                BoxShadow(
                  color: lime.withOpacity(0.45),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final s = (math.sin(_pulse.value * 2 * math.pi) + 1) / 2;
                return Container(
                  margin: const EdgeInsets.only(right: 7),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55 + s * 0.45),
                    shape: BoxShape.circle,
                  ),
                );
              },
            ),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: fg,
              fontSize: 12,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapTools() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          const Spacer(),
          Column(
            children: [
              _roundMapButton(
                icon: Icons.layers_rounded,
                badge: _mapStyle == _MapStyle.dark
                    ? 'D'
                    : _mapStyle == _MapStyle.light
                    ? 'L'
                    : 'S',
                onTap: _showMapStyleSheet,
              ),
              const SizedBox(height: 10),
              _roundMapButton(
                icon: Icons.my_location_rounded,
                onTap: _centerOnCurrentLocation,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roundMapButton({
    required IconData icon,
    required VoidCallback onTap,
    String? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.72),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.24),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          if (badge != null)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.4),
                ),
                child: Center(
                  child: Text(
                    badge,
                    style: GoogleFonts.outfit(
                      color: Colors.black,
                      fontSize: 10,
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

  void _showMapStyleSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Map version',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              _mapOptionTile(
                _MapStyle.dark,
                'Dark map',
                Icons.dark_mode_rounded,
              ),
              _mapOptionTile(
                _MapStyle.light,
                'Light map',
                Icons.light_mode_rounded,
              ),
              _mapOptionTile(
                _MapStyle.satellite,
                'Satellite',
                Icons.satellite_alt_rounded,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _mapOptionTile(_MapStyle style, String title, IconData icon) {
    final selected = _mapStyle == style;

    return GestureDetector(
      onTap: () {
        setState(() => _mapStyle = style);
        Navigator.pop(context);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? lime : Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? lime : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? Colors.black : Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.outfit(
                  color: selected ? Colors.black : Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: Colors.black),
          ],
        ),
      ),
    );
  }

  Widget _errorBox() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.redAccent.withOpacity(0.24)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_rounded, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // NEW UNIFIED FROSTED-GLASS HUD
  // ---------------------------------------------------------------------------

  /// Reusable frosted-glass surface. Map shows through softly.
  Widget _glass({Key? key, required Widget child, double radius = 30}) {
    return ClipRRect(
      key: key,
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.42),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.38),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  /// Live HUD: hero PACE + secondary stats + pause/finish, all one glass module.
  Widget _liveHud({Key? key}) {
    return _glass(
      key: key,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Hero: live pace
            Text(
              'PACE  /KM',
              style: GoogleFonts.outfit(
                color: soft,
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.94, end: 1).animate(anim),
                  child: child,
                ),
              ),
              child: Text(
                _paceLabel(_pace),
                key: ValueKey(_paceLabel(_pace)),
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 72,
                  height: 0.95,
                  letterSpacing: -2.5,
                  fontWeight: FontWeight.w900,
                  shadows: [
                    Shadow(color: lime.withOpacity(0.25), blurRadius: 24),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            // Secondary stats row
            Row(
              children: [
                _hudStat('TIME', _duration(_elapsedSeconds)),
                _hudDivider(),
                _hudStat('DISTANCE', '${_distanceKm.toStringAsFixed(2)} km'),
                _hudDivider(),
                _hudStat('KCAL', '$_calories'),
              ],
            ),
            const SizedBox(height: 18),
            // Controls
            Row(
              children: [
                Expanded(
                  child: _hudButton(
                    label: _paused ? 'Resume' : 'Pause',
                    icon: _paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    bgColor: Colors.white.withOpacity(0.12),
                    fgColor: Colors.white,
                    onTap: _togglePause,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _hudButton(
                    label: _finishing ? 'Saving...' : 'Finish',
                    icon: Icons.flag_rounded,
                    bgColor: lime,
                    fgColor: Colors.black,
                    onTap: _finish,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hudStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Text(
              value,
              key: ValueKey(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 19,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 10.5,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hudDivider() => Container(
    width: 1,
    height: 30,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: Colors.white.withOpacity(0.10),
  );

  Widget _hudButton({
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color fgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 54,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fgColor, size: 20),
            const SizedBox(width: 7),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: fgColor,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pre-start HUD: activity label + breathing start button.
  Widget _preStartHud({Key? key}) {
    return _glass(
      key: key,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: routeOrange.withOpacity(0.18),
                    shape: BoxShape.circle,
                    border: Border.all(color: routeOrange.withOpacity(0.4)),
                  ),
                  child: Icon(_activityIcon, color: routeOrange, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _activityLabel,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 20,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _gpsReady
                            ? 'GPS ready • tap to start'
                            : 'Locking GPS...',
                        style: GoogleFonts.outfit(
                          color: soft,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _glassRoundButton(
                  icon: Icons.my_location_rounded,
                  onTap: _centerOnCurrentLocation,
                ),
              ],
            ),
            const SizedBox(height: 22),
            // Breathing start button
            GestureDetector(
              onTap: _startActivity,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  final s = (math.sin(_pulse.value * 2 * math.pi) + 1) / 2;
                  return Container(
                    width: double.infinity,
                    height: 64,
                    decoration: BoxDecoration(
                      color: routeOrange,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: routeOrange.withOpacity(0.30 + s * 0.25),
                          blurRadius: 22 + s * 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: child,
                  );
                },
                child: Center(
                  child: _starting
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Start ${_activityLabel}',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassRoundButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
