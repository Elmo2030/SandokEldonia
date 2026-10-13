import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/player/playback_speed.dart';

void main() {
  test('presets are sorted and inside the range', () {
    const p = PlaybackSpeed.presets;
    expect(p, [...p]..sort());
    expect(p.first, PlaybackSpeed.min);
    expect(p.last, PlaybackSpeed.max);
    expect(p, containsAll([1.0, 2.0]));
    for (final s in p) {
      expect(PlaybackSpeed.normalized(s), s, reason: 'every preset must survive the rounding unchanged');
    }
  });

  for (final (input, expected) in [
    (0.0, 0.25), (-3.0, 0.25), (0.1, 0.25), (9.0, 4.0), (4.01, 4.0), (1.0, 1.0), (1.12, 1.1), (1.13, 1.15), (0.52, 0.5),
    (1.999, 2.0), (double.nan, 1.0), (double.infinity, 1.0),
  ]) {
    test('normalized($input) clamps and rounds to five hundredths', () => expect(PlaybackSpeed.normalized(input), expected));
  }

  for (final (from, to) in [(1.0, 1.25), (1.25, 1.5), (2.0, 2.5), (3.0, 4.0), (4.0, 4.0), (0.25, 0.5), (1.15, 1.25), (0.1, 0.5)]) {
    test('step up from $from is $to', () => expect(PlaybackSpeed.step(from, up: true), to));
  }

  for (final (from, to) in [(1.0, 0.75), (0.5, 0.25), (0.25, 0.25), (4.0, 3.0), (1.15, 1.0), (1.3, 1.25), (9.0, 3.0)]) {
    test('step down from $from is $to', () => expect(PlaybackSpeed.step(from, up: false), to));
  }

  test('steps walk through all presets and stop at the ends', () {
    var s = PlaybackSpeed.min;
    final seen = [s];
    for (var i = 0; i < 30; i++) {
      s = PlaybackSpeed.step(s, up: true);
      if (seen.last != s) seen.add(s);
    }
    expect(seen, PlaybackSpeed.presets);
    for (var i = 0; i < 30; i++) {
      s = PlaybackSpeed.step(s, up: false);
    }
    expect(s, PlaybackSpeed.min);
  });

  test('labels use a dot and drop trailing zeros', () {
    expect(PlaybackSpeed.label(1), '1×');
    expect(PlaybackSpeed.label(1.5), '1.5×');
    expect(PlaybackSpeed.label(0.25), '0.25×');
    expect(PlaybackSpeed.label(2.0), '2×');
    expect(PlaybackSpeed.label(PlaybackSpeed.normalized(1.05)), '1.05×');
  });
}
