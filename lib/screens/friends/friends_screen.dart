import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/friend_service.dart';
import '../chat/private_chat_screen.dart';
import 'friend_profile_screen.dart';
import 'widgets/friend_request_card.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  static const bg = Color(0xFF0F140D);
  static const lime = Color(0xFFD6FF60);
  static const card = Color(0xFF1A1F17);
  static const soft = Color(0xFFB7C2A8);

  int tab = 0;

  Uint8List? _decode(String value) {
    if (value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  void _openProfile(String uid) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: FriendProfileScreen(uid: uid),
        ),
      ),
    );
  }

  void _openChat({
    required String uid,
    required String name,
    String photoBase64 = '',
  }) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, animation, __) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: PrivateChatScreen(
              friendUid: uid,
              friendName: name,
              friendPhotoBase64: photoBase64,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // No Scaffold here. This keeps the Friends section blended with
    // the Community screen background and removes the dark box.
    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Friends',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _tabs(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: tab == 0
                  ? _friendsList()
                  : tab == 1
                  ? _discoverUsers()
                  : _requests(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    final labels = ['Friends', 'Discover', 'Requests'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = tab == i;

          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => tab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 10),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? lime : Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: selected ? Colors.black : soft,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _friendsList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FriendService.followingStream(),
      builder: (_, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      color: lime.withOpacity(0.13),
                      shape: BoxShape.circle,
                      border: Border.all(color: lime.withOpacity(0.24)),
                    ),
                    child: const Icon(
                      Icons.forum_rounded,
                      color: lime,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'No friends yet',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add friends from Discover, then chat with them here.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: soft,
                      fontSize: 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          key: const ValueKey('friends-list'),
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data = docs[i].data();
            final uid = (data['uid'] ?? docs[i].id).toString();
            final name = (data['name'] ?? 'Friend').toString();
            final photo = (data['photoBase64'] ?? '').toString();
            final bytes = _decode(photo);

            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 280 + (i * 42).clamp(0, 260)),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 14 * (1 - value)),
                  child: Opacity(opacity: value, child: child),
                );
              },
              child: GestureDetector(
                onTap: () =>
                    _openChat(uid: uid, name: name, photoBase64: photo),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.075),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.075)),
                  ),
                  child: Row(
                    children: [
                      Hero(
                        tag: 'private-chat-avatar-$uid',
                        child: CircleAvatar(
                          radius: 25,
                          backgroundColor: lime.withOpacity(0.14),
                          backgroundImage: bytes != null
                              ? MemoryImage(bytes)
                              : null,
                          child: bytes == null
                              ? Text(
                                  name.isEmpty ? 'F' : name[0].toUpperCase(),
                                  style: GoogleFonts.outfit(
                                    color: lime,
                                    fontWeight: FontWeight.w900,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap to open private chat',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: soft.withOpacity(0.76),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: lime,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: lime.withOpacity(0.22),
                              blurRadius: 14,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.chat_bubble_rounded,
                          color: Colors.black,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _discoverUsers() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FriendService.followingStream(),
      builder: (_, followingSnapshot) {
        final followingIds =
            followingSnapshot.data?.docs.map((doc) {
              final data = doc.data();
              return (data['uid'] ?? doc.id).toString();
            }).toSet() ??
            <String>{};

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FriendService.usersStream(),
          builder: (_, snapshot) {
            final rawDocs = snapshot.data?.docs ?? [];

            final docs = rawDocs.where((doc) {
              final uid = doc.id;
              if (uid == FriendService.currentUid) return false;
              if (followingIds.contains(uid)) return false;
              return true;
            }).toList();

            if (docs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 34),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: lime.withOpacity(0.13),
                          shape: BoxShape.circle,
                          border: Border.all(color: lime.withOpacity(0.22)),
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          color: lime,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'No new people to discover',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'People who are already your friends are hidden here.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: soft.withOpacity(0.76),
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

            return ListView.builder(
              key: const ValueKey('discover-list'),
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final uid = docs[i].id;
                final data = docs[i].data();
                final name = (data['name'] ?? 'NutriPulse User').toString();
                final email = (data['email'] ?? '').toString();
                final photo = (data['photoBase64'] ?? '').toString();
                final bytes = _decode(photo);

                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(
                    milliseconds: 280 + (i * 40).clamp(0, 220),
                  ),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, 12 * (1 - value)),
                      child: Opacity(opacity: value, child: child),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.075),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.075),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: lime.withOpacity(0.14),
                          backgroundImage: bytes != null
                              ? MemoryImage(bytes)
                              : null,
                          child: bytes == null
                              ? Text(
                                  name.isEmpty ? 'N' : name[0].toUpperCase(),
                                  style: GoogleFonts.outfit(
                                    color: lime,
                                    fontWeight: FontWeight.w900,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _openProfile(uid),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  email.isEmpty ? 'NutriPulse member' : email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    color: soft.withOpacity(0.72),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            await FriendService.sendFriendRequest(
                              toUid: uid,
                              toName: name,
                            );

                            if (!mounted) return;

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Friend request sent',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                backgroundColor: card,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: lime,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              'Add',
                              style: GoogleFonts.outfit(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _requests() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FriendService.incomingRequestsStream(),
      builder: (_, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Text(
              'No friend requests',
              style: GoogleFonts.outfit(color: soft),
            ),
          );
        }

        return ListView.builder(
          key: const ValueKey('request-list'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          physics: const BouncingScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (_, i) =>
              FriendRequestCard(requestId: docs[i].id, data: docs[i].data()),
        );
      },
    );
  }
}
