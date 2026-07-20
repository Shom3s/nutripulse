import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/group_service.dart';
import '../chat/group_chat_screen.dart';
import 'group_detail_screen.dart';
import 'widgets/group_card.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  static const lime = Color(0xFFD6FF60);
  static const soft = Color(0xFFB7C2A8);

  @override
  void initState() {
    super.initState();
    GroupService.seedDefaultGroups();
  }

  Future<void> _openGroup(String id, Map<String, dynamic> data) async {
    final joined = await GroupService.isMemberStream(id).first;
    if (!mounted) return;

    final name = (data['name'] ?? 'Group').toString();

    if (joined) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(groupId: id, groupName: name),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupDetailScreen(groupId: id, groupData: data),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // This widget is placed inside CommunityScreen's CustomScrollView.
    // Do NOT use Expanded/ListView with its own scrolling here.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Text(
            'Groups',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: GroupService.groupsStream(),
          builder: (_, snapshot) {
            final docs = snapshot.data?.docs ?? [];

            if (snapshot.connectionState == ConnectionState.waiting &&
                docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(top: 40, bottom: 160),
                child: Center(child: CircularProgressIndicator(color: lime)),
              );
            }

            if (docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(top: 40, bottom: 120),
                child: Center(
                  child: Text(
                    'Creating groups...',
                    style: TextStyle(color: soft),
                  ),
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(
                    milliseconds: 260 + (i * 35).clamp(0, 180),
                  ),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) {
                    return Transform.translate(
                      offset: Offset(0, 16 * (1 - t)),
                      child: Opacity(opacity: t, child: child),
                    );
                  },
                  child: GroupCard(
                    groupId: docs[i].id,
                    data: docs[i].data(),
                    onTap: () => _openGroup(docs[i].id, docs[i].data()),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
