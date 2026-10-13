import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/player/player_gestures.dart';
import 'package:iptvmac/player/player_options.dart';

void main() {
  test('a touch belongs to the half it started in', () {
    expect(PlayerGestures.side(10, 800), TouchSide.left);
    expect(PlayerGestures.side(399, 800), TouchSide.left);
    expect(PlayerGestures.side(400, 800), TouchSide.right);
    expect(PlayerGestures.side(790, 800), TouchSide.right);
  });

  test('a drag picks its axis once and after the slop', () {
    expect(PlayerGestures.axis(4, 6), null);
    expect(PlayerGestures.axis(30, 8), DragAxis.horizontal);
    expect(PlayerGestures.axis(-3, -25), DragAxis.vertical);
    expect(PlayerGestures.axis(15, 15), DragAxis.horizontal, reason: 'a tie goes to scrubbing');
    expect(PlayerGestures.axis(double.nan, 50), null);
  });

  for (final (d, span) in [(0.0, 60.0), (120.0, 60.0), (1200.0, 300.0), (7200.0, 600.0), (36000.0, 600.0), (double.nan, 60.0), (-5.0, 60.0)]) {
    test('scrub span for duration $d is $span', () => expect(PlayerGestures.scrubSpan(d), span));
  }

  test('scrubbing moves from where it started and stays inside the file', () {
    double t(double start, double tr, double w, double d) => PlayerGestures.scrubTarget(start: start, translation: tr, width: w, duration: d);
    expect(t(1000, 80, 800, 7200), 1060);
    expect(t(1000, -80, 800, 7200), 940);
    expect(t(30, -800, 800, 7200), 0);
    expect(t(7190, 800, 800, 7200), 7200);
    expect(t(50, 100, 0, 7200), 50);
    expect(t(50, double.infinity, 800, 7200), 50);
    expect(t(50, 100, 800, 0), 50);
  });

  test('dragging up raises the level and three quarters of the height cover the range', () {
    double l(double s, double ty, double h) => PlayerGestures.level(start: s, translationY: ty, height: h);
    expect(l(0.5, 0, 400), 0.5);
    expect(l(0, -150, 400), 0.5);
    expect(l(0.5, 150, 400), closeTo(0, 1e-9));
    expect(l(0.9, -300, 400), 1);
    expect(l(0.1, 300, 400), 0);
    expect(l(0.4, 100, 0), 0.4);
    expect(l(3, double.nan, 400), 1);
  });

  test('only a long fast downward flick dismisses the player', () {
    expect(PlayerGestures.verticalEnd(200, 2200), VerticalEnd.dismiss);
    expect(PlayerGestures.verticalEnd(200, 600), VerticalEnd.commit);
    expect(PlayerGestures.verticalEnd(60, 3000), VerticalEnd.commit);
    expect(PlayerGestures.verticalEnd(-250, -3000), VerticalEnd.commit);
  });

  test('pinching steps fit, fill, stretch and back', () {
    expect(PlayerGestures.scale(1.4, VideoScale.fit), VideoScale.fill);
    expect(PlayerGestures.scale(1.4, VideoScale.fill), VideoScale.stretch);
    expect(PlayerGestures.scale(1.4, VideoScale.stretch), VideoScale.stretch);
    expect(PlayerGestures.scale(0.6, VideoScale.stretch), VideoScale.fill);
    expect(PlayerGestures.scale(0.6, VideoScale.fill), VideoScale.fit);
    expect(PlayerGestures.scale(0.6, VideoScale.fit), VideoScale.fit);
    expect(PlayerGestures.scale(1.05, VideoScale.fit), VideoScale.fit);
    expect(PlayerGestures.scale(0.95, VideoScale.fill), VideoScale.fill);
    expect(PlayerGestures.scale(double.nan, VideoScale.fill), VideoScale.fill);
  });

  test('repeated double taps on one side add up', () {
    final t0 = DateTime.fromMillisecondsSinceEpoch(100000);
    DateTime at(double s) => t0.add(Duration(milliseconds: (s * 1000).round()));
    final a = SkipAccumulator();
    expect(a.isChaining(t0), false);
    expect(a.skip(TouchSide.right, step: 10, now: t0), 10);
    expect(a.isChaining(at(0.5)), true);
    expect(a.skip(TouchSide.right, step: 10, now: at(0.5)), 20);
    expect(a.skip(TouchSide.right, step: 10, now: at(1.2)), 30, reason: 'each tap renews the window');
    expect(a.skip(TouchSide.left, step: 10, now: at(1.5)), -10, reason: 'another side starts over');
    expect(a.skip(TouchSide.left, step: 10, now: at(1.6)), -20);
    expect(a.isChaining(at(2.7)), false, reason: 'a pause of a second ends the chain');
    expect(a.skip(TouchSide.left, step: 15, now: at(5)), -15);
    a.reset();
    expect(a.count, 0);
    expect(a.side, null);
  });

  test('skip labels use a real minus sign and no unit', () {
    expect(SkipAccumulator.label(30), '+30');
    expect(SkipAccumulator.label(-10), '−10');
    expect(SkipAccumulator.label(0), '+0');
  });

  test('video scale cycles and parses', () {
    expect(VideoScale.fit.next, VideoScale.fill);
    expect(VideoScale.stretch.next, VideoScale.fit);
    expect(VideoScale.parse('fill'), VideoScale.fill);
    expect(VideoScale.parse(null), VideoScale.fit);
    expect(BufferSize.parse('large').readaheadSecs, 60);
  });
}
