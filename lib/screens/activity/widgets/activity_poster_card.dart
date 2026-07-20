import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

class ActivityPosterCard extends StatelessWidget {
  const ActivityPosterCard({
    super.key,
    required this.distanceKm,
    required this.durationSeconds,
    required this.paceSecondsPerKm,
    required this.caloriesBurned,
    required this.xpEarned,
    required this.route,
    this.title = 'NutriPulse Run',
  });

  final double distanceKm;
  final int durationSeconds;
  final int paceSecondsPerKm;
  final int caloriesBurned;
  final int xpEarned;
  final List<LatLng> route;
  final String title;

  static const Color lime = Color(0xFFD6FF60);
  static const Color routeOrange = Color(0xFFFF5A1F);
  static const Color bg = Color(0xFF0F140D);
  static const Color card = Color(0xFF1A1F17);
  static const Color soft = Color(0xFFB7C2A8);

  String _duration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return h > 0
        ? '${h}h ${m.toString().padLeft(2, '0')}m'
        : '$m:${s.toString().padLeft(2, '0')}';
  }

  String _pace(int seconds) {
    if (seconds <= 0) return '--';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m\'${s.toString().padLeft(2, '0')}" /km';
  }

  List<LatLng> get _cleanRoute {
    if (route.length < 2) return const [];
    final cleaned = <LatLng>[route.first];
    final distance = const Distance();
    for (final point in route.skip(1)) {
      final gap = distance(cleaned.last, point);
      if (gap < 1.0) continue;
      if (gap > 120) continue;
      cleaned.add(point);
    }
    return cleaned;
  }

  LatLng get _fallbackCenter =>
      route.isNotEmpty ? route.last : const LatLng(3.1390, 101.6869);

  @override
  Widget build(BuildContext context) {
    final points = _cleanRoute;
    final hasRealRoute = points.length >= 2 && distanceKm >= 0.03;
    final bounds = hasRealRoute ? LatLngBounds.fromPoints(points) : null;

    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(34),
            child: Stack(
              children: [
                Positioned.fill(
                  child: _RealMapPreview(
                    route: hasRealRoute ? points : const [],
                    center: _fallbackCenter,
                    bounds: bounds,
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          bg.withOpacity(0.08),
                          bg.withOpacity(0.10),
                          bg.withOpacity(0.84),
                        ],
                        stops: const [0.0, 0.42, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  top: 22,
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: lime,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: lime.withOpacity(0.45),
                              blurRadius: 16,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.directions_run_rounded,
                          color: Colors.black,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 19,
                                height: 1,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                                shadows: const [
                                  Shadow(color: Colors.black54, blurRadius: 10),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'NUTRIPULSE',
                              style: GoogleFonts.outfit(
                                color: lime,
                                fontSize: 10,
                                letterSpacing: 2.5,
                                fontWeight: FontWeight.w900,
                                shadows: const [
                                  Shadow(color: Colors.black54, blurRadius: 8),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!hasRealRoute)
                  Positioned(
                    left: 22,
                    right: 22,
                    top: 86,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.46),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Text(
                        'Route preview appears after a longer GPS track.',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 22,
                  right: 22,
                  bottom: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            distanceKm.toStringAsFixed(2),
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 52,
                              height: 0.92,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -2.5,
                              shadows: const [
                                Shadow(color: Colors.black87, blurRadius: 14),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              'KM',
                              style: GoogleFonts.outfit(
                                color: lime,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                shadows: const [
                                  Shadow(color: Colors.black87, blurRadius: 10),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _stat('Time', _duration(durationSeconds)),
                          const SizedBox(width: 10),
                          _stat('Pace', _pace(paceSecondsPerKm)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _stat('Kcal', '$caloriesBurned'),
                          const SizedBox(width: 10),
                          _stat('XP', '+$xpEarned'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            color: lime.withOpacity(0.9),
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Tracked with NutriPulse',
                            style: GoogleFonts.outfit(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 10.5,
                              letterSpacing: 0.3,
                              fontWeight: FontWeight.w700,
                              shadows: const [
                                Shadow(color: Colors.black87, blurRadius: 8),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: card.withOpacity(0.82),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: lime,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: soft,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RealMapPreview extends StatelessWidget {
  const _RealMapPreview({
    required this.route,
    required this.center,
    required this.bounds,
  });

  final List<LatLng> route;
  final LatLng center;
  final LatLngBounds? bounds;

  static const Color routeOrange = Color(0xFFFF5A1F);

  @override
  Widget build(BuildContext context) {
    final options = bounds == null
        ? MapOptions(
            initialCenter: center,
            initialZoom: 17,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          )
        : MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: bounds!,
              padding: const EdgeInsets.fromLTRB(34, 82, 34, 150),
            ),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          );

    return FlutterMap(
      options: options,
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.example.nutripulse',
        ),
        if (route.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: route,
                strokeWidth: 6,
                color: Colors.black.withOpacity(0.42),
              ),
              Polyline(points: route, strokeWidth: 3.5, color: routeOrange),
            ],
          ),
        if (route.isNotEmpty)
          MarkerLayer(
            markers: [
              Marker(
                point: route.first,
                width: 16,
                height: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: routeOrange, width: 3),
                  ),
                ),
              ),
              Marker(
                point: route.last,
                width: 18,
                height: 18,
                child: Container(
                  decoration: BoxDecoration(
                    color: routeOrange,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
