import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LeaderboardPodium extends StatelessWidget {
  const LeaderboardPodium({super.key, required this.users});

  final List<Map<String, dynamic>> users;

  static const lime = Color(0xFFD6FF60);
  static const card = Color(0xFF1A1F17);
  static const soft = Color(0xFFB7C2A8);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 188,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: card.withOpacity(0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: users.isEmpty
          ? Center(
              child: Text(
                'No rankings yet',
                style: GoogleFonts.outfit(
                  color: soft,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: _podium(index: 1, height: 54)),
                Expanded(child: _podium(index: 0, height: 76, first: true)),
                Expanded(child: _podium(index: 2, height: 44)),
              ],
            ),
    );
  }

  Widget _podium({
    required int index,
    required double height,
    bool first = false,
  }) {
    if (index >= users.length) {
      return const SizedBox.expand();
    }

    final user = users[index];
    final name = (user['name'] ?? 'User').toString();
    final xp = user['xp'] ?? 0;
    final rank = index + 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: first ? 40 : 34,
          height: first ? 40 : 34,
          decoration: BoxDecoration(
            color: first ? lime : Colors.white.withOpacity(0.08),
            shape: BoxShape.circle,
            boxShadow: first
                ? [
                    BoxShadow(
                      color: lime.withOpacity(0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              '#$rank',
              style: GoogleFonts.outfit(
                color: first ? Colors.black : lime,
                fontSize: first ? 15 : 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 11,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$xp XP',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(
            color: soft,
            fontSize: 10,
            height: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: first ? lime : Colors.white.withOpacity(0.10),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16),
              bottom: Radius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}
