import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/player/playback_watch.dart';

final t0 = DateTime.fromMillisecondsSinceEpoch(1000 * 1000);
DateTime at(num s) => t0.add(Duration(milliseconds: (s * 1000).round()));

void main() {
  group('live recovery', () {
    test('a dropped live stream is reloaded three times then gives up', () {
      final r = LiveRecovery();
      expect([r.failed(), r.failed(), r.failed()], [true, true, true]);
      expect(r.retries, 3);
      expect(r.failed(), false);
    });

    test('a stream that plays again gets a fresh retry budget', () {
      final r = LiveRecovery();
      expect([r.failed(), r.failed()], [true, true]);
      r.reloaded();
      r.observe(0.3);
      expect(r.retries, 2);
      r.observe(1.2);
      expect(r.retries, 0);
      expect([r.failed(), r.failed(), r.failed(), r.failed()], [true, true, true, false]);
    });

    test('a stalled stream is not refreshed', () {
      final r = LiveRecovery()..observe(10);
      expect(r.failed(), true);
      r.observe(10.2);
      expect(r.retries, 1);
      r.observe(11);
      expect(r.retries, 0);
      r.failed();
      r.reset();
      expect(r.retries, 0);
    });
  });

  group('end of media', () {
    test('reported once and only when the file really ended', () {
      final e = EndOfMedia();
      expect(e.observe(atEof: false, position: 100, duration: 3600), null);
      expect(e.observe(atEof: true, position: 100, duration: 3600), null, reason: 'a connection cut early also sets eof-reached');
      expect(e.observe(atEof: true, position: 3595, duration: 3600), true);
      expect(e.observe(atEof: true, position: 3599, duration: 3600), null);
      expect(e.observe(atEof: false, position: 3000, duration: 3600), false, reason: 'seeked back');
      expect(e.observe(atEof: true, position: 5, duration: 0), null, reason: 'no duration known');
    });

    test('a new file ignores the old files last tick', () {
      final e = EndOfMedia();
      e.observe(atEof: true, position: 59, duration: 60);
      e.newFile();
      expect(e.observe(atEof: true, position: 59, duration: 60), null);
      expect(e.observe(atEof: false, position: 1, duration: 120), false);
      expect(e.observe(atEof: true, position: 118, duration: 120), true);
    });
  });

  group('paused live stream', () {
    test('is reloaded on resume after a while', () {
      final c = PauseClock();
      c.paused(t0);
      expect(c.resumed(at(5), isLive: true), false);
      c.paused(t0);
      expect(c.resumed(at(PauseClock.staleAfter.inSeconds), isLive: true), true);
      c.paused(t0);
      expect(c.resumed(at(600), isLive: false), false, reason: 'a movie never needs it');
      expect(c.resumed(at(900), isLive: true), false, reason: 'not paused at all');
    });

    test('the first pause counts, not later ones', () {
      final c = PauseClock()..paused(t0)..paused(at(30));
      expect(c.resumed(at(31), isLive: true), true);
    });
  });

  group('controls visibility', () {
    test('hide three seconds after the last touch', () {
      final v = ControlsVisibility(now: t0);
      v.tick(at(2.9), holding: false);
      expect(v.shown, true);
      v.tick(at(3), holding: false);
      expect(v.shown, false);
      v.touch(at(10));
      expect(v.shown, true);
      v.tick(at(12), holding: false);
      expect(v.shown, true, reason: 'the countdown restarted at the touch');
    });

    test('something that needs the controls holds them and restarts the countdown', () {
      final v = ControlsVisibility(now: t0);
      for (var s = 1; s <= 10; s++) {
        v.tick(at(s), holding: true);
      }
      expect(v.shown, true);
      v.tick(at(12), holding: false);
      expect(v.shown, true);
      v.tick(at(13.1), holding: false);
      expect(v.shown, false);
    });

    test('a tap toggles and zero means never hide', () {
      final v = ControlsVisibility(hideAfter: Duration.zero, now: t0);
      v.tick(at(1000), holding: false);
      expect(v.shown, true);
      v.toggle(t0);
      expect(v.shown, false);
      v.toggle(t0);
      expect(v.shown, true);
      v.hide();
      expect(v.shown, false);
    });
  });
}
