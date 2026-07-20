import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/community_post.dart';
import '../../models/story_model.dart';
import '../../services/community_service.dart';
import '../../services/story_service.dart';
import 'create_post_screen.dart';
import 'widgets/post_card.dart';
import 'widgets/story_bar.dart';
import '../friends/friends_screen.dart';
import '../groups/groups_screen.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../notifications/notification_center_screen.dart';
import 'market/market_home_screen.dart';

final ValueNotifier<int> communityTitleReplayTrigger = ValueNotifier<int>(0);

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
    with AutomaticKeepAliveClientMixin {
  static const Color lime = Color(0xFFD6FF60);
  static const Color soft = Color(0xFFB7C2A8);
  static const Color card = Color(0xFF1A1F17);

  final ValueNotifier<int> _tabIndex = ValueNotifier<int>(0);
  final ValueNotifier<_FeedState> _feedState = ValueNotifier<_FeedState>(
    const _FeedState.loading(),
  );
  final ValueNotifier<_StoryState> _storyState = ValueNotifier<_StoryState>(
    const _StoryState.loading(),
  );
  final ScrollController _scrollController = ScrollController();

  late final Stream<int> _unreadStream = _unreadNotificationCountStream()
      .asBroadcastStream();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _postsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _storiesSub;
  Timer? _feedFallbackTimer;
  Timer? _storyFallbackTimer;

  static const List<_CommunityTabData> _tabs = [
    _CommunityTabData('Feed', Icons.dynamic_feed_rounded),
    _CommunityTabData('Market', Icons.storefront_rounded),
    _CommunityTabData('Friends', Icons.people_alt_rounded),
    _CommunityTabData('Groups', Icons.groups_2_rounded),
    _CommunityTabData('Rank', Icons.emoji_events_rounded),
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    unawaited(
      StoryService.cleanupExpiredStories()
          .timeout(const Duration(seconds: 4))
          .catchError((_) {}),
    );
    _startPostsListener();
    _startStoriesListener();
  }

  void _startPostsListener({bool keepCurrent = true}) {
    _postsSub?.cancel();

    final current = _feedState.value;
    if (!keepCurrent || current.posts.isEmpty) {
      _feedState.value = const _FeedState.loading();
    }

    // Keep one live listener for the whole Community tab. Do not reset it on
    // tab switching, because that is what caused the feed to fall back to the
    // loading skeleton after visiting Market/Friends.
    _postsSub = CommunityService.postsStream().listen(
      (snapshot) {
        _feedFallbackTimer?.cancel();

        final posts = snapshot.docs
            .map((doc) => CommunityPost.fromFirestore(doc))
            .toList();

        posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _feedState.value = _FeedState.loaded(posts);
      },
      onError: (Object error, StackTrace stackTrace) {
        final currentPosts = _feedState.value.posts;
        if (currentPosts.isNotEmpty) {
          // Keep the last successful feed instead of replacing the whole UI
          // with a permanent loading/error state during temporary network loss.
          _feedState.value = _FeedState.loaded(currentPosts);
        } else {
          _feedState.value = _FeedState.error(error);
        }
      },
      cancelOnError: false,
    );

    _feedFallbackTimer?.cancel();
    _feedFallbackTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (_feedState.value.isLoading) {
        _feedState.value = const _FeedState.loaded(<CommunityPost>[]);
      }
    });
  }

  void _startStoriesListener({bool keepCurrent = true}) {
    _storiesSub?.cancel();

    final current = _storyState.value;
    if (!keepCurrent || current.stories.isEmpty) {
      _storyState.value = const _StoryState.loading();
    }

    // Cache stories in this screen state so they do not become old/stale or
    // disappear when the Feed sliver is temporarily removed by another tab.
    _storiesSub = StoryService.storiesStream().listen(
      (snapshot) {
        _storyFallbackTimer?.cancel();

        final stories = snapshot.docs
            .map((doc) => StoryModel.fromFirestore(doc))
            .where((story) => !story.isExpired)
            .toList();

        _storyState.value = _StoryState.loaded(stories);
      },
      onError: (Object error, StackTrace stackTrace) {
        final currentStories = _storyState.value.stories;
        if (currentStories.isNotEmpty) {
          _storyState.value = _StoryState.loaded(currentStories);
        } else {
          _storyState.value = _StoryState.error(error);
        }
      },
      cancelOnError: false,
    );

    _storyFallbackTimer?.cancel();
    _storyFallbackTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (_storyState.value.isLoading) {
        _storyState.value = const _StoryState.loaded(<StoryModel>[]);
      }
    });
  }

  @override
  void dispose() {
    _feedFallbackTimer?.cancel();
    _storyFallbackTimer?.cancel();
    _postsSub?.cancel();
    _storiesSub?.cancel();
    _feedState.dispose();
    _storyState.dispose();
    _tabIndex.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Stream<int> _unreadNotificationCountStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream<int>.value(0);

    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Future<void> _refreshCommunity() async {
    // Pull-to-refresh must never put the existing feed into a stuck loading
    // state. Keep current posts/stories on screen and only replace them if a
    // fresh snapshot arrives.
    await Future.wait<void>([
      StoryService.cleanupExpiredStories()
          .timeout(const Duration(seconds: 4))
          .catchError((_) {}),
      _refreshPostsOnce(),
      _refreshStoriesOnce(),
    ]);
  }

  Future<void> _refreshPostsOnce() async {
    try {
      final snapshot = await CommunityService.postsStream().first.timeout(
        const Duration(seconds: 5),
      );

      final posts = snapshot.docs
          .map((doc) => CommunityPost.fromFirestore(doc))
          .toList();
      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (mounted) _feedState.value = _FeedState.loaded(posts);
    } catch (_) {
      // Keep current cached feed. The live listener will update when Firestore
      // reconnects, so the UI should not jump back to a loading screen.
    }
  }

  Future<void> _refreshStoriesOnce() async {
    try {
      final snapshot = await StoryService.storiesStream().first.timeout(
        const Duration(seconds: 5),
      );

      final stories = snapshot.docs
          .map((doc) => StoryModel.fromFirestore(doc))
          .where((story) => !story.isExpired)
          .toList();

      if (mounted) _storyState.value = _StoryState.loaded(stories);
    } catch (_) {
      // Keep current cached stories.
    }
  }

  void _setTab(int index) {
    if (_tabIndex.value == index) return;
    FocusScope.of(context).unfocus();
    _tabIndex.value = index;

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _openNotificationCenter() {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: const NotificationCenterScreen(),
        ),
      ),
    );
  }

  void _openCreatePost() {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: const CreatePostScreen(mode: CreatePostMode.post),
        ),
      ),
    );
  }

  void _openCreateStory() {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: const CreatePostScreen(mode: CreatePostMode.story),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return WillPopScope(
      onWillPop: () async {
        if (_tabIndex.value != 0) {
          _setTab(0);
          return false;
        }
        return true;
      },
      child: RefreshIndicator(
        color: lime,
        backgroundColor: const Color(0xFF141A11),
        onRefresh: _refreshCommunity,
        child: ValueListenableBuilder<int>(
          valueListenable: _tabIndex,
          builder: (context, index, _) {
            return CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              cacheExtent: 520,
              slivers: [
                SliverToBoxAdapter(child: RepaintBoundary(child: _header())),
                if (index == 0) ...[
                  const SliverToBoxAdapter(child: SizedBox(height: 18)),
                  SliverToBoxAdapter(
                    child: RepaintBoundary(child: _storyBar()),
                  ),
                ] else
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: RepaintBoundary(child: _filterTabs(index)),
                ),
                _bodyForTab(index),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    return ValueListenableBuilder<int>(
      valueListenable: communityTitleReplayTrigger,
      builder: (context, replaySeed, _) {
        return TweenAnimationBuilder<double>(
          key: ValueKey<String>('community-title-replay-$replaySeed'),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 460),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: Opacity(opacity: t, child: child),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Community',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 36,
                        height: 0.95,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Share progress, food market, groups, and rankings',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.76),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _roundActionButton(
                icon: Icons.add_rounded,
                onTap: _openCreatePost,
              ),
              const SizedBox(width: 9),
              StreamBuilder<int>(
                stream: _unreadStream,
                builder: (context, snapshot) {
                  return _notificationButton(snapshot.data ?? 0);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _notificationButton(int unread) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openNotificationCenter,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: lime,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Center(
              child: Icon(
                Icons.notifications_rounded,
                color: Colors.black,
                size: 26,
              ),
            ),
            if (unread > 0)
              Positioned(
                right: -5,
                top: -5,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 21,
                    minHeight: 21,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B30),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFF203718),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _roundActionButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: card.withOpacity(0.94),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Icon(icon, color: Colors.white, size: 23),
      ),
    );
  }

  Widget _storyBar() {
    return ValueListenableBuilder<_StoryState>(
      valueListenable: _storyState,
      builder: (context, state, _) {
        return StoryBar(
          stories: state.stories,
          onCreateStory: _openCreateStory,
        );
      },
    );
  }

  Widget _filterTabs(int selectedIndex) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.045)),
      ),
      child: Row(
        children: List.generate(_tabs.length, (index) {
          final tab = _tabs[index];
          final selected = selectedIndex == index;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _setTab(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                height: 40,
                decoration: BoxDecoration(
                  color: selected ? lime : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tab.icon,
                          size: 14,
                          color: selected ? Colors.black : soft,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          tab.label,
                          maxLines: 1,
                          softWrap: false,
                          style: GoogleFonts.outfit(
                            color: selected ? Colors.black : soft,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _bodyForTab(int index) {
    switch (index) {
      case 0:
        return _feedSliver();
      case 1:
        return const MarketHomeScreen(asSliver: true);
      case 2:
        return const SliverFillRemaining(
          hasScrollBody: true,
          child: FriendsScreen(),
        );
      case 3:
        return const SliverToBoxAdapter(child: GroupsScreen());
      case 4:
        return const SliverToBoxAdapter(
          child: LeaderboardScreen(embedded: true, title: 'Global Leaderboard'),
        );
      default:
        return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
  }

  Widget _feedSliver() {
    return ValueListenableBuilder<_FeedState>(
      valueListenable: _feedState,
      builder: (context, state, _) {
        if (state.isLoading) {
          return SliverList.builder(
            itemCount: 4,
            itemBuilder: (context, index) => const _FeedSkeletonCard(),
          );
        }

        if (state.error != null && state.posts.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Text(
                  'Could not load feed. Pull down to refresh.\n${state.error}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: soft,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }

        final posts = state.posts;
        if (posts.isEmpty) {
          return SliverFillRemaining(hasScrollBody: false, child: _emptyFeed());
        }

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 120),
          sliver: SliverList.builder(
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              return RepaintBoundary(
                key: ValueKey('post-boundary-${post.id}'),
                child: PostCard(key: ValueKey('post-${post.id}'), post: post),
              );
            },
          ),
        );
      },
    );
  }

  Widget _emptyFeed() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 130),
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
            child: const Icon(Icons.groups_rounded, color: lime, size: 38),
          ),
          const SizedBox(height: 18),
          Text(
            'No community posts yet',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Create a post or check again when the community is active.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _openCreatePost,
            style: ElevatedButton.styleFrom(
              backgroundColor: lime,
              foregroundColor: Colors.black,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text(
              'Create Post',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedState {
  const _FeedState._({
    required this.posts,
    required this.isLoading,
    required this.error,
  });

  const _FeedState.loading()
    : posts = const <CommunityPost>[],
      isLoading = true,
      error = null;

  const _FeedState.loaded(List<CommunityPost> posts)
    : posts = posts,
      isLoading = false,
      error = null;

  const _FeedState.error(Object error)
    : posts = const <CommunityPost>[],
      isLoading = false,
      error = error;

  final List<CommunityPost> posts;
  final bool isLoading;
  final Object? error;
}

class _StoryState {
  const _StoryState._({
    required this.stories,
    required this.isLoading,
    required this.error,
  });

  const _StoryState.loading()
    : stories = const <StoryModel>[],
      isLoading = true,
      error = null;

  const _StoryState.loaded(List<StoryModel> stories)
    : stories = stories,
      isLoading = false,
      error = null;

  const _StoryState.error(Object error)
    : stories = const <StoryModel>[],
      isLoading = false,
      error = error;

  final List<StoryModel> stories;
  final bool isLoading;
  final Object? error;
}

class _CommunityTabData {
  const _CommunityTabData(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _FeedSkeletonCard extends StatelessWidget {
  const _FeedSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 14),
      height: 138,
      decoration: BoxDecoration(
        color: _CommunityScreenState.card.withOpacity(0.72),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _box(42, 42, 999),
                const SizedBox(width: 12),
                Expanded(child: _box(double.infinity, 14, 999)),
                const SizedBox(width: 16),
                _box(52, 14, 999),
              ],
            ),
            const SizedBox(height: 18),
            _box(double.infinity, 13, 999),
            const SizedBox(height: 10),
            _box(210, 13, 999),
          ],
        ),
      ),
    );
  }

  Widget _box(double width, double height, double radius) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
