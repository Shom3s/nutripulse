import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/mission_model.dart';
import '../../services/gamification_service.dart';

class DailyMissionCard extends StatelessWidget {
  const DailyMissionCard({super.key});

  static const Color lime = Color(0xFFD6FF60);
  static const Color text = Colors.white;
  static const Color soft = Color(0xFFB7C2A8);
  static const Color card = Color(0xFF1A1F17);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    final today = GamificationService.dateKey();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('daily_missions')
          .doc(today)
          .collection('items')
          .snapshots(),
      builder: (context, snapshot) {
        final missions =
            snapshot.data?.docs
                .map((d) => MissionModel.fromMap(d.id, d.data()))
                .toList() ??
            [];
        missions.sort((a, b) => a.done == b.done ? 0 : (a.done ? 1 : -1));

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: _box(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.flag_rounded, color: lime, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Today’s Missions',
                    style: GoogleFonts.outfit(
                      color: text,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (missions.isEmpty)
                Text(
                  'Missions will appear after dashboard loads.',
                  style: GoogleFonts.outfit(color: soft, fontSize: 12),
                )
              else
                ...missions.take(4).map((m) => _missionRow(m)),
            ],
          ),
        );
      },
    );
  }

  Widget _missionRow(MissionModel mission) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: mission.done ? lime : Colors.white.withOpacity(0.06),
              shape: BoxShape.circle,
              border: Border.all(
                color: mission.done ? lime : Colors.white.withOpacity(0.08),
              ),
            ),
            child: Icon(
              mission.done ? Icons.check_rounded : _iconFor(mission.iconName),
              color: mission.done ? Colors.black : lime,
              size: 15,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mission.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: text,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  mission.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.70),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '+${mission.xpReward} XP',
            style: GoogleFonts.outfit(
              color: mission.done ? lime : soft.withOpacity(0.75),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String name) {
    switch (name) {
      case 'food':
        return Icons.restaurant_rounded;
      case 'water':
        return Icons.water_drop_rounded;
      case 'steps':
        return Icons.directions_walk_rounded;
      case 'protein':
        return Icons.fitness_center_rounded;
      default:
        return Icons.flag_rounded;
    }
  }

  BoxDecoration _box() => BoxDecoration(
    color: card,
    borderRadius: BorderRadius.circular(26),
    border: Border.all(color: Colors.white.withOpacity(0.055)),
  );
}
