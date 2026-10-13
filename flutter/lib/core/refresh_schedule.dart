abstract final class RefreshSchedule {
  /// Auto refresh of the playlists. `hours` 0 = only when the app opens (never due here). No previous sync, or a clock
  /// that jumped back, counts as due.
  static bool isDue({required int hours, required DateTime? lastSync, required DateTime now}) {
    if (hours <= 0) return false;
    if (lastSync == null) return true;
    final elapsed = now.difference(lastSync);
    return elapsed.isNegative || elapsed >= Duration(hours: hours);
  }
}
