import 'package:flutter/widgets.dart';

import 'track_label.dart';

/// What the playback controller needs from a player engine (libmpv through media_kit in the app, a fake in the tests).
/// Getters are cheap snapshots (the controller polls them); commands return at once and never throw.
abstract class PlaybackEngine {
  /// Playback ended with an error (not a hiccup that the engine recovers from itself); the value is the reason.
  Stream<String> get failures;
  String? get lastError;

  double get position;
  double get duration;
  bool get paused;

  /// Waiting for data: an empty cache or a seek in flight.
  bool get buffering;

  /// The end of the file was reached (the engine stays on the last frame).
  bool get atEof;
  double get speed;
  List<Track> get tracks;

  /// [start] in seconds (0 = from the beginning).
  void load(String source, {double start = 0});
  void setPaused(bool paused);
  void seekTo(double seconds);
  void seekBy(double seconds);
  void setSpeed(double speed);

  /// 0 turns the subtitles off.
  void selectSubtitle(int id);
  void selectAudio(int id);
  void addSubtitle(String path);

  /// Subtitle size (1 = normal) and delay in seconds.
  void setSubtitleStyle({required double scale, required double delay});

  /// 0...1; 1 is the engine's full volume (the system volume is separate).
  void setVolume(double volume);

  /// How much to read ahead, from the buffer-size preference.
  void setBuffer(int maxBytes, int readaheadSecs);

  /// The picture. [fit] decides how it fills the space (contain = fit, cover = fill, fill = stretch).
  Widget buildVideo(BoxFit fit);

  void dispose();
}
