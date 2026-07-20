class HealthScoreService {
  static int calculateScore({
    required double calories,
    required double targetCalories,
    required double protein,
    required double targetProtein,
    required double waterLiters,
    required double waterGoal,
    required int steps,
    required int stepGoal,
  }) {
    final calorieScore = _rangeScore(
      value: calories,
      target: targetCalories <= 0 ? 2000 : targetCalories,
      lowerGood: 0.82,
      upperGood: 1.12,
      maxPoints: 25,
    );

    final proteinScore = _progressScore(
      protein,
      targetProtein <= 0 ? 100 : targetProtein,
      25,
    );

    final waterScore = _progressScore(
      waterLiters,
      waterGoal <= 0 ? 3.0 : waterGoal,
      20,
    );

    final stepScore = _progressScore(
      steps.toDouble(),
      stepGoal <= 0 ? 8000 : stepGoal.toDouble(),
      30,
    );

    return (calorieScore + proteinScore + waterScore + stepScore)
        .round()
        .clamp(0, 100)
        .toInt();
  }

  static double _progressScore(double value, double target, double maxPoints) {
    if (target <= 0) return 0;
    return ((value / target).clamp(0.0, 1.0)) * maxPoints;
  }

  static double _rangeScore({
    required double value,
    required double target,
    required double lowerGood,
    required double upperGood,
    required double maxPoints,
  }) {
    if (value <= 0 || target <= 0) return 0;
    final ratio = value / target;
    if (ratio >= lowerGood && ratio <= upperGood) return maxPoints;
    if (ratio < lowerGood)
      return (ratio / lowerGood).clamp(0.0, 1.0) * maxPoints;
    final extra = ratio - upperGood;
    return (maxPoints * (1 - extra)).clamp(0.0, maxPoints);
  }

  static String labelForScore(int score) {
    if (score >= 90) return 'Excellent';
    if (score >= 75) return 'Great';
    if (score >= 60) return 'Good';
    return 'Needs work';
  }
}
