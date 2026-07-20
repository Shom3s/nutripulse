import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/activity_record.dart';
import '../../services/activity_service.dart';
import 'activity_summary_screen.dart';
import 'live_activity_screen.dart';

class ActivityHomeScreen extends StatefulWidget {
  const ActivityHomeScreen({super.key});

  @override
  State<ActivityHomeScreen> createState() => _ActivityHomeScreenState();
}

class _ActivityHomeScreenState extends State<ActivityHomeScreen>
    with AutomaticKeepAliveClientMixin<ActivityHomeScreen> {
  static const Color lime = Color(0xFFD6FF60);
  static const Color soft = Color(0xFFB7C2A8);
  static const Color card = Color(0xFF1A1F17);

  DateTime _selectedDate = DateTime.now();
  String _filter = 'all';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _activitiesStream;
  List<ActivityRecord> _cachedRecords = const [];
  bool _hasActivitySnapshot = false;
  bool _playEntranceAnimations = true;
  Timer? _entranceTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _activitiesStream = ActivityService.recentActivitiesStream();

    // Keep the first premium entrance animation, then stop replaying it on
    // every Firestore snapshot/filter/date change. This is what makes the
    // screen feel smooth while still keeping the same design and sections.
    _entranceTimer = Timer(const Duration(milliseconds: 1250), () {
      if (!mounted) return;
      setState(() => _playEntranceAnimations = false);
    });
  }

  @override
  void dispose() {
    _entranceTimer?.cancel();
    super.dispose();
  }

  void _start(BuildContext context, String type) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 340),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, animation, __) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: LiveActivityScreen(activityType: type),
          );
        },
      ),
    );
  }

  void _openSummary(ActivityRecord activity) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: ActivitySummaryScreen(
              activityId: activity.id,
              record: activity,
            ),
          );
        },
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _weekday(DateTime d) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[d.weekday - 1];
  }

  String _month(DateTime d) {
    const labels = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return labels[d.month - 1];
  }

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
    return '$m\'${s.toString().padLeft(2, '0')}"';
  }

  List<ActivityRecord> _recordsFrom(QuerySnapshot<Map<String, dynamic>>? snap) {
    return (snap?.docs ?? [])
        .map((d) => ActivityRecord.fromFirestore(d))
        .toList();
  }

  List<ActivityRecord> _filteredRecords(List<ActivityRecord> records) {
    if (_filter == 'all') return records;
    return records.where((a) => a.type.toLowerCase() == _filter).toList();
  }

  List<ActivityRecord> _recordsForSelectedDay(List<ActivityRecord> records) {
    return _filteredRecords(
      records,
    ).where((a) => _sameDay(a.startedAt, _selectedDate)).toList();
  }

  List<ActivityRecord> _recordsThisWeek(List<ActivityRecord> records) {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final end = start.add(const Duration(days: 7));
    return records
        .where(
          (a) =>
              a.startedAt.isAfter(start.subtract(const Duration(seconds: 1))) &&
              a.startedAt.isBefore(end),
        )
        .toList();
  }

  List<ActivityRecord> _recordsThisMonth(List<ActivityRecord> records) {
    final now = DateTime.now();
    return records
        .where(
          (a) => a.startedAt.year == now.year && a.startedAt.month == now.month,
        )
        .toList();
  }

  int _activityStreak(List<ActivityRecord> records) {
    if (records.isEmpty) return 0;
    final activeDays = records
        .map(
          (a) => DateTime(a.startedAt.year, a.startedAt.month, a.startedAt.day),
        )
        .toSet();

    var streak = 0;
    var cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);

    while (activeDays.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _activitiesStream,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _cachedRecords = _recordsFrom(snapshot.data);
          _hasActivitySnapshot = true;
        }

        // Use the last good snapshot while Firestore reconnects or while the
        // user switches between dashboard tabs. This prevents the activity
        // screen from flashing empty/loading and rebuilding heavy widgets.
        final records = _hasActivitySnapshot
            ? _cachedRecords
            : _recordsFrom(snapshot.data);
        final selectedRecords = _recordsForSelectedDay(records);
        final filteredAll = _filteredRecords(records);
        final weeklyRecords = _recordsThisWeek(filteredAll);
        final monthlyRecords = _recordsThisMonth(filteredAll);

        final dayDistance = selectedRecords.fold<double>(
          0,
          (sum, a) => sum + a.distanceKm,
        );
        final dayCalories = selectedRecords.fold<int>(
          0,
          (sum, a) => sum + a.caloriesBurned,
        );
        final dayDuration = selectedRecords.fold<int>(
          0,
          (sum, a) => sum + a.durationSeconds,
        );

        final weeklyDistance = weeklyRecords.fold<double>(
          0,
          (sum, a) => sum + a.distanceKm,
        );
        final weeklyCalories = weeklyRecords.fold<int>(
          0,
          (sum, a) => sum + a.caloriesBurned,
        );
        final monthlyDistance = monthlyRecords.fold<double>(
          0,
          (sum, a) => sum + a.distanceKm,
        );

        return SingleChildScrollView(
          key: const PageStorageKey('activity-home-full-layout'),
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 126),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 22),
              _rise(0, _heroCard(context)),
              const SizedBox(height: 14),
              _rise(1, _activityModes(context)),
              const SizedBox(height: 14),
              _rise(2, _filterChips()),
              const SizedBox(height: 16),
              _rise(3, _weeklyGoalProgress(weeklyDistance, weeklyCalories)),
              const SizedBox(height: 16),
              _rise(4, _calendarSection(filteredAll)),
              const SizedBox(height: 16),
              _rise(
                5,
                _dailySummary(
                  distanceKm: dayDistance,
                  calories: dayCalories,
                  durationSeconds: dayDuration,
                  count: selectedRecords.length,
                ),
              ),
              const SizedBox(height: 16),
              _rise(6, _weeklyDistanceChart(filteredAll)),
              const SizedBox(height: 16),
              _rise(
                7,
                _monthlyOverview(monthlyRecords.length, monthlyDistance),
              ),
              const SizedBox(height: 16),
              _rise(8, _personalBest(filteredAll)),
              const SizedBox(height: 16),
              _rise(9, _achievementBadges(records)),
              const SizedBox(height: 18),
              _selectedDayActivities(selectedRecords, snapshot.connectionState),
            ],
          ),
        );
      },
    );
  }

  /// Staggered fade-rise entrance for each section.
  /// After the first paint, return the child directly so Firestore updates,
  /// filter taps and date taps do not replay expensive animations.
  Widget _rise(int order, Widget child) {
    if (!_playEntranceAnimations) {
      return RepaintBoundary(child: child);
    }

    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 360 + order * 45),
        curve: Curves.easeOutCubic,
        builder: (context, t, c) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: c),
        ),
        child: child,
      ),
    );
  }

  Widget _header() {
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Run Tracker',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 36,
            height: 0.95,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Calendar, routes, pace and activity history',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(
            color: soft.withOpacity(0.76),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    if (!_playEntranceAnimations) {
      return RepaintBoundary(child: header);
    }

    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: Opacity(opacity: t, child: child),
        ),
        child: header,
      ),
    );
  }

  Widget _heroCard(BuildContext context) {
    return GestureDetector(
      onTap: () => _start(context, 'run'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFD6FF60), Color(0xFFAEE63B)],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: lime.withOpacity(0.28),
              blurRadius: 28,
              spreadRadius: -6,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'OUTDOOR ACTIVITY',
                      style: GoogleFonts.outfit(
                        color: Colors.black,
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ready to move?',
                    style: GoogleFonts.outfit(
                      color: Colors.black,
                      fontSize: 26,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Live route, pace & a shareable poster',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: Colors.black.withOpacity(0.62),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: lime,
                size: 36,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activityModes(BuildContext context) {
    final modes = [
      ('run', Icons.directions_run_rounded, 'Run'),
      ('jog', Icons.directions_run_rounded, 'Jog'),
      ('walk', Icons.directions_walk_rounded, 'Walk'),
    ];

    return Row(
      children: modes.map((m) {
        final isLast = m == modes.last;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 10),
            child: GestureDetector(
              onTap: () => _start(context, m.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  vertical: 15,
                  horizontal: 10,
                ),
                decoration: BoxDecoration(
                  color: card.withOpacity(0.82),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withOpacity(0.055)),
                ),
                child: Column(
                  children: [
                    Icon(m.$2, color: lime, size: 25),
                    const SizedBox(height: 8),
                    Text(
                      m.$3,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _filterChips() {
    final filters = [
      ('all', 'All'),
      ('run', 'Run'),
      ('jog', 'Jog'),
      ('walk', 'Walk'),
    ];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (context, index) {
          final f = filters[index];
          final selected = _filter == f.$1;

          return GestureDetector(
            onTap: () => setState(() => _filter = f.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: selected ? lime : Colors.white.withOpacity(0.075),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? lime : Colors.white.withOpacity(0.06),
                ),
              ),
              child: Center(
                child: Text(
                  f.$2,
                  style: GoogleFonts.outfit(
                    color: selected ? Colors.black : Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _weeklyGoalProgress(double weeklyDistance, int weeklyCalories) {
    const goalKm = 15.0;
    final progress = (weeklyDistance / goalKm).clamp(0.0, 1.0);
    final remaining = (goalKm - weeklyDistance).clamp(0, goalKm);

    return _glass(
      glow: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(
              icon: Icons.flag_rounded,
              title: 'Weekly Goal',
              subtitle:
                  '${weeklyDistance.toStringAsFixed(1)} / ${goalKm.toStringAsFixed(0)} km completed',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Animated circular ring
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: _playEntranceAnimations
                      ? const Duration(milliseconds: 760)
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) {
                    return SizedBox(
                      width: 104,
                      height: 104,
                      child: CustomPaint(
                        painter: _GoalRingPainter(
                          progress: value,
                          track: Colors.white.withOpacity(0.09),
                          color: lime,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(value * 100).round()}%',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 22,
                                  height: 1,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'of goal',
                                style: GoogleFonts.outfit(
                                  color: soft.withOpacity(0.7),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    children: [
                      _smallGoalMetric(
                        'Remaining',
                        '${remaining.toStringAsFixed(1)} km',
                      ),
                      const SizedBox(height: 10),
                      _smallGoalMetric('Burned', '$weeklyCalories kcal'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _calendarSection(List<ActivityRecord> records) {
    final today = DateTime.now();
    final days = List.generate(14, (i) {
      return DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(Duration(days: 13 - i));
    });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.calendar_month_rounded,
            title: 'Activity Calendar',
            subtitle:
                '${_month(_selectedDate)} ${_selectedDate.day}, ${_selectedDate.year}',
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final d = days[index];
                final selected = _sameDay(d, _selectedDate);
                final dayRecords = records
                    .where((a) => _sameDay(a.startedAt, d))
                    .toList();
                final hasData = dayRecords.isNotEmpty;
                final totalKm = dayRecords.fold<double>(
                  0,
                  (sum, a) => sum + a.distanceKm,
                );

                return GestureDetector(
                  onTap: () => setState(() => _selectedDate = d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: 60,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? lime
                          : Colors.white.withOpacity(hasData ? 0.075 : 0.045),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? lime
                            : hasData
                            ? lime.withOpacity(0.24)
                            : Colors.white.withOpacity(0.05),
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: lime.withOpacity(0.18),
                                blurRadius: 16,
                                spreadRadius: -5,
                                offset: const Offset(0, 7),
                              ),
                            ]
                          : [],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _weekday(d),
                          style: GoogleFonts.outfit(
                            color: selected ? Colors.black : soft,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${d.day}',
                          style: GoogleFonts.outfit(
                            color: selected ? Colors.black : Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasData ? '${totalKm.toStringAsFixed(1)}k' : '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: selected
                                ? Colors.black.withOpacity(0.75)
                                : hasData
                                ? lime
                                : soft.withOpacity(0.35),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _dailySummary({
    required double distanceKm,
    required int calories,
    required int durationSeconds,
    required int count,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.insights_rounded,
            title: 'Daily Summary',
            subtitle: count == 0
                ? 'No activity for selected day'
                : '$count activity${count == 1 ? '' : 'ies'} completed',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _metricTile(
                'Distance',
                distanceKm.toStringAsFixed(2),
                'km',
                Icons.straighten_rounded,
              ),
              const SizedBox(width: 10),
              _metricTile(
                'Calories',
                '$calories',
                'kcal',
                Icons.local_fire_department_rounded,
              ),
              const SizedBox(width: 10),
              _metricTile(
                'Time',
                _duration(durationSeconds),
                '',
                Icons.timer_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weeklyDistanceChart(List<ActivityRecord> records) {
    final today = DateTime.now();
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: today.weekday - 1));
    final days = List.generate(7, (i) => start.add(Duration(days: i)));

    final values = days.map((d) {
      return records
          .where((a) => _sameDay(a.startedAt, d))
          .fold<double>(0, (sum, a) => sum + a.distanceKm);
    }).toList();

    final maxValue = values.fold<double>(1, (max, v) => v > max ? v : max);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.bar_chart_rounded,
            title: 'Weekly Distance',
            subtitle: 'Distance trend for this week',
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 132,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final value = values[i];
                final height = (value / maxValue).clamp(0.06, 1.0) * 84;
                final isToday = _sameDay(days[i], DateTime.now());
                final hasValue = value > 0.01;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (hasValue)
                          Text(
                            value.toStringAsFixed(1),
                            style: GoogleFonts.outfit(
                              color: isToday ? lime : soft,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        const SizedBox(height: 5),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: height),
                          duration: _playEntranceAnimations
                              ? Duration(milliseconds: 420 + i * 35)
                              : Duration.zero,
                          curve: Curves.easeOutCubic,
                          builder: (context, h, _) => Container(
                            height: h,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: isToday
                                    ? [lime.withOpacity(0.6), lime]
                                    : [
                                        lime.withOpacity(0.18),
                                        lime.withOpacity(0.5),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _weekday(days[i]).substring(0, 1),
                          style: GoogleFonts.outfit(
                            color: isToday ? lime : soft,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthlyOverview(int count, double distanceKm) {
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
              color: lime.withOpacity(0.13),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.calendar_view_month_rounded,
              color: lime,
              size: 25,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This Month',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$count activities • ${distanceKm.toStringAsFixed(1)} km',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.76),
                    fontSize: 12,
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

  Widget _personalBest(List<ActivityRecord> records) {
    ActivityRecord? longest;
    ActivityRecord? fastest;

    for (final a in records) {
      if (longest == null || a.distanceKm > longest.distanceKm) longest = a;
      if (a.averagePaceSecondsPerKm > 0 &&
          (fastest == null ||
              a.averagePaceSecondsPerKm < fastest.averagePaceSecondsPerKm)) {
        fastest = a;
      }
    }

    final bestDistance = longest == null
        ? '0.00 km'
        : '${longest.distanceKm.toStringAsFixed(2)} km';
    final bestPace = fastest == null
        ? '--'
        : '${_pace(fastest.averagePaceSecondsPerKm)} /km';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.emoji_events_rounded,
            title: 'Personal Best',
            subtitle: 'Your strongest activity records',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _metricTile(
                'Longest',
                bestDistance.replaceAll(' km', ''),
                'km',
                Icons.route_rounded,
              ),
              const SizedBox(width: 10),
              _metricTile(
                'Best Pace',
                bestPace.replaceAll(' /km', ''),
                '/km',
                Icons.speed_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _achievementBadges(List<ActivityRecord> records) {
    final totalKm = records.fold<double>(0, (sum, a) => sum + a.distanceKm);
    final totalCal = records.fold<int>(0, (sum, a) => sum + a.caloriesBurned);
    final streak = _activityStreak(records);

    final badges = [
      _Badge('First Run', Icons.flag_rounded, records.isNotEmpty),
      _Badge('5KM Club', Icons.route_rounded, totalKm >= 5),
      _Badge(
        'Calorie Burner',
        Icons.local_fire_department_rounded,
        totalCal >= 500,
      ),
      _Badge('3-Day Streak', Icons.bolt_rounded, streak >= 3),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.workspace_premium_rounded,
            title: 'Badges',
            subtitle: 'Achievements unlocked from activities',
          ),
          const SizedBox(height: 14),
          Row(
            children: badges.map((b) {
              final isLast = b == badges.last;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: isLast ? 0 : 8),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: b.unlocked ? 1 : 0.38,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 6,
                      ),
                      decoration: BoxDecoration(
                        color: b.unlocked
                            ? lime.withOpacity(0.12)
                            : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: b.unlocked
                              ? lime.withOpacity(0.24)
                              : Colors.white.withOpacity(0.05),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            b.icon,
                            color: b.unlocked ? lime : soft,
                            size: 20,
                          ),
                          const SizedBox(height: 7),
                          Text(
                            b.title,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              color: b.unlocked ? Colors.white : soft,
                              fontSize: 10.2,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _selectedDayActivities(
    List<ActivityRecord> activities,
    ConnectionState state,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Activities',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.35,
          ),
        ),
        const SizedBox(height: 12),
        if (state == ConnectionState.waiting &&
            activities.isEmpty &&
            !_hasActivitySnapshot)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: CircularProgressIndicator(color: lime),
            ),
          )
        else if (activities.isEmpty)
          _emptyState()
        else
          ...activities.map(_activityTile),
      ],
    );
  }

  Widget _activityTile(ActivityRecord a) {
    return GestureDetector(
      onTap: () => _openSummary(a),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: _box(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: lime),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 47,
                          height: 47,
                          decoration: BoxDecoration(
                            color: lime.withOpacity(0.13),
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: const Icon(
                            Icons.route_rounded,
                            color: lime,
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${a.type.toUpperCase()} • ${a.distanceKm.toStringAsFixed(2)} km',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${_duration(a.durationSeconds)} • ${_pace(a.averagePaceSecondsPerKm)} /km • ${a.caloriesBurned} kcal',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: soft,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '+${a.xpEarned} XP',
                              style: GoogleFonts.outfit(
                                color: lime,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: soft.withOpacity(0.70),
                              size: 13,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _box(),
      child: Column(
        children: [
          Icon(
            Icons.directions_run_rounded,
            color: lime.withOpacity(0.85),
            size: 38,
          ),
          const SizedBox(height: 10),
          Text(
            'No activities on this day',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Start a run, jog or walk to fill your calendar.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Icon(icon, color: lime, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: soft.withOpacity(0.72),
                  fontSize: 11.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _smallGoalMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                color: soft,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: lime,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTile(String label, String value, String unit, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            Icon(icon, color: lime, size: 19),
            const SizedBox(height: 9),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(
                unit,
                style: GoogleFonts.outfit(
                  color: soft.withOpacity(0.72),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: soft.withOpacity(0.75),
                fontSize: 10.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Wraps any card child in a frosted-glass surface (map/background shows through).
  Widget _glass({
    required Widget child,
    double radius = 26,
    bool glow = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: card.withOpacity(glow ? 0.55 : 0.42),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withOpacity(glow ? 0.12 : 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(glow ? 0.22 : 0.14),
                blurRadius: glow ? 24 : 14,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  BoxDecoration _box({bool glow = false}) {
    return BoxDecoration(
      color: card.withOpacity(0.84),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Colors.white.withOpacity(0.055)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(glow ? 0.18 : 0.12),
          blurRadius: glow ? 22 : 14,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }
}

class _Badge {
  const _Badge(this.title, this.icon, this.unlocked);

  final String title;
  final IconData icon;
  final bool unlocked;
}

class _GoalRingPainter extends CustomPainter {
  _GoalRingPainter({
    required this.progress,
    required this.track,
    required this.color,
  });

  final double progress;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    final sweep = 2 * math.pi * progress;
    final progressPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + sweep,
        colors: [color.withOpacity(0.55), color],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -math.pi / 2, sweep, false, progressPaint);

    // Glow dot at the leading edge.
    final dotAngle = -math.pi / 2 + sweep;
    final dot = Offset(
      center.dx + radius * math.cos(dotAngle),
      center.dy + radius * math.sin(dotAngle),
    );
    canvas.drawCircle(dot, stroke / 2 + 1, Paint()..color = color);
    canvas.drawCircle(
      dot,
      stroke / 2 + 5,
      Paint()..color = color.withOpacity(0.25),
    );
  }

  @override
  bool shouldRepaint(_GoalRingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}
