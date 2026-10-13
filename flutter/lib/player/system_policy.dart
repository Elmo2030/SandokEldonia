import 'player_system.dart';

// The decisions the player takes about the system around it (calls and other apps, headphones), as plain values: the Android glue
// (audio_session) maps audio focus onto these and does what they say. Headphones unplugged is Android's own
// "becoming noisy" broadcast: it always means pause, so it needs no policy.

/// Audio-focus interruptions (a call, an alarm, another app taking the audio).
sealed class InterruptionEvent {
  const InterruptionEvent();
}

class InterruptionBegan extends InterruptionEvent {
  const InterruptionBegan();
}

class InterruptionEnded extends InterruptionEvent {
  const InterruptionEnded({required this.shouldResume});
  final bool shouldResume;
}

enum InterruptionAction { none, pause, resume }

class InterruptionPolicy {
  bool _pausedByInterruption = false;

  /// [isPlaying]: whether the player was playing when the event arrived. Playback is resumed after the interruption only when the
  /// interruption itself paused it and the system says resuming is appropriate (a call: yes once it ends; another music app: no).
  InterruptionAction handle(InterruptionEvent e, {required bool isPlaying}) {
    switch (e) {
      case InterruptionBegan():
        _pausedByInterruption = isPlaying;
        return isPlaying ? InterruptionAction.pause : InterruptionAction.none;
      case InterruptionEnded(:final shouldResume):
        final resume = _pausedByInterruption && shouldResume;
        _pausedByInterruption = false;
        return resume ? InterruptionAction.resume : InterruptionAction.none;
    }
  }

  /// The user pressed play or pause during the interruption: that choice wins over the automatic resume.
  void userChose() => _pausedByInterruption = false;
}

/// The system extrapolates the elapsed time from the rate, so the media session is only told what it cannot extrapolate: the title,
/// pause/speed, the duration, the buffering state, or a jump of the position (a seek). Without this the notification is rebuilt 4 times a second.
class NowPlayingThrottle {
  NowPlaying? _last;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool shouldPublish(NowPlaying s, DateTime now) {
    final need = _needed(s, now);
    if (need) {
      _last = s;
      _lastAt = now;
    }
    return need;
  }

  void reset() => _last = null;

  bool _needed(NowPlaying s, DateTime now) {
    final l = _last;
    if (l == null) return true;
    if (l.title != s.title || l.subtitle != s.subtitle || l.isLive != s.isLive || l.paused != s.paused || l.speed != s.speed) return true;
    if (l.buffering != s.buffering || l.canNext != s.canNext || l.canPrevious != s.canPrevious) return true;
    if ((l.duration - s.duration).abs() > 1) return true;
    final expected = l.position + (l.paused ? 0 : now.difference(_lastAt).inMicroseconds / 1e6 * l.speed);
    return !s.isLive && (s.position - expected).abs() > 2;
  }
}
