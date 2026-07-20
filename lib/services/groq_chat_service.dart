import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/groq_config.dart';

class GroqChatService {
  static const Duration _timeout = Duration(seconds: 25);

  Future<String> sendMessage({
    required String userMessage,
    required Map<String, dynamic> userContext,
    required List<Map<String, String>> history,
  }) async {
    final apiKey = GroqConfig.apiKey.trim();

    if (apiKey.isEmpty || apiKey == 'PASTE_YOUR_GROQ_API_KEY_HERE') {
      return _fallbackReply(userMessage, userContext);
    }

    final systemPrompt = _buildSystemPrompt(userContext);

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      ...history
          .take(10)
          .map(
            (m) => {
              'role': m['role'] == 'assistant' ? 'assistant' : 'user',
              'content': m['text'] ?? '',
            },
          ),
      {'role': 'user', 'content': userMessage},
    ];

    try {
      final response = await http
          .post(
            Uri.parse(GroqConfig.endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': GroqConfig.model,
              'messages': messages,
              'temperature': 0.65,
              'max_tokens': 650,
              'top_p': 0.9,
            }),
          )
          .timeout(_timeout);

      final decoded = jsonDecode(response.body);

      if (response.statusCode != 200) {
        return 'Groq API Error ${response.statusCode}\n\n${response.body}\n\nFallback suggestion:\n${_fallbackReply(userMessage, userContext)}';
      }

      final choices = decoded['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        return 'Groq returned an empty response.\n\n${_fallbackReply(userMessage, userContext)}';
      }

      final message = choices.first['message'] as Map<String, dynamic>?;
      final content = message?['content']?.toString().trim();

      if (content == null || content.isEmpty) {
        return 'Groq returned no text response.\n\n${_fallbackReply(userMessage, userContext)}';
      }

      return content;
    } catch (e) {
      return 'Groq is not reachable right now. Here is a local NutriPulse suggestion:\n\n${_fallbackReply(userMessage, userContext)}';
    }
  }

  String _buildSystemPrompt(Map<String, dynamic> c) {
    return '''
You are NutriPulse AI Assistant inside a Flutter app.

MAIN BEHAVIOR:
- You can answer all kinds of user questions: health, lifestyle, nutrition, fitness, study, technology, coding, general knowledge, daily life, and app guidance.
- If the question is about health, nutrition, calories, protein, workouts, heart rate, SpO2, steps, hydration, or lifestyle, act as a personal health and lifestyle coach and use the NutriPulse app context.
- If the question is NOT health-related, answer normally as a helpful general AI assistant. Do not force the answer back to health topics.
- If the user asks for calculations, show the formula clearly.

HEALTH SAFETY RULES:
- Give general wellness and lifestyle guidance only.
- Do not diagnose diseases.
- Do not prescribe medicine.
- For serious symptoms, chest pain, fainting, severe fever, very abnormal SpO2, or emergency signs, tell the user to seek medical help.
- Keep answers practical, concise, and personalized.
- Prefer Malaysian food examples when relevant.

USER CONTEXT FROM APP:
Name: ${c['name'] ?? 'User'}
Goal: ${c['goal'] ?? 'Not set'}
Height: ${c['heightCm'] ?? 'Not set'} cm
Weight: ${c['weightKg'] ?? 'Not set'} kg
Target calories: ${c['targetCalories'] ?? 'Not set'} kcal
Today calories: ${c['todayCalories'] ?? 0} kcal
Protein today: ${c['todayProtein'] ?? 0} g
Carbs today: ${c['todayCarbs'] ?? 0} g
Fat today: ${c['todayFat'] ?? 0} g
Step goal: ${c['stepGoal'] ?? 8000}
Steps today: ${c['stepsToday'] ?? 0}
Water intake: ${c['waterLiters'] ?? 0} L

Answer clearly and naturally. For health-related questions, answer like a personal coach. Use short paragraphs and simple bullet points when useful.
''';
  }

  String _fallbackReply(String message, Map<String, dynamic> c) {
    final msg = message.toLowerCase();

    final calories = _numValue(c['todayCalories']);
    final target = _numValue(c['targetCalories'], fallback: 2000);
    final protein = _numValue(c['todayProtein']);
    final steps = _numValue(c['stepsToday']);
    final stepGoal = _numValue(c['stepGoal'], fallback: 8000);

    final extractedWeight = _extractWeightKg(msg);
    final profileWeight = _numValue(c['weightKg']);
    final weightKg = extractedWeight > 0 ? extractedWeight : profileWeight;

    if (msg.contains('protein')) {
      if (weightKg > 0) {
        final generalLow = (weightKg * 0.8).round();
        final generalHigh = (weightKg * 1.2).round();
        final muscleLow = (weightKg * 1.6).round();
        final muscleHigh = (weightKg * 2.2).round();
        final fatLossLow = (weightKg * 1.4).round();
        final fatLossHigh = (weightKg * 2.0).round();

        return '''
For ${weightKg.toStringAsFixed(weightKg.truncateToDouble() == weightKg ? 0 : 1)} kg body weight, your estimated protein intake is:

• General health: $generalLow–$generalHigh g/day
• Muscle gain / gym training: $muscleLow–$muscleHigh g/day
• Fat loss while preserving muscle: $fatLossLow–$fatLossHigh g/day

Formula:
• Fitness target: 1.6–2.2 g protein × body weight
• ${weightKg.toStringAsFixed(1)} × 1.6 = $muscleLow g
• ${weightKg.toStringAsFixed(1)} × 2.2 = $muscleHigh g

A good practical target for you is around $muscleLow–${(weightKg * 2.0).round()} g protein daily.
''';
      }

      return 'Today you have logged about ${protein.toStringAsFixed(0)} g protein. For fitness, try adding chicken breast, eggs, tuna, tofu, Greek yogurt, tempeh, or lean beef.';
    }

    if (msg.contains('calorie') || msg.contains('kcal')) {
      return 'Today you have logged ${calories.toStringAsFixed(0)} / ${target.toStringAsFixed(0)} kcal. Choose a balanced meal with protein, carbs, vegetables, and enough water.';
    }

    if (msg.contains('step') || msg.contains('walk')) {
      return 'You have around ${steps.toStringAsFixed(0)} / ${stepGoal.toStringAsFixed(0)} steps today. Try a 10–15 minute walk after meals to improve consistency.';
    }

    if (msg.contains('water') || msg.contains('hydrate')) {
      return 'Hydration supports energy, digestion, and recovery. Sip water regularly, especially after workouts or when your step count is high.';
    }

    if (msg.contains('heart') || msg.contains('bpm') || msg.contains('spo2')) {
      return 'For heart rate, SpO2, or temperature, use the ESP32 health monitor reading. If values are very abnormal or you feel unwell, consult a healthcare professional.';
    }

    return _generalFallback(message);
  }

  String _generalFallback(String message) {
    final msg = message.toLowerCase().trim();

    if (msg.isEmpty) {
      return 'Ask me anything. I can help with health, food, workouts, study, coding, technology, daily life, and general questions.';
    }

    if (msg.contains('hello') || msg.contains('hi') || msg.contains('hey')) {
      return 'Hi! I’m NutriPulse AI Assistant. You can ask me about health, nutrition, workouts, coding, studies, lifestyle, or any general question.';
    }

    if (msg.contains('flutter')) {
      return 'Flutter is a UI framework by Google for building mobile, web, and desktop apps using one codebase. In Flutter, screens are built using widgets such as Scaffold, Column, Row, Container, Text, and GestureDetector.';
    }

    if (msg.contains('firebase')) {
      return 'Firebase is a backend platform used for authentication, database, storage, notifications, and hosting. In your NutriPulse app, Firebase is useful for login, user profiles, food logs, step goals, and health history.';
    }

    if (msg.contains('study') || msg.contains('exam')) {
      return 'For studying, use active recall and spaced repetition. Study in short focused sessions, test yourself without looking at notes, revise weak topics first, and summarize each chapter into key points.';
    }

    if (msg.contains('ai') || msg.contains('artificial intelligence')) {
      return 'Artificial Intelligence is technology that allows computers to perform tasks that usually need human intelligence, such as understanding language, recognizing images, making recommendations, and detecting patterns.';
    }

    if (msg.contains('iot')) {
      return 'IoT means Internet of Things. It connects physical devices, such as ESP32 sensors, to apps or cloud systems so data like BPM, SpO2, temperature, or steps can be monitored in real time.';
    }

    return 'I can answer that, but my online AI connection may be unavailable right now. Please try again in a moment, or ask in a more specific way so I can give a better local response.';
  }

  double _numValue(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _extractWeightKg(String text) {
    final kgPattern = RegExp(r'(\d+(?:\.\d+)?)\s*kg');
    final match = kgPattern.firstMatch(text);
    if (match != null) {
      return double.tryParse(match.group(1) ?? '') ?? 0;
    }
    return 0;
  }
}
