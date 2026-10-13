import 'package:shared_preferences/shared_preferences.dart';

import 'player_options.dart';

/// The player's settings, under the same keys the Apple apps use (so the shell's settings screen can share them): they are read once
/// when the player opens; the video scale and the subtitle style are written back when the user changes them in the player.
class PlayerPrefs {
  PlayerPrefs({
    this.seekStep = 10,
    this.barsHideSeconds = 3,
    this.bufferSize = BufferSize.normal,
    this.autoNextEpisode = true,
    this.subLang,
    this.audioLang,
    this.videoScale = VideoScale.fit,
    this.subScale = 1,
    this.subDelay = 0,
  });

  final int seekStep;
  final double barsHideSeconds;
  final BufferSize bufferSize;
  final bool autoNextEpisode;
  final String? subLang;
  final String? audioLang;
  VideoScale videoScale;
  double subScale;
  double subDelay;

  static Future<PlayerPrefs> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return PlayerPrefs(
        seekStep: (p.getInt('seekStep') ?? 10).clamp(1, 120),
        barsHideSeconds: (p.getInt('barsHideSeconds') ?? p.getDouble('barsHideSeconds')?.round() ?? 3).toDouble(),
        bufferSize: BufferSize.parse(p.getString('bufferSize')),
        autoNextEpisode: p.getBool('autoNextEpisode') ?? true,
        subLang: p.getString('prefSubLang'),
        audioLang: p.getString('prefAudioLang'),
        videoScale: VideoScale.parse(p.getString('videoScale')),
        subScale: p.getDouble('subScale') ?? 1,
        subDelay: p.getDouble('subDelay') ?? 0,
      );
    } catch (_) {
      return PlayerPrefs(); // no storage (a test, a private mode): the defaults
    }
  }

  Future<void> saveLook() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('videoScale', videoScale.name);
      await p.setDouble('subScale', subScale);
      await p.setDouble('subDelay', subDelay);
    } catch (_) {}
  }
}
