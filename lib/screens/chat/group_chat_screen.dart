import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/group_chat_service.dart';
import '../../services/group_service.dart';
import '../leaderboard/leaderboard_screen.dart';
import 'widgets/chat_message_bubble.dart';

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  static const bg = Color(0xFF0F140D);
  static const lime = Color(0xFFD6FF60);
  static const card = Color(0xFF1A1F17);
  static const soft = Color(0xFFB7C2A8);

  final TextEditingController ctrl = TextEditingController();
  final ImagePicker picker = ImagePicker();

  bool _isSending = false;

  @override
  void dispose() {
    GroupChatService.setTyping(widget.groupId, false);
    ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = ctrl.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    ctrl.clear();

    try {
      await GroupChatService.sendMessage(groupId: widget.groupId, text: text);
      await GroupChatService.setTyping(widget.groupId, false);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendImage() async {
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 72,
      maxWidth: 1100,
    );
    if (picked == null) return;

    final b64 = await GroupChatService.fileToBase64(File(picked.path));
    await GroupChatService.sendMessage(
      groupId: widget.groupId,
      text: '',
      imageBase64: b64,
    );
  }

  void _openLeaderboard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeaderboardScreen(
          groupId: widget.groupId,
          title: '${widget.groupName} Leaderboard',
        ),
      ),
    );
  }

  void _openMembersSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          _MembersSheet(groupId: widget.groupId, groupName: widget.groupName),
    );
  }

  Future<void> _toggleMute(bool muted) async {
    await GroupService.setGroupMuted(groupId: widget.groupId, muted: !muted);
  }

  Future<void> _confirmLeaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Leave group?',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          'You will no longer be able to send messages until you join again.',
          style: GoogleFonts.outfit(color: soft, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: soft)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Leave',
              style: GoogleFonts.outfit(
                color: Colors.redAccent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await GroupService.leaveGroup(widget.groupId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      extendBody: true,
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.18,
            colors: [Color(0xFF253618), Color(0xFF10150D), Color(0xFF070907)],
          ),
        ),
        child: StreamBuilder<bool>(
          stream: GroupService.isMemberStream(widget.groupId),
          builder: (context, memberSnap) {
            final joined = memberSnap.data ?? false;

            return SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _topBar(joined),
                  if (!joined)
                    Expanded(child: _lockedChat())
                  else ...[
                    _pinnedBanner(),
                    _typingBar(),
                    Expanded(child: _messagesList()),
                    _inputBar(),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(bool joined) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 8),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.20),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.045)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: lime.withOpacity(0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups_rounded, color: lime, size: 23),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: _openMembersSheet,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.groupName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 17.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    joined ? 'Tap for members' : 'join required',
                    style: GoogleFonts.outfit(
                      color: joined ? lime : soft,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (joined) _chatMenu(),
        ],
      ),
    );
  }

  Widget _chatMenu() {
    return StreamBuilder<bool>(
      stream: GroupService.isGroupMutedStream(widget.groupId),
      builder: (context, snapshot) {
        final muted = snapshot.data ?? false;

        return PopupMenuButton<String>(
          tooltip: 'Group options',
          color: const Color(0xFF1A1F17),
          elevation: 10,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          onSelected: (value) {
            if (value == 'mute') _toggleMute(muted);
            if (value == 'leaderboard') _openLeaderboard();
            if (value == 'members') _openMembersSheet();
            if (value == 'leave') _confirmLeaveGroup();
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'mute',
              child: _menuRow(
                muted
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_off_rounded,
                muted ? 'Unmute Group' : 'Mute Group',
                lime,
              ),
            ),
            PopupMenuItem(
              value: 'leaderboard',
              child: _menuRow(Icons.emoji_events_rounded, 'Leaderboard', lime),
            ),
            PopupMenuItem(
              value: 'members',
              child: _menuRow(Icons.groups_rounded, 'Members', lime),
            ),
            PopupMenuItem(
              value: 'leave',
              child: _menuRow(
                Icons.logout_rounded,
                'Leave Group',
                Colors.redAccent,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _menuRow(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 10),
        Text(
          label,
          style: GoogleFonts.outfit(
            color: color == Colors.redAccent ? Colors.redAccent : Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _lockedChat() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: lime.withOpacity(0.12),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.lock_rounded, color: lime, size: 42),
            ),
            const SizedBox(height: 18),
            Text(
              'Join the group to access chat',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Only group members can send messages and images.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: soft,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pinnedBanner() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: GroupChatService.pinnedMessagesStream(widget.groupId),
      builder: (_, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        final data = docs.first.data();
        final text = (data['text'] ?? 'Pinned message').toString();

        return Container(
          margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: lime.withOpacity(0.13),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: lime.withOpacity(0.16)),
          ),
          child: Row(
            children: [
              const Icon(Icons.push_pin_rounded, color: lime, size: 18),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  text.isEmpty ? 'Image message pinned' : text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _typingBar() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: GroupChatService.typingStream(widget.groupId),
      builder: (_, snapshot) {
        final docs =
            snapshot.data?.docs
                .where((d) => d.id != GroupChatService.uid)
                .toList() ??
            [];

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: docs.isEmpty
              ? const SizedBox(height: 0)
              : Padding(
                  key: const ValueKey('typing'),
                  padding: const EdgeInsets.only(bottom: 4, top: 4),
                  child: Text(
                    '${docs.first.data()['name'] ?? 'Someone'} is typing...',
                    style: GoogleFonts.outfit(
                      color: lime,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _messagesList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: GroupChatService.messagesStream(widget.groupId),
      builder: (_, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Text(
              'No messages yet. Start the conversation.',
              style: GoogleFonts.outfit(color: soft),
            ),
          );
        }

        return ListView.builder(
          reverse: true,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          itemCount: docs.length,
          itemBuilder: (_, i) => TweenAnimationBuilder<double>(
            key: ValueKey(docs[i].id),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Transform.translate(
              offset: Offset(0, 10 * (1 - t)),
              child: Opacity(opacity: t, child: child),
            ),
            child: ChatMessageBubble(
              groupId: widget.groupId,
              messageId: docs[i].id,
              data: docs[i].data(),
            ),
          ),
        );
      },
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
        decoration: BoxDecoration(
          color: bg.withOpacity(0.84),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.06)),
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: _sendImage,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.075),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_rounded, color: lime, size: 24),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: card.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: TextField(
                  controller: ctrl,
                  minLines: 1,
                  maxLines: 4,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  onChanged: (v) => GroupChatService.setTyping(
                    widget.groupId,
                    v.trim().isNotEmpty,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Message group...',
                    hintStyle: GoogleFonts.outfit(
                      color: soft.withOpacity(0.72),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: lime,
                  shape: BoxShape.circle,
                ),
                child: _isSending
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 2.2,
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        color: Colors.black,
                        size: 21,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MembersSheet extends StatelessWidget {
  const _MembersSheet({required this.groupId, required this.groupName});

  final String groupId;
  final String groupName;

  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color soft = Color(0xFFB7C2A8);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.88,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: Row(
                  children: [
                    Text(
                      'Members',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    StreamBuilder<int>(
                      stream: GroupService.membersCountStream(groupId),
                      builder: (context, snapshot) {
                        return Text(
                          '${snapshot.data ?? 0}',
                          style: GoogleFonts.outfit(
                            color: lime,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: GroupService.membersStream(groupId),
                  builder: (context, snapshot) {
                    final docs = snapshot.data?.docs ?? [];

                    if (docs.isEmpty) {
                      return Center(
                        child: Text(
                          'No members yet',
                          style: GoogleFonts.outfit(color: soft),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data();
                        final name = (data['name'] ?? 'Member').toString();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: card,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.06),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: lime.withOpacity(0.15),
                                child: Text(
                                  name.isEmpty ? 'U' : name[0].toUpperCase(),
                                  style: GoogleFonts.outfit(
                                    color: lime,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  name,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
