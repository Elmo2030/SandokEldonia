// Small state machines behind the playback controller, kept free of the engine and of the clock so they can be tested exactly.

/// A live stream that dropped is reloaded up to [maxRetries] times, [delay] apart; a stream that plays again gets a fresh budget.
class LiveRecovery {
  static const maxRetries = 3;
  static const delay = Duration(seconds: 2);
  int retries = 0;
  double _lastPosition = 0;

  /// A tick while the stream plays: moving forward by more than half a second refreshes the retry budget.
  void observe(double position) {
    if (position > _lastPosition + 0.5) {
      retries = 0;
      _lastPosition = position;
    }
  }

  /// The stream failed. True = reload after [delay]; false = the budget is spent, show the error.
  bool failed() {
    if (retries >= maxRetries) return false;
    retries++;
    return true;
  }

  /// After a reload the position restarts at 0: the position bookkeeping starts over, the retry count stays until playback moves again.
  void reloaded() => _lastPosition = 0;

  void reset() {
    retries = 0;
    _lastPosition = 0;
  }
}

/// "The movie reached its end" with hysteresis: only the real end of the file counts (a connection cut early also sets eof-reached),
/// and only a change is reported (true when it ends, false when it leaves the end again, e.g. after a seek back).
class EndOfMedia {
  /// Within this many seconds of the duration counts as the end (credits, rounding of the duration).
  static const tail = 15.0;
  bool atEnd = false;

  bool? observe({required bool atEof, required double position, required double duration}) {
    final now = atEof && duration > 0 && position >= duration - tail;
    if (now == atEnd) return null;
    atEnd = now;
    return now;
  }

  /// A new file starts: the old one may still report its end for a tick, so only a real false -> true change counts afterwards.
  void newFile() => atEnd = true;
}

/// A paused live stream goes stale (the provider cuts the connection, the cache holds old data): resuming after a while reloads it.
class PauseClock {
  static const staleAfter = Duration(seconds: 20);
  DateTime? _since;

  void paused(DateTime now) => _since ??= now;

  /// Playing again. True when a live stream was paused long enough to need a reload.
  bool resumed(DateTime now, {required bool isLive}) {
    final s = _since;
    _since = null;
    return isLive && s != null && now.difference(s) >= staleAfter;
  }

  void reset() => _since = null;
}

/// The controls fade out [hideAfter] after the last touch (zero = never). Something that needs them (paused, scrubbing, a sheet,
/// an error) holds them on screen and restarts the countdown.
class ControlsVisibility {
  ControlsVisibility({this.hideAfter = const Duration(seconds: 3), required DateTime now}) : _touched = now;

  Duration hideAfter;
  bool shown = true;
  DateTime _touched;

  void touch(DateTime now) {
    shown = true;
    _touched = now;
  }

  void toggle(DateTime now) => shown ? shown = false : touch(now);
  void hide() => shown = false;

  void tick(DateTime now, {required bool holding}) {
    if (holding) {
      _touched = now;
      return;
    }
    if (shown && hideAfter > Duration.zero && now.difference(_touched) >= hideAfter) shown = false;
  }
}
