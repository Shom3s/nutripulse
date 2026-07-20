class GamificationProfile {
  const GamificationProfile({
    required this.xp,
    required this.level,
    required this.streak,
    required this.lastActiveDate,
    required this.updatedAt,
  });

  final int xp;
  final int level;
  final int streak;
  final String lastActiveDate;
  final DateTime? updatedAt;

  int get currentLevelStartXp => XpRules.xpForLevel(level);
  int get nextLevelXp => XpRules.xpForLevel(level + 1);
  int get xpInsideLevel =>
      (xp - currentLevelStartXp).clamp(0, nextLevelXp).toInt();
  int get xpNeededForNextLevel =>
      (nextLevelXp - currentLevelStartXp).clamp(1, 999999).toInt();
  double get progressToNextLevel =>
      (xpInsideLevel / xpNeededForNextLevel).clamp(0.0, 1.0);

  factory GamificationProfile.empty() {
    return const GamificationProfile(
      xp: 0,
      level: 1,
      streak: 0,
      lastActiveDate: '',
      updatedAt: null,
    );
  }

  factory GamificationProfile.fromMap(Map<String, dynamic>? map) {
    if (map == null) return GamificationProfile.empty();
    final xp = _asInt(map['xp']);
    return GamificationProfile(
      xp: xp,
      level: _asInt(map['level'], fallback: XpRules.levelForXp(xp)),
      streak: _asInt(map['streak']),
      lastActiveDate: (map['lastActiveDate'] ?? '').toString(),
      updatedAt: null,
    );
  }

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class XpRules {
  static int xpForLevel(int level) {
    final safeLevel = level < 1 ? 1 : level;
    return ((safeLevel - 1) * safeLevel * 125);
  }

  static int levelForXp(int xp) {
    var level = 1;
    while (xp >= xpForLevel(level + 1)) {
      level++;
      if (level >= 100) break;
    }
    return level;
  }

  static String titleForLevel(int level) {
    if (level >= 50) return 'NutriPulse Legend';
    if (level >= 25) return 'Elite Athlete';
    if (level >= 15) return 'Nutrition Warrior';
    if (level >= 8) return 'Health Explorer';
    if (level >= 4) return 'Momentum Builder';
    return 'Beginner';
  }
}
