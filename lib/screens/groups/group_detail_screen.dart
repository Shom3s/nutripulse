import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/group_service.dart';
import '../chat/group_chat_screen.dart';
import '../leaderboard/leaderboard_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({
    super.key,
    required this.groupId,
    required this.groupData,
  });

  final String groupId;
  final Map<String, dynamic> groupData;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  static const bg = Color(0xFF0F140D);
  static const lime = Color(0xFFD6FF60);
  static const card = Color(0xFF1A1F17);
  static const soft = Color(0xFFB7C2A8);

  bool _joining = false;

  String get _name => (widget.groupData['name'] ?? 'Group').toString();
  String get _desc => (widget.groupData['description'] ?? '').toString();
  String get _icon => (widget.groupData['icon'] ?? '✨').toString();

  Future<void> _joinAndOpenChat() async {
    if (_joining) return;

    setState(() => _joining = true);

    try {
      await GroupService.joinGroup(widget.groupId);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              GroupChatScreen(groupId: widget.groupId, groupName: _name),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not join group: $e',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openChat() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            GroupChatScreen(groupId: widget.groupId, groupName: _name),
      ),
    );
  }

  void _openLeaderboard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeaderboardScreen(
          groupId: widget.groupId,
          title: '$_name Leaderboard',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      extendBody: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.18,
            colors: [Color(0xFF253618), Color(0xFF10150D), Color(0xFF070907)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: StreamBuilder<bool>(
            stream: GroupService.isMemberStream(widget.groupId),
            builder: (context, memberSnap) {
              final joined = memberSnap.data ?? false;

              return CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(child: _topBar()),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      10,
                      20,
                      MediaQuery.of(context).padding.bottom + 110,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate.fixed([
                        _heroCard(joined),
                        const SizedBox(height: 16),
                        _leaderboardCard(),
                      ]),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              _name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 27,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroCard(bool joined) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_icon, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 10),
          Text(
            _name,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 25,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _desc,
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          StreamBuilder<int>(
            stream: GroupService.membersCountStream(widget.groupId),
            builder: (context, snapshot) {
              return Text(
                '${snapshot.data ?? 0} members',
                style: GoogleFonts.outfit(
                  color: lime,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _button(
                  joined ? 'Open Chat' : 'Join & Chat',
                  joined ? Icons.chat_bubble_rounded : Icons.group_add_rounded,
                  lime,
                  Colors.black,
                  joined ? _openChat : _joinAndOpenChat,
                  loading: !joined && _joining,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _button(
                  'Leaderboard',
                  Icons.emoji_events_rounded,
                  Colors.white.withOpacity(0.08),
                  Colors.white,
                  _openLeaderboard,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _leaderboardCard() {
    return GestureDetector(
      onTap: _openLeaderboard,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: _box(),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: lime.withOpacity(0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                color: lime,
                size: 27,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'View group leaderboard and XP rankings.',
                style: GoogleFonts.outfit(
                  color: soft,
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: lime, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _button(
    String label,
    IconData icon,
    Color bgColor,
    Color fgColor,
    VoidCallback? onTap, {
    bool loading = false,
  }) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: fgColor,
                  strokeWidth: 2.4,
                ),
              )
            else
              Icon(icon, color: fgColor, size: 18),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: fgColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _box() {
    return BoxDecoration(
      color: card.withOpacity(0.88),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
    );
  }
}
