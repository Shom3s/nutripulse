import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/private_chat_service.dart';

class PrivateChatScreen extends StatefulWidget {
  const PrivateChatScreen({
    super.key,
    required this.friendUid,
    required this.friendName,
    this.friendPhotoBase64 = '',
  });

  final String friendUid;
  final String friendName;
  final String friendPhotoBase64;

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color soft = Color(0xFFB7C2A8);

  final TextEditingController _messageCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  bool _sending = false;
  bool _hasText = false;
  bool _chatReady = false;

  @override
  void initState() {
    super.initState();
    _prepareChat();

    _messageCtrl.addListener(() {
      final hasText = _messageCtrl.text.trim().isNotEmpty;
      if (hasText != _hasText && mounted) {
        setState(() => _hasText = hasText);
      }
    });

    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _prepareChat() async {
    try {
      await PrivateChatService.ensureChat(
        friendUid: widget.friendUid,
        friendName: widget.friendName,
        friendPhotoBase64: widget.friendPhotoBase64,
      );
      await PrivateChatService.markAsRead(widget.friendUid);

      if (mounted) setState(() => _chatReady = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _chatReady = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to open chat: $e',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: card,
        ),
      );
    }
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Uint8List? _decodeAvatar(String value) {
    if (value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> _send() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    _messageCtrl.clear();

    try {
      await PrivateChatService.sendTextMessage(
        friendUid: widget.friendUid,
        friendName: widget.friendName,
        friendPhotoBase64: widget.friendPhotoBase64,
        text: text,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (!mounted) return;
      _messageCtrl.text = text;
      _messageCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageCtrl.text.length),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Message not sent: $e',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: card,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;

    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _clearChat() async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ClearChatSheet(friendName: widget.friendName),
    );

    if (confirm != true) return;

    await PrivateChatService.clearChatForEveryone(widget.friendUid);
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _decodeAvatar(widget.friendPhotoBase64);

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF243519), Color(0xFF0F140D), Color(0xFF060806)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _header(avatar),
              Expanded(
                child: !_chatReady
                    ? const Center(
                        child: CircularProgressIndicator(color: lime),
                      )
                    : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: PrivateChatService.messagesStream(
                          widget.friendUid,
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return _emptyState();
                          }

                          final docs = snapshot.data?.docs ?? [];

                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            PrivateChatService.markAsRead(widget.friendUid);
                            _scrollToBottom();
                          });

                          if (docs.isEmpty) {
                            return _emptyState();
                          }

                          return ListView.builder(
                            controller: _scrollCtrl,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final data = docs[index].data();
                              final isMe =
                                  data['senderId'] ==
                                  PrivateChatService.currentUid;

                              final previous = index > 0
                                  ? docs[index - 1].data()
                                  : null;

                              final showDate = _shouldShowDate(
                                previous?['createdAt'],
                                data['createdAt'],
                              );

                              return Column(
                                children: [
                                  if (showDate)
                                    _DateChip(createdAt: data['createdAt']),
                                  _MessageBubble(
                                    isMe: isMe,
                                    text: (data['text'] ?? '').toString(),
                                    createdAt: data['createdAt'],
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
              ),
              _composer(),
            ],
          ),
        ),
      ),
    );
  }

  bool _shouldShowDate(dynamic previous, dynamic current) {
    if (current is! Timestamp) return false;
    if (previous is! Timestamp) return true;

    final p = previous.toDate();
    final c = current.toDate();

    return p.year != c.year || p.month != c.month || p.day != c.day;
  }

  Widget _header(Uint8List? avatar) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: bg.withOpacity(0.72),
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
            ),
          ),
          child: Row(
            children: [
              _circleButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(width: 12),
              Stack(
                children: [
                  Hero(
                    tag: 'private-chat-avatar-${widget.friendUid}',
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: lime.withOpacity(0.14),
                      backgroundImage: avatar != null
                          ? MemoryImage(avatar)
                          : null,
                      child: avatar == null
                          ? Text(
                              widget.friendName.isEmpty
                                  ? 'F'
                                  : widget.friendName[0].toUpperCase(),
                              style: GoogleFonts.outfit(
                                color: lime,
                                fontWeight: FontWeight.w900,
                              ),
                            )
                          : null,
                    ),
                  ),
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: lime,
                        shape: BoxShape.circle,
                        border: Border.all(color: bg, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.friendName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: lime,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Private chat',
                          style: GoogleFonts.outfit(
                            color: soft.withOpacity(0.72),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _circleButton(icon: Icons.more_horiz_rounded, onTap: _clearChat),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 540),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: Opacity(opacity: value, child: child),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: lime.withOpacity(0.13),
                  shape: BoxShape.circle,
                  border: Border.all(color: lime.withOpacity(0.22)),
                  boxShadow: [
                    BoxShadow(
                      color: lime.withOpacity(0.15),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.forum_rounded, color: lime, size: 36),
              ),
              const SizedBox(height: 18),
              Text(
                'Start the conversation',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Chat with ${widget.friendName}, share progress, and motivate each other.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: soft.withOpacity(0.75),
                  fontSize: 13.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composer() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            14,
            10,
            14,
            12 + MediaQuery.of(context).padding.bottom * 0.2,
          ),
          decoration: BoxDecoration(
            color: bg.withOpacity(0.76),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.06)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Activity sharing coming soon',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
                      ),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: card,
                    ),
                  );
                },
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 23,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    color: card.withOpacity(0.94),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _focusNode.hasFocus
                          ? lime.withOpacity(0.32)
                          : Colors.white.withOpacity(0.07),
                    ),
                  ),
                  child: TextField(
                    focusNode: _focusNode,
                    controller: _messageCtrl,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Message ${widget.friendName}...',
                      hintStyle: GoogleFonts.outfit(
                        color: soft.withOpacity(0.55),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _send,
                child: AnimatedScale(
                  scale: _hasText ? 1 : 0.92,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _hasText ? lime : Colors.white.withOpacity(0.10),
                      shape: BoxShape.circle,
                      boxShadow: _hasText
                          ? [
                              BoxShadow(
                                color: lime.withOpacity(0.26),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : [],
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.black,
                            ),
                          )
                        : Icon(
                            Icons.arrow_upward_rounded,
                            color: _hasText
                                ? Colors.black
                                : soft.withOpacity(0.7),
                            size: 25,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circleButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: card.withOpacity(0.86),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.createdAt});

  final dynamic createdAt;

  @override
  Widget build(BuildContext context) {
    DateTime? date;

    if (createdAt is Timestamp) {
      date = (createdAt as Timestamp).toDate();
    }

    final label = date == null
        ? 'Today'
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Text(
            label,
            style: GoogleFonts.outfit(
              color: const Color(0xFFB7C2A8),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.isMe,
    required this.text,
    required this.createdAt,
  });

  final bool isMe;
  final String text;
  final dynamic createdAt;

  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color soft = Color(0xFFB7C2A8);

  @override
  Widget build(BuildContext context) {
    final time = _formatTime(createdAt);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(isMe ? 12 * (1 - value) : -12 * (1 - value), 0),
            child: Opacity(opacity: value, child: child),
          );
        },
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.76,
          ),
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 8),
          decoration: BoxDecoration(
            gradient: isMe
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFD6FF60), Color(0xFFBFFF2E)],
                  )
                : null,
            color: isMe ? null : card.withOpacity(0.95),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: Radius.circular(isMe ? 22 : 7),
              bottomRight: Radius.circular(isMe ? 7 : 22),
            ),
            border: isMe
                ? null
                : Border.all(color: Colors.white.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: GoogleFonts.outfit(
                  color: isMe ? Colors.black : Colors.white,
                  fontSize: 14.6,
                  height: 1.28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: GoogleFonts.outfit(
                      color: isMe
                          ? Colors.black.withOpacity(0.55)
                          : soft.withOpacity(0.58),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.done_all_rounded,
                      size: 13,
                      color: Colors.black.withOpacity(0.48),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(dynamic value) {
    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    }

    if (date == null) return 'Sending';

    final h = date.hour > 12
        ? date.hour - 12
        : date.hour == 0
        ? 12
        : date.hour;
    final m = date.minute.toString().padLeft(2, '0');
    final ap = date.hour >= 12 ? 'PM' : 'AM';

    return '$h:$m $ap';
  }
}

class _ClearChatSheet extends StatelessWidget {
  const _ClearChatSheet({required this.friendName});

  final String friendName;

  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color soft = Color(0xFFB7C2A8);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      decoration: const BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Clear chat?',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This will delete messages in this chat. Use only for testing or cleanup.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: soft.withOpacity(0.72),
              fontSize: 13.2,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _sheetButton(
                  label: 'Cancel',
                  color: card,
                  textColor: Colors.white,
                  onTap: () => Navigator.pop(context, false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _sheetButton(
                  label: 'Clear',
                  color: lime,
                  textColor: Colors.black,
                  onTap: () => Navigator.pop(context, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sheetButton({
    required String label,
    required Color color,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: textColor,
            fontSize: 14.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
