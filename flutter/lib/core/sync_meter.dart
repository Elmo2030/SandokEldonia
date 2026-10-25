import 'dart:math' as math;

/// How far a sync is, 0..1, and never backwards: the three Xtream lists load at the same time and finish in any order. The sink is
/// told only when the value really grew. Same idea as SyncMeter.swift; here everything runs on one isolate.
class SyncMeter {
  SyncMeter(this._sink);
  final void Function(double fraction)? _sink;
  double _value = 0;

  void reach(double v) => _move(math.min(v, 1));
  void advance(double d) => _move(math.min(_value + d, 1));

  void _move(double n) {
    if (n <= _value) return;
    _value = n;
    _sink?.call(n);
  }
}
