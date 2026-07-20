import 'local_food_database_service.dart';

class NutritionService {
  // Offline-first nutrition database.
  // This avoids API downtime/key limits and works during demo without internet.
  static const Map<String, String> _labelToSearch = {
    'nasi_lemak': 'nasi lemak',
    'roti_canai': 'roti canai',
    'laksa': 'laksa',
    'fried_rice': 'nasi goreng',
    'fried_noodles': 'mee goreng',
    'satay': 'satay',
    'kaya_toast': 'kaya toast',
    'mixed_rice': 'nasi campur',
    'popiah': 'popiah',
    'hamburger': 'burger',
    'fish_and_chips': 'fish and chips',
  };

  static Future<Map<String, dynamic>> getNutrition(String foodLabel) async {
    final searchTerm = _labelToSearch[foodLabel] ?? foodLabel;
    return LocalFoodDatabaseService.bestMatch(searchTerm);
  }

  static Future<List<Map<String, dynamic>>> searchFoods(String query) async {
    return LocalFoodDatabaseService.searchFoods(query);
  }

  static Map<String, dynamic> manualEstimate(String query) {
    return LocalFoodDatabaseService.manualEstimate(query);
  }
}
