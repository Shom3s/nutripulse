import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/story_model.dart';
import '../../services/story_service.dart';
import '../../services/community_service.dart';
import 'story_viewers_sheet.dart';

class StoryViewScreen extends StatefulWidget {
  const StoryViewScreen({
    super.key,
    required this.stories,
    required this.initialIndex,
  });

  final List<StoryModel> stories;
  final int initialIndex;

  @override
  State<StoryViewScreen> createState() => _StoryViewScreenState();
}

class _StoryViewScreenState extends State<StoryViewScreen>
    with SingleTickerProviderStateMixin {
  static const Color lime = Color(0xFFD6FF60);
  static const Color soft = Color(0xFFB7C2A8);

  late int _index;
  late AnimationController _controller;

  StoryModel get _story => widget.stories[_index];
  bool get _isOwnStory => _story.uid == StoryService.currentUid;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.stories.length - 1);

    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 6))
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              _nextStory();
            }
          })
          ..forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markCurrentStoryViewed();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _markCurrentStoryViewed() async {
    await StoryService.markStoryViewed(_story.id);
  }

  void _nextStory() {
    if (_index < widget.stories.length - 1) {
      setState(() => _index++);
      _controller.forward(from: 0);
      _markCurrentStoryViewed();
    } else {
      Navigator.pop(context);
    }
  }

  void _previousStory() {
    if (_index > 0) {
      setState(() => _index--);
      _controller.forward(from: 0);
      _markCurrentStoryViewed();
    } else {
      _controller.forward(from: 0);
    }
  }

  Uint8List? _decode(String value) {
    if (value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> _react(String emoji) async {
    if (_isOwnStory) {
      _showMiniMessage('You cannot react to your own story');
      return;
    }

    try {
      await StoryService.reactToStory(storyId: _story.id, emoji: emoji);

      // StoryService saves the reaction. CommunityService creates the
      // receiver's notification document using the story owner's uid.
      await CommunityService.createStoryReactionNotification(
        storyOwnerUid: _story.uid,
        storyId: _story.id,
        reaction: emoji,
      );

      if (!mounted) return;
      _showMiniMessage('Reacted $emoji');
    } catch (e) {
      if (!mounted) return;
      _showMiniMessage(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showMiniMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color(0xFF1A1F17),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 950),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  void _openViewers() {
    _controller.stop();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StoryViewersSheet(storyId: _story.id),
    ).whenComplete(() {
      if (mounted) _controller.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = _decode(_story.imageBase64);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (details) {
          final width = MediaQuery.of(context).size.width;
          if (details.localPosition.dx < width * 0.35) {
            _previousStory();
          } else {
            _nextStory();
          }
        },
        onLongPressStart: (_) => _controller.stop(),
        onLongPressEnd: (_) => _controller.forward(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageBytes != null) ...[
              Image.memory(
                imageBytes,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
              ),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(color: Colors.black.withOpacity(0.32)),
              ),
              Center(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 3.5,
                  child: Image.memory(
                    imageBytes,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ] else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF263719),
                      Color(0xFF0F140D),
                      Colors.black,
                    ],
                  ),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.62),
                    Colors.transparent,
                    Colors.black.withOpacity(0.82),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _progressBars(),
                  _topUserRow(),
                  const Spacer(),
                  _captionAndActions(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressBars() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: List.generate(widget.stories.length, (i) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, __) {
                  double value;
                  if (i < _index) {
                    value = 1;
                  } else if (i == _index) {
                    value = _controller.value;
                  } else {
                    value = 0;
                  }

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 3,
                      color: lime,
                      backgroundColor: Colors.white.withOpacity(0.25),
                    ),
                  );
                },
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _topUserRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: lime.withOpacity(0.20),
            child: Text(
              _story.username.isEmpty ? 'U' : _story.username[0].toUpperCase(),
              style: GoogleFonts.outfit(
                color: lime,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _story.username,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (_isOwnStory)
            GestureDetector(
              onTap: _openViewers,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.34),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.visibility_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${_story.viewsCount}',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _captionAndActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      child: Column(
        children: [
          if (_story.caption.trim().isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.42),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Text(
                _story.caption,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          if (!_isOwnStory)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: ['❤️', '🔥', '👏', '😮', '💪'].map((emoji) {
                return GestureDetector(
                  onTap: () => _react(emoji),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.38),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 21)),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
