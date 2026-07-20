import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/gamification_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({
    super.key,
    this.groupId,
    this.title = 'Leaderboard',
    this.embedded = false,
  });

  final String? groupId;
  final String title;
  final bool embedded;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Map<String, dynamic>>> _rankedFuture;
  bool _syncedCurrentUser = false;

  String? get groupId => widget.groupId;
  String get title => widget.title;
  bool get embedded => widget.embedded;

  static const bg = Color(0xFF0F140D);
  static const lime = Color(0xFFD6FF60);
  static const card = Color(0xFF1A1F17);
  static const soft = Color(0xFFB7C2A8);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _rankedFuture = _loadRankedUsers();
  }

  @override
  void didUpdateWidget(covariant LeaderboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId ||
        oldWidget.title != widget.title ||
        oldWidget.embedded != widget.embedded) {
      _rankedFuture = _loadRankedUsers();
    }
  }

  Future<void> _refreshLeaderboard() async {
    setState(() {
      _rankedFuture = _loadRankedUsers(forceSync: true);
    });
    await _rankedFuture;
  }

  int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  String _name(Map<String, dynamic> data) {
    return (data['name'] ??
            data['username'] ??
            data['displayName'] ??
            data['fullName'] ??
            data['userName'] ??
            data['email'] ??
            'NutriPulse User')
        .toString();
  }

  int _xp(Map<String, dynamic> data) {
    final gamificationProfile = _map(data['gamificationProfile']);
    final gamification = _map(data['gamification']);
    final stats = _map(data['stats']);
    final progress = _map(data['progress']);
    final leaderboard = _map(data['leaderboard']);

    return _safeInt(
      gamificationProfile['xp'] ??
          gamificationProfile['totalXp'] ??
          data['xp'] ??
          data['XP'] ??
          data['totalXp'] ??
          data['totalXP'] ??
          leaderboard['xp'] ??
          leaderboard['totalXp'] ??
          gamification['xp'] ??
          gamification['XP'] ??
          gamification['totalXp'] ??
          gamification['totalXP'] ??
          gamification['points'] ??
          stats['xp'] ??
          stats['totalXp'] ??
          progress['xp'] ??
          data['points'] ??
          data['score'] ??
          data['earnedXp'] ??
          data['earnedXP'] ??
          0,
    );
  }

  int _steps(Map<String, dynamic> data) {
    final daily = _map(data['daily']);
    final stats = _map(data['stats']);
    final leaderboard = _map(data['leaderboard']);

    return _safeInt(
      data['steps'] ??
          data['totalSteps'] ??
          leaderboard['steps'] ??
          daily['steps'] ??
          daily['totalSteps'] ??
          stats['steps'] ??
          0,
    );
  }

  int _streak(Map<String, dynamic> data) {
    final gamificationProfile = _map(data['gamificationProfile']);
    final gamification = _map(data['gamification']);
    final stats = _map(data['stats']);
    final leaderboard = _map(data['leaderboard']);

    return _safeInt(
      gamificationProfile['streak'] ??
          data['streak'] ??
          data['dayStreak'] ??
          data['currentStreak'] ??
          leaderboard['streak'] ??
          gamification['streak'] ??
          gamification['dayStreak'] ??
          stats['streak'] ??
          0,
    );
  }

  List<Map<String, dynamic>> _currentUserFallback() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const <Map<String, dynamic>>[];

    return [
      {
        'uid': user.uid,
        'name': user.displayName ?? user.email ?? 'You',
        'email': user.email ?? '',
        'xp': 0,
        'totalXp': 0,
        'steps': 0,
        'streak': 0,
      },
    ];
  }

  Future<List<Map<String, dynamic>>> _loadRankedUsers({
    bool forceSync = false,
  }) async {
    final db = FirebaseFirestore.instance;

    if (forceSync || !_syncedCurrentUser) {
      _syncedCurrentUser = true;
      unawaited(GamificationService.syncMyProgressToLeaderboard());
    }

    try {
      if (groupId == null || groupId!.trim().isEmpty) {
        return _loadGlobalRankedUsers(db);
      }
      return _loadGroupRankedUsers(db, groupId!);
    } catch (_) {
      return _currentUserFallback();
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _getFast(
    Query<Map<String, dynamic>> query, {
    Duration timeout = const Duration(milliseconds: 2200),
  }) async {
    try {
      return await query.get().timeout(timeout);
    } catch (_) {
      return query.get(const GetOptions(source: Source.cache));
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getDocFast(
    DocumentReference<Map<String, dynamic>> ref, {
    Duration timeout = const Duration(milliseconds: 1800),
  }) async {
    try {
      return await ref.get().timeout(timeout);
    } catch (_) {
      return ref.get(const GetOptions(source: Source.cache));
    }
  }

  Future<List<Map<String, dynamic>>> _loadGlobalRankedUsers(
    FirebaseFirestore db,
  ) async {
    // Load root users first. This is faster and your Firestore rules allow it.
    final users = await _loadRootUsers(db);
    if (users.isNotEmpty) return users;

    final board = await _loadGlobalBoard(db);
    if (board.isNotEmpty) return board;

    return _currentUserFallback();
  }

  Future<List<Map<String, dynamic>>> _loadRootUsers(
    FirebaseFirestore db,
  ) async {
    try {
      final snap = await _getFast(db.collection('users').limit(80));
      final users = snap.docs
          .map((doc) {
            final data = Map<String, dynamic>.from(doc.data());
            data['uid'] ??= doc.id;
            return data;
          })
          .where((data) => _name(data).trim().isNotEmpty)
          .toList();

      users.sort((a, b) => _xp(b).compareTo(_xp(a)));
      return users;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _loadGlobalBoard(
    FirebaseFirestore db,
  ) async {
    try {
      final snap = await _getFast(
        db
            .collection('leaderboards')
            .doc('global')
            .collection('users')
            .limit(100),
      );
      final users = snap.docs
          .map((doc) {
            final data = Map<String, dynamic>.from(doc.data());
            data['uid'] ??= doc.id;
            return data;
          })
          .where((data) => _name(data).trim().isNotEmpty)
          .toList();

      users.sort((a, b) => _xp(b).compareTo(_xp(a)));
      return users;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _loadGroupRankedUsers(
    FirebaseFirestore db,
    String groupId,
  ) async {
    try {
      final membersSnap = await _getFast(
        db.collection('groups').doc(groupId).collection('members'),
      );

      if (membersSnap.docs.isEmpty) return _currentUserFallback();

      final users = <Map<String, dynamic>>[];
      for (final member in membersSnap.docs.take(60)) {
        final data = Map<String, dynamic>.from(member.data());
        data['uid'] ??= member.id;

        try {
          final userDoc = await _getDocFast(
            db.collection('users').doc(member.id),
          );
          final userData = userDoc.data();
          if (userData != null) data.addAll(userData);
        } catch (_) {}

        users.add(data);
      }

      users.sort((a, b) => _xp(b).compareTo(_xp(a)));
      return users.isEmpty ? _currentUserFallback() : users;
    } catch (_) {
      return _currentUserFallback();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final content = FutureBuilder<List<Map<String, dynamic>>>(
      future: _rankedFuture,
      initialData: _currentUserFallback(),
      builder: (context, snapshot) {
        final ranked = snapshot.data ?? _currentUserFallback();
        if (embedded) return _embeddedContent(context, ranked);
        return _fullScreenContent(context, ranked);
      },
    );

    if (embedded) return content;

    return Scaffold(
      backgroundColor: bg,
      extendBody: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.18,
            colors: [Color(0xFF253618), Color(0xFF10150D), Color(0xFF070907)],
          ),
        ),
        child: SafeArea(bottom: false, child: content),
      ),
    );
  }

  Widget _embeddedContent(
    BuildContext context,
    List<Map<String, dynamic>> ranked,
  ) {
    if (ranked.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 40, bottom: 160),
        child: _emptyState(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _topBar(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: _podium(ranked.take(3).toList()),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Text(
            'Rankings',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 30,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 145),
          itemCount: ranked.length,
          itemBuilder: (context, index) {
            return _rankTile(rank: index + 1, data: ranked[index]);
          },
        ),
      ],
    );
  }

  Widget _fullScreenContent(
    BuildContext context,
    List<Map<String, dynamic>> ranked,
  ) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(child: _topBar(context)),
        if (ranked.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: _emptyState())
        else ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            sliver: SliverToBoxAdapter(child: _podium(ranked.take(3).toList())),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Rankings',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 30,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              MediaQuery.of(context).padding.bottom + 80,
            ),
            sliver: SliverList.builder(
              itemCount: ranked.length,
              itemBuilder: (context, index) {
                return _rankTile(rank: index + 1, data: ranked[index]);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(embedded ? 20 : 4, 6, 16, 8),
      child: Row(
        children: [
          if (!embedded)
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
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: embedded ? 30 : 25,
                height: 0.96,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.7,
              ),
            ),
          ),
          IconButton(
            onPressed: _refreshLeaderboard,
            icon: const Icon(Icons.refresh_rounded, color: lime, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _podium(List<Map<String, dynamic>> top) {
    final first = top.isNotEmpty ? top[0] : null;
    final second = top.length > 1 ? top[1] : null;
    final third = top.length > 2 ? top[2] : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: card.withOpacity(0.88),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _podiumUser(second, 2, 92)),
          const SizedBox(width: 10),
          Expanded(child: _podiumUser(first, 1, 132)),
          const SizedBox(width: 10),
          Expanded(child: _podiumUser(third, 3, 78)),
        ],
      ),
    );
  }

  Widget _podiumUser(Map<String, dynamic>? data, int rank, double barHeight) {
    final active = data != null;
    final isFirst = rank == 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isFirst ? 58 : 48,
          height: isFirst ? 58 : 48,
          decoration: BoxDecoration(
            color: active
                ? (isFirst ? lime : Colors.white.withOpacity(0.12))
                : Colors.white.withOpacity(0.06),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '#$rank',
              style: GoogleFonts.outfit(
                color: active && isFirst ? Colors.black : lime,
                fontSize: isFirst ? 19 : 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          active ? _name(data) : '-',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: isFirst ? 15 : 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          active ? '${_xp(data)} XP' : '0 XP',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(
            color: soft,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          height: barHeight,
          decoration: BoxDecoration(
            color: active
                ? (isFirst ? lime : Colors.white.withOpacity(0.14))
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ],
    );
  }

  Widget _rankTile({required int rank, required Map<String, dynamic> data}) {
    final isFirst = rank == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: card.withOpacity(0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isFirst
              ? lime.withOpacity(0.30)
              : Colors.white.withOpacity(0.055),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              '#$rank',
              style: GoogleFonts.outfit(
                color: lime,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name(data),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 18,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_steps(data)} steps • ${_streak(data)}d streak',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${_xp(data)} XP',
            style: GoogleFonts.outfit(
              color: lime,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final text = groupId == null
        ? 'No users found yet.'
        : 'No group members found yet.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: soft,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
