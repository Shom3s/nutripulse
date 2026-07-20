import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/gamification_profile.dart';
import 'level_progress_bar.dart';

class XpLevelCard extends StatelessWidget {
  const XpLevelCard({super.key});

  static const Color lime = Color(0xFFD6FF60);
  static const Color text = Colors.white;
  static const Color soft = Color(0xFFB7C2A8);
  static const Color card = Color(0xFF1A1F17);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('gamification')
          .doc('profile')
          .snapshots(),
      builder: (context, snapshot) {
        final profile = GamificationProfile.fromMap(snapshot.data?.data());
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: _box(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: lime.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: lime,
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Level ${profile.level}',
                          style: GoogleFonts.outfit(
                            color: text,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          XpRules.titleForLevel(profile.level),
                          style: GoogleFonts.outfit(
                            color: soft,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${profile.xp} XP',
                    style: GoogleFonts.outfit(
                      color: lime,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LevelProgressBar(
                progress: profile.progressToNextLevel,
                color: lime,
                backgroundColor: Colors.white.withOpacity(0.08),
              ),
              const SizedBox(height: 8),
              Text(
                '${profile.xpInsideLevel} / ${profile.xpNeededForNextLevel} XP to next level',
                style: GoogleFonts.outfit(
                  color: soft.withOpacity(0.75),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  BoxDecoration _box() => BoxDecoration(
    color: card,
    borderRadius: BorderRadius.circular(26),
    border: Border.all(color: Colors.white.withOpacity(0.055)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.30),
        blurRadius: 20,
        offset: const Offset(0, 10),
      ),
    ],
  );
}
