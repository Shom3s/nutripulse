import 'package:flutter/services.dart';

class LocalFoodDatabaseService {
  LocalFoodDatabaseService._();

  static final List<Map<String, dynamic>> _foods = [];
  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;

    final raw = await rootBundle.loadString('assets/data/food_database.csv');
    final rows = _parseCsv(raw);

    _foods
      ..clear()
      ..addAll(rows.map(_normalizeRow));

    _loaded = true;
  }

  static Future<List<Map<String, dynamic>>> searchFoods(
    String query, {
    int limit = 30,
  }) async {
    await ensureLoaded();

    final cleanQuery = _clean(query);
    if (cleanQuery.isEmpty) return [];

    final scored = <_ScoredFood>[];

    for (final food in _foods) {
      final name = _clean(food['name']);
      final category = _clean(food['category']);
      final cuisine = _clean(food['cuisine']);
      final tags = _clean(food['tags']);

      int score = 0;

      if (name == cleanQuery) {
        score += 1000;
      } else if (name.startsWith(cleanQuery)) {
        score += 800;
      } else if (name.contains(cleanQuery)) {
        score += 650;
      }

      final queryWords = cleanQuery.split(' ').where((w) => w.isNotEmpty);
      for (final word in queryWords) {
        if (name.split(' ').contains(word)) score += 140;
        if (name.contains(word)) score += 90;
        if (tags.contains(word)) score += 70;
        if (category.contains(word)) score += 30;
        if (cuisine.contains(word)) score += 25;
      }

      // Basic fuzzy tolerance for typo / partial text.
      final distance = _levenshtein(name, cleanQuery);
      if (distance <= 2) score += 420;
      if (distance <= 4 && cleanQuery.length >= 5) score += 180;

      if (score > 0) {
        scored.add(_ScoredFood(food, score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored
        .take(limit)
        .map((item) => Map<String, dynamic>.from(item.food))
        .toList();
  }

  static Future<Map<String, dynamic>> bestMatch(String query) async {
    final results = await searchFoods(query, limit: 1);

    if (results.isNotEmpty) {
      return results.first;
    }

    return manualEstimate(query);
  }

  static Map<String, dynamic> manualEstimate(String name) {
    return {
      'id': 'manual_estimate',
      'name': name.trim().isEmpty ? 'Custom Food' : name.trim(),
      'category': 'Manual Estimate',
      'cuisine': 'Custom',
      'serving': '1 serving',
      'servingSize': '1 serving',
      'serving_grams': 250.0,
      'calories': 300.0,
      'protein': 10.0,
      'carbs': 40.0,
      'fat': 10.0,
      'sugar': 0.0,
      'source': 'manual_estimate',
      'tags': 'custom estimate',
      'per100g': false,
    };
  }

  static List<List<String>> _parseCsv(String raw) {
    final rows = <List<String>>[];
    final current = <String>[];
    final buffer = StringBuffer();

    bool inQuotes = false;

    for (int i = 0; i < raw.length; i++) {
      final char = raw[i];

      if (char == '"') {
        if (inQuotes && i + 1 < raw.length && raw[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }

      if (char == ',' && !inQuotes) {
        current.add(buffer.toString());
        buffer.clear();
        continue;
      }

      if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && i + 1 < raw.length && raw[i + 1] == '\n') {
          i++;
        }

        current.add(buffer.toString());
        buffer.clear();

        if (current.any((cell) => cell.trim().isNotEmpty)) {
          rows.add(List<String>.from(current));
        }

        current.clear();
        continue;
      }

      buffer.write(char);
    }

    if (buffer.isNotEmpty || current.isNotEmpty) {
      current.add(buffer.toString());
      rows.add(List<String>.from(current));
    }

    return rows;
  }

  static Map<String, dynamic> _normalizeRow(List<String> row) {
    // Header:
    // id,name,category,cuisine,serving,serving_grams,calories,protein,carbs,fat,sugar,source,tags
    String s(int index) => index < row.length ? row[index].trim() : '';

    double d(int index) {
      final text = s(index).replaceAll(',', '');
      return double.tryParse(text) ?? 0.0;
    }

    final serving = s(4).isEmpty ? '1 serving' : s(4);

    return {
      'id': s(0),
      'name': s(1),
      'category': s(2),
      'cuisine': s(3),
      'serving': serving,
      'servingSize': serving,
      'serving_grams': d(5),
      'calories': d(6),
      'protein': d(7),
      'carbs': d(8),
      'fat': d(9),
      'sugar': d(10),
      'source': s(11).isEmpty ? 'estimated_csv' : s(11),
      'tags': s(12),
      'per100g': false,
    };
  }

  static String _clean(Object? value) {
    return (value ?? '')
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final previous = List<int>.generate(b.length + 1, (i) => i);
    final current = List<int>.filled(b.length + 1, 0);

    for (int i = 0; i < a.length; i++) {
      current[0] = i + 1;

      for (int j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;

        current[j + 1] = [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }

      for (int j = 0; j <= b.length; j++) {
        previous[j] = current[j];
      }
    }

    return previous[b.length];
  }
}

class _ScoredFood {
  const _ScoredFood(this.food, this.score);

  final Map<String, dynamic> food;
  final int score;
}
