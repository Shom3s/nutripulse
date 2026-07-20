import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/groq_chat_service.dart';
import '../../services/gamification_service.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  static const Color lime = Color(0xFFD6FF60);
  static const Color text = Colors.white;
  static const Color soft = Color(0xFFB7C2A8);
  static const Color card = Color(0xFF1A1F17);
  static const Color bg = Color(0xFF0F140D);

  static const String _prefAiChatHistory = 'setting_ai_chat_history';
  static const String _prefAiSaveHistory = 'setting_ai_save_chat_history';

  // Keeps the loading bubble visible for at least 3 seconds before showing
  // the assistant result. If the AI response takes longer, it waits naturally.
  static const Duration _minimumAiLoadingTime = Duration(seconds: 3);

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GroqChatService _service = GroqChatService();

  final List<Map<String, String>> _messages = [
    {
      'role': 'assistant',
      'text':
          'Hi, I\'m NutriPulse AI. Ask me anything about nutrition, fitness, food, steps, lifestyle, studies, coding, or general questions.',
    },
  ];

  final List<String> _suggestions = const [
    'Analyze my nutrition today',
    'Calculate my protein target',
    'Suggest healthy Malaysian meals',
    'Plan a workout for today',
  ];

  bool _isSending = false;
  Map<String, dynamic> _userData = {};
  Map<String, dynamic> _todayNutrition = {};
  Map<String, dynamic> _todayActivity = {};
  Map<String, dynamic> _todayDailySummary = {};

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _mealSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _activitySub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _dailySummarySub;

  @override
  void initState() {
    super.initState();
    _startUserContextListeners();
    _loadSavedChatHistory();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _mealSub?.cancel();
    _activitySub?.cancel();
    _dailySummarySub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Map<String, String> _defaultAssistantMessage() {
    return {
      'role': 'assistant',
      'text':
          'Hi, I\'m NutriPulse AI. Ask me anything about nutrition, fitness, food, steps, lifestyle, studies, coding, or general questions.',
    };
  }

  Future<void> _loadSavedChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saveHistory = prefs.getBool(_prefAiSaveHistory) ?? true;
      if (!saveHistory) return;

      final raw = prefs.getString(_prefAiChatHistory);
      if (raw == null || raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final loaded = decoded
          .whereType<Map>()
          .map((item) {
            return {
              'role': (item['role'] ?? '').toString(),
              'text': (item['text'] ?? '').toString(),
            };
          })
          .where(
            (item) =>
                (item['role'] == 'user' || item['role'] == 'assistant') &&
                (item['text'] ?? '').trim().isNotEmpty,
          )
          .toList();

      if (loaded.isEmpty || !mounted) return;

      setState(() {
        _messages
          ..clear()
          ..addAll(loaded);
      });
    } catch (_) {
      // Keep the AI coach usable even if local history cannot be read.
    }
  }

  Future<void> _saveChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saveHistory = prefs.getBool(_prefAiSaveHistory) ?? true;

      if (!saveHistory) {
        await prefs.remove(_prefAiChatHistory);
        return;
      }

      final safeMessages = _messages
          .where((m) => (m['text'] ?? '').trim().isNotEmpty)
          .take(60)
          .toList();

      await prefs.setString(_prefAiChatHistory, jsonEncode(safeMessages));
    } catch (_) {}
  }

  void _startUserContextListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = _dateKey(DateTime.now());
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);

    _userSub?.cancel();
    _mealSub?.cancel();
    _activitySub?.cancel();
    _dailySummarySub?.cancel();

    _userSub = userRef.snapshots().listen(
      (doc) {
        if (!mounted) return;
        setState(() => _userData = doc.data() ?? {});
      },
      onError: (_) {},
      cancelOnError: false,
    );

    _mealSub = userRef
        .collection('meals')
        .doc(today)
        .snapshots()
        .listen(
          (doc) {
            if (!mounted) return;
            setState(() => _todayNutrition = doc.data() ?? {});
          },
          onError: (_) {},
          cancelOnError: false,
        );

    _activitySub = userRef
        .collection('activity')
        .doc(today)
        .snapshots()
        .listen(
          (doc) {
            if (!mounted) return;
            setState(() => _todayActivity = doc.data() ?? {});
          },
          onError: (_) {},
          cancelOnError: false,
        );

    // Dashboard/Gamification saves water, calories, protein and sometimes steps
    // here. Reading it live prevents the AI context chips from showing 0.
    _dailySummarySub = userRef
        .collection('daily_summary')
        .doc(today)
        .snapshots()
        .listen(
          (doc) {
            if (!mounted) return;
            setState(() => _todayDailySummary = doc.data() ?? {});
          },
          onError: (_) {},
          cancelOnError: false,
        );
  }

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _name() => (_userData['name'] ?? 'User').toString();

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _todayCaloriesValue() {
    return _asDouble(
      _todayNutrition['calories'] ??
          _todayNutrition['totalCalories'] ??
          _todayDailySummary['calories'] ??
          _todayDailySummary['totalCalories'] ??
          _todayDailySummary['todayCalories'] ??
          0,
    );
  }

  double _todayProteinValue() {
    return _asDouble(
      _todayNutrition['protein'] ??
          _todayNutrition['proteinGrams'] ??
          _todayDailySummary['protein'] ??
          _todayDailySummary['proteinGrams'] ??
          _todayDailySummary['totalProtein'] ??
          0,
    );
  }

  double _todayCarbsValue() {
    return _asDouble(
      _todayNutrition['carbs'] ??
          _todayNutrition['carbohydrates'] ??
          _todayDailySummary['carbs'] ??
          _todayDailySummary['carbsGrams'] ??
          _todayDailySummary['totalCarbs'] ??
          0,
    );
  }

  double _todayFatValue() {
    return _asDouble(
      _todayNutrition['fat'] ??
          _todayNutrition['fats'] ??
          _todayDailySummary['fat'] ??
          _todayDailySummary['fats'] ??
          _todayDailySummary['fatGrams'] ??
          _todayDailySummary['totalFat'] ??
          0,
    );
  }

  int _todayStepsValue() {
    return _asInt(
      _todayActivity['steps'] ??
          _todayDailySummary['steps'] ??
          _userData['steps'] ??
          _userData['totalSteps'] ??
          0,
    );
  }

  double _todayWaterValue() {
    return _asDouble(
      _todayDailySummary['waterLiters'] ??
          _userData['waterLiters'] ??
          _userData['water'] ??
          0,
    );
  }

  Map<String, dynamic> _buildContext() {
    return {
      'name': _userData['name'] ?? 'User',
      'goal': _userData['goal'] ?? 'Not set',
      'heightCm': _userData['heightCm'] ?? 'Not set',
      'weightKg': _userData['weightKg'] ?? 'Not set',
      'targetCalories': _userData['targetCalories'] ?? 2000,
      'todayCalories': _todayCaloriesValue(),
      'todayProtein': _todayProteinValue(),
      'todayCarbs': _todayCarbsValue(),
      'todayFat': _todayFatValue(),
      'stepGoal':
          _userData['stepGoal'] ?? _todayDailySummary['stepGoal'] ?? 8000,
      'stepsToday': _todayStepsValue(),
      'waterLiters': _todayWaterValue(),
    };
  }

  Future<void> _sendMessage([String? preset]) async {
    final message = (preset ?? _controller.text).trim();
    if (message.isEmpty || _isSending) return;

    setState(() {
      _messages.add({'role': 'user', 'text': message});
      _controller.clear();
      _isSending = true;
    });

    await _saveChatHistory();
    _scrollToBottom();

    GamificationService.onAiCoachUsed();

    final history = _messages
        .where((m) => (m['text'] ?? '').trim().isNotEmpty)
        .toList();

    try {
      final results = await Future.wait<dynamic>([
        _service.sendMessage(
          userMessage: message,
          userContext: _buildContext(),
          history: history,
        ),
        Future.delayed(_minimumAiLoadingTime),
      ]);

      if (!mounted) return;

      final reply = (results.first ?? '').toString().trim();

      setState(() {
        _messages.add({
          'role': 'assistant',
          'text': reply.isEmpty
              ? 'Sorry, I could not generate a response. Please try again.'
              : reply,
        });
        _isSending = false;
      });

      await _saveChatHistory();
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _messages.add({
          'role': 'assistant',
          'text':
              'Sorry, NutriPulse AI is having trouble replying right now. Please check your internet connection and try again.',
        });
        _isSending = false;
      });

      await _saveChatHistory();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 160,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _clearChat() {
    setState(() {
      _messages
        ..clear()
        ..add({
          'role': 'assistant',
          'text':
              'Chat cleared. Ask me anything — health, fitness, food, and lifestyle.',
        });
    });
    _saveChatHistory();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A3A18), Color(0xFF0F140D), Color(0xFF070907)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _topHeader(),
                  _contextStrip(),
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      physics: const BouncingScrollPhysics(
                        decelerationRate: ScrollDecelerationRate.fast,
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 154),
                      itemCount: _messages.length + (_isSending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_isSending && index == _messages.length) {
                          return _typingBubble();
                        }
                        final msg = _messages[index];
                        return _animatedMessageBubble(
                          textValue: msg['text'] ?? '',
                          isUser: msg['role'] == 'user',
                          index: index,
                        );
                      },
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: keyboard > 0 ? keyboard : 0,
                child: _bottomComposer(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.045)),
        ),
      ),
      child: Row(
        children: [
          _headerButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 12),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: lime,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: lime.withOpacity(0.20),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.smart_toy_rounded,
              color: Colors.black,
              size: 23,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NutriPulse AI',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: text,
                    fontSize: 24,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Personal coach for ${_name()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.75),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _headerButton(
            icon: Icons.delete_outline_rounded,
            onTap: _isSending ? null : _clearChat,
          ),
        ],
      ),
    );
  }

  Widget _headerButton({required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Icon(icon, color: soft.withOpacity(0.9), size: 18),
      ),
    );
  }

  Widget _contextStrip() {
    final cal = _todayCaloriesValue().round();
    final protein = _todayProteinValue().toStringAsFixed(0);
    final steps = _todayStepsValue();
    final goal = (_userData['goal'] ?? 'Not set').toString();

    return Container(
      height: 64,
      margin: const EdgeInsets.only(top: 6),
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _metricChip(
            Icons.local_fire_department_rounded,
            'Calories',
            '$cal kcal',
          ),
          _metricChip(Icons.fitness_center_rounded, 'Protein', '${protein}g'),
          _metricChip(
            Icons.directions_walk_rounded,
            'Steps',
            _formatCompact(steps),
          ),
          _metricChip(Icons.flag_rounded, 'Goal', goal),
        ],
      ),
    );
  }

  Widget _metricChip(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(right: 9, top: 4, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: card.withOpacity(0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: lime, size: 16),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: soft.withOpacity(0.64),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: text,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatCompact(int value) {
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return '$value';
  }

  Widget _animatedMessageBubble({
    required String textValue,
    required bool isUser,
    required int index,
  }) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('$index-${textValue.hashCode}'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final safe = value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 8 * (1 - safe)),
          child: Opacity(opacity: safe, child: child),
        );
      },
      child: _messageBubble(textValue: textValue, isUser: isUser),
    );
  }

  Widget _messageBubble({required String textValue, required bool isUser}) {
    final maxWidth = MediaQuery.of(context).size.width * (isUser ? 0.78 : 0.90);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(left: 3, bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.smart_toy_rounded, color: lime, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'NutriPulse AI',
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.78),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: EdgeInsets.symmetric(
                horizontal: isUser ? 15 : 17,
                vertical: isUser ? 12 : 15,
              ),
              decoration: BoxDecoration(
                color: isUser ? lime : card.withOpacity(0.96),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 18),
                ),
                border: Border.all(
                  color: isUser
                      ? Colors.white.withOpacity(0.10)
                      : Colors.white.withOpacity(0.055),
                ),
              ),
              child: SelectableText(
                textValue,
                style: GoogleFonts.outfit(
                  color: isUser ? Colors.black : text,
                  fontSize: isUser ? 14.5 : 15,
                  height: isUser ? 1.45 : 1.58,
                  fontWeight: isUser ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typingBubble() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final safe = value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 8 * (1 - safe)),
          child: Opacity(opacity: safe, child: child),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: lime.withOpacity(0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: lime.withOpacity(0.18)),
                boxShadow: [
                  BoxShadow(
                    color: lime.withOpacity(0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.smart_toy_rounded,
                color: lime,
                size: 18,
              ),
            ),
            const SizedBox(width: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              decoration: BoxDecoration(
                color: card.withOpacity(0.96),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.055)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _LoadingDot(delay: Duration.zero),
                  const SizedBox(width: 5),
                  const _LoadingDot(delay: Duration(milliseconds: 130)),
                  const SizedBox(width: 5),
                  const _LoadingDot(delay: Duration(milliseconds: 260)),
                  const SizedBox(width: 11),
                  Text(
                    'Preparing your answer...',
                    style: GoogleFonts.outfit(
                      color: soft,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomComposer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1209).withOpacity(0.94),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.32),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_messages.length <= 1) _suggestionChips(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.055),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.075),
                          ),
                        ),
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          keyboardAppearance: Brightness.dark,
                          scrollPadding: const EdgeInsets.only(bottom: 140),
                          onSubmitted: (_) => _sendMessage(),
                          style: GoogleFonts.outfit(
                            color: text,
                            fontSize: 14.6,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Ask NutriPulse AI anything...',
                            hintStyle: GoogleFonts.outfit(
                              color: soft.withOpacity(0.48),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            prefixIcon: Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: soft.withOpacity(0.42),
                              size: 18,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 15,
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _isSending ? null : _sendMessage,
                      child: AnimatedScale(
                        scale: _isSending ? 0.94 : 1,
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _isSending ? soft.withOpacity(0.18) : lime,
                            borderRadius: BorderRadius.circular(17),
                            boxShadow: _isSending
                                ? []
                                : [
                                    BoxShadow(
                                      color: lime.withOpacity(0.22),
                                      blurRadius: 14,
                                      offset: const Offset(0, 7),
                                    ),
                                  ],
                          ),
                          child: Icon(
                            _isSending
                                ? Icons.hourglass_top_rounded
                                : Icons.arrow_upward_rounded,
                            color: _isSending ? soft : Colors.black,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _suggestionChips() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(
          decelerationRate: ScrollDecelerationRate.fast,
        ),
        child: Row(
          children: _suggestions.map((s) {
            return Padding(
              padding: const EdgeInsets.only(right: 7),
              child: GestureDetector(
                onTap: () => _sendMessage(s),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: card.withOpacity(0.90),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.065)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt_rounded, color: lime, size: 13),
                      const SizedBox(width: 5),
                      Text(
                        s,
                        style: GoogleFonts.outfit(
                          color: soft,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _LoadingDot extends StatefulWidget {
  final Duration delay;

  const _LoadingDot({required this.delay});

  @override
  State<_LoadingDot> createState() => _LoadingDotState();
}

class _LoadingDotState extends State<_LoadingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );

    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    _opacity = Tween<double>(begin: 0.35, end: 1).animate(curved);
    _scale = Tween<double>(begin: 0.72, end: 1.12).animate(curved);

    Future.delayed(widget.delay, () {
      if (!mounted) return;
      _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: _ChatbotScreenState.lime,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

