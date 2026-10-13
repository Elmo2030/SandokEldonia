import 'dart:math' as math;

import 'player_options.dart';

/// The numbers behind the touch gestures (drag to scrub, drag for brightness/volume, pinch for the video scale, double tap to skip),
/// kept out of the widgets so they can be tested. Garbage input (NaN, a view without size) changes nothing.
enum TouchSide { left, right }

enum DragAxis { horizontal, vertical }

enum VerticalEnd { commit, dismiss }

abstract final class PlayerGestures {
  /// The half of the screen a touch started in (physical left/right, whatever the layout direction).
  static TouchSide side(double x, double width) => x < width / 2 ? TouchSide.left : TouchSide.right;

  /// Which way a drag goes, decided once it moved [slop] points; null until then. Diagonal drags go to the stronger axis.
  static DragAxis? axis(double dx, double dy, {double slop = 10}) {
    if (!dx.isFinite || !dy.isFinite || math.max(dx.abs(), dy.abs()) < slop) return null;
    return dx.abs() >= dy.abs() ? DragAxis.horizontal : DragAxis.vertical;
  }

  /// Seconds a drag across the whole width covers: a quarter of the duration, between a minute and ten minutes.
  static double scrubSpan(double duration) => duration.isFinite && duration > 0 ? (duration * 0.25).clamp(60.0, 600.0) : 60;

  /// Where a horizontal drag of [translation] points leads, from [start], clamped to the file.
  static double scrubTarget({required double start, required double translation, required double width, required double duration}) {
    if (!start.isFinite) return 0;
    if (!translation.isFinite || !width.isFinite || width <= 0 || !duration.isFinite || duration <= 0) return start;
    return (start + translation / width * scrubSpan(duration)).clamp(0.0, duration);
  }

  /// Brightness or volume (0...1) after a vertical drag: up raises it, three quarters of the height cover the whole range.
  static double level({required double start, required double translationY, required double height}) {
    if (!start.isFinite || !translationY.isFinite || !height.isFinite || height <= 0) return (start.isFinite ? start : 0.0).clamp(0.0, 1.0);
    return (start - translationY / (height * 0.75)).clamp(0.0, 1.0);
  }

  /// A long, fast flick downwards closes the player; anything slower was a level adjustment (which is then kept).
  static VerticalEnd verticalEnd(double translationY, double velocityY) =>
      translationY > 120 && velocityY > 1500 ? VerticalEnd.dismiss : VerticalEnd.commit;

  /// Pinching out steps fit -> fill -> stretch, pinching in steps back; a small pinch changes nothing.
  static VideoScale scale(double pinch, VideoScale from) {
    if (!pinch.isFinite) return from;
    if (pinch >= 1.15) return from == VideoScale.fit ? VideoScale.fill : VideoScale.stretch;
    if (pinch <= 0.87) return from == VideoScale.stretch ? VideoScale.fill : VideoScale.fit;
    return from;
  }
}

/// Repeated double taps on one side keep adding to one skip ("+10", "+20", "+30"); another side or a pause of a second starts over.
class SkipAccumulator {
  static const window = Duration(seconds: 1);
  TouchSide? side;
  int count = 0;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// True while a further tap on the same side counts as another skip instead of toggling the controls.
  bool isChaining(DateTime now) => side != null && now.difference(_last) < window;

  /// Registers one skip of [step] seconds on [s]; returns the signed total of the chain so far (negative = backwards).
  int skip(TouchSide s, {required int step, required DateTime now}) {
    if (s == side && isChaining(now)) {
      count++;
    } else {
      side = s;
      count = 1;
    }
    _last = now;
    return (s == TouchSide.left ? -1 : 1) * count * step;
  }

  void reset() {
    side = null;
    count = 0;
  }

  /// "+30" / "−10": numbers with a real minus sign, no unit, the same in every language.
  static String label(int total) => '${total < 0 ? '−' : '+'}${total.abs()}';
}
