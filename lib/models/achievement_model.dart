class AchievementModel {
  const AchievementModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.unlocked,
  });

  final String id;
  final String title;
  final String subtitle;
  final String icon;
  final bool unlocked;

  factory AchievementModel.fromMap(String id, Map<String, dynamic> map) {
    return AchievementModel(
      id: id,
      title: (map['title'] ?? '').toString(),
      subtitle: (map['subtitle'] ?? '').toString(),
      icon: (map['icon'] ?? '🏆').toString(),
      unlocked: map['unlocked'] == true,
    );
  }
}
