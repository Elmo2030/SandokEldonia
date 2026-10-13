import 'package:flutter_test/flutter_test.dart';
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
}
