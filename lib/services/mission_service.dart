class MissionService {
  static Map<String, Map<String, dynamic>> defaultMissions() => {
    'log_meal': {
      'title': 'Log one meal',
      'subtitle': 'Track at least one meal today',
      'icon': 'food',
      'xpReward': 20,
      'done': false,
    },
    'water_goal': {
      'title': 'Hydration target',
      'subtitle': 'Reach your daily water target',
      'icon': 'water',
      'xpReward': 20,
      'done': false,
    },
    'steps_goal': {
      'title': 'Move your body',
      'subtitle': 'Reach your daily step goal',
      'icon': 'steps',
      'xpReward': 25,
      'done': false,
    },
    'protein_goal': {
      'title': 'Hit protein goal',
      'subtitle': 'Reach today’s protein target',
      'icon': 'protein',
      'xpReward': 25,
      'done': false,
    },
  };
}
