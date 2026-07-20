import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/achievement_model.dart';

class AchievementBadges extends StatelessWidget {
  const AchievementBadges({super.key});

  static const Color lime = Color(0xFFD6FF60);
  static const Color text = Colors.white;
  static const Color soft = Color(0xFFB7C2A8);
  static const Color card = Color(0xFF1A1F17);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('achievements')
          .snapshots(),
      builder: (context, snapshot) {
        final badges =
            snapshot.data?.docs
                .map((d) => AchievementModel.fromMap(d.id, d.data()))
                .toList() ??
            [];
        badges.sort(
          (a, b) => a.unlocked == b.unlocked ? 0 : (a.unlocked ? -1 : 1),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Achievements',
              style: GoogleFonts.outfit(
                color: text,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemBuilder: (context, index) {
                  if (badges.isEmpty) return _badgePlaceholder();
                  return _badge(badges[index]);
                },
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemCount: badges.isEmpty ? 1 : badges.length,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _badge(AchievementModel badge) {
    final unlocked = badge.unlocked;
    return Container(
      width: 106,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: unlocked
              ? lime.withOpacity(0.28)
              : Colors.white.withOpacity(0.055),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            badge.icon,
            style: TextStyle(
              fontSize: unlocked ? 20 : 18,
              color: unlocked ? null : Colors.white.withOpacity(0.35),
            ),
          ),
          const Spacer(),
          Text(
            badge.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: unlocked ? text : soft.withOpacity(0.55),
              fontSize: 11.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            unlocked ? 'Unlocked' : 'Locked',
            style: GoogleFonts.outfit(
              color: unlocked ? lime : soft.withOpacity(0.45),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badgePlaceholder() {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.055)),
      ),
      child: Text(
        'Achievements loading...',
        style: GoogleFonts.outfit(color: soft, fontSize: 12),
      ),
    );
  }
}
