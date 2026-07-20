import '../models/gamification_profile.dart';

class XpService {
  static int levelForXp(int xp) => XpRules.levelForXp(xp);
  static int xpForLevel(int level) => XpRules.xpForLevel(level);
  static String titleForLevel(int level) => XpRules.titleForLevel(level);

  static const Map<String, int> actionXp = {
    'food_logged': 10,
    'ai_food_scan': 15,
    'barcode_scan': 15,
    'manual_food': 8,
    'water_goal': 15,
    'step_goal': 25,
    'protein_goal': 20,
    'ai_coach': 5,
    'daily_mission': 20,
    'weekly_challenge': 120,
  };
}
