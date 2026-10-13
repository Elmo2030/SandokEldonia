import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/player/player_system.dart';
import 'package:iptvmac/player/system_policy.dart';

const began = InterruptionBegan();
InterruptionEnded ended(bool resume) => InterruptionEnded(shouldResume: resume);

void main() {
  test('a call pauses and resumes when it ends if the system says so', () {
    final p = InterruptionPolicy();
    expect(p.handle(began, isPlaying: true), InterruptionAction.pause);
    expect(p.handle(ended(true), isPlaying: false), InterruptionAction.resume);
  });

  test('nothing resumes without the systems shouldResume', () {
    final p = InterruptionPolicy();
    p.handle(began, isPlaying: true);
    expect(p.handle(ended(false), isPlaying: false), InterruptionAction.none, reason: 'another app took the audio for good');
    expect(p.handle(ended(true), isPlaying: false), InterruptionAction.none, reason: 'and the flag does not stay armed');
  });

  test('a player that was paused before the interruption stays paused', () {
    final p = InterruptionPolicy();
    expect(p.handle(began, isPlaying: false), InterruptionAction.none);
    expect(p.handle(ended(true), isPlaying: false), InterruptionAction.none);
  });

  test('a choice of the user during the interruption wins', () {
    final p = InterruptionPolicy();
    p.handle(began, isPlaying: true);
    p.userChose();
    expect(p.handle(ended(true), isPlaying: false), InterruptionAction.none);
  });

  test('the media session is only told what it cannot extrapolate', () {
    final t0 = DateTime.fromMillisecondsSinceEpoch(0);
    DateTime at(num s) => t0.add(Duration(milliseconds: (s * 1000).round()));
    NowPlaying n(double pos, {bool paused = false, double speed = 1, String title = 'A'}) =>
        NowPlaying(title: title, isLive: false, position: pos, duration: 600, speed: speed, paused: paused);
    final th = NowPlayingThrottle();
    expect(th.shouldPublish(n(0), t0), true, reason: 'first time');
    expect(th.shouldPublish(n(1), at(1)), false, reason: 'playing on as expected');
    expect(th.shouldPublish(n(10.4), at(10)), false);
    expect(th.shouldPublish(n(10.4, paused: true), at(10)), true, reason: 'pause');
    expect(th.shouldPublish(n(10.4, paused: true), at(20)), false);
    expect(th.shouldPublish(n(10.4, speed: 2), at(21)), true, reason: 'resume at another speed');
    expect(th.shouldPublish(n(300, speed: 2), at(22)), true, reason: 'a seek');
    expect(th.shouldPublish(n(302, speed: 2, title: 'B'), at(23)), true, reason: 'next episode');
    th.reset();
    expect(th.shouldPublish(n(302, speed: 2, title: 'B'), at(24)), true);
  });

  test('a live channel never publishes for position jumps', () {
    final t0 = DateTime.fromMillisecondsSinceEpoch(0);
    NowPlaying n(double pos) => NowPlaying(title: 'C', isLive: true, position: pos, duration: 0, speed: 1, paused: false);
    final th = NowPlayingThrottle();
    expect(th.shouldPublish(n(0), t0), true);
    expect(th.shouldPublish(n(500), t0.add(const Duration(seconds: 1))), false);
  });
}
