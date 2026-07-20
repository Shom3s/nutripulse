import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HealthCalendarDiaryScreen extends StatefulWidget {
  const HealthCalendarDiaryScreen({super.key});

  @override
  State<HealthCalendarDiaryScreen> createState() =>
      _HealthCalendarDiaryScreenState();
}

class _HealthCalendarDiaryScreenState extends State<HealthCalendarDiaryScreen> {
  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color soft = Color(0xFFB7C2A8);
  static const Color surface = Color(0xFF141A11);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _noteCtrl = TextEditingController();

  late DateTime _focusedMonth;
  late DateTime _selectedDate;

  String _mood = 'Motivated';
  String _energy = 'Good';
  String _sleepQuality = 'Okay';
  String _aiReflection = '';
  bool _saving = false;
  String? _loadedJournalKey;

  final List<String> _moods = const [
    'Happy',
    'Motivated',
    'Calm',
    'Tired',
    'Stressed',
  ];

  final List<String> _energies = const ['Low', 'Okay', 'Good', 'High'];

  final List<String> _sleepOptions = const ['Poor', 'Okay', 'Good', 'Great'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _focusedMonth = DateTime(now.year, now.month);
    _loadJournalForSelectedDate();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  int _safeInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _safeDouble(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _safeString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  Future<void> _loadJournalForSelectedDate() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final key = _dateKey(_selectedDate);
    _loadedJournalKey = key;

    try {
      final doc = await _db
          .collection('users')
          .doc(user.uid)
          .collection('daily_journal')
          .doc(key)
          .get()
          .timeout(const Duration(seconds: 6));

      final data = doc.data() ?? {};
      if (!mounted || _loadedJournalKey != key) return;

      setState(() {
        _mood = _safeString(data['mood'], fallback: 'Motivated');
        _energy = _safeString(data['energy'], fallback: 'Good');
        _sleepQuality = _safeString(data['sleepQuality'], fallback: 'Okay');
        _aiReflection = _safeString(data['aiReflection']);
        _noteCtrl.text = _safeString(data['note']);
      });
    } catch (_) {
      if (!mounted || _loadedJournalKey != key) return;
      setState(() {
        _mood = 'Motivated';
        _energy = 'Good';
        _sleepQuality = 'Okay';
        _aiReflection = '';
        _noteCtrl.clear();
      });
    }
  }

  int _firstPositiveInt(List<dynamic> values, {int fallback = 0}) {
    for (final value in values) {
      final parsed = _safeInt(value, fallback: fallback);
      if (parsed > 0) return parsed;
    }
    return fallback;
  }

  double _firstPositiveDouble(List<dynamic> values, {double fallback = 0}) {
    for (final value in values) {
      final parsed = _safeDouble(value, fallback: fallback);
      if (parsed > 0) return parsed;
    }
    return fallback;
  }

  int _caloriesFrom(Map<String, dynamic> meal, Map<String, dynamic> summary) {
    return _firstPositiveInt([
      meal['calories'],
      meal['totalCalories'],
      meal['kcal'],
      meal['todayCalories'],
      summary['calories'],
      summary['totalCalories'],
      summary['todayCalories'],
      summary['mealCalories'],
    ]);
  }

  double _proteinFrom(Map<String, dynamic> meal, Map<String, dynamic> summary) {
    return _firstPositiveDouble([
      meal['protein'],
      meal['proteinGrams'],
      meal['totalProtein'],
      summary['protein'],
      summary['proteinGrams'],
      summary['totalProtein'],
    ]);
  }

  double _carbsFrom(Map<String, dynamic> meal, Map<String, dynamic> summary) {
    return _firstPositiveDouble([
      meal['carbs'],
      meal['carbohydrates'],
      meal['carbsGrams'],
      meal['totalCarbs'],
      summary['carbs'],
      summary['carbohydrates'],
      summary['carbsGrams'],
      summary['totalCarbs'],
    ]);
  }

  double _fatFrom(Map<String, dynamic> meal, Map<String, dynamic> summary) {
    return _firstPositiveDouble([
      meal['fat'],
      meal['fats'],
      meal['fatGrams'],
      meal['totalFat'],
      summary['fat'],
      summary['fats'],
      summary['fatGrams'],
      summary['totalFat'],
    ]);
  }

  int _stepsFrom(Map<String, dynamic> activity, Map<String, dynamic> summary) {
    return _firstPositiveInt([
      activity['steps'],
      activity['todaySteps'],
      summary['steps'],
      summary['todaySteps'],
    ]);
  }

  double _waterFrom(Map<String, dynamic> summary) {
    return _firstPositiveDouble([
      summary['waterLiters'],
      summary['water'],
      summary['waterIntake'],
      summary['currentWaterLiters'],
      summary['liters'],
    ]);
  }

  Map<String, dynamic> _combineDailySummary({
    required Map<String, dynamic> meal,
    required Map<String, dynamic> activity,
    required Map<String, dynamic> summary,
    required Map<String, dynamic> journal,
  }) {
    return {
      'calories': _caloriesFrom(meal, summary),
      'protein': _proteinFrom(meal, summary),
      'carbs': _carbsFrom(meal, summary),
      'fat': _fatFrom(meal, summary),
      'steps': _stepsFrom(activity, summary),
      'waterLiters': _waterFrom(summary),
      'mood': _safeString(journal['mood'], fallback: _mood),
      'energy': _safeString(journal['energy'], fallback: _energy),
      'sleepQuality': _safeString(
        journal['sleepQuality'],
        fallback: _sleepQuality,
      ),
      'note': _safeString(journal['note']),
      'aiReflection': _safeString(journal['aiReflection']),
    };
  }

  Stream<Map<String, dynamic>> _dailySummaryStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream<Map<String, dynamic>>.value({});

    final key = _dateKey(_selectedDate);
    final userRef = _db.collection('users').doc(user.uid);

    late final StreamController<Map<String, dynamic>> controller;
    final docs = <String, Map<String, dynamic>>{
      'meal': <String, dynamic>{},
      'activity': <String, dynamic>{},
      'summary': <String, dynamic>{},
      'journal': <String, dynamic>{},
    };
    final subscriptions =
        <StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>[];

    void emit() {
      if (controller.isClosed) return;
      controller.add(
        _combineDailySummary(
          meal: docs['meal'] ?? <String, dynamic>{},
          activity: docs['activity'] ?? <String, dynamic>{},
          summary: docs['summary'] ?? <String, dynamic>{},
          journal: docs['journal'] ?? <String, dynamic>{},
        ),
      );
    }

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> listenDoc({
      required String name,
      required CollectionReference<Map<String, dynamic>> collection,
    }) {
      return collection.doc(key).snapshots().listen((snapshot) {
        docs[name] = snapshot.data() ?? <String, dynamic>{};
        emit();
      }, onError: (_) => emit());
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        subscriptions.addAll([
          listenDoc(name: 'meal', collection: userRef.collection('meals')),
          listenDoc(
            name: 'activity',
            collection: userRef.collection('activity'),
          ),
          listenDoc(
            name: 'summary',
            collection: userRef.collection('daily_summary'),
          ),
          listenDoc(
            name: 'journal',
            collection: userRef.collection('daily_journal'),
          ),
        ]);
        emit();
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );

    return controller.stream;
  }

  Stream<Map<String, Map<String, dynamic>>> _monthMarkersStream() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream<Map<String, Map<String, dynamic>>>.value({});
    }

    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final nextMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
    final daysInMonth = nextMonth.subtract(const Duration(days: 1)).day;
    final startKey = _dateKey(firstDay);
    final endKey = _dateKey(nextMonth);
    final userRef = _db.collection('users').doc(user.uid);

    late final StreamController<Map<String, Map<String, dynamic>>> controller;
    final mealDocs = <String, Map<String, dynamic>>{};
    final activityDocs = <String, Map<String, dynamic>>{};
    final summaryDocs = <String, Map<String, dynamic>>{};
    final journalDocs = <String, Map<String, dynamic>>{};
    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    Map<String, Map<String, dynamic>> emptyResult() {
      final result = <String, Map<String, dynamic>>{};
      for (int day = 1; day <= daysInMonth; day++) {
        final key = _dateKey(
          DateTime(_focusedMonth.year, _focusedMonth.month, day),
        );
        result[key] = {
          'food': false,
          'water': false,
          'steps': false,
          'diary': false,
        };
      }
      return result;
    }

    void emit() {
      if (controller.isClosed) return;

      final result = emptyResult();
      for (final key in result.keys) {
        final meal = mealDocs[key] ?? <String, dynamic>{};
        final activity = activityDocs[key] ?? <String, dynamic>{};
        final summary = summaryDocs[key] ?? <String, dynamic>{};
        final journal = journalDocs[key] ?? <String, dynamic>{};

        result[key] = {
          'food': _caloriesFrom(meal, summary) > 0,
          'steps': _stepsFrom(activity, summary) > 0,
          'water': _waterFrom(summary) > 0,
          'diary': journal.isNotEmpty,
        };
      }

      controller.add(result);
    }

    Query<Map<String, dynamic>> monthQuery(
      CollectionReference<Map<String, dynamic>> collection,
    ) {
      return collection
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: startKey)
          .where(FieldPath.documentId, isLessThan: endKey);
    }

    StreamSubscription<QuerySnapshot<Map<String, dynamic>>> listenCollection({
      required CollectionReference<Map<String, dynamic>> collection,
      required Map<String, Map<String, dynamic>> target,
    }) {
      return monthQuery(collection).snapshots().listen((snapshot) {
        target
          ..clear()
          ..addEntries(
            snapshot.docs.map((doc) => MapEntry(doc.id, doc.data())),
          );
        emit();
      }, onError: (_) => emit());
    }

    controller = StreamController<Map<String, Map<String, dynamic>>>(
      onListen: () {
        subscriptions.addAll([
          listenCollection(
            collection: userRef.collection('meals'),
            target: mealDocs,
          ),
          listenCollection(
            collection: userRef.collection('activity'),
            target: activityDocs,
          ),
          listenCollection(
            collection: userRef.collection('daily_summary'),
            target: summaryDocs,
          ),
          listenCollection(
            collection: userRef.collection('daily_journal'),
            target: journalDocs,
          ),
        ]);
        emit();
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );

    return controller.stream;
  }

  String _monthTitle(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _selectedDateTitle() {
    const months = [
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
    return '${_selectedDate.day} ${months[_selectedDate.month - 1]} ${_selectedDate.year}';
  }

  String _formatNumber(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
      buffer.write(text[i]);
    }
    return buffer.toString();
  }

  void _changeMonth(int offset) {
    setState(() {
      _focusedMonth = DateTime(
        _focusedMonth.year,
        _focusedMonth.month + offset,
      );
      final lastDay = DateTime(
        _focusedMonth.year,
        _focusedMonth.month + 1,
        0,
      ).day;
      final safeDay = _selectedDate.day.clamp(1, lastDay).toInt();
      _selectedDate = DateTime(
        _focusedMonth.year,
        _focusedMonth.month,
        safeDay,
      );
    });
    _loadJournalForSelectedDate();
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
      _focusedMonth = DateTime(date.year, date.month);
    });
    _loadJournalForSelectedDate();
  }

  String _buildReflection(Map<String, dynamic> summary) {
    final calories = _safeInt(summary['calories']);
    final protein = _safeDouble(summary['protein']);
    final steps = _safeInt(summary['steps']);
    final water = _safeDouble(summary['waterLiters']);
    final note = _noteCtrl.text.trim();

    final positives = <String>[];
    final improve = <String>[];

    if (calories > 0) positives.add('you logged your food');
    if (protein >= 80) positives.add('protein intake looks strong');
    if (steps >= 8000) positives.add('your activity level was solid');
    if (water >= 3.0) positives.add('hydration goal was completed');
    if (note.isNotEmpty) positives.add('you reflected on your day');

    if (calories == 0) improve.add('log at least one meal');
    if (protein > 0 && protein < 80) improve.add('add more protein tomorrow');
    if (steps > 0 && steps < 8000)
      improve.add('increase walking or light movement');
    if (water > 0 && water < 3.0)
      improve.add('drink more water earlier in the day');
    if (_energy == 'Low' || _mood == 'Tired' || _mood == 'Stressed') {
      improve.add('prioritize rest and a lighter routine');
    }

    final positiveText = positives.isEmpty
        ? 'You have not logged much health data for this date yet'
        : 'Good progress: ${positives.join(', ')}';

    final improveText = improve.isEmpty
        ? 'Keep this pattern consistent tomorrow.'
        : 'Next step: ${improve.take(2).join(' and ')}.';

    return '$positiveText. Mood: $_mood, energy: $_energy, sleep quality: $_sleepQuality. $improveText';
  }

  Future<void> _saveJournal(Map<String, dynamic> summary) async {
    final user = _auth.currentUser;
    if (user == null || _saving) return;

    setState(() => _saving = true);

    final key = _dateKey(_selectedDate);
    final reflection = _buildReflection(summary);

    try {
      await _db
          .collection('users')
          .doc(user.uid)
          .collection('daily_journal')
          .doc(key)
          .set({
            'date': key,
            'mood': _mood,
            'energy': _energy,
            'sleepQuality': _sleepQuality,
            'note': _noteCtrl.text.trim(),
            'aiReflection': reflection,
            'summarySnapshot': {
              'calories': _safeInt(summary['calories']),
              'protein': _safeDouble(summary['protein']),
              'steps': _safeInt(summary['steps']),
              'waterLiters': _safeDouble(summary['waterLiters']),
            },
            'updatedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      setState(() {
        _saving = false;
        _aiReflection = reflection;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Diary saved for $_selectedDateTitle()',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
          ),
          backgroundColor: card,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save diary: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
            colors: [Color(0xFF263719), Color(0xFF0F140D), Color(0xFF070907)],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<Map<String, dynamic>>(
            key: ValueKey('daily-summary-${_dateKey(_selectedDate)}'),
            stream: _dailySummaryStream(),
            builder: (context, snapshot) {
              final summary = snapshot.data ?? {};
              final loading =
                  snapshot.connectionState == ConnectionState.waiting;

              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _header()),
                  SliverToBoxAdapter(child: _calendarCard()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: _dailySummaryCard(summary, loading),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: _diaryEditor(summary),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                      child: _aiReflectionCard(summary),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: card.withOpacity(0.9),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.07)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Health Calendar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 31,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Daily diary, mood and progress history',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.74),
                    fontSize: 12.5,
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

  Widget _calendarCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: _boxDecoration(),
        child: Column(
          children: [
            Row(
              children: [
                _monthButton(
                  Icons.chevron_left_rounded,
                  () => _changeMonth(-1),
                ),
                Expanded(
                  child: Text(
                    _monthTitle(_focusedMonth),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                _monthButton(
                  Icons.chevron_right_rounded,
                  () => _changeMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((day) {
                return Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.58),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            StreamBuilder<Map<String, Map<String, dynamic>>>(
              key: ValueKey(
                'markers-${_focusedMonth.year}-${_focusedMonth.month}',
              ),
              stream: _monthMarkersStream(),
              builder: (context, snapshot) {
                final markers = snapshot.data ?? {};
                return _calendarGrid(markers);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.065),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.055)),
        ),
        child: Icon(icon, color: Colors.white, size: 23),
      ),
    );
  }

  Widget _calendarGrid(Map<String, Map<String, dynamic>> markers) {
    final first = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final startOffset = first.weekday - 1;
    final start = first.subtract(Duration(days: startOffset));
    final today = DateTime.now();

    return Column(
      children: List.generate(6, (week) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            children: List.generate(7, (day) {
              final date = start.add(Duration(days: (week * 7) + day));
              final key = _dateKey(date);
              final inMonth = date.month == _focusedMonth.month;
              final selected = _sameDay(date, _selectedDate);
              final isToday = _sameDay(date, today);
              final marker = markers[key] ?? {};
              final markerCount = [
                'food',
                'water',
                'steps',
                'diary',
              ].where((m) => marker[m] == true).length;

              return Expanded(
                child: GestureDetector(
                  onTap: () => _selectDate(date),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    height: 48,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: selected
                          ? lime
                          : isToday
                          ? lime.withOpacity(0.10)
                          : Colors.white.withOpacity(0.035),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: selected
                            ? lime
                            : isToday
                            ? lime.withOpacity(0.22)
                            : Colors.white.withOpacity(0.035),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${date.day}',
                          style: GoogleFonts.outfit(
                            color: selected
                                ? Colors.black
                                : inMonth
                                ? Colors.white
                                : Colors.white.withOpacity(0.28),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (i) {
                            final active = i < markerCount;
                            return Container(
                              width: 4.5,
                              height: 4.5,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 1.3,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? Colors.black.withOpacity(
                                        active ? 0.50 : 0.12,
                                      )
                                    : active
                                    ? lime.withOpacity(inMonth ? 0.95 : 0.30)
                                    : Colors.white.withOpacity(0.10),
                                shape: BoxShape.circle,
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  Widget _dailySummaryCard(Map<String, dynamic> summary, bool loading) {
    final calories = _safeInt(summary['calories']);
    final protein = _safeDouble(summary['protein']);
    final steps = _safeInt(summary['steps']);
    final water = _safeDouble(summary['waterLiters']);
    final score = _dailyScore(summary);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedDateTitle(),
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.35,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      loading
                          ? 'Loading health summary...'
                          : 'Food, water, steps and diary overview',
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.70),
                        fontSize: 12.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 62,
                height: 62,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: score / 100,
                        strokeWidth: 7,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.white.withOpacity(0.08),
                        valueColor: const AlwaysStoppedAnimation<Color>(lime),
                      ),
                    ),
                    Text(
                      '$score',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
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
              _summaryMetric(
                'Calories',
                '$calories',
                'kcal',
                Icons.local_fire_department_rounded,
              ),
              const SizedBox(width: 10),
              _summaryMetric(
                'Protein',
                protein.toStringAsFixed(0),
                'g',
                Icons.fitness_center_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _summaryMetric(
                'Steps',
                _formatNumber(steps),
                '',
                Icons.directions_walk_rounded,
              ),
              const SizedBox(width: 10),
              _summaryMetric(
                'Water',
                water.toStringAsFixed(water % 1 == 0 ? 0 : 1),
                'L',
                Icons.water_drop_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _dailyScore(Map<String, dynamic> summary) {
    var score = 0;
    if (_safeInt(summary['calories']) > 0) score += 25;
    if (_safeDouble(summary['protein']) >= 80) score += 25;
    if (_safeInt(summary['steps']) >= 8000) score += 25;
    if (_safeDouble(summary['waterLiters']) >= 3.0) score += 15;
    if (_noteCtrl.text.trim().isNotEmpty || _aiReflection.isNotEmpty)
      score += 10;
    return score.clamp(0, 100).toInt();
  }

  Widget _summaryMetric(
    String label,
    String value,
    String unit,
    IconData icon,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.052),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.045)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: lime.withOpacity(0.13),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: lime, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value$unit',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: soft.withOpacity(0.64),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
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

  Widget _diaryEditor(Map<String, dynamic> summary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.edit_note_rounded,
            title: 'Daily Diary',
            subtitle: 'Record how your body and mind felt today',
          ),
          const SizedBox(height: 16),
          _choiceSection('Mood', _moods, _mood, (value) {
            setState(() => _mood = value);
          }),
          const SizedBox(height: 15),
          _choiceSection('Energy', _energies, _energy, (value) {
            setState(() => _energy = value);
          }),
          const SizedBox(height: 15),
          _choiceSection('Sleep quality', _sleepOptions, _sleepQuality, (
            value,
          ) {
            setState(() => _sleepQuality = value);
          }),
          const SizedBox(height: 18),
          Text(
            'Notes',
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            minLines: 4,
            maxLines: 7,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 14.2,
              fontWeight: FontWeight.w600,
              height: 1.32,
            ),
            decoration: InputDecoration(
              hintText:
                  'Example: Felt strong today, but protein was low. Need to sleep earlier tonight.',
              hintStyle: GoogleFonts.outfit(
                color: soft.withOpacity(0.45),
                fontSize: 13.3,
                fontWeight: FontWeight.w600,
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.052),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: lime.withOpacity(0.42),
                  width: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : () => _saveJournal(summary),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.black,
                        strokeWidth: 2.2,
                      ),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(
                _saving ? 'Saving...' : 'Save Diary & Generate Reflection',
                style: GoogleFonts.outfit(
                  fontSize: 14.8,
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: lime,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(19),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _choiceSection(
    String label,
    List<String> values,
    String selected,
    ValueChanged<String> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            color: soft,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values.map((value) {
            final isSelected = selected == value;
            return GestureDetector(
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 190),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? lime : Colors.white.withOpacity(0.055),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSelected ? lime : Colors.white.withOpacity(0.055),
                  ),
                ),
                child: Text(
                  value,
                  style: GoogleFonts.outfit(
                    color: isSelected ? Colors.black : soft.withOpacity(0.86),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _aiReflectionCard(Map<String, dynamic> summary) {
    final reflection = _aiReflection.trim().isNotEmpty
        ? _aiReflection
        : _buildReflection(summary);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: lime.withOpacity(0.095),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: lime.withOpacity(0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.psychology_rounded,
            title: 'AI Daily Reflection',
            subtitle: 'Personal advice based on your health data and diary',
            iconColor: lime,
          ),
          const SizedBox(height: 14),
          Text(
            reflection,
            style: GoogleFonts.outfit(
              color: Colors.white.withOpacity(0.86),
              fontSize: 13.6,
              height: 1.38,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    Color iconColor = lime,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.13),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: iconColor, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: soft.withOpacity(0.66),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      color: surface.withOpacity(0.96),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.30),
          blurRadius: 22,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }
}
