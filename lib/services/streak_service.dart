class StreakService {
  static String dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static int nextStreak({
    required String lastActiveDate,
    required int currentStreak,
    DateTime? now,
  }) {
    final today = dateKey(now ?? DateTime.now());
    if (lastActiveDate == today) return currentStreak;

    final yesterday = dateKey(
      (now ?? DateTime.now()).subtract(const Duration(days: 1)),
    );
    if (lastActiveDate == yesterday) return currentStreak + 1;
    return 1;
  }
}
