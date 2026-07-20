import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../models/meal_entry.dart';

class MealFirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String get _uid {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'not-logged-in',
        message: 'User is not logged in. Please login again.',
      );
    }
    return user.uid;
  }

  static String get _today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  /// Save a meal and update today's total.
  ///
  /// Uses a batch + FieldValue.increment instead of a transaction so the save is
  /// faster and less likely to stay loading for a long time.
  static Future<void> saveMeal(MealEntry meal) async {
    final dayRef = _db
        .collection('users')
        .doc(_uid)
        .collection('meals')
        .doc(_today);

    final entryRef = dayRef.collection('entries').doc();
    final batch = _db.batch();

    final mealMap = Map<String, dynamic>.from(meal.toMap());
    mealMap['id'] = entryRef.id;
    mealMap['savedAt'] = FieldValue.serverTimestamp();

    batch.set(entryRef, mealMap);

    batch.set(dayRef, {
      'calories': FieldValue.increment(meal.calories),
      'protein': FieldValue.increment(meal.protein),
      'carbs': FieldValue.increment(meal.carbs),
      'fat': FieldValue.increment(meal.fat),
      'sugar': FieldValue.increment(meal.sugar),
      'date': _today,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit().timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        throw TimeoutException(
          'Saving took too long. Check your internet connection and Firestore rules.',
        );
      },
    );
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> getDailyTotals() {
    return _db
        .collection('users')
        .doc(_uid)
        .collection('meals')
        .doc(_today)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getTodayMeals() {
    return _db
        .collection('users')
        .doc(_uid)
        .collection('meals')
        .doc(_today)
        .collection('entries')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }
}
