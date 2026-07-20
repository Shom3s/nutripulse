import 'dart:convert';
import 'package:http/http.dart' as http;

class BarcodeFoodService {
  static const Duration _timeout = Duration(seconds: 12);

  static Future<Map<String, dynamic>?> getFoodByBarcode(String barcode) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) return null;

    final uri = Uri.parse(
      'https://world.openfoodfacts.org/api/v2/product/$cleanBarcode.json?fields=product_name,brands,nutriments,image_front_url,quantity,serving_size',
    );

    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('Barcode API error ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (data['status'] != 1 || data['product'] == null) {
      return null;
    }

    final product = data['product'] as Map<String, dynamic>;
    final nutriments =
        (product['nutriments'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    double readNum(List<String> keys) {
      for (final key in keys) {
        final value = nutriments[key];
        if (value is num) return value.toDouble();
        final parsed = double.tryParse(value?.toString() ?? '');
        if (parsed != null) return parsed;
      }
      return 0.0;
    }

    final productName = (product['product_name'] ?? '').toString().trim();
    final brands = (product['brands'] ?? '').toString().trim();

    return {
      'barcode': cleanBarcode,
      'name': productName.isEmpty ? 'Packaged Food' : productName,
      'brand': brands,
      'quantity': (product['quantity'] ?? '').toString(),
      'servingSize': (product['serving_size'] ?? '').toString(),
      'imageUrl': (product['image_front_url'] ?? '').toString(),
      // Values are per 100g / 100ml from Open Food Facts.
      'calories': readNum([
        'energy-kcal_100g',
        'energy-kcal',
        'energy-kcal_serving',
      ]),
      'protein': readNum(['proteins_100g', 'proteins', 'proteins_serving']),
      'carbs': readNum([
        'carbohydrates_100g',
        'carbohydrates',
        'carbohydrates_serving',
      ]),
      'fat': readNum(['fat_100g', 'fat', 'fat_serving']),
      'sugar': readNum(['sugars_100g', 'sugars', 'sugars_serving']),
      'source': 'Open Food Facts',
    };
  }
}
