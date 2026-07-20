import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/friend_service.dart';

class FriendRequestCard extends StatelessWidget {
  const FriendRequestCard({
    super.key,
    required this.requestId,
    required this.data,
  });

  final String requestId;
  final Map<String, dynamic> data;

  static const lime = Color(0xFFD6FF60);
  static const card = Color(0xFF1A1F17);
  static const soft = Color(0xFFB7C2A8);

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
    final name = (data['fromName'] ?? 'User').toString();
    final photo = (data['fromPhotoBase64'] ?? '').toString();
    final bytes = _decode(photo);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: lime.withOpacity(0.14),
            backgroundImage: bytes != null ? MemoryImage(bytes) : null,
            child: bytes == null
                ? Text(
                    name[0].toUpperCase(),
                    style: GoogleFonts.outfit(
                      color: lime,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Sent you a friend request',
                  style: GoogleFonts.outfit(color: soft, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => FriendService.rejectRequest(requestId),
            icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
          ),
          IconButton(
            onPressed: () => FriendService.acceptRequest(requestId, data),
            icon: const Icon(Icons.check_circle_rounded, color: lime),
          ),
        ],
      ),
    );
  }
}
