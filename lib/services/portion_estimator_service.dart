import 'dart:io';
import 'package:image/image.dart' as img;

class PortionEstimatorService {
  static Future<Map<String, dynamic>> estimatePortion({
    required File imageFile,
    required String foodName,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded == null) {
        return fallback(foodName);
      }

      final image = img.copyResize(decoded, width: 224, height: 224);

      // ===== Improved portion estimation =====

      int detectedPixels = 0;
      int totalPixels = 0;

      int minX = 224;
      int minY = 224;
      int maxX = 0;
      int maxY = 0;

      // Ignore outer edges because background usually there
      for (int y = 25; y < 199; y++) {
        for (int x = 25; x < 199; x++) {
          final p = image.getPixel(x, y);

          final r = p.r.toDouble();
          final g = p.g.toDouble();
          final b = p.b.toDouble();

          final maxVal = [r, g, b].reduce((a, b) => a > b ? a : b);

          final minVal = [r, g, b].reduce((a, b) => a < b ? a : b);

          final brightness = maxVal / 255.0;

          final saturation = maxVal == 0 ? 0 : (maxVal - minVal) / maxVal;

          // Better food detection
          final looksLikeFood =
              brightness > 0.18 && brightness < 0.95 && saturation > 0.12;

          if (looksLikeFood) {
            detectedPixels++;

            if (x < minX) minX = x;
            if (y < minY) minY = y;
            if (x > maxX) maxX = x;
            if (y > maxY) maxY = y;
          }

          totalPixels++;
        }
      }

      // No food detected
      if (detectedPixels == 0) {
        return fallback(foodName);
      }

      // Bounding box size
      final width = (maxX - minX).abs();
      final height = (maxY - minY).abs();

      final area = width * height;

      // Normalize against center scan area
      final normalizedArea = area / (174 * 174);

      // More realistic thresholds
      String size;

      if (normalizedArea < 0.18) {
        size = 'Small';
      } else if (normalizedArea < 0.42) {
        size = 'Medium';
      } else {
        size = 'Large';
      }

      // Food-specific correction
      if (foodName.toLowerCase().contains('satay')) {
        if (normalizedArea < 0.28) {
          size = 'Small';
        }
      }

      if (foodName.toLowerCase().contains('roti')) {
        if (normalizedArea < 0.36) {
          size = 'Medium';
        }
      }

      final grams = gramsFor(foodName, size);

      return {
        'size': size,
        'grams': grams,
        'coverage': normalizedArea,
        'confidence': confidenceFromCoverage(normalizedArea),
      };
    } catch (_) {
      return fallback(foodName);
    }
  }

  static Map<String, dynamic> fallback(String foodName) {
    return {
      'size': 'Medium',
      'grams': gramsFor(foodName, 'Medium'),
      'coverage': 0.0,
      'confidence': 0.45,
    };
  }

  static double confidenceFromCoverage(double coverage) {
    if (coverage <= 0) return 0.45;

    if (coverage > 0.32 && coverage < 0.48) {
      return 0.70;
    }

    if (coverage >= 0.48) {
      return 0.78;
    }

    return 0.62;
  }

  static double gramsFor(String foodName, String size) {
    final food = foodName.toLowerCase().replaceAll('_', ' ');

    final Map<String, List<double>> portions = {
      'roti canai': [70, 100, 150],
      'nasi lemak': [250, 350, 500],
      'fried rice': [250, 350, 500],
      'nasi goreng': [250, 350, 500],
      'fried noodles': [250, 350, 500],
      'mee goreng': [250, 350, 500],
      'laksa': [300, 450, 600],
      'satay': [80, 150, 250],
      'hamburger': [120, 180, 250],
      'mixed rice': [300, 450, 650],
      'fish and chips': [250, 400, 550],
      'kaya toast': [60, 100, 150],
      'popiah': [80, 130, 200],
    };

    final match = portions.entries.firstWhere(
      (e) => food.contains(e.key),
      orElse: () => const MapEntry('default', [100, 200, 300]),
    );

    final values = match.value;

    switch (size.toLowerCase()) {
      case 'small':
        return values[0];

      case 'large':
        return values[2];

      default:
        return values[1];
    }
  }
}
