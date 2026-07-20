class MissionModel {
  const MissionModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconName,
    required this.xpReward,
    required this.done,
  });

  final String id;
  final String title;
  final String subtitle;
  final String iconName;
  final int xpReward;
  final bool done;

  factory MissionModel.fromMap(String id, Map<String, dynamic> map) {
    return MissionModel(
      id: id,
      title: (map['title'] ?? '').toString(),
      subtitle: (map['subtitle'] ?? '').toString(),
      iconName: (map['icon'] ?? 'flag').toString(),
      xpReward: _asInt(map['xpReward']),
      done: map['done'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'subtitle': subtitle,
    'icon': iconName,
    'xpReward': xpReward,
    'done': done,
  };

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
