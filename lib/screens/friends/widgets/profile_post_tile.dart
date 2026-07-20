import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../models/community_post.dart';

class ProfilePostTile extends StatelessWidget {
  const ProfilePostTile({super.key, required this.post});

  final CommunityPost post;

  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color soft = Color(0xFFB7C2A8);

  Uint8List? _decode(String value) {
    if (value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'meal':
        return Icons.restaurant_rounded;
      case 'workout':
        return Icons.fitness_center_rounded;
      case 'steps':
        return Icons.directions_walk_rounded;
      case 'water':
        return Icons.water_drop_rounded;
      case 'streak':
        return Icons.local_fire_department_rounded;
      case 'progress':
        return Icons.trending_up_rounded;
      default:
        return Icons.forum_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = _decode(post.imageBase64);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: card.withOpacity(0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.055)),
      ),
      child: Row(
        children: [
          if (imageBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.memory(
                imageBytes,
                width: 82,
                height: 82,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                cacheWidth: 180,
              ),
            )
          else
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: lime.withOpacity(0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(_typeIcon(post.type), color: lime, size: 28),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 82,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.caption.isEmpty ? 'NutriPulse update' : post.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 14.5,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(_typeIcon(post.type), color: lime, size: 13),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          timeago.format(post.createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: soft,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      _metric(Icons.favorite_rounded, '${post.likesCount}'),
                      const SizedBox(width: 8),
                      _metric(
                        Icons.mode_comment_rounded,
                        '${post.commentsCount}',
                      ),
                      const SizedBox(width: 8),
                      if (post.xp > 0)
                        _metric(Icons.bolt_rounded, '${post.xp} XP'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, color: lime, size: 12),
          const SizedBox(width: 4),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
