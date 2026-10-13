import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/player/sleep_timer.dart';

final t0 = DateTime.fromMillisecondsSinceEpoch(1000000 * 1000);
DateTime at(num s) => t0.add(Duration(milliseconds: (s * 1000).round()));

void main() {
  test('starts off', () {
    final t = SleepTimer();
    expect(t.isActive, false);
    expect(t.remaining(t0), null);
    expect(t.remainingMinutes(t0), null);
    expect(t.expired(t0), false);
  });

  test('counts down and expires at the deadline', () {
    final t = SleepTimer()..set(15, t0);
    expect(t.isActive, true);
    expect(t.remaining(t0), 900);
    expect(t.remaining(at(600)), 300);
    expect(t.expired(at(899)), false);
    expect(t.expired(at(900)), true);
    expect(t.expired(at(5000)), true);
    expect(t.remaining(at(5000)), 0, reason: 'the remaining time never goes negative');
  });

  for (final (elapsed, minutes) in [(0, 15), (1, 15), (59, 15), (60, 14), (840, 1), (899, 1), (900, 0), (1200, 0)]) {
    test('remaining minutes round up ($elapsed s -> $minutes)', () {
      final t = SleepTimer()..set(15, t0);
      expect(t.remainingMinutes(at(elapsed)), minutes);
    });
  }

  test('cancel and zero turn it off', () {
    final t = SleepTimer()..set(30, t0);
    t.cancel();
    expect(t.isActive || t.expired(at(99999)) || t.remaining(t0) != null, false);
    t.set(30, t0);
    t.set(0, t0);
    expect(t.isActive, false, reason: '0 minutes is the Off entry');
    t.set(-5, t0);
    expect(t.isActive, false);
  });

  test('setting again replaces the deadline', () {
    final t = SleepTimer()..set(15, t0);
    t.set(60, at(600));
    expect(t.remaining(at(600)), 3600);
    expect(t.expired(at(900)), false);
  });
}
