import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../friend_profile_screen.dart';

class FriendUserCard extends StatelessWidget {
  const FriendUserCard({super.key, required this.uid, required this.data});

  final String uid;
  final Map<String, dynamic> data;

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

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? data['username'] ?? 'NutriPulse User')
        .toString();
    final photo = (data['photoBase64'] ?? data['userImageBase64'] ?? '')
        .toString();
    final avatar = _decode(photo);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FriendProfileScreen(uid: uid, initialData: data),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: card.withOpacity(0.92),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: lime.withOpacity(0.14),
              backgroundImage: avatar != null ? MemoryImage(avatar) : null,
              child: avatar == null
                  ? Text(
                      name.isEmpty ? 'U' : name[0].toUpperCase(),
                      style: GoogleFonts.outfit(
                        color: lime,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: soft, size: 24),
          ],
        ),
      ),
    );
  }
}
