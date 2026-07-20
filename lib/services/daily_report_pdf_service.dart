import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class DailyReportData {
  const DailyReportData({
    required this.date,
    required this.name,
    required this.goal,
    required this.targetCalories,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.sugar,
    required this.activityBurned,
    required this.steps,
    required this.waterLiters,
    required this.activityDistanceKm,
    required this.activityDurationSeconds,
    required this.foodNames,
  });

  final DateTime date;
  final String name;
  final String goal;
  final int targetCalories;
  final int calories;
  final double protein;
  final double carbs;
  final double fat;
  final double sugar;
  final int activityBurned;
  final int steps;
  final double waterLiters;
  final double activityDistanceKm;
  final int activityDurationSeconds;
  final List<String> foodNames;

  int get netCalories => (calories - activityBurned).clamp(0, 999999);
  int get remainingCalories =>
      (targetCalories - netCalories).clamp(-999999, 999999);
  double get calorieProgress =>
      targetCalories <= 0 ? 0 : (netCalories / targetCalories).clamp(0.0, 1.0);
}

class DailyReportPdfService {
  DailyReportPdfService._();

  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String dateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  static Future<DailyReportData> loadReport({DateTime? date}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not logged in');
    }

    final selectedDate = date ?? DateTime.now();
    final key = dateKey(selectedDate);

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final profile = userDoc.data() ?? {};

    final mealDoc = await _db
        .collection('users')
        .doc(user.uid)
        .collection('meals')
        .doc(key)
        .get();

    final meal = mealDoc.data() ?? {};

    final activityDoc = await _db
        .collection('users')
        .doc(user.uid)
        .collection('activity')
        .doc(key)
        .get();

    final activity = activityDoc.data() ?? {};

    final summaryDoc = await _db
        .collection('users')
        .doc(user.uid)
        .collection('daily_summary')
        .doc(key)
        .get();

    final summary = summaryDoc.data() ?? {};

    final start = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final end = start.add(const Duration(days: 1));

    final runSnap = await _db
        .collection('users')
        .doc(user.uid)
        .collection('activities')
        .where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('startedAt', isLessThan: Timestamp.fromDate(end))
        .get();

    int activityBurned = _safeInt(meal['activityBurnedCalories']);
    double distanceKm = 0;
    int durationSeconds = 0;

    for (final doc in runSnap.docs) {
      final data = doc.data();
      activityBurned += _safeInt(data['caloriesBurned']);
      distanceKm += _safeDouble(data['distanceKm']);
      durationSeconds += _safeInt(data['durationSeconds']);
    }

    final entriesSnap = await _db
        .collection('users')
        .doc(user.uid)
        .collection('meals')
        .doc(key)
        .collection('entries')
        .orderBy('timestamp', descending: true)
        .limit(8)
        .get();

    final names = entriesSnap.docs
        .map((doc) {
          final data = doc.data();
          return (data['name'] ?? data['foodName'] ?? data['label'] ?? 'Food')
              .toString();
        })
        .where((e) => e.trim().isNotEmpty)
        .toList();

    return DailyReportData(
      date: selectedDate,
      name:
          (profile['name'] ??
                  profile['username'] ??
                  user.displayName ??
                  'NutriPulse User')
              .toString(),
      goal: (profile['goal'] ?? 'Stay consistent').toString(),
      targetCalories: _safeInt(
        profile['targetCalories'],
        fallback: 2000,
      ).clamp(1, 10000),
      calories: _safeInt(meal['calories']),
      protein: _safeDouble(meal['protein']),
      carbs: _safeDouble(meal['carbs']),
      fat: _safeDouble(meal['fat']),
      sugar: _safeDouble(meal['sugar']),
      activityBurned: activityBurned,
      steps: _safeInt(activity['steps']),
      waterLiters: _safeDouble(summary['waterLiters']),
      activityDistanceKm: distanceKm,
      activityDurationSeconds: durationSeconds,
      foodNames: names,
    );
  }

  static Future<void> sharePdf(DailyReportData data) async {
    final bytes = await buildPdf(data);
    final filename = 'nutripulse_daily_report_${dateKey(data.date)}.pdf';

    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  static Future<Uint8List> buildPdf(DailyReportData data) async {
    final pdf = pw.Document();
    final dateLabel = DateFormat('EEE, d MMM yyyy').format(data.date);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          return [
            _header(data, dateLabel),
            pw.SizedBox(height: 18),
            _summaryGrid(data),
            pw.SizedBox(height: 18),
            _sectionTitle('Nutrition'),
            _metricTable([
              ['Calories eaten', '${data.calories} kcal'],
              ['Activity burned', '${data.activityBurned} kcal'],
              ['Net calories', '${data.netCalories} kcal'],
              ['Remaining', '${data.remainingCalories} kcal'],
              ['Protein', '${data.protein.toStringAsFixed(0)} g'],
              ['Carbs', '${data.carbs.toStringAsFixed(0)} g'],
              ['Fat', '${data.fat.toStringAsFixed(0)} g'],
              ['Sugar', '${data.sugar.toStringAsFixed(0)} g'],
            ]),
            pw.SizedBox(height: 16),
            _sectionTitle('Activity & Wellness'),
            _metricTable([
              ['Steps', '${data.steps} steps'],
              ['Water', '${data.waterLiters.toStringAsFixed(1)} L'],
              ['Distance', '${data.activityDistanceKm.toStringAsFixed(2)} km'],
              ['Duration', _duration(data.activityDurationSeconds)],
              ['Goal', data.goal],
            ]),
            if (data.foodNames.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              _sectionTitle('Logged Food'),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: data.foodNames
                    .map(
                      (food) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 5),
                        child: pw.Text('• $food'),
                      ),
                    )
                    .toList(),
              ),
            ],
            pw.SizedBox(height: 18),
            _insightBox(data),
            pw.SizedBox(height: 24),
            pw.Text(
              'Generated by NutriPulse',
              style: pw.TextStyle(color: PdfColors.grey600, fontSize: 10),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _header(DailyReportData data, String dateLabel) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#10150D'),
        borderRadius: pw.BorderRadius.circular(18),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'NutriPulse Daily Report',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  dateLabel,
                  style: const pw.TextStyle(
                    color: PdfColors.grey300,
                    fontSize: 12,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  data.name,
                  style: const pw.TextStyle(
                    color: PdfColors.grey200,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#D6FF60'),
              borderRadius: pw.BorderRadius.circular(999),
            ),
            child: pw.Text(
              '${(data.calorieProgress * 100).round()}% goal',
              style: pw.TextStyle(
                color: PdfColors.black,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryGrid(DailyReportData data) {
    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _summaryCard('Calories', '${data.netCalories}', 'net kcal'),
        _summaryCard('Protein', data.protein.toStringAsFixed(0), 'grams'),
        _summaryCard('Steps', '${data.steps}', 'completed'),
        _summaryCard('Water', data.waterLiters.toStringAsFixed(1), 'litres'),
      ],
    );
  }

  static pw.Widget _summaryCard(String title, String value, String unit) {
    return pw.Container(
      width: 122,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(14),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(title, style: const pw.TextStyle(fontSize: 11)),
          pw.Text(
            unit,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  static pw.Widget _sectionTitle(String title) {
    return pw.Text(
      title,
      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
    );
  }

  static pw.Widget _metricTable(List<List<String>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.4),
        1: pw.FlexColumnWidth(1),
      },
      children: rows.map((row) {
        return pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(row[0], style: const pw.TextStyle(fontSize: 11)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                row[1],
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  static pw.Widget _insightBox(DailyReportData data) {
    String insight =
        'Good progress. Keep logging your meals and activity daily.';

    if (data.calories == 0) {
      insight =
          'No meals were logged today. Add meals to make tomorrow’s report more accurate.';
    } else if (data.remainingCalories < 0) {
      insight =
          'You passed your calorie target today. Balance tomorrow with lean protein and lighter meals.';
    } else if (data.protein < 80) {
      insight =
          'Protein looks low today. Try chicken breast, eggs, tuna, tofu, tempeh or Greek yogurt.';
    } else if (data.steps < 5000) {
      insight =
          'Steps are low today. A short evening walk can improve your activity score.';
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F1FFD0'),
        borderRadius: pw.BorderRadius.circular(14),
      ),
      child: pw.Text(
        'AI Insight: $insight',
        style: const pw.TextStyle(fontSize: 12),
      ),
    );
  }

  static int _safeInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static double _safeDouble(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static String _duration(int seconds) {
    if (seconds <= 0) return '0 min';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m} min';
  }
}
