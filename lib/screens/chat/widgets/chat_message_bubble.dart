import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/group_chat_service.dart';
import 'emoji_reaction_picker.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.groupId,
    required this.messageId,
    required this.data,
  });

  final String groupId;
  final String messageId;
  final Map<String, dynamic> data;

  static const lime = Color(0xFFD6FF60);
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
    final mine = data['uid'] == GroupChatService.uid;
    final text = (data['text'] ?? '').toString();
    final image = (data['imageBase64'] ?? '').toString();
    final imageBytes = _decode(image);
    final isAi = data['isAiTip'] == true;
    final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (_) => EmojiReactionPicker(
              onSelected: (emoji) => GroupChatService.addReaction(
                groupId: groupId,
                messageId: messageId,
                emoji: emoji,
              ),
              onPin: () => GroupChatService.pinMessage(
                groupId: groupId,
                messageId: messageId,
                message: data,
              ),
            ),
          );
        },
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isAi
                ? lime.withOpacity(0.16)
                : mine
                ? lime
                : const Color(0xFF1A1F17),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Text(
                  (data['username'] ?? 'User').toString(),
                  style: GoogleFonts.outfit(
                    color: isAi ? lime : soft,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              if (imageBytes != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    imageBytes,
                    height: 190,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              if (text.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  text,
                  style: GoogleFonts.outfit(
                    color: mine ? Colors.black : Colors.white,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (reactions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 5,
                  children: reactions.entries
                      .map(
                        (e) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '${e.key} ${e.value}',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
