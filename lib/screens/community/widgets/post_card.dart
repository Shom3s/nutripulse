import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../models/community_post.dart';
import '../../../services/community_service.dart';
import 'comments_sheet.dart';
import '../../friends/friend_profile_screen.dart';
import '../create_post_screen.dart';

class PostCard extends StatefulWidget {
  const PostCard({super.key, required this.post});

  final CommunityPost post;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with AutomaticKeepAliveClientMixin {
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color soft = Color(0xFFB7C2A8);

  @override
  bool get wantKeepAlive => true;

  bool _heartBurst = false;
  late int _localLikesCount;
  bool? _localLiked;
  bool _likeSyncing = false;
  bool _likeTouched = false;
  bool? _desiredLiked;
  Uint8List? _cachedPostImageBytes;
  Uint8List? _cachedAvatarBytes;
  String _cachedImageBase64 = '';
  String _cachedAvatarBase64 = '';

  @override
  void initState() {
    super.initState();
    _localLikesCount = widget.post.likesCount;
    _refreshDecodedMediaCache();
    _loadInitialLikeState();
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) {
      _localLikesCount = widget.post.likesCount;
      _localLiked = null;
      _desiredLiked = null;
      _likeTouched = false;
      _likeSyncing = false;
      _refreshDecodedMediaCache();
      _loadInitialLikeState();
      return;
    }

    _refreshDecodedMediaCache();

    // Accept the Firestore like count only when we are not syncing an
    // optimistic tap. This prevents old snapshots from undoing a like/unlike
    // when the Feed is rebuilt after switching Community tabs.
    if (!_likeSyncing &&
        _desiredLiked == null &&
        widget.post.likesCount != _localLikesCount) {
      _localLikesCount = widget.post.likesCount;
    }
  }

  void _refreshDecodedMediaCache() {
    if (_cachedImageBase64 != widget.post.imageBase64) {
      _cachedImageBase64 = widget.post.imageBase64;
      _cachedPostImageBytes = _decode(widget.post.imageBase64);
    }

    if (_cachedAvatarBase64 != widget.post.userImageBase64) {
      _cachedAvatarBase64 = widget.post.userImageBase64;
      _cachedAvatarBytes = _decode(widget.post.userImageBase64);
    }
  }

  Future<void> _loadInitialLikeState() async {
    final postId = widget.post.id;

    // 1) Restore the last local choice immediately. This prevents the heart
    // from going back to empty after app restart while Firestore is still
    // connecting.
    final cached = await _cachedLikeState(postId);
    final hasPending = await _hasPendingLikeWrite(postId);

    if (mounted && widget.post.id == postId && cached != null) {
      setState(() => _localLiked = cached);
    }

    // 2) Read the real server state. If there was a pending write from the
    // previous app session, keep the local state and write it again.
    final liked = await _safeServerLikeState(postId);
    if (!mounted || widget.post.id != postId) return;

    if (hasPending && cached != null) {
      _likeTouched = true;
      _desiredLiked = cached;
      setState(() => _localLiked = cached);
      _syncDesiredLikeState();
      return;
    }

    if (liked == null) return;

    // Do not overwrite the user's local tap if they liked/unliked before this
    // async check returns.
    if (_likeTouched || _desiredLiked != null) return;

    await _saveLikeCache(postId: postId, liked: liked, pending: false);
    if (mounted && widget.post.id == postId) {
      setState(() => _localLiked = liked);
    }
  }

  String _likeCacheKey(String postId) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    return 'np_like_${uid}_$postId';
  }

  String _likePendingKey(String postId) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    return 'np_like_pending_${uid}_$postId';
  }

  Future<bool?> _cachedLikeState(String postId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_likeCacheKey(postId));
    } catch (_) {
      return null;
    }
  }

  Future<bool> _hasPendingLikeWrite(String postId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_likePendingKey(postId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveLikeCache({
    required String postId,
    required bool liked,
    required bool pending,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_likeCacheKey(postId), liked);
      if (pending) {
        await prefs.setBool(_likePendingKey(postId), true);
      } else {
        await prefs.remove(_likePendingKey(postId));
      }
    } catch (_) {}
  }

  int _safeLikeCount(int value) => value.clamp(0, 999999).toInt();

  Uint8List? _decode(String value) {
    if (value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'meal':
        return 'Meal';
      case 'workout':
        return 'Workout';
      case 'steps':
        return 'Steps';
      case 'water':
        return 'Hydration';
      case 'streak':
        return 'Streak';
      case 'progress':
        return 'Progress';
      default:
        return 'Update';
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'meal':
        return Icons.restaurant_rounded;
      case 'workout':
        return Icons.fitness_center_rounded;
      case 'steps':
        return Icons.directions_walk_rounded;
      case 'water':
        return Icons.water_drop_rounded;
      case 'streak':
        return Icons.local_fire_department_rounded;
      case 'progress':
        return Icons.trending_up_rounded;
      default:
        return Icons.forum_rounded;
    }
  }

  Future<void> _toggleLike() async {
    HapticFeedback.selectionClick();

    final currentLiked = _desiredLiked ?? _localLiked ?? false;
    final nextLiked = !currentLiked;

    _likeTouched = true;
    _desiredLiked = nextLiked;

    setState(() {
      _localLiked = nextLiked;
      _localLikesCount = _safeLikeCount(
        _localLikesCount + (nextLiked ? 1 : -1),
      );
      _heartBurst = nextLiked;
    });

    Future.delayed(const Duration(milliseconds: 460), () {
      if (mounted) setState(() => _heartBurst = false);
    });

    await _saveLikeCache(
      postId: widget.post.id,
      liked: nextLiked,
      pending: true,
    );

    _syncDesiredLikeState();
  }

  Future<void> _syncDesiredLikeState() async {
    if (_likeSyncing) return;

    _likeSyncing = true;

    while (mounted && _desiredLiked != null) {
      final postId = widget.post.id;
      final targetLiked = _desiredLiked!;

      try {
        await _writeExactLikeState(postId: postId, shouldLike: targetLiked);
      } catch (_) {
        if (!mounted || widget.post.id != postId) return;

        // Keep the desired state locally and mark it pending. On the next app
        // open, the card will restore this value and try to sync again.
        await _saveLikeCache(postId: postId, liked: targetLiked, pending: true);

        setState(() {
          _desiredLiked = null;
          _likeSyncing = false;
          _localLiked = targetLiked;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Like update failed. Check your internet and try again.',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
            ),
            backgroundColor: card,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      if (!mounted || widget.post.id != postId) return;

      // If the user tapped again while the write was running, loop once more
      // and write the latest desired state. This makes like -> unlike reliable.
      if (_desiredLiked == targetLiked) {
        await _saveLikeCache(
          postId: postId,
          liked: targetLiked,
          pending: false,
        );

        setState(() {
          _desiredLiked = null;
          _likeSyncing = false;
        });
        return;
      }
    }

    if (mounted) {
      setState(() => _likeSyncing = false);
    }
  }

  Future<bool?> _safeServerLikeState(String postId) async {
    try {
      return await CommunityService.isPostLiked(
        postId,
      ).timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeExactLikeState({
    required String postId,
    required bool shouldLike,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not logged in');

    final db = FirebaseFirestore.instance;
    final postRef = db.collection('posts').doc(postId);
    final likeRef = postRef.collection('likes').doc(user.uid);

    var createdLike = false;
    var removedLike = false;
    var ownerUid = widget.post.uid;
    var postCaption = widget.post.caption;

    await db.runTransaction((transaction) async {
      final postSnap = await transaction.get(postRef);
      final postData = postSnap.data();
      if (postData == null) throw Exception('Post not found');

      ownerUid = (postData['uid'] ?? ownerUid).toString();
      postCaption = (postData['caption'] ?? postCaption).toString();

      final likeSnap = await transaction.get(likeRef);

      if (shouldLike) {
        if (!likeSnap.exists) {
          createdLike = true;
          transaction.set(likeRef, {
            'uid': user.uid,
            'username': user.displayName ?? 'NutriPulse User',
            'likedAt': FieldValue.serverTimestamp(),
          });
          transaction.update(postRef, {'likesCount': FieldValue.increment(1)});
        }
      } else {
        if (likeSnap.exists) {
          removedLike = true;
          transaction.delete(likeRef);
          transaction.update(postRef, {'likesCount': FieldValue.increment(-1)});
        }
      }
    });

    if (createdLike && ownerUid.isNotEmpty && ownerUid != user.uid) {
      await _createLikeNotification(
        ownerUid: ownerUid,
        postId: postId,
        postCaption: postCaption,
      );
    }

    if (removedLike && ownerUid.isNotEmpty && ownerUid != user.uid) {
      await db
          .collection('users')
          .doc(ownerUid)
          .collection('notifications')
          .doc('post_${postId}_like_${user.uid}')
          .delete()
          .catchError((_) {});
    }
  }

  Future<void> _createLikeNotification({
    required String ownerUid,
    required String postId,
    required String postCaption,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    var actorName = user.displayName ?? 'NutriPulse User';
    var actorImageBase64 = '';

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? {};
      final savedName =
          (userData['name'] ??
                  userData['username'] ??
                  userData['displayName'] ??
                  '')
              .toString()
              .trim();
      if (savedName.isNotEmpty) actorName = savedName;
      actorImageBase64 =
          (userData['photoBase64'] ?? userData['userImageBase64'] ?? '')
              .toString();
    } catch (_) {}

    await FirebaseFirestore.instance
        .collection('users')
        .doc(ownerUid)
        .collection('notifications')
        .doc('post_${postId}_like_${user.uid}')
        .set({
          'type': 'like',
          'title': '$actorName liked your post',
          'body': postCaption.trim().isEmpty
              ? '$actorName liked your post.'
              : '$actorName liked: ${postCaption.trim()}',
          'actorUid': user.uid,
          'actorName': actorName,
          'actorImageBase64': actorImageBase64,
          'senderId': user.uid,
          'receiverId': ownerUid,
          'postId': postId,
          'commentText': '',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
          'screen': 'community',
        }, SetOptions(merge: true));
  }

  void _openComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentsSheet(post: widget.post),
    );
  }

  void _openAuthorProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          uid: widget.post.uid,
          initialData: {
            'name': widget.post.username,
            'username': widget.post.username,
            'photoBase64': widget.post.userImageBase64,
            'userImageBase64': widget.post.userImageBase64,
          },
        ),
      ),
    );
  }

  bool get _isOwnPost =>
      widget.post.uid == FirebaseAuth.instance.currentUser?.uid;

  Future<void> _openEditPost() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(
          mode: CreatePostMode.post,
          editingPost: widget.post,
        ),
      ),
    );
  }

  Future<void> _confirmDeletePost() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Delete post?',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'This post will be removed permanently.',
            style: GoogleFonts.outfit(color: soft, fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.outfit(color: soft)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'Delete',
                style: GoogleFonts.outfit(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await CommunityService.deletePost(widget.post.id);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Post deleted',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
        ),
        backgroundColor: card,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _ownerPostMenu() {
    if (!_isOwnPost) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      tooltip: 'Post options',
      color: const Color(0xFF1A1F17),
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 22),
      onSelected: (value) {
        if (value == 'edit') _openEditPost();
        if (value == 'delete') _confirmDeletePost();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit_rounded, color: lime, size: 19),
              const SizedBox(width: 10),
              Text(
                'Edit Post',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(
                Icons.delete_rounded,
                color: Colors.redAccent,
                size: 19,
              ),
              const SizedBox(width: 10),
              Text(
                'Delete Post',
                style: GoogleFonts.outfit(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final imageBytes = _cachedPostImageBytes;
    final avatarBytes = _cachedAvatarBytes;

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: card.withOpacity(0.96),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.055)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.20),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(avatarBytes),
            const SizedBox(height: 12),
            if (imageBytes != null) _image(imageBytes),
            if (imageBytes != null) const SizedBox(height: 12),
            _caption(),
            const SizedBox(height: 10),
            _statsRow(),
            const SizedBox(height: 10),
            _actionRow(),
          ],
        ),
      ),
    );
  }

  Widget _header(Uint8List? avatarBytes) {
    return Row(
      children: [
        GestureDetector(
          onTap: _openAuthorProfile,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFE8FF8A), Color(0xFFD6FF60)],
              ),
            ),
            child: CircleAvatar(
              backgroundColor: const Color(0xFF11170F),
              backgroundImage: avatarBytes != null
                  ? MemoryImage(avatarBytes)
                  : null,
              child: avatarBytes == null
                  ? Text(
                      widget.post.username.isEmpty
                          ? 'U'
                          : widget.post.username[0].toUpperCase(),
                      style: GoogleFonts.outfit(
                        color: lime,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: _openAuthorProfile,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.post.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(_typeIcon(widget.post.type), color: lime, size: 12),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${_typeLabel(widget.post.type)} • ${timeago.format(widget.post.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: soft.withOpacity(0.75),
                          fontSize: 10.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (widget.post.xp > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: lime.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '+${widget.post.xp} XP',
              style: GoogleFonts.outfit(
                color: lime,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        _ownerPostMenu(),
      ],
    );
  }

  Widget _image(Uint8List imageBytes) {
    return GestureDetector(
      onDoubleTap: _toggleLike,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.memory(
              imageBytes,
              key: ValueKey('post-image-${widget.post.id}'),
              width: double.infinity,
              height: 230,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
            ),
            IgnorePointer(
              child: AnimatedScale(
                scale: _heartBurst ? 1.05 : 0.30,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: AnimatedOpacity(
                  opacity: _heartBurst ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.favorite_rounded,
                    color: lime.withOpacity(0.92),
                    size: 88,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _caption() {
    return Text(
      widget.post.caption,
      style: GoogleFonts.outfit(
        color: Colors.white,
        fontSize: 15.5,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _statsRow() {
    return Row(
      children: [
        Text(
          '$_localLikesCount likes',
          style: GoogleFonts.outfit(
            color: soft.withOpacity(0.82),
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${widget.post.commentsCount} comments',
          style: GoogleFonts.outfit(
            color: soft.withOpacity(0.82),
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _actionRow() {
    final liked = _localLiked ?? false;

    return Row(
      children: [
        Expanded(
          child: _actionButton(
            icon: liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: 'Like',
            color: liked ? lime : Colors.white,
            onTap: _toggleLike,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionButton(
            icon: Icons.mode_comment_outlined,
            label: 'Comment',
            color: Colors.white,
            onTap: _openComments,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 44, height: 42, child: _miniShareChip()),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color == lime
              ? lime.withOpacity(0.18)
              : Colors.white.withOpacity(0.065),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color == lime
                ? lime.withOpacity(0.30)
                : Colors.white.withOpacity(0.05),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: color,
                  fontSize: 12.8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniShareChip() {
    return Container(
      height: 42,
      width: 44,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.065),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: const Icon(Icons.ios_share_rounded, color: Colors.white, size: 17),
    );
  }
}
