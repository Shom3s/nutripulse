import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'daily_report_detail_screen.dart';

class NotificationCenterScreen extends StatelessWidget {
  const NotificationCenterScreen({super.key});

  static const Color bg = Color(0xFF10150D);
  static const Color surface = Color(0xFF1A2214);
  static const Color lime = Color(0xFFD6FF60);
  static const Color soft = Color(0xFFE8F1D5);

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Stream<QuerySnapshot<Map<String, dynamic>>> _notificationsStream() {
    final uid = _uid;

    if (uid == null) {
      return const Stream.empty();
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  Future<void> _markAllRead() async {
    final uid = _uid;
    if (uid == null) return;

    final docs = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .limit(100)
        .get();

    final batch = FirebaseFirestore.instance.batch();

    for (final doc in docs.docs) {
      batch.update(doc.reference, {'read': true});
    }

    await batch.commit();
  }

  Future<void> _handleTap({
    required BuildContext context,
    required DocumentReference ref,
    required Map<String, dynamic> data,
  }) async {
    await ref.update({'read': true});

    final type = (data['type'] ?? '').toString();

    if (type == 'daily_report') {
      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DailyReportDetailScreen(
            reportDate: (data['reportDate'] ?? '').toString(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _notificationsStream(),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ?? [];

                  if (snapshot.connectionState == ConnectionState.waiting &&
                      docs.isEmpty) {
                    return const Center(
                      child: CircularProgressIndicator(color: lime),
                    );
                  }

                  if (docs.isEmpty) {
                    return _emptyState();
                  }

                  return ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
                    itemCount: docs.length + _sectionHeaderCount(docs),
                    itemBuilder: (context, index) {
                      final item = _itemAt(docs, index);

                      if (item is _NotificationSection) {
                        return _sectionTitle(item.title);
                      }

                      final doc =
                          item as QueryDocumentSnapshot<Map<String, dynamic>>;
                      final data = doc.data();

                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(
                          milliseconds: 300 + (index * 32).clamp(0, 240),
                        ),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Transform.translate(
                            offset: Offset(0, 12 * (1 - value)),
                            child: Opacity(opacity: value, child: child),
                          );
                        },
                        child: _notificationTile(
                          data: data,
                          onTap: () => _handleTap(
                            context: context,
                            ref: doc.reference,
                            data: data,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _sectionHeaderCount(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    bool hasToday = false;
    bool hasEarlier = false;

    for (final doc in docs) {
      if (_isToday(doc.data()['createdAt'])) {
        hasToday = true;
      } else {
        hasEarlier = true;
      }
    }

    return (hasToday ? 1 : 0) + (hasEarlier ? 1 : 0);
  }

  Object _itemAt(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int visualIndex,
  ) {
    final items = <Object>[];
    bool addedToday = false;
    bool addedEarlier = false;

    for (final doc in docs) {
      final today = _isToday(doc.data()['createdAt']);

      if (today && !addedToday) {
        items.add(const _NotificationSection('Today'));
        addedToday = true;
      }

      if (!today && !addedEarlier) {
        items.add(const _NotificationSection('Earlier'));
        addedEarlier = true;
      }

      items.add(doc);
    }

    return items[visualIndex];
  }

  bool _isToday(dynamic timestamp) {
    if (timestamp is! Timestamp) return true;

    final date = timestamp.toDate();
    final now = DateTime.now();

    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
      child: Row(
        children: [
          _circleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Notifications',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 31,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.9,
              ),
            ),
          ),
          GestureDetector(
            onTap: _markAllRead,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Text(
                'Read all',
                style: GoogleFonts.outfit(
                  color: lime,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  Widget _notificationTile({
    required Map<String, dynamic> data,
    required VoidCallback onTap,
  }) {
    final title = (data['title'] ?? '').toString();
    final body = (data['body'] ?? '').toString();
    final type = (data['type'] ?? 'general').toString();
    final read = data['read'] == true;
    final actorName = (data['actorName'] ?? '').toString();
    final time = _timeAgo(data['createdAt']);

    final text = _displayText(
      type: type,
      title: title,
      body: body,
      actorName: actorName,
    );

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: read ? Colors.transparent : lime.withOpacity(0.055),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _colorFor(type).withOpacity(0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _colorFor(type).withOpacity(0.22),
                    ),
                  ),
                  child: Icon(_iconFor(type), color: _colorFor(type), size: 24),
                ),
                if (!read)
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30),
                        shape: BoxShape.circle,
                        border: Border.all(color: bg, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 13),
            Expanded(
              child: RichText(
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: [
                    if (actorName.isNotEmpty)
                      TextSpan(
                        text: '$actorName ',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 13.8,
                          height: 1.25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    TextSpan(
                      text: text,
                      style: GoogleFonts.outfit(
                        color: Colors.white.withOpacity(0.88),
                        fontSize: 13.8,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: '  $time',
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.58),
                        fontSize: 12.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            _rightPreview(type),
          ],
        ),
      ),
    );
  }

  Widget _rightPreview(String type) {
    if (type == 'like') {
      return const Icon(
        Icons.favorite_rounded,
        color: Color(0xFFFF4D6D),
        size: 24,
      );
    }

    if (type == 'comment' || type == 'chat' || type == 'story_reaction') {
      return Container(
        width: 35,
        height: 35,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Icon(_iconFor(type), color: lime, size: 17),
      );
    }

    if (type == 'friend_request' || type == 'friend_accept') {
      return Container(
        width: 36,
        height: 28,
        decoration: BoxDecoration(
          color: lime,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Center(
          child: Text(
            type == 'friend_request' ? 'View' : 'Chat',
            style: GoogleFonts.outfit(
              color: Colors.black,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
    }

    return const Icon(Icons.chevron_right_rounded, color: soft, size: 24);
  }

  String _displayText({
    required String type,
    required String title,
    required String body,
    required String actorName,
  }) {
    if (type == 'daily_report') {
      return body.isEmpty ? 'Your daily report is ready.' : body;
    }

    if (body.isNotEmpty) {
      if (actorName.isNotEmpty && body.startsWith(actorName)) {
        return body.replaceFirst(actorName, '').trim();
      }
      return body;
    }

    switch (type) {
      case 'like':
        return 'liked your post.';
      case 'comment':
        return 'commented on your post.';
      case 'chat':
        return 'sent you a message.';
      case 'story_reaction':
        return 'reacted to your story.';
      case 'friend_request':
        return 'sent you a friend request.';
      case 'friend_accept':
        return 'accepted your friend request.';
      case 'group':
        return 'sent a group update.';
      default:
        return title.isEmpty ? 'sent you a notification.' : title;
    }
  }

  String _timeAgo(dynamic timestamp) {
    if (timestamp is! Timestamp) return 'now';

    final date = timestamp.toDate();
    final diff = DateTime.now().difference(date);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'daily_report':
        return Icons.insert_chart_rounded;
      case 'chat':
        return Icons.forum_rounded;
      case 'story_reaction':
        return Icons.auto_awesome_rounded;
      case 'friend_request':
        return Icons.person_add_alt_1_rounded;
      case 'friend_accept':
        return Icons.verified_rounded;
      case 'like':
        return Icons.favorite_rounded;
      case 'comment':
        return Icons.mode_comment_rounded;
      case 'group':
        return Icons.groups_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'like':
        return const Color(0xFFFF4D6D);
      case 'daily_report':
      case 'comment':
      case 'chat':
      case 'story_reaction':
        return lime;
      case 'friend_request':
      case 'friend_accept':
        return const Color(0xFF7CFFB2);
      case 'group':
        return const Color(0xFF8FB7FF);
      default:
        return lime;
    }
  }

  Widget _emptyState() {
    return Center(
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
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                color: lime,
                size: 38,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No notifications yet',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Likes, comments, story reactions, reports and chats will appear here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: soft.withOpacity(0.72),
                fontSize: 13.3,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: surface.withOpacity(0.92),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _NotificationSection {
  const _NotificationSection(this.title);

  final String title;
}
