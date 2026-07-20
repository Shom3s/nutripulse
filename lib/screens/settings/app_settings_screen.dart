import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/notification_service.dart';
import '../../theme/nutripulse_theme_controller.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color text = Colors.white;
  static const Color soft = Color(0xFFB7C2A8);
  static const Color card = Color(0xFF1A1F17);

  static const String _prefAiFloatingButton = 'setting_ai_floating_button';
  static const String _prefAiResetPositionRequest =
      'setting_ai_reset_position_request';
  static const String _prefAiButtonDx = 'setting_ai_button_dx';
  static const String _prefAiButtonDy = 'setting_ai_button_dy';
  static const String _prefAiChatHistory = 'setting_ai_chat_history';
  static const String _prefAiSaveHistory = 'setting_ai_save_chat_history';
  static const String _prefGraphAnimation = 'setting_graph_animation_enabled';
  static const String _prefReduceAnimations = 'setting_reduce_animations';
  static const String _prefPremiumGlow = 'setting_premium_glow';

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _loading = true;
  bool _saving = false;

  Map<String, bool> _notificationSettings = {};

  bool _aiFloatingButton = true;
  bool _aiSaveChatHistory = true;
  bool _graphAnimation = true;
  bool _reduceAnimations = false;
  bool _premiumGlow = true;

  bool _allowPrivateMessages = true;
  bool _storyReactionNotifications = true;
  bool _communityProfileVisible = true;

  Map<String, dynamic> _userData = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  String _uid() => _auth.currentUser?.uid ?? '';

  int _safeInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _safeDouble(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  bool _safeBool(dynamic value, {bool fallback = true}) {
    if (value is bool) return value;
    return fallback;
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notif = await NotificationService.instance.getSettings();

      final uid = _uid();
      Map<String, dynamic> data = {};
      if (uid.isNotEmpty) {
        final userDoc = await _db.collection('users').doc(uid).get();
        data = userDoc.data() ?? {};
      }

      final privacy = data['privacy'];
      final appSettings = data['appSettings'];

      if (!mounted) return;

      setState(() {
        _notificationSettings = notif;
        _userData = data;

        _aiFloatingButton =
            prefs.getBool(_prefAiFloatingButton) ??
            _safeBool(
              appSettings is Map ? appSettings['aiFloatingButton'] : null,
            );
        _aiSaveChatHistory =
            prefs.getBool(_prefAiSaveHistory) ??
            _safeBool(
              appSettings is Map ? appSettings['aiSaveChatHistory'] : null,
            );
        _graphAnimation =
            prefs.getBool(_prefGraphAnimation) ??
            _safeBool(
              appSettings is Map ? appSettings['graphAnimation'] : null,
            );
        _reduceAnimations =
            prefs.getBool(_prefReduceAnimations) ??
            _safeBool(
              appSettings is Map ? appSettings['reduceAnimations'] : null,
              fallback: false,
            );
        _premiumGlow =
            prefs.getBool(_prefPremiumGlow) ??
            _safeBool(appSettings is Map ? appSettings['premiumGlow'] : null);

        _allowPrivateMessages = _safeBool(
          privacy is Map ? privacy['allowPrivateMessages'] : null,
        );
        _storyReactionNotifications = _safeBool(
          privacy is Map ? privacy['storyReactionNotifications'] : null,
        );
        _communityProfileVisible = _safeBool(
          privacy is Map ? privacy['communityProfileVisible'] : null,
        );

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('Could not load settings: $e', isError: true);
    }
  }

  Future<void> _saveLocalBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveAppSettingsToFirestore({
    bool? aiFloatingButton,
    bool? aiSaveChatHistory,
    bool? graphAnimation,
    bool? reduceAnimations,
    bool? premiumGlow,
  }) async {
    final uid = _uid();
    if (uid.isEmpty) return;

    final update = <String, dynamic>{
      'appSettings.updatedAt': FieldValue.serverTimestamp(),
    };

    if (aiFloatingButton != null) {
      update['appSettings.aiFloatingButton'] = aiFloatingButton;
    }
    if (aiSaveChatHistory != null) {
      update['appSettings.aiSaveChatHistory'] = aiSaveChatHistory;
    }
    if (graphAnimation != null) {
      update['appSettings.graphAnimation'] = graphAnimation;
    }
    if (reduceAnimations != null) {
      update['appSettings.reduceAnimations'] = reduceAnimations;
    }
    if (premiumGlow != null) {
      update['appSettings.premiumGlow'] = premiumGlow;
    }

    await _db.collection('users').doc(uid).set(update, SetOptions(merge: true));
  }

  Future<void> _setNotification(String key, bool enabled) async {
    setState(() {
      _notificationSettings[key] = enabled;
      _saving = true;
    });

    try {
      final service = NotificationService.instance;

      switch (key) {
        case NotificationService.prefDailyReport:
          await service.setDailyReportEnabled(enabled);
          break;
        case NotificationService.prefMealReminder:
          await service.setMealReminderEnabled(enabled);
          break;
        case NotificationService.prefWaterReminder:
          await service.setWaterReminderEnabled(enabled);
          break;
        case NotificationService.prefActivityReminder:
          await service.setActivityReminderEnabled(enabled);
          break;
        case NotificationService.prefHealthScanReminder:
          await service.setHealthScanReminderEnabled(enabled);
          break;
        case NotificationService.prefCommunityPush:
          await service.setCommunityPushEnabled(enabled);
          break;
      }

      _showSnack(enabled ? 'Notification enabled' : 'Notification disabled');
    } catch (e) {
      setState(() => _notificationSettings[key] = !enabled);
      _showSnack('Could not update notification: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePrivacySetting({
    bool? allowPrivateMessages,
    bool? storyReactionNotifications,
    bool? communityProfileVisible,
  }) async {
    final uid = _uid();
    if (uid.isEmpty) return;

    final update = <String, dynamic>{
      'privacy.updatedAt': FieldValue.serverTimestamp(),
    };

    if (allowPrivateMessages != null) {
      update['privacy.allowPrivateMessages'] = allowPrivateMessages;
    }
    if (storyReactionNotifications != null) {
      update['privacy.storyReactionNotifications'] = storyReactionNotifications;
    }
    if (communityProfileVisible != null) {
      update['privacy.communityProfileVisible'] = communityProfileVisible;
    }

    await _db.collection('users').doc(uid).set(update, SetOptions(merge: true));
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        backgroundColor: isError ? Colors.red : card,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Future<void> _showHealthGoalsSheet() async {
    final calorieCtrl = TextEditingController(
      text: _safeInt(_userData['targetCalories'], fallback: 2000).toString(),
    );
    final proteinCtrl = TextEditingController(
      text: _safeDouble(
        _userData['proteinGoal'] ?? _userData['proteinGrams'],
        fallback: 120,
      ).round().toString(),
    );
    final carbsCtrl = TextEditingController(
      text: _safeDouble(
        _userData['carbsGoal'] ?? _userData['carbsGrams'],
        fallback: 250,
      ).round().toString(),
    );
    final fatCtrl = TextEditingController(
      text: _safeDouble(
        _userData['fatGoal'] ?? _userData['fatsGrams'],
        fallback: 70,
      ).round().toString(),
    );
    final waterCtrl = TextEditingController(
      text: _safeDouble(
        _userData['waterGoalLiters'],
        fallback: 3,
      ).toStringAsFixed(1),
    );
    final stepCtrl = TextEditingController(
      text: _safeInt(_userData['stepGoal'], fallback: 8000).toString(),
    );

    bool isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return Container(
            height: MediaQuery.of(ctx).size.height * 0.88,
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 22,
            ),
            decoration: const BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Health Goals',
                        style: GoogleFonts.outfit(
                          color: text,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: soft),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        _goalField(
                          'Calories goal',
                          calorieCtrl,
                          Icons.local_fire_department_rounded,
                          'kcal',
                        ),
                        const SizedBox(height: 12),
                        _goalField(
                          'Protein goal',
                          proteinCtrl,
                          Icons.fitness_center_rounded,
                          'g',
                        ),
                        const SizedBox(height: 12),
                        _goalField(
                          'Carbs goal',
                          carbsCtrl,
                          Icons.grain_rounded,
                          'g',
                        ),
                        const SizedBox(height: 12),
                        _goalField(
                          'Fat goal',
                          fatCtrl,
                          Icons.opacity_rounded,
                          'g',
                        ),
                        const SizedBox(height: 12),
                        _goalField(
                          'Water goal',
                          waterCtrl,
                          Icons.water_drop_rounded,
                          'liters',
                          decimal: true,
                        ),
                        const SizedBox(height: 12),
                        _goalField(
                          'Step goal',
                          stepCtrl,
                          Icons.directions_walk_rounded,
                          'steps',
                        ),
                        const SizedBox(height: 22),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            setSheet(() => isSaving = true);

                            try {
                              final uid = _uid();
                              if (uid.isEmpty) return;

                              final targetCalories =
                                  int.tryParse(calorieCtrl.text.trim()) ?? 2000;
                              final protein =
                                  double.tryParse(proteinCtrl.text.trim()) ??
                                  120;
                              final carbs =
                                  double.tryParse(carbsCtrl.text.trim()) ?? 250;
                              final fat =
                                  double.tryParse(fatCtrl.text.trim()) ?? 70;
                              final water =
                                  double.tryParse(waterCtrl.text.trim()) ?? 3.0;
                              final steps =
                                  int.tryParse(stepCtrl.text.trim()) ?? 8000;

                              final update = {
                                'targetCalories': targetCalories.clamp(
                                  800,
                                  6000,
                                ),
                                'proteinGoal': protein.clamp(0, 400),
                                'carbsGoal': carbs.clamp(0, 700),
                                'fatGoal': fat.clamp(0, 250),
                                'waterGoalLiters': water.clamp(1.0, 8.0),
                                'stepGoal': steps.clamp(1000, 50000),
                                // Keep old dashboard macro fields updated too.
                                'proteinGrams': protein
                                    .clamp(0, 400)
                                    .round()
                                    .toString(),
                                'carbsGrams': carbs
                                    .clamp(0, 700)
                                    .round()
                                    .toString(),
                                'fatsGrams': fat
                                    .clamp(0, 250)
                                    .round()
                                    .toString(),
                                'goalsUpdatedAt': FieldValue.serverTimestamp(),
                              };

                              await _db
                                  .collection('users')
                                  .doc(uid)
                                  .set(update, SetOptions(merge: true));

                              if (!mounted) return;
                              setState(() {
                                _userData = {..._userData, ...update};
                              });

                              if (ctx.mounted) Navigator.pop(ctx);
                              _showSnack('Health goals updated');
                            } catch (e) {
                              _showSnack(
                                'Could not save goals: $e',
                                isError: true,
                              );
                            } finally {
                              if (ctx.mounted) {
                                setSheet(() => isSaving = false);
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: lime,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: isSaving
                        ? const CircularProgressIndicator(color: Colors.black)
                        : Text(
                            'Save Goals',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _goalField(
    String label,
    TextEditingController controller,
    IconData icon,
    String suffix, {
    bool decimal = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _premiumBox(),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        style: GoogleFonts.outfit(
          color: text,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          prefixIcon: Icon(icon, color: lime),
          labelText: label,
          labelStyle: GoogleFonts.outfit(
            color: soft,
            fontWeight: FontWeight.w700,
          ),
          suffixText: suffix,
          suffixStyle: GoogleFonts.outfit(
            color: lime,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Future<void> _resetAiButtonPosition() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefAiButtonDx);
    await prefs.remove(_prefAiButtonDy);
    await prefs.setBool(_prefAiResetPositionRequest, true);
    _showSnack('AI button position will reset when you return');
  }

  Future<void> _clearAiChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefAiChatHistory);
    _showSnack('AI chat history cleared');
  }

  Future<void> _clearLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefAiChatHistory);
    await prefs.remove(_prefAiButtonDx);
    await prefs.remove(_prefAiButtonDy);
    await prefs.setBool(_prefAiResetPositionRequest, true);
    _showSnack('Local cache cleared');
  }

  Future<void> _resyncData() async {
    setState(() => _saving = true);
    try {
      await NotificationService.instance.saveFcmToken();
      await NotificationService.instance.scheduleEnabledLocalNotifications();
      _showSnack('Notifications and sync refreshed');
    } catch (e) {
      _showSnack('Could not refresh sync: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetTodayStepBaseline() async {
    final uid = _uid();
    if (uid.isEmpty) return;

    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    await _db
        .collection('users')
        .doc(uid)
        .collection('activity')
        .doc(today)
        .set({
          'baselineSteps': FieldValue.delete(),
          'steps': 0,
          'resetAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    _showSnack('Today step baseline reset');
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: card,
        title: Text(
          'Delete account?',
          style: GoogleFonts.outfit(color: text, fontWeight: FontWeight.w900),
        ),
        content: Text(
          'This removes your user profile document and attempts to delete your Firebase account. Firebase may ask you to login again before deletion.',
          style: GoogleFonts.outfit(color: soft, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: soft)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: GoogleFonts.outfit(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      await _db.collection('users').doc(user.uid).delete();
      await user.delete();

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
    } on FirebaseAuthException catch (e) {
      _showSnack(
        e.code == 'requires-recent-login'
            ? 'Login again first, then delete the account.'
            : 'Could not delete account: ${e.message}',
        isError: true,
      );
    } catch (e) {
      _showSnack('Could not delete account: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  BoxDecoration _premiumBox() {
    return BoxDecoration(
      color: card.withOpacity(0.92),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.16),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, String subtitle, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 24, 2, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: lime.withOpacity(0.13),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: lime, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: text,
                    fontSize: 20,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
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
        ],
      ),
    );
  }

  Widget _settingsCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: _premiumBox(),
      child: Column(children: children),
    );
  }

  Widget _settingsSwitchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: lime.withOpacity(0.11),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: lime, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: soft.withOpacity(0.72),
                      fontSize: 11.5,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Switch(
            value: value,
            activeColor: lime,
            activeTrackColor: lime.withOpacity(0.25),
            inactiveThumbColor: soft,
            inactiveTrackColor: Colors.white.withOpacity(0.08),
            onChanged: _saving ? null : onChanged,
          ),
        ],
      ),
    );
  }

  Widget _settingsActionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    Color? titleColor,
  }) {
    final effectiveIconColor = iconColor ?? lime;
    final effectiveTitleColor = titleColor ?? text;

    return InkWell(
      onTap: _saving ? null : onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: Row(
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: effectiveIconColor.withOpacity(0.11),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: effectiveIconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: effectiveTitleColor,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: soft.withOpacity(0.72),
                        fontSize: 11.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: soft.withOpacity(0.62),
              size: 15,
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.only(left: 69),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.white.withOpacity(0.055),
      ),
    );
  }

  Widget _themeModePicker() {
    return AnimatedBuilder(
      animation: nutriThemeController,
      builder: (context, _) {
        final selected = nutriThemeController.mode;
        final p = nutriThemeController.palette;

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: p.lime.withOpacity(0.11),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.color_lens_rounded,
                      color: p.lime,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dashboard theme',
                          style: GoogleFonts.outfit(
                            color: text,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Choose Normal or Premium Dark Mode',
                          style: GoogleFonts.outfit(
                            color: soft.withOpacity(0.72),
                            fontSize: 11.5,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _themePreviewTile(NutriThemeMode.normal, selected),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _themePreviewTile(
                      NutriThemeMode.premiumDark,
                      selected,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _themePreviewTile(NutriThemeMode mode, NutriThemeMode selected) {
    final isSelected = selected == mode;
    final preview = switch (mode) {
      NutriThemeMode.normal => NutriPalette.normal,
      NutriThemeMode.premiumDark => NutriPalette.premiumDark,
    };

    return GestureDetector(
      onTap: _saving
          ? null
          : () async {
              await nutriThemeController.setMode(mode);
              if (mounted) setState(() {});
              _showSnack('${mode.title} enabled');
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: preview.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? preview.lime.withOpacity(0.95)
                : Colors.white.withOpacity(0.07),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: preview.lime.withOpacity(0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(mode.icon, color: preview.lime, size: 17),
                const Spacer(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? preview.lime : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? preview.lime
                          : preview.subText.withOpacity(0.35),
                      width: 1.4,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: Colors.black,
                        )
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 26,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  colors: [
                    preview.topGradient,
                    preview.bg,
                    preview.bottomGradient,
                  ],
                ),
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: preview.lime,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              mode == NutriThemeMode.premiumDark ? 'Premium' : 'Normal',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: preview.text,
                fontSize: 12.2,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dailyReport =
        _notificationSettings[NotificationService.prefDailyReport] ?? true;
    final mealReminder =
        _notificationSettings[NotificationService.prefMealReminder] ?? true;
    final waterReminder =
        _notificationSettings[NotificationService.prefWaterReminder] ?? true;
    final activityReminder =
        _notificationSettings[NotificationService.prefActivityReminder] ?? true;
    final healthReminder =
        _notificationSettings[NotificationService.prefHealthScanReminder] ??
        true;
    final communityPush =
        _notificationSettings[NotificationService.prefCommunityPush] ?? true;

    return Scaffold(
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
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: lime))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.maybePop(context),
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.08),
                                ),
                              ),
                              child: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'App Settings',
                                  style: GoogleFonts.outfit(
                                    color: text,
                                    fontSize: 28,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Control NutriPulse your way',
                                  style: GoogleFonts.outfit(
                                    color: soft.withOpacity(0.78),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_saving)
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: lime,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle(
                              'Notifications',
                              'Reminders and social alerts',
                              Icons.notifications_rounded,
                            ),
                            _settingsCard(
                              children: [
                                _settingsSwitchRow(
                                  icon: Icons.insert_chart_rounded,
                                  title: 'Daily report',
                                  subtitle:
                                      '9 PM summary for calories, water and activity',
                                  value: dailyReport,
                                  onChanged: (v) => _setNotification(
                                    NotificationService.prefDailyReport,
                                    v,
                                  ),
                                ),
                                _divider(),
                                _settingsSwitchRow(
                                  icon: Icons.restaurant_rounded,
                                  title: 'Meal reminders',
                                  subtitle:
                                      'Breakfast, lunch and dinner log alerts',
                                  value: mealReminder,
                                  onChanged: (v) => _setNotification(
                                    NotificationService.prefMealReminder,
                                    v,
                                  ),
                                ),
                                _divider(),
                                _settingsSwitchRow(
                                  icon: Icons.water_drop_rounded,
                                  title: 'Water reminders',
                                  subtitle:
                                      'Hydration alerts throughout the day',
                                  value: waterReminder,
                                  onChanged: (v) => _setNotification(
                                    NotificationService.prefWaterReminder,
                                    v,
                                  ),
                                ),
                                _divider(),
                                _settingsSwitchRow(
                                  icon: Icons.directions_run_rounded,
                                  title: 'Activity reminder',
                                  subtitle:
                                      'Evening movement and walking reminder',
                                  value: activityReminder,
                                  onChanged: (v) => _setNotification(
                                    NotificationService.prefActivityReminder,
                                    v,
                                  ),
                                ),
                                _divider(),
                                _settingsSwitchRow(
                                  icon: Icons.monitor_heart_rounded,
                                  title: 'Health scan reminder',
                                  subtitle:
                                      'BPM, SpO₂ and body temperature reminder',
                                  value: healthReminder,
                                  onChanged: (v) => _setNotification(
                                    NotificationService.prefHealthScanReminder,
                                    v,
                                  ),
                                ),
                                _divider(),
                                _settingsSwitchRow(
                                  icon: Icons.forum_rounded,
                                  title: 'Community and private chat alerts',
                                  subtitle:
                                      'Post likes, story reactions and private messages',
                                  value: communityPush,
                                  onChanged: (v) => _setNotification(
                                    NotificationService.prefCommunityPush,
                                    v,
                                  ),
                                ),
                                _divider(),
                                _settingsActionRow(
                                  icon: Icons.notifications_active_rounded,
                                  title: 'Send test notification',
                                  subtitle:
                                      'Check notification permission and sound',
                                  onTap: () async {
                                    await NotificationService.instance
                                        .showTestNotification();
                                    _showSnack('Test notification sent');
                                  },
                                ),
                              ],
                            ),
                            _sectionTitle(
                              'Health Goals',
                              'Calories, macros, water and steps',
                              Icons.flag_rounded,
                            ),
                            _settingsCard(
                              children: [
                                _settingsActionRow(
                                  icon: Icons.tune_rounded,
                                  title: 'Edit health goals',
                                  subtitle:
                                      'Calories, protein, carbs, fat, water and steps',
                                  onTap: _showHealthGoalsSheet,
                                ),
                              ],
                            ),
                            _sectionTitle(
                              'AI Coach',
                              'Floating assistant and chat memory',
                              Icons.smart_toy_rounded,
                            ),
                            _settingsCard(
                              children: [
                                _settingsSwitchRow(
                                  icon: Icons.chat_bubble_rounded,
                                  title: 'Floating AI button',
                                  subtitle:
                                      'Show the draggable AI coach button on every tab',
                                  value: _aiFloatingButton,
                                  onChanged: (v) async {
                                    setState(() => _aiFloatingButton = v);
                                    await _saveLocalBool(
                                      _prefAiFloatingButton,
                                      v,
                                    );
                                    await _saveAppSettingsToFirestore(
                                      aiFloatingButton: v,
                                    );
                                    _showSnack(
                                      v
                                          ? 'Floating AI button enabled'
                                          : 'Floating AI button hidden',
                                    );
                                  },
                                ),
                                _divider(),
                                _settingsSwitchRow(
                                  icon: Icons.history_rounded,
                                  title: 'Save AI chat history',
                                  subtitle:
                                      'Keep recent AI coach messages on this device',
                                  value: _aiSaveChatHistory,
                                  onChanged: (v) async {
                                    setState(() => _aiSaveChatHistory = v);
                                    await _saveLocalBool(_prefAiSaveHistory, v);
                                    await _saveAppSettingsToFirestore(
                                      aiSaveChatHistory: v,
                                    );
                                    if (!v) await _clearAiChatHistory();
                                  },
                                ),
                                _divider(),
                                _settingsActionRow(
                                  icon: Icons.center_focus_strong_rounded,
                                  title: 'Reset AI button position',
                                  subtitle:
                                      'Move the floating AI button back to default',
                                  onTap: _resetAiButtonPosition,
                                ),
                                _divider(),
                                _settingsActionRow(
                                  icon: Icons.delete_sweep_rounded,
                                  title: 'Clear AI chat history',
                                  subtitle:
                                      'Remove saved AI messages from this device',
                                  onTap: _clearAiChatHistory,
                                ),
                              ],
                            ),
                            _sectionTitle(
                              'Privacy & Social',
                              'Private messages and community visibility',
                              Icons.lock_rounded,
                            ),
                            _settingsCard(
                              children: [
                                _settingsSwitchRow(
                                  icon: Icons.mark_unread_chat_alt_rounded,
                                  title: 'Allow private messages',
                                  subtitle:
                                      'Let other NutriPulse users message you',
                                  value: _allowPrivateMessages,
                                  onChanged: (v) async {
                                    setState(() => _allowPrivateMessages = v);
                                    await _savePrivacySetting(
                                      allowPrivateMessages: v,
                                    );
                                    _showSnack('Private message setting saved');
                                  },
                                ),
                                _divider(),
                                _settingsSwitchRow(
                                  icon: Icons.auto_awesome_rounded,
                                  title: 'Story reaction notifications',
                                  subtitle:
                                      'Receive alerts when users react to your story',
                                  value: _storyReactionNotifications,
                                  onChanged: (v) async {
                                    setState(
                                      () => _storyReactionNotifications = v,
                                    );
                                    await _savePrivacySetting(
                                      storyReactionNotifications: v,
                                    );
                                    _showSnack('Story reaction setting saved');
                                  },
                                ),
                                _divider(),
                                _settingsSwitchRow(
                                  icon: Icons.public_rounded,
                                  title: 'Community profile visible',
                                  subtitle:
                                      'Show your profile in community discovery',
                                  value: _communityProfileVisible,
                                  onChanged: (v) async {
                                    setState(
                                      () => _communityProfileVisible = v,
                                    );
                                    await _savePrivacySetting(
                                      communityProfileVisible: v,
                                    );
                                    _showSnack('Community visibility saved');
                                  },
                                ),
                              ],
                            ),
                            _sectionTitle(
                              'Appearance',
                              'Motion and visual style',
                              Icons.palette_rounded,
                            ),
                            _settingsCard(
                              children: [
                                _themeModePicker(),
                                _divider(),
                                _settingsSwitchRow(
                                  icon: Icons.show_chart_rounded,
                                  title: 'Dashboard graph animation',
                                  subtitle:
                                      'Animate the weekly calories graph on open',
                                  value: _graphAnimation,
                                  onChanged: (v) async {
                                    setState(() => _graphAnimation = v);
                                    await _saveLocalBool(
                                      _prefGraphAnimation,
                                      v,
                                    );
                                    await _saveAppSettingsToFirestore(
                                      graphAnimation: v,
                                    );
                                  },
                                ),
                                _divider(),
                                _settingsSwitchRow(
                                  icon: Icons.motion_photos_off_rounded,
                                  title: 'Reduce animations',
                                  subtitle:
                                      'Use fewer transitions for smoother low-end devices',
                                  value: _reduceAnimations,
                                  onChanged: (v) async {
                                    setState(() => _reduceAnimations = v);
                                    await _saveLocalBool(
                                      _prefReduceAnimations,
                                      v,
                                    );
                                    await _saveAppSettingsToFirestore(
                                      reduceAnimations: v,
                                    );
                                  },
                                ),
                                _divider(),
                                _settingsSwitchRow(
                                  icon: Icons.auto_fix_high_rounded,
                                  title: 'Premium glow style',
                                  subtitle:
                                      'Keep lime highlights and soft glow effects',
                                  value: _premiumGlow,
                                  onChanged: (v) async {
                                    setState(() => _premiumGlow = v);
                                    await _saveLocalBool(_prefPremiumGlow, v);
                                    await _saveAppSettingsToFirestore(
                                      premiumGlow: v,
                                    );
                                  },
                                ),
                              ],
                            ),
                            _sectionTitle(
                              'Data & Sync',
                              'Refresh sensors and local app data',
                              Icons.sync_rounded,
                            ),
                            _settingsCard(
                              children: [
                                _settingsActionRow(
                                  icon: Icons.cloud_sync_rounded,
                                  title: 'Refresh notifications and sync',
                                  subtitle:
                                      'Save FCM token and reschedule reminders',
                                  onTap: _resyncData,
                                ),
                                _divider(),
                                _settingsActionRow(
                                  icon: Icons.directions_walk_rounded,
                                  title: 'Reset today step baseline',
                                  subtitle:
                                      'Use when step count starts from wrong number',
                                  onTap: _resetTodayStepBaseline,
                                ),
                                _divider(),
                                _settingsActionRow(
                                  icon: Icons.cleaning_services_rounded,
                                  title: 'Clear local cache',
                                  subtitle:
                                      'Clear saved AI history and reset local positions',
                                  onTap: _clearLocalCache,
                                ),
                              ],
                            ),
                            _sectionTitle(
                              'Account',
                              'Session and account controls',
                              Icons.person_rounded,
                            ),
                            _settingsCard(
                              children: [
                                _settingsActionRow(
                                  icon: Icons.logout_rounded,
                                  title: 'Logout',
                                  subtitle: 'Sign out from this device',
                                  onTap: _logout,
                                ),
                                _divider(),
                                _settingsActionRow(
                                  icon: Icons.delete_forever_rounded,
                                  title: 'Delete account',
                                  subtitle:
                                      'Remove account after recent login confirmation',
                                  titleColor: Colors.red,
                                  iconColor: Colors.red,
                                  onTap: _deleteAccount,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
