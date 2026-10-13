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
