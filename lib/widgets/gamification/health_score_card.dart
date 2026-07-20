import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/gamification_service.dart';
import '../../services/health_score_service.dart';

class HealthScoreCard extends StatelessWidget {
  const HealthScoreCard({super.key});

  static const Color lime = Color(0xFFD6FF60);
  static const Color text = Colors.white;
  static const Color soft = Color(0xFFB7C2A8);
  static const Color card = Color(0xFF1A1F17);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    final today = GamificationService.dateKey();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('daily_summary')
          .doc(today)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? {};
        final score = _asInt(data['healthScore']);
        final label = HealthScoreService.labelForScore(score);
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: _box(),
          child: Row(
            children: [
              SizedBox(
                width: 66,
                height: 66,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: (score / 100).clamp(0.0, 1.0),
                        strokeWidth: 7,
                        backgroundColor: Colors.white.withOpacity(0.08),
                        valueColor: const AlwaysStoppedAnimation<Color>(lime),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Text(
                      '$score',
                      style: GoogleFonts.outfit(
                        color: text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Health Score',
                      style: GoogleFonts.outfit(
                        color: text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: GoogleFonts.outfit(
                        color: lime,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Based on calories, protein, water and steps',
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.75),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  BoxDecoration _box() => BoxDecoration(
    color: card,
    borderRadius: BorderRadius.circular(26),
    border: Border.all(color: Colors.white.withOpacity(0.055)),
  );
}
