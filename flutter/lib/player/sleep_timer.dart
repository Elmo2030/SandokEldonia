/// A deadline with injected time (the controller polls it). Setting 0 minutes or fewer means Off.
class SleepTimer {
  DateTime? _deadline;

  bool get isActive => _deadline != null;
  void set(int minutes, DateTime now) => _deadline = minutes > 0 ? now.add(Duration(minutes: minutes)) : null;
  void cancel() => _deadline = null;

  /// Seconds left (never negative); null when off.
  double? remaining(DateTime now) {
    final d = _deadline;
    return d == null ? null : (d.difference(now).inMicroseconds / 1e6).clamp(0.0, double.infinity);
  }

  /// Whole minutes left, rounded up, so "1" is shown until the very end; null when off.
  int? remainingMinutes(DateTime now) {
    final r = remaining(now);
    return r == null ? null : (r / 60).ceil();
  }

  bool expired(DateTime now) => _deadline != null && !now.isBefore(_deadline!);
}
