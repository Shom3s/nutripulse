import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/community_post.dart';
import '../../services/community_service.dart';
import '../../services/friend_service.dart';
import '../community/widgets/comments_sheet.dart';
import '../community/create_post_screen.dart';

class FriendProfileScreen extends StatefulWidget {
  const FriendProfileScreen({super.key, required this.uid, this.initialData});

  final String uid;
  final Map<String, dynamic>? initialData;

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  static const bg = Color(0xFF0F140D);
  static const lime = Color(0xFFD6FF60);
  static const card = Color(0xFF1A1F17);
  static const soft = Color(0xFFB7C2A8);

  late final Future<Map<String, dynamic>> _profileFuture;

  Uint8List? _avatarCache;
  String _lastAvatarBase64 = '';

  bool get _isMe => widget.uid == FriendService.currentUid;

  @override
  void initState() {
    super.initState();
    _profileFuture = FriendService.getProfileBundle(widget.uid);
  }

  Uint8List? _decode(String value) {
    if (value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  Uint8List? _decodeCached(String value) {
    if (value.isEmpty) return null;

    if (_avatarCache != null && _lastAvatarBase64 == value) {
      return _avatarCache;
    }

    try {
      _lastAvatarBase64 = value;
      _avatarCache = base64Decode(value);
      return _avatarCache;
    } catch (_) {
      return null;
    }
  }

  String _nameFrom(Map<String, dynamic> data) {
    return (data['name'] ??
            data['username'] ??
            data['displayName'] ??
            'NutriPulse User')
        .toString();
  }

  String _photoFrom(Map<String, dynamic> data) {
    return (data['photoBase64'] ?? data['userImageBase64'] ?? '').toString();
  }

  String _bioFrom(Map<String, dynamic> data) {
    return (data['bio'] ??
            data['about'] ??
            data['description'] ??
            data['profileBio'] ??
            '')
        .toString()
        .trim();
  }

  int _safeInt(dynamic value) => FriendService.safeInt(value);

  double _safeDouble(dynamic value) => FriendService.safeDouble(value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.18,
            colors: [Color(0xFF253618), Color(0xFF10150D), Color(0xFF070907)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: FutureBuilder<Map<String, dynamic>>(
            future: _profileFuture,
            builder: (context, snapshot) {
              final bundle = snapshot.data;
              final user =
                  (bundle?['user'] as Map<String, dynamic>?) ??
                  widget.initialData ??
                  {};
              final gamification =
                  (bundle?['gamification'] as Map<String, dynamic>?) ?? {};
              final daily = (bundle?['daily'] as Map<String, dynamic>?) ?? {};
              final activity =
                  (bundle?['activity'] as Map<String, dynamic>?) ?? {};
              final meals = (bundle?['meals'] as Map<String, dynamic>?) ?? {};

              final name = _nameFrom(user);
              final photo = _photoFrom(user);
              final avatar = _decodeCached(photo);
              final bio = _bioFrom(user);

              final xp = _safeInt(gamification['xp']);
              final streak = _safeInt(
                gamification['streak'] ?? gamification['dayStreak'],
              );
              final steps = _safeInt(
                daily['steps'] ?? daily['totalSteps'] ?? activity['steps'],
              );
              final calories = _safeDouble(
                daily['calories'] ??
                    daily['totalCalories'] ??
                    meals['calories'],
              ).toInt();

              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                cacheExtent: 900,
                slivers: [
                  SliverToBoxAdapter(child: _topBar(context)),
                  SliverToBoxAdapter(
                    child: RepaintBoundary(
                      child: _profileHeader(
                        name: name,
                        photo: photo,
                        avatar: avatar,
                        bio: bio,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: RepaintBoundary(
                      child: _statsSection(
                        xp: xp,
                        streak: streak,
                        steps: steps,
                        calories: calories,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: _sectionTitle()),
                  _postsSliver(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 16, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.075),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.07)),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 23,
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _profileHeader({
    required String name,
    required String photo,
    required Uint8List? avatar,
    required String bio,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: card.withOpacity(0.94),
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 22,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFE9FF8E),
                        Color(0xFFD6FF60),
                        Color(0xFF91D82E),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: lime.withOpacity(0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    backgroundColor: const Color(0xFF11170F),
                    backgroundImage: avatar != null
                        ? MemoryImage(avatar)
                        : null,
                    child: avatar == null
                        ? Text(
                            name.isEmpty ? 'U' : name[0].toUpperCase(),
                            style: GoogleFonts.outfit(
                              color: lime,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 16),
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
                          fontSize: 28,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (bio.isNotEmpty)
                        Text(
                          bio,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: soft,
                            fontSize: 12.5,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (!_isMe) ...[
              const SizedBox(height: 18),
              StreamBuilder<bool>(
                stream: FriendService.isFollowingStream(widget.uid),
                builder: (context, snap) {
                  final following = snap.data ?? false;

                  return GestureDetector(
                    onTap: () => FriendService.toggleFollow(
                      otherUid: widget.uid,
                      otherName: name,
                      otherPhoto: photo,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        color: following
                            ? Colors.white.withOpacity(0.075)
                            : lime,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: following
                              ? Colors.white.withOpacity(0.08)
                              : lime,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            following
                                ? Icons.person_remove_alt_1_rounded
                                : Icons.person_add_alt_1_rounded,
                            color: following ? Colors.white : Colors.black,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            following ? 'Following' : 'Follow',
                            style: GoogleFonts.outfit(
                              color: following ? Colors.white : Colors.black,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statsSection({
    required int xp,
    required int streak,
    required int steps,
    required int calories,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Row(
        children: [
          Expanded(
            child: _statCard(
              icon: Icons.bolt_rounded,
              label: 'XP',
              value: '$xp',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statCard(
              icon: Icons.local_fire_department_rounded,
              label: 'Streak',
              value: '$streak',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statCard(
              icon: Icons.directions_walk_rounded,
              label: 'Steps',
              value: '$steps',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statCard(
              icon: Icons.local_dining_rounded,
              label: 'Cal',
              value: '$calories',
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      height: 92,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: card.withOpacity(0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.055)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: lime, size: 20),
          const SizedBox(height: 7),
          FittedBox(
            child: Text(
              value,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
      child: Row(
        children: [
          Text(
            'Posts',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 24,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const Spacer(),
          const Icon(Icons.grid_on_rounded, color: lime, size: 19),
        ],
      ),
    );
  }

  Widget _postsSliver() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: CommunityService.userPostsStream(widget.uid),
      builder: (context, snapshot) {
        final posts =
            snapshot.data?.docs
                .map((doc) => CommunityPost.fromFirestore(doc))
                .toList() ??
            [];

        posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (snapshot.connectionState == ConnectionState.waiting &&
            posts.isEmpty) {
          return SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 140),
            sliver: SliverGrid.builder(
              itemCount: 9,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              itemBuilder: (_, __) => const _PostSkeleton(),
            ),
          );
        }

        if (posts.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 28, 26, 140),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.grid_on_rounded, color: lime, size: 44),
                  const SizedBox(height: 12),
                  Text(
                    'No posts yet',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 140),
          sliver: SliverGrid.builder(
            itemCount: posts.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
            ),
            itemBuilder: (context, index) {
              return _postGridTile(posts[index]);
            },
          ),
        );
      },
    );
  }

  Widget _postGridTile(CommunityPost post) {
    final imageBytes = _decode(post.imageBase64);

    return GestureDetector(
      onTap: () => _openPostPreview(post),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: Colors.white.withOpacity(0.045),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageBytes != null)
                Image.memory(
                  imageBytes,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  cacheWidth: 260,
                )
              else
                Container(
                  color: card.withOpacity(0.92),
                  child: Icon(_typeIcon(post.type), color: lime, size: 28),
                ),
              Positioned(
                right: 6,
                top: 6,
                child: Icon(
                  imageBytes != null
                      ? Icons.photo_library_rounded
                      : _typeIcon(post.type),
                  color: Colors.white.withOpacity(0.92),
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPostPreview(CommunityPost post) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ProfilePostDetailScreen(
          post: post,
          imageBytes: _decode(post.imageBase64),
          avatarBytes: _decode(post.userImageBase64),
        ),
      ),
    );
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
}

class _ProfilePostDetailScreen extends StatefulWidget {
  const _ProfilePostDetailScreen({
    required this.post,
    required this.imageBytes,
    required this.avatarBytes,
  });

  final CommunityPost post;
  final Uint8List? imageBytes;
  final Uint8List? avatarBytes;

  @override
  State<_ProfilePostDetailScreen> createState() =>
      _ProfilePostDetailScreenState();
}

class _ProfilePostDetailScreenState extends State<_ProfilePostDetailScreen> {
  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color soft = Color(0xFFB7C2A8);

  CommunityPost get post => widget.post;

  bool _isOwnPost(CommunityPost livePost) {
    return livePost.uid == FirebaseAuth.instance.currentUser?.uid;
  }

  Future<void> _openEditPost(CommunityPost livePost) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CreatePostScreen(mode: CreatePostMode.post, editingPost: livePost),
      ),
    );
  }

  Future<void> _confirmDeletePost(CommunityPost livePost) async {
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

    await CommunityService.deletePost(livePost.id);

    if (!mounted) return;
    Navigator.pop(context);
  }

  Widget _ownerPostMenu(CommunityPost livePost) {
    if (!_isOwnPost(livePost)) return const SizedBox.shrink();

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
        if (value == 'edit') _openEditPost(livePost);
        if (value == 'delete') _confirmDeletePost(livePost);
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

  Future<void> _toggleLike() async {
    await CommunityService.toggleLike(post.id);
  }

  void _openComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentsSheet(post: post),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      extendBody: true,
      extendBodyBehindAppBar: true,
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
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('posts')
                .doc(post.id)
                .snapshots(),
            builder: (context, snapshot) {
              final livePost = snapshot.data?.exists == true
                  ? CommunityPost.fromFirestore(snapshot.data!)
                  : post;

              return CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(child: _topBar(context)),
                  SliverToBoxAdapter(child: _authorHeader(livePost)),
                  SliverToBoxAdapter(child: _mainImage(livePost)),
                  SliverToBoxAdapter(child: _actionRow(livePost)),
                  SliverToBoxAdapter(child: _likedRow(livePost)),
                  SliverToBoxAdapter(child: _captionBlock(livePost)),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 70,
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

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
          Text(
            'Post',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _authorHeader(CommunityPost livePost) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFE8FF8A), Color(0xFFD6FF60)],
              ),
            ),
            child: CircleAvatar(
              backgroundColor: const Color(0xFF11170F),
              backgroundImage: widget.avatarBytes != null
                  ? MemoryImage(widget.avatarBytes!)
                  : null,
              child: widget.avatarBytes == null
                  ? Text(
                      livePost.username.isEmpty
                          ? 'U'
                          : livePost.username[0].toUpperCase(),
                      style: GoogleFonts.outfit(
                        color: lime,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  livePost.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(_typeIcon(livePost.type), color: lime, size: 12),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _typeLabel(livePost.type),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: soft,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _ownerPostMenu(livePost),
        ],
      ),
    );
  }

  Widget _mainImage(CommunityPost livePost) {
    return GestureDetector(
      onDoubleTap: _toggleLike,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          width: double.infinity,
          color: card.withOpacity(0.55),
          child: widget.imageBytes != null
              ? Image.memory(
                  widget.imageBytes!,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                )
              : Center(
                  child: Icon(_typeIcon(livePost.type), color: lime, size: 54),
                ),
        ),
      ),
    );
  }

  Widget _actionRow(CommunityPost livePost) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Row(
        children: [
          StreamBuilder<bool>(
            stream: CommunityService.isPostLikedStream(livePost.id),
            builder: (context, snapshot) {
              final liked = snapshot.data ?? false;

              return GestureDetector(
                onTap: _toggleLike,
                child: Icon(
                  liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: liked ? Colors.redAccent : Colors.white,
                  size: 28,
                ),
              );
            },
          ),
          const SizedBox(width: 18),
          GestureDetector(
            onTap: _openComments,
            child: const Icon(
              Icons.mode_comment_outlined,
              color: Colors.white,
              size: 27,
            ),
          ),
        ],
      ),
    );
  }

  Widget _likedRow(CommunityPost livePost) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: Text(
        '${livePost.likesCount} likes',
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _captionBlock(CommunityPost livePost) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 13.5,
            height: 1.28,
            fontWeight: FontWeight.w600,
          ),
          children: [
            TextSpan(
              text: livePost.username,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            TextSpan(
              text: livePost.caption.isEmpty
                  ? ' NutriPulse update'
                  : ' ${livePost.caption}',
            ),
          ],
        ),
      ),
    );
  }
}

class _PostSkeleton extends StatelessWidget {
  const _PostSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _FriendProfileScreenState.card.withOpacity(0.70),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.045)),
      ),
    );
  }
}
