import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EmojiReactionPicker extends StatelessWidget {
  const EmojiReactionPicker({
    super.key,
    required this.onSelected,
    required this.onPin,
  });

  final ValueChanged<String> onSelected;
  final VoidCallback onPin;

  static const lime = Color(0xFFD6FF60);
  static const bg = Color(0xFF10150D);

  @override
  Widget build(BuildContext context) {
    const emojis = ['❤️', '🔥', '💪', '👏', '😂', '🥗'];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      decoration: const BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: emojis
                .map(
                  (e) => GestureDetector(
                    onTap: () {
                      onSelected(e);
                      Navigator.pop(context);
                    },
                    child: Text(e, style: const TextStyle(fontSize: 30)),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () {
              onPin();
              Navigator.pop(context);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: lime,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                'Pin Message',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
