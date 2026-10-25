import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/player/playback_controller.dart';
import 'package:iptvmac/player/playback_watch.dart';
import 'package:iptvmac/player/track_label.dart';

import 'fake_engine.dart';

const retryDelay = Duration(milliseconds: 30);
final t0 = DateTime.fromMillisecondsSinceEpoch(5000 * 1000);
DateTime at(num s) => t0.add(Duration(milliseconds: (s * 1000).round()));

(PlaybackController, FakeEngine) make() {
  final e = FakeEngine();
  return (PlaybackController(e, tickInterval: null, retryDelay: retryDelay), e);
}

Future<void> wait(Duration d) => Future<void>.delayed(d);

void main() {
  test('ticking reflects playback and pause', () {
    final (c, e) = make();
    c.play('http://x/movie.mp4', live: false);
    expect(c.buffering, true, reason: 'nothing decoded yet');
    e..position = 3..duration = 100;
    c.tick();
    expect(c.position, 3);
    expect(c.buffering, false);
    e.tracks = [const Track(id: 1, type: 'video')];
    c.tick();
    expect(c.tracks, isNotEmpty);
    c.setPlaying(false);
    expect(c.paused, true);
    expect(e.commands.last, 'pause');
    c.togglePause();
    expect(c.paused, false);
    expect(e.commands.last, 'play');
    c.close();
  });

  test('the quality tag follows the decoded picture size', () {
    final (c, e) = make();
    c.play('http://x/live.m3u8', live: true);
    c.tick();
    expect(c.quality, isNull, reason: 'unknown until a picture is decoded');
    e..videoWidth = 1920..videoHeight = 1080;
    c.tick();
    expect(c.quality, 'FHD');
    e..videoWidth = 3840..videoHeight = 2160;
    c.tick();
    expect(c.quality, '4K', reason: 'an adaptive stream can change size while it plays');
    c.close();
  });

  test('buffering while the engine waits for data, never while paused', () {
    final (c, e) = make();
    c.play('u', live: false);
    e..position = 3..duration = 100..buffering = true;
    c.tick();
    expect(c.buffering, true);
    e.paused = true;
    c.tick();
    expect(c.buffering, false);
  });

  test('speed is clamped and rounded and set at once', () {
    final (c, e) = make();
    c.setSpeed(1.52);
    expect((c.speed, e.speed), (1.5, 1.5));
    c.setSpeed(9);
    expect(c.speed, 4);
    c.setSpeed(double.nan);
    expect(c.speed, 1);
  });

  test('a new item starts at normal speed', () {
    final (c, e) = make();
    c.setSpeed(2);
    c.play('u', live: false);
    expect(e.speed, 1);
  });

  test('seeking moves the position at once and stays inside the file', () {
    final (c, e) = make();
    c.play('u', live: false);
    e..position = 1..duration = 100;
    c.tick();
    c.seekTo(7);
    expect(c.position, 7);
    c.seekBy(-100);
    expect(c.position, 0);
    c.seekTo(-4);
    expect(c.position, 0);
    c.seekTo(500);
    expect(c.position, 100);
  });

  test('a movie that cannot be opened fails with the engines reason', () {
    final (c, e) = make();
    c.play('file:///none.mkv', live: false);
    e.fail('loading failed');
    expect(c.failed, true);
    expect(c.failure, 'loading failed');
    expect(c.buffering, false);
    c.tick();
    expect(c.buffering, false);
  });

  test('a live stream that cannot be opened is retried three times before it fails', () async {
    final (c, e) = make();
    c.play('http://x/live.ts', live: true);
    for (var i = 1; i <= 3; i++) {
      e.fail();
      expect(c.failed, false, reason: 'retry $i is pending');
      await wait(retryDelay * 2);
      expect(e.loads.length, 1 + i);
      expect(e.loads.last, ('http://x/live.ts', 0.0));
    }
    e.fail();
    expect(c.failed, true, reason: 'after three reloads the live stream gives up');
    expect(e.loads.length, 4);
  });

  test('a live stream that plays again gets a fresh retry budget', () async {
    final (c, e) = make();
    c.play('live', live: true);
    for (var i = 0; i < 3; i++) {
      e.fail();
      await wait(retryDelay * 2);
    }
    e..position = 0.2..duration = 0;
    c.tick();
    e.position = 5;
    c.tick();
    e.fail();
    expect(c.failed, false);
  });

  test('a failure while a retry is pending counts once', () async {
    final (c, e) = make();
    c.play('live', live: true);
    e.fail();
    e.fail();
    e.fail();
    await wait(retryDelay * 2);
    expect(e.loads.length, 2);
    expect(c.failed, false);
  });

  test('a stale retry never reloads an old item', () async {
    final (c, e) = make();
    c.play('channel-a', live: true);
    e.fail();
    c.play('channel-b', live: true);
    await wait(retryDelay * 3);
    expect(e.loads.map((l) => l.$1), ['channel-a', 'channel-b']);
  });

  test('a live stream that stops at the end of the file is treated as a failure', () async {
    final (c, e) = make();
    c.play('live', live: true);
    e..position = 30..atEof = true;
    c.tick();
    await wait(retryDelay * 2);
    expect(e.loads.length, 2);
  });

  test('retry clears the failure and reloads (a movie at its position, live at the edge)', () {
    final (c, e) = make();
    c.play('movie', live: false, start: 0);
    e..position = 120..duration = 3000;
    c.tick();
    e.fail();
    expect(c.failed, true);
    c.retry();
    expect((c.failed, c.failure, c.buffering), (false, null, true));
    expect(e.loads.last, ('movie', 120.0));
    c.play('live', live: true);
    e.fail();
    e.fail(); // pending retry: still not failed
    c.retry();
    expect(e.loads.last, ('live', 0.0));
  });

  test('the sleep timer fires once and the minutes left are shown', () {
    final (c, _) = make();
    var slept = 0;
    c.onSleep = () => slept++;
    c.setSleep(15, t0);
    expect(c.sleepMinutesLeft, 15);
    c.tick(at(61));
    expect((c.sleepMinutesLeft, slept), (14, 0));
    c.tick(at(15 * 60));
    expect((slept, c.sleepMinutesLeft), (1, null));
    c.tick(at(16 * 60));
    expect(slept, 1);
    c.setSleep(30, t0);
    c.setSleep(0, t0);
    expect(c.sleepMinutesLeft, null);
  });

  test('a movie reports its end once and replay starts over', () {
    final (c, e) = make();
    final changes = <bool>[];
    c.onEndChanged = changes.add;
    c.play('movie', live: false);
    e..position = 2..duration = 60;
    c.tick();
    e..position = 59..atEof = true;
    c.tick();
    expect(changes, [false, true], reason: 'the new file left the "end" state first, then really ended');
    expect(c.atEnd, true);
    for (var i = 0; i < 5; i++) {
      c.tick();
    }
    expect(changes.where((x) => x).length, 1);
    c.setPlaying(true, t0); // at the end, play means replay
    expect((c.paused, c.position), (false, 0));
    expect(e.commands, containsAllInOrder(['seekTo 0.0', 'play']));
  });

  test('progress is saved periodically, on close and on replace, never as 0 or for live', () {
    final (c, e) = make();
    final saves = <(double, double)>[];
    c.onSaveProgress = (p, d) => saves.add((p, d));
    c.play('movie', live: false);
    expect(saves, isEmpty, reason: 'nothing played yet: a 0 would erase the resume point');
    e..position = 12..duration = 600;
    for (var i = 0; i < 80; i++) {
      c.tick();
    }
    expect(saves, [(12.0, 600.0)], reason: '80 ticks of 250 ms = one periodic save');
    c.play('live', live: true); // replace: the old position is saved first
    expect(saves.length, 2);
    e.position = 50;
    for (var i = 0; i < 200; i++) {
      c.tick();
    }
    c.close();
    expect(saves.length, 2, reason: 'a live stream is never saved');
    expect(e.disposed, true);
  });

  test('a movie saved on close', () {
    final (c, e) = make();
    final saves = <double>[];
    c.onSaveProgress = (p, _) => saves.add(p);
    c.play('movie', live: false);
    e..position = 33..duration = 100;
    c.tick();
    c.close();
    expect(saves, [33.0]);
    c.close();
    expect(saves.length, 1, reason: 'closing twice saves once');
  });

  test('a live stream paused long enough is reloaded on resume, a short pause is not', () {
    final (c, e) = make();
    c.play('live', live: true);
    c.setPlaying(false, t0);
    c.setPlaying(true, at(5));
    expect(e.loads.length, 1);
    c.setPlaying(false, t0);
    c.setPlaying(true, at(PauseClock.staleAfter.inSeconds));
    expect(e.loads.length, 2);
    c.play('movie', live: false);
    c.setPlaying(false, t0);
    c.setPlaying(true, at(600));
    expect(e.loads.length, 3, reason: 'a movie never needs it');
  });

  test('nothing happens after close', () {
    final (c, e) = make();
    c.close();
    c.play('x', live: false);
    c.tick();
    expect(e.loads, isEmpty);
  });
}
