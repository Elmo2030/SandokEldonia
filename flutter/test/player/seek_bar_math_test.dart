import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/player/seek_bar_math.dart';

void main() {
  test('pointer position maps to time across the bar', () {
    expect(SeekBarMath.time(0, 400, 200), 0);
    expect(SeekBarMath.time(100, 400, 200), 50);
    expect(SeekBarMath.time(400, 400, 200), 200);
    expect(SeekBarMath.fraction(300, 400), 0.75);
  });

  test('pointer outside the bar is clamped to its ends', () {
    expect(SeekBarMath.time(-30, 400, 200), 0);
    expect(SeekBarMath.time(999, 400, 200), 200);
    expect(SeekBarMath.fraction(double.infinity, 400), 0);
  });

  test('degenerate bars and durations give zero, not NaN', () {
    expect(SeekBarMath.time(10, 0, 200), 0);
    expect(SeekBarMath.time(10, -5, 200), 0);
    expect(SeekBarMath.time(10, 400, 0), 0);
    expect(SeekBarMath.time(10, 400, -3), 0);
    expect(SeekBarMath.time(double.nan, 400, 200), 0);
    expect(SeekBarMath.time(10, 400, double.nan), 0);
    expect(SeekBarMath.fractionOf(5, 0), 0);
    expect(SeekBarMath.fractionOf(double.nan, 10), 0);
    expect(SeekBarMath.fractionOf(50, 10), 1);
    expect(SeekBarMath.fractionOf(-5, 10), 0);
  });

  test('the bubble centres on the marker and stays inside the player', () {
    double left(double c, {double container = 1000}) => SeekBarMath.bubbleLeft(center: c, width: 188, container: container, margin: 8);
    expect(left(500), 406);
    expect(left(20), 8, reason: 'stuck to the left edge');
    expect(left(990), 804, reason: 'stuck to the right edge');
    expect(left(-50), 8);
    expect(left(5000), 804);
  });

  test('a bubble wider than the player sticks to the left margin', () {
    expect(SeekBarMath.bubbleLeft(center: 100, width: 188, container: 150, margin: 8), 8);
    expect(SeekBarMath.bubbleLeft(center: 100, width: 188, container: 0, margin: 8), 8);
  });

  for (final (s, text) in [
    (0.0, '0:00'), (5.9, '0:05'), (65.0, '1:05'), (600.0, '10:00'), (3599.9, '59:59'), (3600.0, '1:00:00'), (3725.0, '1:02:05'),
    (36000.0, '10:00:00'), (-4.0, '0:00'), (double.nan, '0:00'), (double.infinity, '0:00'),
  ]) {
    test('format($s) is $text', () => expect(SeekBarMath.format(s), text));
  }
}
