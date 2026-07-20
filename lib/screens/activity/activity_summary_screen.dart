import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/activity_record.dart';
import '../../services/community_service.dart';
import 'widgets/activity_poster_card.dart';

class ActivitySummaryScreen extends StatefulWidget {
  const ActivitySummaryScreen({
    super.key,
    required this.activityId,
    required this.record,
  });

  final String activityId;
  final ActivityRecord record;

  @override
  State<ActivitySummaryScreen> createState() => _ActivitySummaryScreenState();
}

class _ActivitySummaryScreenState extends State<ActivitySummaryScreen> {
  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color soft = Color(0xFFB7C2A8);
  static const Color card = Color(0xFF1A1F17);

  final GlobalKey _posterKey = GlobalKey();
  bool _sharing = false;
  bool _posting = false;

  String _duration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0)
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _pace(int seconds) {
    if (seconds <= 0) return '--';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return "$m'${s.toString().padLeft(2, '0')}\\\" /km";
  }

  Future<Uint8List> _capturePoster() async {
    final boundary =
        _posterKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw Exception('Could not export poster.');
    return data.buffer.asUint8List();
  }

  Future<void> _shareExternal() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await _capturePoster();
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/nutripulse_run_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            'My NutriPulse activity: ${widget.record.distanceKm.toStringAsFixed(2)} km 🏃',
      );
    } catch (e) {
      if (!mounted) return;
      _snack('Share failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareCommunity() async {
    if (_posting) return;
    setState(() => _posting = true);
    try {
      final bytes = await _capturePoster();
      final posterBase64 = base64Encode(bytes);
      await CommunityService.createActivityPost(
        activityId: widget.activityId,
        posterBase64: posterBase64,
        distanceKm: widget.record.distanceKm,
        durationSeconds: widget.record.durationSeconds,
        paceSecondsPerKm: widget.record.averagePaceSecondsPerKm,
        caloriesBurned: widget.record.caloriesBurned,
        xp: widget.record.xpEarned,
        caption:
            'Completed a ${widget.record.distanceKm.toStringAsFixed(2)} km ${widget.record.type} 🏃 • Pace ${_pace(widget.record.averagePaceSecondsPerKm)} • +${widget.record.xpEarned} XP',
      );
      if (!mounted) return;
      _snack('Shared to Community feed');
    } catch (e) {
      if (!mounted) return;
      _snack('Community share failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        backgroundColor: error ? Colors.redAccent : card,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    return Scaffold(
      backgroundColor: bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.18,
            colors: [Color(0xFF253618), Color(0xFF10150D), Color(0xFF070907)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _topBar(),
                const SizedBox(height: 8),
                _rise(0, _achievementHeader(r)),
                const SizedBox(height: 18),
                _rise(
                  1,
                  RepaintBoundary(
                    key: _posterKey,
                    child: ActivityPosterCard(
                      distanceKm: r.distanceKm,
                      durationSeconds: r.durationSeconds,
                      paceSecondsPerKm: r.averagePaceSecondsPerKm,
                      caloriesBurned: r.caloriesBurned,
                      xpEarned: r.xpEarned,
                      route: r.route,
                      title: 'NutriPulse ${r.type.toUpperCase()}',
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _rise(2, _statsGrid(r)),
                const SizedBox(height: 18),
                _rise(
                  3,
                  _actionButton(
                    label: _posting ? 'Sharing...' : 'Share to Community',
                    icon: Icons.groups_rounded,
                    bgColor: lime,
                    fgColor: Colors.black,
                    onTap: _posting ? null : _shareCommunity,
                  ),
                ),
                const SizedBox(height: 10),
                _rise(
                  4,
                  _actionButton(
                    label: _sharing
                        ? 'Preparing...'
                        : 'Share Poster Externally',
                    icon: Icons.ios_share_rounded,
                    bgColor: Colors.white.withOpacity(0.08),
                    fgColor: Colors.white,
                    onTap: _sharing ? null : _shareExternal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Staggered fade-rise entrance. [order] delays each child slightly.
  Widget _rise(int order, Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 480 + order * 90),
      curve: Curves.easeOutCubic,
      builder: (context, t, c) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 22 * (1 - t)), child: c),
      ),
      child: child,
    );
  }

  Widget _achievementHeader(ActivityRecord r) {
    final headline = r.distanceKm >= 5
        ? 'Outstanding run!'
        : r.distanceKm >= 2
        ? 'Great work!'
        : 'Nice one!';
    return _glass(
      radius: 26,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: lime.withOpacity(0.16),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: lime.withOpacity(0.4)),
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                color: lime,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 20,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${r.type[0].toUpperCase()}${r.type.substring(1)} • ${r.distanceKm.toStringAsFixed(2)} km completed',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: soft,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '+${r.xpEarned}',
                  style: GoogleFonts.outfit(
                    color: lime,
                    fontSize: 26,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                Text(
                  'XP',
                  style: GoogleFonts.outfit(
                    color: soft,
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Frosted-glass surface matching the live activity screen.
  Widget _glass({required Widget child, double radius = 26}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.38),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _topBar() => Row(
    children: [
      IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
      Expanded(
        child: Text(
          'Activity Summary',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 25,
            height: 1,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.7,
          ),
        ),
      ),
    ],
  );

  Widget _statsGrid(ActivityRecord r) => _glass(
    radius: 26,
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        children: [
          Row(
            children: [
              _stat('Distance', '${r.distanceKm.toStringAsFixed(2)} km'),
              const SizedBox(width: 10),
              _stat('Duration', _duration(r.durationSeconds)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _stat('Pace', _pace(r.averagePaceSecondsPerKm)),
              const SizedBox(width: 10),
              _stat('Calories', '${r.caloriesBurned} kcal'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _stat('Speed', '${r.averageSpeedKmh.toStringAsFixed(1)} km/h'),
              const SizedBox(width: 10),
              _stat('XP Earned', '+${r.xpEarned} XP'),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _stat(String label, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
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
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color fgColor,
    required VoidCallback? onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: onTap == null ? 0.65 : 1,
      child: Container(
        height: 55,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fgColor, size: 20),
            const SizedBox(width: 8),
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
    ),
  );
}
