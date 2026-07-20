import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LeaderboardRow extends StatelessWidget {
  const LeaderboardRow({super.key, required this.rank, required this.data});

  final int rank;
  final Map<String, dynamic> data;

  static const lime = Color(0xFFD6FF60);
  static const card = Color(0xFF1A1F17);
  static const soft = Color(0xFFB7C2A8);

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? 'User').toString();
    final xp = data['xp'] ?? 0;
    final steps = data['steps'] ?? 0;
    final streak = data['streak'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Text(
            '#$rank',
            style: GoogleFonts.outfit(
              color: lime,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '$steps steps • ${streak}d streak',
                  style: GoogleFonts.outfit(color: soft, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Text(
            '$xp XP',
            style: GoogleFonts.outfit(
              color: lime,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
