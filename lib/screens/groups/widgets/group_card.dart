import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/group_service.dart';

class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.groupId,
    required this.data,
    required this.onTap,
  });

  final String groupId;
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  static const lime = Color(0xFFD6FF60);
  static const card = Color(0xFF1A1F17);
  static const soft = Color(0xFFB7C2A8);

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? 'Group').toString();
    final desc = (data['description'] ?? '').toString();
    final icon = (data['icon'] ?? '✨').toString();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: card.withOpacity(0.92),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: lime.withOpacity(0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(icon, style: const TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: soft,
                      fontSize: 12.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<int>(
                    stream: GroupService.membersCountStream(groupId),
                    builder: (context, snapshot) {
                      final members =
                          snapshot.data ??
                          int.tryParse(
                            (data['membersCount'] ?? 0).toString(),
                          ) ??
                          0;

                      return Text(
                        '$members members',
                        style: GoogleFonts.outfit(
                          color: lime,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: lime, size: 16),
          ],
        ),
      ),
    );
  }
}
