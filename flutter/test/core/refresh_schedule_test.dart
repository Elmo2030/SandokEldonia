import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/refresh_schedule.dart';

DateTime at(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);

void main() {
  test('auto refresh off never fires', () {
    final t = at(1000000);
    expect(RefreshSchedule.isDue(hours: 0, lastSync: null, now: t), isFalse);
    expect(RefreshSchedule.isDue(hours: 0, lastSync: t.subtract(const Duration(hours: 999)), now: t), isFalse);
  });

  test('auto refresh fires once the interval has elapsed', () {
    final last = at(1000000);
    bool due(int hours, Duration after) => RefreshSchedule.isDue(hours: hours, lastSync: last, now: last.add(after));
    expect(due(6, const Duration(hours: 6) - const Duration(seconds: 1)), isFalse);
    expect(due(6, const Duration(hours: 6)), isTrue);
    expect(due(24, const Duration(hours: 23)), isFalse);
    expect(due(24, const Duration(hours: 25)), isTrue);
  });

  test('auto refresh without a previous sync is due, and a clock that jumped back too', () {
    final t = at(1000000);
    expect(RefreshSchedule.isDue(hours: 12, lastSync: null, now: t), isTrue);
    expect(RefreshSchedule.isDue(hours: 12, lastSync: t.add(const Duration(hours: 1)), now: t), isTrue);
  });
}
