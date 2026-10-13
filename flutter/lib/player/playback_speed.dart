/// The playback speeds the player offers: the preset list of the picker, the allowed range and the rounding of a free value.
abstract final class PlaybackSpeed {
  static const presets = <double>[0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4];
  static const min = 0.25;
  static const max = 4.0;

  /// Clamped to the range and rounded to 0.05, so the value shown and the value the engine gets are the same.
  static double normalized(double s) {
    if (!s.isFinite) return 1;
    return (s.clamp(min, max) * 20).roundToDouble() / 20;
  }

  /// The next preset above (or below) [s]; a value between presets (1.15) steps to its neighbour, the ends stay put.
  static double step(double s, {required bool up}) {
    final v = normalized(s);
    if (up) {
      for (final p in presets) {
        if (p > v) return p;
      }
      return max;
    }
    for (final p in presets.reversed) {
      if (p < v) return p;
    }
    return min;
  }

  /// "1×", "1.5×", "0.25×" (always a dot, whatever the UI language).
  static String label(double s) => '${s == s.roundToDouble() ? s.toInt() : s}×';
}
