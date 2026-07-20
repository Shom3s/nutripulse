import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/story_model.dart';
import '../../../services/story_service.dart';
import '../story_view_screen.dart';

class StoryBar extends StatelessWidget {
  const StoryBar({
    super.key,
    required this.stories,
    required this.onCreateStory,
  });

  final List<StoryModel> stories;
  final VoidCallback onCreateStory;

  static const Color lime = Color(0xFFD6FF60);
  static const Color soft = Color(0xFFB7C2A8);

  Uint8List? _decode(String value) {
    if (value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  List<List<StoryModel>> _groupStoriesByUser() {
    final activeStories = stories.where((story) => !story.isExpired).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final grouped = <String, List<StoryModel>>{};

    for (final story in activeStories) {
      grouped.putIfAbsent(story.uid, () => <StoryModel>[]);
      grouped[story.uid]!.add(story);
    }

    final groups = grouped.values.toList();

    groups.sort((a, b) => b.last.createdAt.compareTo(a.last.createdAt));

    return groups;
  }

  bool _groupViewed(List<StoryModel> group) {
    final uid = StoryService.currentUid;
    if (uid == null) return false;

    // Own story: show green ring if you still have active story.
    // Other user's story: grey only when all their story segments are viewed.
    if (group.isNotEmpty && group.first.uid == uid) return false;

    return group.every((story) => story.viewedByUser(uid));
  }

  void _openStoryGroup(BuildContext context, List<StoryModel> group) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: StoryViewScreen(stories: group, initialIndex: 0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storyGroups = _groupStoriesByUser();

    return SizedBox(
      height: 112,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        itemCount: storyGroups.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _createStoryButton();
          }

          final group = storyGroups[index - 1];
          final latestStory = group.last;
          final storyImage = _decode(latestStory.imageBase64);
          final avatarImage = _decode(latestStory.userImageBase64);
          final viewed = _groupViewed(group);

          return GestureDetector(
            onTap: () => _openStoryGroup(context, group),
            child: SizedBox(
              width: 72,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 66,
                        height: 66,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: viewed
                              ? LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0.20),
                                    Colors.white.withOpacity(0.10),
                                  ],
                                )
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFFE9FF8E),
                                    Color(0xFFD6FF60),
                                    Color(0xFF91D82E),
                                  ],
                                ),
                          boxShadow: viewed
                              ? []
                              : [
                                  BoxShadow(
                                    color: lime.withOpacity(0.34),
                                    blurRadius: 14,
                                    spreadRadius: 1,
                                  ),
                                ],
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Color(0xFF0F140D),
                            shape: BoxShape.circle,
                          ),
                          child: CircleAvatar(
                            backgroundColor: lime.withOpacity(0.14),
                            backgroundImage: storyImage != null
                                ? MemoryImage(storyImage)
                                : avatarImage != null
                                ? MemoryImage(avatarImage)
                                : null,
                            child: storyImage == null && avatarImage == null
                                ? Text(
                                    latestStory.username.isEmpty
                                        ? 'U'
                                        : latestStory.username[0].toUpperCase(),
                                    style: GoogleFonts.outfit(
                                      color: lime,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      if (group.length > 1)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: viewed ? Colors.white24 : lime,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFF0F140D),
                                width: 2,
                              ),
                            ),
                            child: Text(
                              '${group.length}',
                              style: GoogleFonts.outfit(
                                color: viewed ? Colors.white : Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    latestStory.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: viewed
                          ? Colors.white.withOpacity(0.48)
                          : Colors.white.withOpacity(0.90),
                      fontSize: 11.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _createStoryButton() {
    return GestureDetector(
      onTap: onCreateStory,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.075),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.auto_stories_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: lime,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Colors.black,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Your story',
              maxLines: 1,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: soft,
                fontSize: 11.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
