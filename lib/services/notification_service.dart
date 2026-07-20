import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Background push received: ${message.data}');
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static GlobalKey<NavigatorState>? navigatorKey;

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _initialized = false;
  bool _skipInitialNotificationCenterSnapshot = true;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _notificationCenterSubscription;
  StreamSubscription<User?>? _authSubscription;

  static const String prefDailyReport = 'notif_daily_report';
  static const String prefMealReminder = 'notif_meal_reminder';
  static const String prefWaterReminder = 'notif_water_reminder';
  static const String prefActivityReminder = 'notif_activity_reminder';
  static const String prefHealthScanReminder = 'notif_health_scan_reminder';
  static const String prefCommunityPush = 'notif_community_push';

  static const int _dailyReportId = 1001;
  static const int _breakfastId = 1101;
  static const int _lunchId = 1102;
  static const int _dinnerId = 1103;
  static const int _waterBaseId = 1200;
  static const int _activityId = 1301;
  static const int _healthScanId = 1401;

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleLocalNotificationTap,
    );

    await setupDefaultPreferencesIfNeeded();
    await _configureFirebaseMessaging();

    _initialized = true;
  }

  Future<void> setupDefaultPreferencesIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      prefDailyReport,
      prefs.getBool(prefDailyReport) ?? true,
    );
    await prefs.setBool(
      prefMealReminder,
      prefs.getBool(prefMealReminder) ?? true,
    );
    await prefs.setBool(
      prefWaterReminder,
      prefs.getBool(prefWaterReminder) ?? true,
    );
    await prefs.setBool(
      prefActivityReminder,
      prefs.getBool(prefActivityReminder) ?? true,
    );
    await prefs.setBool(
      prefHealthScanReminder,
      prefs.getBool(prefHealthScanReminder) ?? true,
    );
    await prefs.setBool(
      prefCommunityPush,
      prefs.getBool(prefCommunityPush) ?? true,
    );
  }

  Future<Map<String, bool>> getSettings() async {
    await setupDefaultPreferencesIfNeeded();

    final prefs = await SharedPreferences.getInstance();

    return {
      prefDailyReport: prefs.getBool(prefDailyReport) ?? true,
      prefMealReminder: prefs.getBool(prefMealReminder) ?? true,
      prefWaterReminder: prefs.getBool(prefWaterReminder) ?? true,
      prefActivityReminder: prefs.getBool(prefActivityReminder) ?? true,
      prefHealthScanReminder: prefs.getBool(prefHealthScanReminder) ?? true,
      prefCommunityPush: prefs.getBool(prefCommunityPush) ?? true,
    };
  }

  Future<bool> requestPermission() async {
    final fcmSettings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    bool granted =
        fcmSettings.authorizationStatus == AuthorizationStatus.authorized ||
        fcmSettings.authorizationStatus == AuthorizationStatus.provisional;

    if (Platform.isAndroid) {
      final android = _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      final androidGranted =
          await android?.requestNotificationsPermission() ?? true;

      granted = granted && androidGranted;
    }

    if (Platform.isIOS) {
      final ios = _local
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();

      final iosGranted =
          await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;

      granted = granted && iosGranted;
    }

    return granted;
  }

  Future<void> _configureFirebaseMessaging() async {
    await requestPermission();

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final title =
          message.notification?.title ??
          message.data['title']?.toString() ??
          'NutriPulse';

      final body =
          message.notification?.body ??
          message.data['body']?.toString() ??
          'You have a new update.';

      await showInstantNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: title,
        body: body,
        payload: message.data['screen']?.toString() ?? 'push',
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Opened from push: ${message.data}');
      _openFromPayload(message.data['screen']?.toString() ?? '');
    });

    await saveFcmToken();
    await startNotificationCenterListener();

    _messaging.onTokenRefresh.listen((token) async {
      await saveFcmToken(token: token);
    });

    await _authSubscription?.cancel();
    _authSubscription = _auth.authStateChanges().listen((user) async {
      if (user == null) {
        await stopNotificationCenterListener();
        return;
      }

      await saveFcmToken();
      await startNotificationCenterListener();
    });
  }

  Future<void> saveFcmToken({String? token}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final fcmToken = token ?? await _messaging.getToken();
    if (fcmToken == null || fcmToken.isEmpty) return;

    await _db
        .collection('users')
        .doc(user.uid)
        .collection('fcmTokens')
        .doc(fcmToken)
        .set({
          'token': fcmToken,
          'platform': Platform.operatingSystem,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    await _db.collection('users').doc(user.uid).set({
      'lastFcmToken': fcmToken,
      'lastFcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteMyFcmToken() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final token = await _messaging.getToken();
    if (token == null) return;

    await _db
        .collection('users')
        .doc(user.uid)
        .collection('fcmTokens')
        .doc(token)
        .delete();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> userNotificationsStream({
    String? userId,
  }) {
    final uid = userId ?? _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }

    return _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  Stream<int> unreadNotificationCountStream({String? userId}) {
    final uid = userId ?? _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return Stream<int>.value(0);

    return _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Future<Map<String, String>> _currentUserProfileForNotification() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not logged in');
    }

    String name = user.displayName ?? 'NutriPulse User';
    String photoBase64 = '';

    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      final savedName = (data['name'] ?? data['username'] ?? '').toString();
      if (savedName.trim().isNotEmpty) name = savedName.trim();
      photoBase64 = (data['photoBase64'] ?? data['userImageBase64'] ?? '')
          .toString();
    } catch (_) {}

    return {'uid': user.uid, 'name': name, 'photoBase64': photoBase64};
  }

  Future<void> createUserNotification({
    required String receiverUid,
    required String type,
    required String title,
    required String body,
    String screen = 'notifications',
    String? notificationId,
    Map<String, dynamic> extraData = const {},
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final cleanedReceiverUid = receiverUid.trim();
    if (cleanedReceiverUid.isEmpty || cleanedReceiverUid == user.uid) return;

    final profile = await _currentUserProfileForNotification();
    final id =
        notificationId ??
        '${type}_${DateTime.now().millisecondsSinceEpoch}_${user.uid}';

    await _db
        .collection('users')
        .doc(cleanedReceiverUid)
        .collection('notifications')
        .doc(id)
        .set({
          'type': type,
          'title': title,
          'body': body,
          'actorUid': user.uid,
          'actorName': profile['name'],
          'actorImageBase64': profile['photoBase64'],
          // Firestore rules require these fields for cross-user notification writes.
          'senderId': user.uid,
          'receiverId': cleanedReceiverUid,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
          'screen': screen,
          ...extraData,
        }, SetOptions(merge: true));
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    final user = _auth.currentUser;
    if (user == null || notificationId.isEmpty) return;

    await _db
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .doc(notificationId)
        .set({
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> markAllNotificationsAsRead() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final unread = await _db
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .limit(100)
        .get();

    if (unread.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in unread.docs) {
      batch.set(doc.reference, {
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> startNotificationCenterListener() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _notificationCenterSubscription?.cancel();
    _skipInitialNotificationCenterSnapshot = true;

    _notificationCenterSubscription = _db
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(25)
        .snapshots()
        .listen((snapshot) async {
          if (_skipInitialNotificationCenterSnapshot) {
            _skipInitialNotificationCenterSnapshot = false;
            return;
          }

          final settings = await getSettings();
          if (settings[prefCommunityPush] != true) return;

          for (final change in snapshot.docChanges) {
            if (change.type != DocumentChangeType.added) continue;

            final data = change.doc.data() ?? {};
            if (data['read'] == true) continue;

            final title = (data['title'] ?? 'NutriPulse').toString();
            final body = (data['body'] ?? 'You have a new notification.')
                .toString();
            final payload = (data['screen'] ?? 'notifications').toString();

            await showInstantNotification(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: title,
              body: body,
              payload: payload,
            );
          }
        });
  }

  Future<void> stopNotificationCenterListener() async {
    await _notificationCenterSubscription?.cancel();
    _notificationCenterSubscription = null;
  }

  Future<void> scheduleEnabledLocalNotifications() async {
    await init();

    final granted = await requestPermission();
    if (!granted) return;

    final settings = await getSettings();

    if (settings[prefDailyReport] == true) {
      await scheduleDailyReport();
    }

    if (settings[prefMealReminder] == true) {
      await scheduleMealReminders();
    }

    if (settings[prefWaterReminder] == true) {
      await scheduleWaterReminders();
    }

    if (settings[prefActivityReminder] == true) {
      await scheduleActivityReminder();
    }

    if (settings[prefHealthScanReminder] == true) {
      await scheduleHealthScanReminder();
    }
  }

  Future<void> setDailyReportEnabled(bool enabled) async {
    await _saveBool(prefDailyReport, enabled);

    if (enabled) {
      await requestPermission();
      await scheduleDailyReport();
    } else {
      await _local.cancel(_dailyReportId);
    }
  }

  Future<void> setMealReminderEnabled(bool enabled) async {
    await _saveBool(prefMealReminder, enabled);

    if (enabled) {
      await requestPermission();
      await scheduleMealReminders();
    } else {
      await _local.cancel(_breakfastId);
      await _local.cancel(_lunchId);
      await _local.cancel(_dinnerId);
    }
  }

  Future<void> setWaterReminderEnabled(bool enabled) async {
    await _saveBool(prefWaterReminder, enabled);

    if (enabled) {
      await requestPermission();
      await scheduleWaterReminders();
    } else {
      await cancelWaterReminders();
    }
  }

  Future<void> setActivityReminderEnabled(bool enabled) async {
    await _saveBool(prefActivityReminder, enabled);

    if (enabled) {
      await requestPermission();
      await scheduleActivityReminder();
    } else {
      await _local.cancel(_activityId);
    }
  }

  Future<void> setHealthScanReminderEnabled(bool enabled) async {
    await _saveBool(prefHealthScanReminder, enabled);

    if (enabled) {
      await requestPermission();
      await scheduleHealthScanReminder();
    } else {
      await _local.cancel(_healthScanId);
    }
  }

  Future<void> setCommunityPushEnabled(bool enabled) async {
    await _saveBool(prefCommunityPush, enabled);

    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).set({
        'notificationSettings.communityPush': enabled,
        'notificationSettings.updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (enabled) {
      await requestPermission();
      await saveFcmToken();
    } else {
      await deleteMyFcmToken();
    }
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> scheduleDailyReport() async {
    await _scheduleDaily(
      id: _dailyReportId,
      hour: 21,
      minute: 0,
      title: 'Your NutriPulse report is ready 📊',
      body: 'See today’s calories, water, steps and progress.',
      payload: 'daily_report',
    );
  }

  Future<void> scheduleMealReminders() async {
    await _scheduleDaily(
      id: _breakfastId,
      hour: 8,
      minute: 0,
      title: 'Time to log breakfast 🍳',
      body: 'Track your first meal and start your day right.',
      payload: 'nutrition',
    );

    await _scheduleDaily(
      id: _lunchId,
      hour: 13,
      minute: 0,
      title: 'Time to log lunch 🍱',
      body: 'Add your meal to keep your calories accurate.',
      payload: 'nutrition',
    );

    await _scheduleDaily(
      id: _dinnerId,
      hour: 20,
      minute: 0,
      title: 'Time to log dinner 🌙',
      body: 'Complete your food log for today.',
      payload: 'nutrition',
    );
  }

  Future<void> scheduleWaterReminders() async {
    const hours = [9, 11, 13, 15, 17, 19, 21];

    for (int i = 0; i < hours.length; i++) {
      await _scheduleDaily(
        id: _waterBaseId + i,
        hour: hours[i],
        minute: 0,
        title: 'Drink some water 💧',
        body: 'Stay hydrated and complete your daily water goal.',
        payload: 'water',
      );
    }
  }

  Future<void> cancelWaterReminders() async {
    for (int i = 0; i < 7; i++) {
      await _local.cancel(_waterBaseId + i);
    }
  }

  Future<void> scheduleActivityReminder() async {
    await _scheduleDaily(
      id: _activityId,
      hour: 18,
      minute: 0,
      title: 'Ready for a quick walk? 🏃',
      body: 'Complete your activity goal today.',
      payload: 'run_tracker',
    );
  }

  Future<void> scheduleHealthScanReminder() async {
    await _scheduleDaily(
      id: _healthScanId,
      hour: 20,
      minute: 30,
      title: 'Do your health scan ❤️',
      body: 'Check BPM, SpO₂ and body temperature today.',
      payload: 'health',
    );
  }

  Future<void> showInstantNotification({
    required int id,
    required String title,
    required String body,
    String payload = '',
  }) async {
    await _local.show(id, title, body, _details(), payload: payload);
  }

  Future<void> showTestNotification() async {
    await requestPermission();

    await showInstantNotification(
      id: 9999,
      title: 'NutriPulse notifications are ready ✅',
      body: 'Your reminders and community alerts are now active.',
      payload: 'test',
    );
  }

  Future<void> cancelAllLocalNotifications() async {
    await _local.cancelAll();
  }

  Future<void> _scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
    required String payload,
  }) async {
    await _local.zonedSchedule(
      id,
      title,
      body,
      _nextInstanceOfTime(hour, minute),
      _details(),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  NotificationDetails _details() {
    const android = AndroidNotificationDetails(
      'nutripulse_reminders',
      'NutriPulse Reminders',
      channelDescription:
          'Daily report, meal, water, activity, health and community reminders.',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    return const NotificationDetails(android: android, iOS: ios);
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);

    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  void _handleLocalNotificationTap(NotificationResponse response) {
    debugPrint('Local notification tapped: ${response.payload}');
    _openFromPayload(response.payload ?? '');
  }

  void _openFromPayload(String payload) {
    final nav = navigatorKey?.currentState;
    if (nav == null) return;

    if (payload == 'daily_report') {
      nav.pushNamed('/daily-report');
      return;
    }

    if (payload == 'nutrition') {
      nav.pushNamed('/dashboard');
      return;
    }

    if (payload == 'water' ||
        payload == 'run_tracker' ||
        payload == 'health' ||
        payload == 'test') {
      nav.pushNamed('/dashboard');
      return;
    }
  }
}
