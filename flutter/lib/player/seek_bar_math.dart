import 'dart:math' as math;

/// The numbers behind the seek bar and its bubble, kept out of the widgets so they can be tested.
abstract final class SeekBarMath {
  /// 0...1 for a pointer at [x] on a bar [width] wide; garbage (NaN, infinity, a bar without width) is 0.
  static double fraction(double x, double width) {
    if (!x.isFinite || !width.isFinite || width <= 0) return 0;
    return (x / width).clamp(0.0, 1.0);
  }

  static double fractionOf(double value, double total) {
    if (!value.isFinite || !total.isFinite || total <= 0) return 0;
    return (value / total).clamp(0.0, 1.0);
  }

  static double time(double x, double width, double duration) => duration.isFinite && duration > 0 ? fraction(x, width) * duration : 0;

  /// Left edge of the bubble in the player's coordinates: centred on the marker, [margin] away from both edges of the player.
  /// A bubble wider than the player sticks to the left margin.
  static double bubbleLeft({required double center, required double width, required double container, required double margin}) =>
      math.max(margin, math.min(center - width / 2, container - width - margin));

  /// "1:05", or "1:02:05" from one hour on.
  static String format(double seconds) {
    final t = seconds.isFinite ? math.max(seconds, 0).toInt() : 0;
    String two(int n) => n.toString().padLeft(2, '0');
    return t >= 3600 ? '${t ~/ 3600}:${two(t % 3600 ~/ 60)}:${two(t % 60)}' : '${t ~/ 60}:${two(t % 60)}';
  }
}
