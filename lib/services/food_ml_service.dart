import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as pathLib;

class FoodMLService {
  static Interpreter? _interpreter;
  static Map<String, String> _labels = {};
  static bool _isLoaded = false;

  static const List<String> _classNames = [
    'fish_and_chips',
    'fried_noodles',
    'fried_rice',
    'hamburger',
    'kaya_toast',
    'laksa',
    'mixed_rice',
    'nasi_lemak',
    'popiah',
    'roti_canai',
    'satay',
  ];

  // Copy model from assets to device storage then load
  static Future<String> _extractModel() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelFile = File(pathLib.join(dir.path, 'food_model_v2.tflite'));

    // Always re-extract to get latest model
    print('Extracting model...');
    final data = await rootBundle.load('assets/ml/food_model.tflite');
    final bytes = data.buffer.asUint8List();
    await modelFile.writeAsBytes(bytes, flush: true);
    print('Model extracted: ${bytes.length} bytes → ${modelFile.path}');

    return modelFile.path;
  }

  static Future<void> loadModel() async {
    if (_isLoaded) return;
    try {
      final modelPath = await _extractModel();

      // Load interpreter from file
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromFile(
        File(modelPath),
        options: options,
      );

      print('✅ Interpreter created');
      print('   Input:  ${_interpreter!.getInputTensor(0).shape}');
      print('   Output: ${_interpreter!.getOutputTensor(0).shape}');

      // Load labels
      final raw = await rootBundle.loadString('assets/ml/food_labels.json');
      final Map<String, dynamic> parsed = jsonDecode(raw);
      _labels = parsed.map((k, v) => MapEntry(k, v.toString()));
      print('✅ Labels: $_labels');

      _isLoaded = true;
    } catch (e, stack) {
      print('❌ loadModel error: $e');
      print(stack);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> classifyFood(File imageFile) async {
    await loadModel();

    try {
      // Read and resize image
      final bytes = await imageFile.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) throw Exception('Cannot decode image');
      image = img.copyResize(image, width: 224, height: 224);
      print('Image decoded: ${image.width}x${image.height}');

      // Build input [1, 224, 224, 3] as nested List (most compatible)
      final input = List.generate(
        1,
        (_) => List.generate(
          224,
          (y) => List.generate(224, (x) {
            final p = image!.getPixel(x, y);
            return [
              p.r.toDouble() / 255.0,
              p.g.toDouble() / 255.0,
              p.b.toDouble() / 255.0,
            ];
          }),
        ),
      );

      // Output [1, 11]
      final output = List.generate(1, (_) => List.filled(11, 0.0));

      // Run inference
      print('Running inference...');
      _interpreter!.run(input, output);
      print('Inference complete');

      final scores = List<double>.from(output[0]);
      print('Scores: $scores');

      // Find best
      int bestIdx = 0;
      double bestScore = 0;
      for (int i = 0; i < scores.length; i++) {
        if (scores[i] > bestScore) {
          bestScore = scores[i];
          bestIdx = i;
        }
      }

      final bestLabel = _labels[bestIdx.toString()] ?? _classNames[bestIdx];
      print('🍽️ $bestLabel @ ${(bestScore * 100).toStringAsFixed(1)}%');

      // Top 3
      final indexed = scores.asMap().entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final top3 = indexed
          .take(3)
          .map(
            (e) => {
              'label': _labels[e.key.toString()] ?? _classNames[e.key],
              'score': e.value,
            },
          )
          .toList();

      return {'foodName': bestLabel, 'confidence': bestScore, 'top3': top3};
    } catch (e, stack) {
      print('❌ classifyFood error: $e');
      print(stack);
      rethrow;
    }
  }

  static void dispose() {
    _interpreter?.close();
    _isLoaded = false;
  }
}
