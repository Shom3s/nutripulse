import 'package:cloud_firestore/cloud_firestore.dart';

class MealEntry {
  final String id;
  final String name;
  final String mealType; // breakfast / lunch / dinner / snack
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double sugar;
  final double portionG;
  final String portionSize;
  final bool portionEstimated;
  final double portionConfidence;
  final String method; // 'ai_scan' / 'manual' / 'barcode_scan'
  final String imageUrl;
  final String barcode;
  final String brand;
  final DateTime timestamp;

  MealEntry({
    required this.id,
    required this.name,
    required this.mealType,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.sugar = 0,
    required this.portionG,
    this.portionSize = 'Medium',
    this.portionEstimated = false,
    this.portionConfidence = 0,
    required this.method,
    this.imageUrl = '',
    this.barcode = '',
    this.brand = '',
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'mealType': mealType,
    'calories': calories,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'sugar': sugar,
    'portionG': portionG,
    'portionSize': portionSize,
    'portionEstimated': portionEstimated,
    'portionConfidence': portionConfidence,
    'method': method,
    'imageUrl': imageUrl,
    'barcode': barcode,
    'brand': brand,
    'timestamp': Timestamp.fromDate(timestamp),
  };

  MealEntry withPortion(double grams) {
    final ratio = grams / 100.0;
    return MealEntry(
      id: id,
      name: name,
      mealType: mealType,
      calories: double.parse((calories * ratio).toStringAsFixed(1)),
      protein: double.parse((protein * ratio).toStringAsFixed(1)),
      carbs: double.parse((carbs * ratio).toStringAsFixed(1)),
      fat: double.parse((fat * ratio).toStringAsFixed(1)),
      sugar: double.parse((sugar * ratio).toStringAsFixed(1)),
      portionG: grams,
      portionSize: portionSize,
      portionEstimated: portionEstimated,
      portionConfidence: portionConfidence,
      method: method,
      imageUrl: imageUrl,
      barcode: barcode,
      brand: brand,
      timestamp: timestamp,
    );
  }
}
