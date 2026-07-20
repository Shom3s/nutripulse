import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class DailyReportDetailScreen extends StatefulWidget {
  const DailyReportDetailScreen({
    super.key,
    this.reportDate = '',
    this.title = '',
    this.body = '',
  });

  // Keep these optional so the screen works from both places:
  // 1) Dashboard: const DailyReportDetailScreen()
  // 2) Notification center: DailyReportDetailScreen(reportDate: ...)
  final String reportDate;
  final String title;
  final String body;

  @override
  State<DailyReportDetailScreen> createState() =>
      _DailyReportDetailScreenState();
}

class _DailyReportDetailScreenState extends State<DailyReportDetailScreen> {
  static const Color bg = Color(0xFF0F140D);
  static const Color card = Color(0xFF1A1F17);
  static const Color card2 = Color(0xFF23291F);
  static const Color lime = Color(0xFFD6FF60);
  static const Color soft = Color(0xFFB7C2A8);

  DateTime _selectedDate = DateTime.now();
  late Future<_DailyMedicalReport> _reportFuture;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _selectedDate =
        _parseInitialReportDate(widget.reportDate) ?? DateTime.now();
    _reportFuture = _loadReport(_selectedDate);
  }

  DateTime? _parseInitialReportDate(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return null;

    try {
      return DateTime.parse(clean);
    } catch (_) {}

    final formats = <DateFormat>[
      DateFormat('yyyy-MM-dd'),
      DateFormat('dd/MM/yyyy'),
      DateFormat('MM/dd/yyyy'),
    ];

    for (final format in formats) {
      try {
        return format.parseStrict(clean);
      } catch (_) {}
    }

    return null;
  }

  void _reload() {
    setState(() => _reportFuture = _loadReport(_selectedDate));
  }

  String _dateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
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

  DateTime? _readTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  Future<_DailyMedicalReport> _loadReport(DateTime date) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not logged in');
    }

    final uid = user.uid;
    final dateKey = _dateKey(date);
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    final results = await Future.wait<dynamic>([
      userRef.get(),
      userRef.collection('meals').doc(dateKey).get(),
      userRef
          .collection('meals')
          .doc(dateKey)
          .collection('entries')
          .orderBy('timestamp', descending: true)
          .limit(40)
          .get(),
      userRef.collection('activity').doc(dateKey).get(),
      userRef.collection('daily_summary').doc(dateKey).get(),
      userRef.collection('daily_journal').doc(dateKey).get(),
      userRef
          .collection('health_scans')
          .where('dateKey', isEqualTo: dateKey)
          .limit(8)
          .get(),
      _todayActivityBurnedCalories(uid, date),
    ]);

    final userSnap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final mealSnap = results[1] as DocumentSnapshot<Map<String, dynamic>>;
    final entriesSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;
    final activitySnap = results[3] as DocumentSnapshot<Map<String, dynamic>>;
    final summarySnap = results[4] as DocumentSnapshot<Map<String, dynamic>>;
    final journalSnap = results[5] as DocumentSnapshot<Map<String, dynamic>>;
    final healthSnap = results[6] as QuerySnapshot<Map<String, dynamic>>;
    final activityBurnedFromRuns = results[7] as int;

    final userData = userSnap.data() ?? {};
    final mealData = mealSnap.data() ?? {};
    final activityData = activitySnap.data() ?? {};
    final summaryData = summarySnap.data() ?? {};
    final journalData = journalSnap.data() ?? {};

    final entries = entriesSnap.docs.map((doc) {
      final data = doc.data();
      return _MealLine(
        name: _safeString(
          data['foodName'] ?? data['name'] ?? data['mealName'],
          fallback: 'Food item',
        ),
        mealType: _safeString(data['mealType'], fallback: 'meal'),
        calories: _safeDouble(data['calories']),
        protein: _safeDouble(data['protein']),
        carbs: _safeDouble(data['carbs']),
        fat: _safeDouble(data['fat']),
        sugar: _safeDouble(data['sugar']),
        fibre: _safeDouble(data['fibre'] ?? data['fiber']),
        timestamp: _readTimestamp(data['timestamp'] ?? data['createdAt']),
      );
    }).toList();

    final healthDocs = healthSnap.docs.toList();
    healthDocs.sort((a, b) {
      final ad =
          _readTimestamp(a.data()['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bd =
          _readTimestamp(b.data()['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    _HealthLine? health;
    if (healthDocs.isNotEmpty) {
      final data = healthDocs.first.data();
      final bpm = _safeDouble(data['avgBpm'] ?? data['bpm']);
      final temp = _safeDouble(data['temperature']);
      health = _HealthLine(
        bpm: bpm,
        minBpm: _safeDouble(data['minBpm'], fallback: bpm),
        maxBpm: _safeDouble(data['maxBpm'], fallback: bpm),
        temperature: temp,
        status: _safeString(data['status'], fallback: _healthStatus(bpm, temp)),
        recommendation: _safeString(
          data['recommendation'],
          fallback: _healthRecommendation(bpm, temp),
        ),
        recordedAt: _readTimestamp(data['createdAt']),
      );
    }

    final targetCalories = _safeDouble(
      userData['targetCalories'],
      fallback: 2000,
    ).clamp(1, 10000).toDouble();
    final calories = _safeDouble(mealData['calories']);
    final protein = _safeDouble(mealData['protein']);
    final carbs = _safeDouble(mealData['carbs']);
    final fat = _safeDouble(mealData['fat']);
    final sugar = entries.isNotEmpty
        ? entries.fold<double>(0, (sum, e) => sum + e.sugar)
        : _safeDouble(mealData['sugar']);
    final fibre = entries.isNotEmpty
        ? entries.fold<double>(0, (sum, e) => sum + e.fibre)
        : _safeDouble(mealData['fibre'] ?? mealData['fiber']);

    final activityBurned = math
        .max(
          activityBurnedFromRuns,
          _safeInt(mealData['activityBurnedCalories']),
        )
        .toInt();
    final netCalories = math.max(0, calories.round() - activityBurned);

    final report = _DailyMedicalReport(
      uid: uid,
      patientName: _safeString(
        userData['name'] ?? user.displayName,
        fallback: 'NutriPulse User',
      ),
      email: _safeString(user.email, fallback: 'Not available'),
      goal: _safeString(userData['goal'], fallback: 'Eat healthy'),
      heightCm: _safeDouble(userData['heightCm']),
      weightKg: _safeDouble(userData['weightKg']),
      date: date,
      dateKey: dateKey,
      generatedAt: DateTime.now(),
      targetCalories: targetCalories,
      calories: calories,
      netCalories: netCalories.toDouble(),
      remainingCalories: math
          .max(0, targetCalories.round() - netCalories)
          .toDouble(),
      activityBurnedCalories: activityBurned,
      protein: protein,
      proteinGoal: _safeDouble(
        userData['proteinGoal'] ?? userData['proteinGrams'],
        fallback: 120,
      ),
      carbs: carbs,
      carbsGoal: _safeDouble(
        userData['carbsGoal'] ?? userData['carbsGrams'],
        fallback: 250,
      ),
      fat: fat,
      fatGoal: _safeDouble(
        userData['fatGoal'] ?? userData['fatsGrams'],
        fallback: 70,
      ),
      sugar: sugar,
      fibre: fibre,
      steps: _safeInt(activityData['steps']),
      stepGoal: _safeInt(userData['stepGoal'], fallback: 8000),
      waterLiters: _safeDouble(summaryData['waterLiters']),
      waterGoalLiters: _safeDouble(userData['waterGoalLiters'], fallback: 3),
      meals: entries,
      health: health,
      mood: _safeString(journalData['mood'], fallback: ''),
      journal: _safeString(
        journalData['note'] ?? journalData['notes'],
        fallback: '',
      ),
    );

    return report.copyWithAssessment(assessment: _buildAssessment(report));
  }

  Future<int> _todayActivityBurnedCalories(String uid, DateTime date) async {
    try {
      final start = DateTime(date.year, date.month, date.day);
      final end = start.add(const Duration(days: 1));
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('activities')
          .where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('startedAt', isLessThan: Timestamp.fromDate(end))
          .limit(30)
          .get();

      var total = 0;
      for (final doc in snap.docs) {
        total += _safeInt(doc.data()['caloriesBurned']);
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  String _healthStatus(double bpm, double temp) {
    if (bpm <= 0 && temp <= 0) return 'No scan recorded';
    if ((bpm > 0 && (bpm < 50 || bpm > 120)) ||
        (temp > 0 && (temp < 35.5 || temp > 38.0))) {
      return 'Review recommended';
    }
    if ((bpm > 0 && (bpm < 60 || bpm > 100)) ||
        (temp > 0 && (temp < 36.1 || temp > 37.2))) {
      return 'Monitor';
    }
    return 'Within expected wellness range';
  }

  String _healthRecommendation(double bpm, double temp) {
    if (bpm <= 0 && temp <= 0)
      return 'No health scan was recorded today. Perform a scan for a complete daily report.';
    if ((bpm > 0 && bpm > 100) || (temp > 0 && temp > 37.2)) {
      return 'Rest, hydrate, and recheck. Seek medical advice if readings stay abnormal or symptoms occur.';
    }
    return 'Readings look acceptable for a wellness report. Continue normal hydration and activity habits.';
  }

  _ReportAssessment _buildAssessment(_DailyMedicalReport report) {
    var score = 100;
    final findings = <String>[];
    final recommendations = <String>[];

    final calorieRatio = report.targetCalories <= 0
        ? 0.0
        : report.netCalories / report.targetCalories;
    if (report.calories <= 0) {
      score -= 12;
      findings.add(
        'No meals were logged for this date, so nutrition analysis is incomplete.',
      );
      recommendations.add('Log each meal to improve report accuracy.');
    } else if (calorieRatio > 1.12) {
      score -= 14;
      findings.add(
        'Net calorie intake exceeded the daily target by more than 12%.',
      );
      recommendations.add(
        'Choose lighter meals or increase activity tomorrow to rebalance energy intake.',
      );
    } else if (calorieRatio < 0.55) {
      score -= 8;
      findings.add('Net calorie intake is much lower than target.');
      recommendations.add(
        'Avoid under-eating. Add balanced meals with protein, carbs, and healthy fats.',
      );
    } else {
      findings.add('Daily calorie intake is close to the planned target.');
    }

    if (report.proteinGoal > 0 && report.protein < report.proteinGoal * 0.65) {
      score -= 10;
      findings.add(
        'Protein intake is below the recommended target for the selected goal.',
      );
      recommendations.add(
        'Add eggs, chicken, fish, tofu, tempeh, dhal, or Greek yogurt.',
      );
    } else if (report.protein > 0) {
      findings.add('Protein intake supports recovery and satiety.');
    }

    if (report.sugar > 50) {
      score -= 10;
      findings.add(
        'Sugar intake is above the general daily limit used by this report.',
      );
      recommendations.add(
        'Reduce sweet drinks, desserts, and high-sugar snacks.',
      );
    }

    if (report.fibre < 15 && report.calories > 0) {
      score -= 7;
      findings.add('Fibre intake is low for a full day.');
      recommendations.add(
        'Add vegetables, fruits, oats, beans, or whole-grain foods.',
      );
    }

    if (report.waterGoalLiters > 0 &&
        report.waterLiters < report.waterGoalLiters * 0.65) {
      score -= 9;
      findings.add('Hydration is below the daily target.');
      recommendations.add(
        'Drink water consistently across the day rather than all at once.',
      );
    } else if (report.waterLiters > 0) {
      findings.add('Hydration progress is acceptable for today.');
    }

    if (report.stepGoal > 0 && report.steps < report.stepGoal * 0.55) {
      score -= 8;
      findings.add('Physical activity is below the daily step goal.');
      recommendations.add('Add a short walk or light activity session.');
    } else if (report.steps > 0) {
      findings.add('Activity level contributes positively to daily wellness.');
    }

    final health = report.health;
    if (health == null) {
      score -= 6;
      findings.add('No health scan was found for this date.');
      recommendations.add(
        'Complete a health scan to include heart rate and temperature in the report.',
      );
    } else {
      if ((health.bpm > 0 && (health.bpm < 50 || health.bpm > 120)) ||
          (health.temperature > 0 &&
              (health.temperature < 35.5 || health.temperature > 38.0))) {
        score -= 15;
        findings.add('One or more health readings may need attention.');
        recommendations.add(
          'Repeat the scan after resting. Consult a medical professional if abnormal readings continue.',
        );
      } else {
        findings.add(
          'Recorded health scan does not show urgent wellness red flags.',
        );
      }
    }

    score = score.clamp(0, 100);
    final status = score >= 85
        ? 'Stable'
        : score >= 70
        ? 'Good with minor watch points'
        : score >= 55
        ? 'Moderate attention needed'
        : 'Review recommended';

    if (recommendations.isEmpty) {
      recommendations.add(
        'Maintain the current routine and continue tracking daily.',
      );
    }

    return _ReportAssessment(
      score: score,
      status: status,
      findings: findings.take(7).toList(),
      recommendations: recommendations.take(6).toList(),
    );
  }

  Future<void> _openPdf(_DailyMedicalReport report) async {
    HapticFeedback.mediumImpact();
    setState(() => _exporting = true);
    try {
      final bytes = await _buildMedicalPdf(report);
      await Printing.layoutPdf(
        name: _pdfFileName(report),
        onLayout: (_) async => bytes,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _sharePdf(_DailyMedicalReport report) async {
    HapticFeedback.lightImpact();
    setState(() => _exporting = true);
    try {
      final bytes = await _buildMedicalPdf(report);
      await Printing.sharePdf(bytes: bytes, filename: _pdfFileName(report));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _pdfFileName(_DailyMedicalReport report) {
    final safeName = report.patientName.replaceAll(
      RegExp(r'[^A-Za-z0-9]+'),
      '_',
    );
    return 'NutriPulse_Medical_Daily_Report_${safeName}_${report.dateKey}.pdf';
  }

  Future<Uint8List> _buildMedicalPdf(_DailyMedicalReport report) async {
    final pdf = pw.Document(
      title: 'NutriPulse Professional Daily Medical Report',
      author: 'NutriPulse',
      creator: 'NutriPulse Health Platform',
      subject:
          'Professional daily wellness, nutrition, activity and health scan report',
    );

    // Formal white-background medical report palette.
    const black = PdfColor(0.06, 0.07, 0.08);
    const darkBlue = PdfColor(0.04, 0.16, 0.30);
    const blue = PdfColor(0.08, 0.28, 0.55);
    const grey = PdfColor(0.36, 0.40, 0.45);
    const lightGrey = PdfColor(0.96, 0.97, 0.98);
    const line = PdfColor(0.78, 0.82, 0.86);
    const green = PdfColor(0.12, 0.48, 0.29);
    const amber = PdfColor(0.78, 0.49, 0.08);
    const red = PdfColor(0.70, 0.12, 0.10);

    PdfColor statusColor(String label) {
      final lower = label.toLowerCase();
      if (lower.contains('review') ||
          lower.contains('attention') ||
          lower.contains('high') ||
          lower.contains('above')) {
        return red;
      }
      if (lower.contains('minor') ||
          lower.contains('moderate') ||
          lower.contains('monitor') ||
          lower.contains('low') ||
          lower.contains('below')) {
        return amber;
      }
      return green;
    }

    String reportId() {
      final safeUid = report.uid
          .substring(0, math.min(6, report.uid.length))
          .toUpperCase();
      return 'NP-MR-${report.dateKey.replaceAll('-', '')}-$safeUid';
    }

    final bmi = report.heightCm > 0
        ? report.weightKg / math.pow(report.heightCm / 100, 2)
        : 0.0;

    String bmiStatus() {
      if (bmi <= 0) return 'Not available';
      if (bmi < 18.5) return 'Below reference';
      if (bmi < 25) return 'Normal range';
      if (bmi < 30) return 'Above reference';
      return 'Review recommended';
    }

    String calorieStatus() {
      if (report.calories <= 0) return 'Incomplete';
      final ratio = report.targetCalories <= 0
          ? 0.0
          : report.netCalories / report.targetCalories;
      if (ratio > 1.12) return 'Above target';
      if (ratio < 0.55) return 'Below target';
      return 'Within target';
    }

    String proteinStatus() {
      if (report.protein <= 0) return 'Not logged';
      if (report.proteinGoal > 0 && report.protein < report.proteinGoal * 0.65)
        return 'Low';
      return 'Acceptable';
    }

    String sugarStatus() {
      if (report.sugar <= 0) return 'Not logged';
      if (report.sugar > 50) return 'High';
      return 'Acceptable';
    }

    String fibreStatus() {
      if (report.fibre <= 0) return 'Not logged';
      if (report.fibre < 15) return 'Low';
      return 'Acceptable';
    }

    String waterStatus() {
      if (report.waterLiters <= 0) return 'Not logged';
      if (report.waterGoalLiters > 0 &&
          report.waterLiters < report.waterGoalLiters * 0.65)
        return 'Low';
      return 'Acceptable';
    }

    String stepsStatus() {
      if (report.steps <= 0) return 'Not recorded';
      if (report.stepGoal > 0 && report.steps < report.stepGoal * 0.55)
        return 'Low activity';
      return 'Active';
    }

    String reportDateLong() =>
        DateFormat('EEEE, dd MMMM yyyy').format(report.date);
    String generatedAt() =>
        DateFormat('dd MMM yyyy, hh:mm a').format(report.generatedAt);

    pw.TextStyle labelStyle() =>
        const pw.TextStyle(fontSize: 8.5, color: grey, letterSpacing: 0.2);

    pw.TextStyle bodyStyle({PdfColor color = black, double size = 9.2}) =>
        pw.TextStyle(fontSize: size, color: color, lineSpacing: 2.2);

    pw.TextStyle boldStyle({PdfColor color = black, double size = 9.5}) =>
        pw.TextStyle(
          fontSize: size,
          color: color,
          fontWeight: pw.FontWeight.bold,
          lineSpacing: 2.2,
        );

    pw.Widget documentHeader() {
      return pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 12),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.8)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 52,
              height: 52,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: darkBlue, width: 1.4),
              ),
              child: pw.Center(
                child: pw.Text(
                  'NP',
                  style: pw.TextStyle(
                    fontSize: 18,
                    color: darkBlue,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'NUTRIPULSE MEDICAL WELLNESS REPORT',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: darkBlue,
                      letterSpacing: 0.5,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Daily Health, Nutrition, Activity and Wellness Record',
                    style: const pw.TextStyle(fontSize: 10, color: grey),
                  ),
                  pw.SizedBox(height: 7),
                  pw.Text(
                    'Patient Copy | Generated by NutriPulse Health Platform',
                    style: const pw.TextStyle(fontSize: 8.5, color: grey),
                  ),
                ],
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border.all(
                  color: statusColor(report.assessment.status),
                  width: 0.8,
                ),
              ),
              child: pw.Text(
                report.assessment.status.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 8,
                  color: statusColor(report.assessment.status),
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget sectionTitle(String title, {String subtitle = ''}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 16, bottom: 7),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 11.5,
                color: darkBlue,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.4,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                subtitle,
                style: const pw.TextStyle(fontSize: 8.5, color: grey),
              ),
            ],
            pw.SizedBox(height: 5),
            pw.Container(height: 0.8, color: line),
          ],
        ),
      );
    }

    pw.Widget infoCell(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 7),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 88, child: pw.Text(label, style: labelStyle())),
            pw.Expanded(child: pw.Text(value, style: boldStyle(size: 9.2))),
          ],
        ),
      );
    }

    pw.Widget borderedBox(pw.Widget child, {PdfColor fill = PdfColors.white}) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(11),
        decoration: pw.BoxDecoration(
          color: fill,
          border: pw.Border.all(color: line, width: 0.7),
        ),
        child: child,
      );
    }

    pw.Widget summaryScoreBox() {
      final color = statusColor(report.assessment.status);
      return pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: lightGrey,
          border: pw.Border.all(color: line, width: 0.7),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 88,
              height: 88,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                border: pw.Border.all(color: color, width: 4),
                color: PdfColors.white,
              ),
              child: pw.Center(
                child: pw.Text(
                  '${report.assessment.score}',
                  style: pw.TextStyle(
                    fontSize: 28,
                    color: color,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Overall Wellness Assessment',
                    style: pw.TextStyle(
                      fontSize: 13.5,
                      color: darkBlue,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    'Score: ${report.assessment.score}/100',
                    style: boldStyle(size: 10.5, color: color),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Interpretation: ${report.assessment.status}',
                    style: boldStyle(size: 10.5),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'This score is calculated from logged meals, macronutrients, hydration, physical activity and available health scan readings for the selected date.',
                    style: bodyStyle(size: 8.7, color: grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget bullet(String text, PdfColor color) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 4),
              width: 5,
              height: 5,
              decoration: pw.BoxDecoration(
                color: color,
                shape: pw.BoxShape.circle,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(child: pw.Text(text, style: bodyStyle(size: 9))),
          ],
        ),
      );
    }

    List<List<String>> observationRows() {
      final h = report.health;
      return [
        [
          'Vital Signs',
          'Heart Rate',
          h == null || h.bpm <= 0
              ? 'No data'
              : '${h.bpm.toStringAsFixed(0)} bpm',
          'Resting reference: 60-100 bpm',
          h == null ? 'Not recorded' : _bpmStatus(h.bpm),
        ],
        [
          'Vital Signs',
          'Body Temperature',
          h == null || h.temperature <= 0
              ? 'No data'
              : '${h.temperature.toStringAsFixed(1)} deg C',
          'Reference: 36.1-37.2 deg C',
          h == null ? 'Not recorded' : _tempStatus(h.temperature),
        ],
        [
          'Body Metrics',
          'Body Mass Index',
          bmi > 0 ? bmi.toStringAsFixed(1) : 'Not available',
          'Reference: 18.5-24.9',
          bmiStatus(),
        ],
        [
          'Energy',
          'Net Calories',
          '${report.netCalories.round()} kcal',
          'Target: ${report.targetCalories.round()} kcal',
          calorieStatus(),
        ],
        [
          'Nutrition',
          'Protein',
          '${report.protein.toStringAsFixed(1)} g',
          'Goal: ${report.proteinGoal.toStringAsFixed(0)} g',
          proteinStatus(),
        ],
        [
          'Nutrition',
          'Carbohydrate',
          '${report.carbs.toStringAsFixed(1)} g',
          'Goal: ${report.carbsGoal.toStringAsFixed(0)} g',
          report.carbs <= 0 ? 'Not logged' : 'Tracked',
        ],
        [
          'Nutrition',
          'Fat',
          '${report.fat.toStringAsFixed(1)} g',
          'Goal: ${report.fatGoal.toStringAsFixed(0)} g',
          report.fat <= 0
              ? 'Not logged'
              : report.fat > report.fatGoal
              ? 'Above target'
              : 'Tracked',
        ],
        [
          'Nutrition',
          'Sugar',
          '${report.sugar.toStringAsFixed(1)} g',
          'General limit: <=50 g/day',
          sugarStatus(),
        ],
        [
          'Nutrition',
          'Fibre',
          '${report.fibre.toStringAsFixed(1)} g',
          'Goal: 25 g/day',
          fibreStatus(),
        ],
        [
          'Activity',
          'Steps',
          '${report.steps}',
          'Goal: ${report.stepGoal}',
          stepsStatus(),
        ],
        [
          'Hydration',
          'Water Intake',
          '${report.waterLiters.toStringAsFixed(1)} L',
          'Goal: ${report.waterGoalLiters.toStringAsFixed(1)} L',
          waterStatus(),
        ],
        [
          'Activity',
          'Activity Burn',
          '${report.activityBurnedCalories} kcal',
          'Logged activity calories',
          report.activityBurnedCalories > 0 ? 'Recorded' : 'No activity burn',
        ],
      ];
    }

    pw.Widget observationTable() {
      return pw.TableHelper.fromTextArray(
        border: pw.TableBorder.all(color: line, width: 0.5),
        headerDecoration: const pw.BoxDecoration(color: darkBlue),
        headerStyle: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 8.2,
          fontWeight: pw.FontWeight.bold,
        ),
        cellStyle: const pw.TextStyle(fontSize: 7.9, color: black),
        cellPadding: const pw.EdgeInsets.symmetric(
          horizontal: 5.2,
          vertical: 5,
        ),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.1),
          1: const pw.FlexColumnWidth(1.35),
          2: const pw.FlexColumnWidth(1.1),
          3: const pw.FlexColumnWidth(1.7),
          4: const pw.FlexColumnWidth(1.15),
        },
        headers: [
          'Category',
          'Indicator',
          'Result',
          'Reference / Target',
          'Interpretation',
        ],
        data: observationRows(),
      );
    }

    pw.Widget nutritionSummaryTable() {
      final rows = [
        [
          'Calories Consumed',
          '${report.calories.round()} kcal',
          'Target ${report.targetCalories.round()} kcal',
        ],
        [
          'Activity Burned',
          '${report.activityBurnedCalories} kcal',
          'Logged activity',
        ],
        ['Net Calories', '${report.netCalories.round()} kcal', calorieStatus()],
        [
          'Remaining Calories',
          '${report.remainingCalories.round()} kcal',
          'After activity adjustment',
        ],
        [
          'Protein',
          '${report.protein.toStringAsFixed(1)} g',
          'Goal ${report.proteinGoal.toStringAsFixed(0)} g',
        ],
        [
          'Carbohydrate',
          '${report.carbs.toStringAsFixed(1)} g',
          'Goal ${report.carbsGoal.toStringAsFixed(0)} g',
        ],
        [
          'Fat',
          '${report.fat.toStringAsFixed(1)} g',
          'Goal ${report.fatGoal.toStringAsFixed(0)} g',
        ],
        ['Sugar', '${report.sugar.toStringAsFixed(1)} g', sugarStatus()],
        ['Fibre', '${report.fibre.toStringAsFixed(1)} g', fibreStatus()],
      ];

      return pw.TableHelper.fromTextArray(
        border: pw.TableBorder.all(color: line, width: 0.5),
        headerDecoration: const pw.BoxDecoration(color: lightGrey),
        headerStyle: pw.TextStyle(
          color: darkBlue,
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
        ),
        cellStyle: const pw.TextStyle(fontSize: 8.3, color: black),
        cellPadding: const pw.EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 5.5,
        ),
        columnWidths: {
          0: const pw.FlexColumnWidth(2),
          1: const pw.FlexColumnWidth(1.3),
          2: const pw.FlexColumnWidth(2),
        },
        headers: ['Parameter', 'Value', 'Target / Status'],
        data: rows,
      );
    }

    pw.Widget mealLogTable() {
      if (report.meals.isEmpty) {
        return borderedBox(
          pw.Text(
            'No meals were logged for this report date.',
            style: bodyStyle(),
          ),
          fill: lightGrey,
        );
      }

      return pw.TableHelper.fromTextArray(
        border: pw.TableBorder.all(color: line, width: 0.45),
        headerDecoration: const pw.BoxDecoration(color: darkBlue),
        headerStyle: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 7.8,
          fontWeight: pw.FontWeight.bold,
        ),
        cellStyle: const pw.TextStyle(fontSize: 7.4, color: black),
        cellPadding: const pw.EdgeInsets.symmetric(
          horizontal: 4.5,
          vertical: 4.5,
        ),
        columnWidths: {
          0: const pw.FlexColumnWidth(0.7),
          1: const pw.FlexColumnWidth(2.3),
          2: const pw.FlexColumnWidth(0.9),
          3: const pw.FlexColumnWidth(0.8),
          4: const pw.FlexColumnWidth(0.8),
          5: const pw.FlexColumnWidth(0.8),
          6: const pw.FlexColumnWidth(0.75),
        },
        headers: [
          'Time',
          'Food Item',
          'Meal',
          'kcal',
          'Protein',
          'Carbs',
          'Fat',
        ],
        data: report.meals.map((m) {
          final time = m.timestamp == null
              ? '-'
              : DateFormat('hh:mm a').format(m.timestamp!);
          return [
            time,
            m.name,
            m.mealType,
            m.calories.round().toString(),
            '${m.protein.toStringAsFixed(1)} g',
            '${m.carbs.toStringAsFixed(1)} g',
            '${m.fat.toStringAsFixed(1)} g',
          ];
        }).toList(),
      );
    }

    pw.Widget recommendationList() {
      return borderedBox(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            ...report.assessment.recommendations.map(
              (item) => bullet(item, statusColor(report.assessment.status)),
            ),
          ],
        ),
        fill: PdfColors.white,
      );
    }

    pw.Widget clinicalNotes() {
      final h = report.health;
      return borderedBox(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            ...report.assessment.findings.map((item) => bullet(item, blue)),
            if (h != null && h.recommendation.trim().isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Container(height: 0.7, color: line),
              pw.SizedBox(height: 8),
              pw.Text(
                'Health Scan Recommendation',
                style: boldStyle(size: 9.5, color: darkBlue),
              ),
              pw.SizedBox(height: 4),
              pw.Text(h.recommendation, style: bodyStyle()),
            ],
          ],
        ),
        fill: PdfColors.white,
      );
    }

    pw.Widget journalBox() {
      if (report.mood.isEmpty && report.journal.isEmpty)
        return pw.SizedBox.shrink();
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          sectionTitle('Patient Journal / Self-Reported Notes'),
          borderedBox(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (report.mood.isNotEmpty) infoCell('Mood', report.mood),
                if (report.journal.isNotEmpty)
                  pw.Text(report.journal, style: bodyStyle()),
              ],
            ),
            fill: lightGrey,
          ),
        ],
      );
    }

    pw.Widget disclaimerBox() {
      return pw.Container(
        padding: const pw.EdgeInsets.all(11),
        decoration: pw.BoxDecoration(
          color: const PdfColor(1.0, 0.985, 0.94),
          border: pw.Border.all(
            color: const PdfColor(0.88, 0.70, 0.35),
            width: 0.7,
          ),
        ),
        child: pw.Text(
          'Medical Disclaimer: This report is automatically generated from user-entered data and NutriPulse sensor/app records. It is a wellness monitoring document only. It is not a clinical diagnosis, treatment plan, prescription, medical certificate, or substitute for consultation with a qualified healthcare professional. If symptoms are present or abnormal values persist, seek professional medical advice.',
          style: const pw.TextStyle(
            fontSize: 8.2,
            color: PdfColor(0.36, 0.24, 0.05),
            lineSpacing: 2.1,
          ),
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(38, 30, 38, 34),
          theme: pw.ThemeData.withFont(
            base: pw.Font.helvetica(),
            bold: pw.Font.helveticaBold(),
          ),
        ),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 7),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: line, width: 0.6)),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'NutriPulse Medical Wellness Report | Report ID: ${reportId()}',
                  style: const pw.TextStyle(fontSize: 7.6, color: grey),
                ),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 7.6, color: grey),
              ),
            ],
          ),
        ),
        build: (context) => [
          documentHeader(),
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 3,
                child: borderedBox(
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'PATIENT AND REPORT INFORMATION',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: darkBlue,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      infoCell('Patient Name', report.patientName),
                      infoCell('Email', report.email),
                      infoCell('Report Date', reportDateLong()),
                      infoCell('Generated At', generatedAt()),
                      infoCell('Report ID', reportId()),
                    ],
                  ),
                  fill: PdfColors.white,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                flex: 2,
                child: borderedBox(
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'PROFILE SUMMARY',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: darkBlue,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      infoCell('Goal', report.goal),
                      infoCell(
                        'Height',
                        report.heightCm > 0
                            ? '${report.heightCm.round()} cm'
                            : 'Not available',
                      ),
                      infoCell(
                        'Weight',
                        report.weightKg > 0
                            ? '${report.weightKg.toStringAsFixed(1)} kg'
                            : 'Not available',
                      ),
                      infoCell(
                        'BMI',
                        bmi > 0
                            ? '${bmi.toStringAsFixed(1)} ($bmiStatus())'
                            : 'Not available',
                      ),
                    ],
                  ),
                  fill: lightGrey,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          summaryScoreBox(),

          sectionTitle(
            'Summary',
            subtitle:
                'Automated interpretation based on tracked wellness records',
          ),
          clinicalNotes(),

          sectionTitle(
            'Observation Results',
            subtitle:
                'Key daily indicators compared with personal targets or general wellness reference ranges',
          ),
          observationTable(),

          sectionTitle(
            'Nutrition and Energy Analysis',
            subtitle:
                'Calories, macronutrients, sugar and fibre profile for the selected date',
          ),
          nutritionSummaryTable(),

          sectionTitle(
            'Meal Log Record',
            subtitle:
                'Food entries used to calculate the daily nutrition values',
          ),
          mealLogTable(),

          sectionTitle(
            'Professional Recommendations',
            subtitle: 'Suggested actions for the next 24 hours',
          ),
          recommendationList(),

          journalBox(),

          sectionTitle('Report Declaration'),
          borderedBox(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'This report was generated electronically by NutriPulse using available app records for the selected date. No manual clinical examination was performed by NutriPulse.',
                  style: bodyStyle(),
                ),
                pw.SizedBox(height: 14),
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(height: 0.8, color: line),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Generated by NutriPulse AI Wellness System',
                            style: const pw.TextStyle(fontSize: 8, color: grey),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 30),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(height: 0.8, color: line),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Patient / User Copy',
                            style: const pw.TextStyle(fontSize: 8, color: grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          disclaimerBox(),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _pdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 78,
            child: pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: PdfColor(0.35, 0.40, 0.43),
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 9.2,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor(0.08, 0.10, 0.12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfBullet(String text, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 4),
            width: 6,
            height: 6,
            decoration: pw.BoxDecoration(
              color: color,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              text,
              style: const pw.TextStyle(
                fontSize: 9.2,
                color: PdfColor(0.08, 0.10, 0.12),
                lineSpacing: 2.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _bpmStatus(double bpm) {
    if (bpm <= 0) return 'Not recorded';
    if (bpm < 50 || bpm > 120) return 'Review recommended';
    if (bpm < 60 || bpm > 100) return 'Monitor';
    return 'Normal range';
  }

  String _tempStatus(double temp) {
    if (temp <= 0) return 'Not recorded';
    if (temp < 35.5 || temp > 38.0) return 'Review recommended';
    if (temp < 36.1 || temp > 37.2) return 'Monitor';
    return 'Normal range';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: bg,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF243519), bg, Color(0xFF060806)],
            ),
          ),
          child: SafeArea(
            child: FutureBuilder<_DailyMedicalReport>(
              future: _reportFuture,
              builder: (context, snapshot) {
                final report = snapshot.data;
                return Column(
                  children: [
                    _header(report),
                    Expanded(
                      child:
                          snapshot.connectionState == ConnectionState.waiting &&
                              report == null
                          ? const Center(
                              child: CircularProgressIndicator(color: lime),
                            )
                          : snapshot.hasError
                          ? _errorState(snapshot.error.toString())
                          : _reportBody(report!),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(_DailyMedicalReport? report) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: card.withOpacity(0.92),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Medical Report',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 27,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  report == null
                      ? 'Loading today’s medical-style PDF'
                      : DateFormat('EEE, dd MMM yyyy').format(report.date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.78),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _pickReportDate,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: lime,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.calendar_month_rounded,
                color: Colors.black,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickReportDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 180)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: lime,
              onPrimary: Colors.black,
              surface: card,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: bg,
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;
    setState(() {
      _selectedDate = picked;
      _reportFuture = _loadReport(picked);
    });
  }

  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent.shade100,
              size: 48,
            ),
            const SizedBox(height: 14),
            Text(
              'Could not load report',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: soft,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _reload,
              style: ElevatedButton.styleFrom(
                backgroundColor: lime,
                foregroundColor: Colors.black,
              ),
              child: Text(
                'Retry',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportBody(_DailyMedicalReport report) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
      children: [
        RepaintBoundary(child: _medicalHero(report)),
        const SizedBox(height: 16),
        RepaintBoundary(child: _actionRow(report)),
        const SizedBox(height: 18),
        RepaintBoundary(child: _patientCard(report)),
        const SizedBox(height: 18),
        RepaintBoundary(child: _clinicalSummaryCard(report)),
        const SizedBox(height: 18),
        RepaintBoundary(child: _vitalsCard(report)),
        const SizedBox(height: 18),
        RepaintBoundary(child: _nutritionCard(report)),
        const SizedBox(height: 18),
        RepaintBoundary(child: _activityHydrationCard(report)),
        const SizedBox(height: 18),
        RepaintBoundary(child: _recommendationCard(report)),
        const SizedBox(height: 18),
        RepaintBoundary(child: _mealLogCard(report)),
        const SizedBox(height: 18),
        _disclaimerCard(),
      ],
    );
  }

  Widget _medicalHero(_DailyMedicalReport report) {
    final statusColor = _statusColor(report.assessment.status);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            lime.withOpacity(0.22),
            card.withOpacity(0.98),
            card2.withOpacity(0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: lime.withOpacity(0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: lime.withOpacity(0.25)),
                ),
                child: const Icon(
                  Icons.local_hospital_rounded,
                  color: lime,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NutriPulse Health Report',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Medical-style daily wellness summary',
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.78),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${report.assessment.score}',
                style: GoogleFonts.outfit(
                  color: statusColor,
                  fontSize: 58,
                  height: 0.9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2.2,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '/100',
                  style: GoogleFonts.outfit(
                    color: soft,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Spacer(),
              _statusPill(report.assessment.status),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: report.assessment.score / 100,
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(_DailyMedicalReport report) {
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            icon: Icons.picture_as_pdf_rounded,
            label: _exporting ? 'Preparing...' : 'Preview PDF',
            filled: true,
            onTap: _exporting ? null : () => _openPdf(report),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _actionButton(
            icon: Icons.ios_share_rounded,
            label: 'Share PDF',
            filled: false,
            onTap: _exporting ? null : () => _sharePdf(report),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: onTap == null ? 0.55 : 1,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: filled ? lime : card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: filled ? lime : Colors.white.withOpacity(0.08),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: filled ? Colors.black : lime, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: filled ? Colors.black : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _patientCard(_DailyMedicalReport report) {
    final bmi = report.heightCm > 0
        ? report.weightKg / math.pow(report.heightCm / 100, 2)
        : 0.0;
    return _sectionCard(
      title: 'Patient Information',
      subtitle: 'Identity and health target',
      icon: Icons.badge_rounded,
      children: [
        _infoRow('Name', report.patientName),
        _infoRow('Email', report.email),
        _infoRow('Report date', DateFormat('dd MMMM yyyy').format(report.date)),
        _infoRow('Goal', report.goal),
        _infoRow(
          'Height / Weight',
          '${report.heightCm.round()} cm / ${report.weightKg.toStringAsFixed(1)} kg',
        ),
        _infoRow('BMI', bmi > 0 ? bmi.toStringAsFixed(1) : 'Not available'),
      ],
    );
  }

  Widget _clinicalSummaryCard(_DailyMedicalReport report) {
    return _sectionCard(
      title: 'Clinical Summary',
      subtitle: 'Automated wellness interpretation',
      icon: Icons.medical_information_rounded,
      children: [
        ...report.assessment.findings.map((item) => _bullet(item, lime)),
      ],
    );
  }

  Widget _vitalsCard(_DailyMedicalReport report) {
    final h = report.health;
    return _sectionCard(
      title: 'Vital Signs',
      subtitle: h == null
          ? 'No health scan recorded today'
          : 'Latest health scan readings',
      icon: Icons.favorite_rounded,
      children: [
        Row(
          children: [
            Expanded(
              child: _metricTile(
                label: 'Heart rate',
                value: h == null || h.bpm <= 0
                    ? '--'
                    : '${h.bpm.toStringAsFixed(0)}',
                unit: 'bpm',
                status: h == null ? 'Not recorded' : _bpmStatus(h.bpm),
                icon: Icons.monitor_heart_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricTile(
                label: 'Temperature',
                value: h == null || h.temperature <= 0
                    ? '--'
                    : h.temperature.toStringAsFixed(1),
                unit: '°C',
                status: h == null ? 'Not recorded' : _tempStatus(h.temperature),
                icon: Icons.thermostat_rounded,
              ),
            ),
          ],
        ),
        if (h != null) ...[
          const SizedBox(height: 12),
          _infoRow('Device status', h.status),
          _infoRow('Recommendation', h.recommendation),
        ],
      ],
    );
  }

  Widget _nutritionCard(_DailyMedicalReport report) {
    return _sectionCard(
      title: 'Nutrition Panel',
      subtitle: 'Calories and macronutrients',
      icon: Icons.restaurant_menu_rounded,
      children: [
        Row(
          children: [
            Expanded(
              child: _metricTile(
                label: 'Net kcal',
                value: report.netCalories.round().toString(),
                unit: 'kcal',
                status: '${report.targetCalories.round()} target',
                icon: Icons.local_fire_department_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricTile(
                label: 'Remaining',
                value: report.remainingCalories.round().toString(),
                unit: 'kcal',
                status: 'after activity',
                icon: Icons.bolt_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _macroTile(
                'Protein',
                report.protein,
                report.proteinGoal,
                const Color(0xFF7CA8FF),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _macroTile(
                'Carbs',
                report.carbs,
                report.carbsGoal,
                const Color(0xFFFFD24D),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _macroTile(
                'Fat',
                report.fat,
                report.fatGoal,
                const Color(0xFFFF8B7A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _metricTile(
                label: 'Sugar',
                value: report.sugar.toStringAsFixed(1),
                unit: 'g',
                status: report.sugar > 50 ? 'High' : 'Ok',
                icon: Icons.icecream_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricTile(
                label: 'Fibre',
                value: report.fibre.toStringAsFixed(1),
                unit: 'g',
                status: report.fibre < 15 ? 'Low' : 'Ok',
                icon: Icons.grass_rounded,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _activityHydrationCard(_DailyMedicalReport report) {
    return _sectionCard(
      title: 'Activity & Hydration',
      subtitle: 'Movement and water balance',
      icon: Icons.directions_walk_rounded,
      children: [
        Row(
          children: [
            Expanded(
              child: _metricTile(
                label: 'Steps',
                value: '${report.steps}',
                unit: '',
                status: '${report.stepGoal} goal',
                icon: Icons.directions_walk_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricTile(
                label: 'Water',
                value: report.waterLiters.toStringAsFixed(1),
                unit: 'L',
                status: '${report.waterGoalLiters.toStringAsFixed(1)} L goal',
                icon: Icons.water_drop_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _metricTile(
          label: 'Activity calories burned',
          value: '${report.activityBurnedCalories}',
          unit: 'kcal',
          status: 'from logged activities',
          icon: Icons.local_fire_department_rounded,
        ),
      ],
    );
  }

  Widget _recommendationCard(_DailyMedicalReport report) {
    return _sectionCard(
      title: 'Recommendations',
      subtitle: 'Next 24-hour guidance',
      icon: Icons.recommend_rounded,
      children: [
        ...report.assessment.recommendations.map(
          (item) => _bullet(item, _statusColor(report.assessment.status)),
        ),
      ],
    );
  }

  Widget _mealLogCard(_DailyMedicalReport report) {
    return _sectionCard(
      title: 'Meal Log',
      subtitle: '${report.meals.length} food entries used for this report',
      icon: Icons.receipt_long_rounded,
      children: report.meals.isEmpty
          ? [
              Text(
                'No meals were logged for this date.',
                style: GoogleFonts.outfit(
                  color: soft,
                  fontSize: 13.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ]
          : report.meals.take(8).map((meal) => _mealRow(meal)).toList(),
    );
  }

  Widget _mealRow(_MealLine meal) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withOpacity(0.055)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: lime.withOpacity(0.13),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.restaurant_rounded, color: lime, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meal.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${meal.mealType} • ${meal.protein.toStringAsFixed(1)}g protein • ${meal.carbs.toStringAsFixed(1)}g carbs',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.78),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${meal.calories.round()} kcal',
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

  Widget _disclaimerCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD24D).withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD24D).withOpacity(0.25)),
      ),
      child: Text(
        'This is a medical-style wellness report generated from NutriPulse data. It is not a diagnosis or replacement for professional medical advice.',
        style: GoogleFonts.outfit(
          color: const Color(0xFFFFE39B),
          fontSize: 12.5,
          height: 1.35,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card.withOpacity(0.95),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.065)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: lime.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: lime, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.72),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: GoogleFonts.outfit(
                color: soft.withOpacity(0.78),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 12.8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.outfit(
                color: Colors.white.withOpacity(0.80),
                fontSize: 13,
                height: 1.34,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String status) {
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: c.withOpacity(0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(0.30)),
      ),
      child: Text(
        status,
        style: GoogleFonts.outfit(
          color: c,
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    final lower = status.toLowerCase();
    if (lower.contains('review') ||
        lower.contains('attention') ||
        lower.contains('high')) {
      return const Color(0xFFFF8B7A);
    }
    if (lower.contains('minor') ||
        lower.contains('moderate') ||
        lower.contains('monitor') ||
        lower.contains('low')) {
      return const Color(0xFFFFD24D);
    }
    return lime;
  }

  Widget _metricTile({
    required String label,
    required String value,
    required String unit,
    required String status,
    required IconData icon,
  }) {
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: c, size: 17),
              const Spacer(),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              text: value,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
              children: [
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: GoogleFonts.outfit(
                      color: soft,
                      fontSize: 10.8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: c,
              fontSize: 10.8,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _macroTile(String label, double value, double goal, Color color) {
    final progress = goal <= 0
        ? 0.0
        : (value / goal).clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withOpacity(0.055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${value.toStringAsFixed(1)}g',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyMedicalReport {
  const _DailyMedicalReport({
    required this.uid,
    required this.patientName,
    required this.email,
    required this.goal,
    required this.heightCm,
    required this.weightKg,
    required this.date,
    required this.dateKey,
    required this.generatedAt,
    required this.targetCalories,
    required this.calories,
    required this.netCalories,
    required this.remainingCalories,
    required this.activityBurnedCalories,
    required this.protein,
    required this.proteinGoal,
    required this.carbs,
    required this.carbsGoal,
    required this.fat,
    required this.fatGoal,
    required this.sugar,
    required this.fibre,
    required this.steps,
    required this.stepGoal,
    required this.waterLiters,
    required this.waterGoalLiters,
    required this.meals,
    required this.health,
    required this.mood,
    required this.journal,
    this.assessment = const _ReportAssessment(
      score: 0,
      status: 'Loading',
      findings: [],
      recommendations: [],
    ),
  });

  final String uid;
  final String patientName;
  final String email;
  final String goal;
  final double heightCm;
  final double weightKg;
  final DateTime date;
  final String dateKey;
  final DateTime generatedAt;
  final double targetCalories;
  final double calories;
  final double netCalories;
  final double remainingCalories;
  final int activityBurnedCalories;
  final double protein;
  final double proteinGoal;
  final double carbs;
  final double carbsGoal;
  final double fat;
  final double fatGoal;
  final double sugar;
  final double fibre;
  final int steps;
  final int stepGoal;
  final double waterLiters;
  final double waterGoalLiters;
  final List<_MealLine> meals;
  final _HealthLine? health;
  final String mood;
  final String journal;
  final _ReportAssessment assessment;

  _DailyMedicalReport copyWithAssessment({
    required _ReportAssessment assessment,
  }) {
    return _DailyMedicalReport(
      uid: uid,
      patientName: patientName,
      email: email,
      goal: goal,
      heightCm: heightCm,
      weightKg: weightKg,
      date: date,
      dateKey: dateKey,
      generatedAt: generatedAt,
      targetCalories: targetCalories,
      calories: calories,
      netCalories: netCalories,
      remainingCalories: remainingCalories,
      activityBurnedCalories: activityBurnedCalories,
      protein: protein,
      proteinGoal: proteinGoal,
      carbs: carbs,
      carbsGoal: carbsGoal,
      fat: fat,
      fatGoal: fatGoal,
      sugar: sugar,
      fibre: fibre,
      steps: steps,
      stepGoal: stepGoal,
      waterLiters: waterLiters,
      waterGoalLiters: waterGoalLiters,
      meals: meals,
      health: health,
      mood: mood,
      journal: journal,
      assessment: assessment,
    );
  }
}

class _ReportAssessment {
  const _ReportAssessment({
    required this.score,
    required this.status,
    required this.findings,
    required this.recommendations,
  });

  final int score;
  final String status;
  final List<String> findings;
  final List<String> recommendations;
}

class _MealLine {
  const _MealLine({
    required this.name,
    required this.mealType,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.sugar,
    required this.fibre,
    required this.timestamp,
  });

  final String name;
  final String mealType;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double sugar;
  final double fibre;
  final DateTime? timestamp;
}

class _HealthLine {
  const _HealthLine({
    required this.bpm,
    required this.minBpm,
    required this.maxBpm,
    required this.temperature,
    required this.status,
    required this.recommendation,
    required this.recordedAt,
  });

  final double bpm;
  final double minBpm;
  final double maxBpm;
  final double temperature;
  final String status;
  final String recommendation;
  final DateTime? recordedAt;
}
