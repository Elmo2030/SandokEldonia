import 'dart:async';

import 'package:flutter/foundation.dart';

import 'play_request.dart';

/// The "up next" countdown after an episode ends: [begin] counts [seconds] down, then calls [onDone] with the next request.
class UpNext extends ChangeNotifier {
  UpNext({this.seconds = 5, this.tick = const Duration(seconds: 1)});

  final int seconds;
  final Duration tick;
  PlayRequest? next;
  int secondsLeft = 0;
  Timer? _timer;

  bool get isCounting => next != null;

  void begin(PlayRequest n, void Function(PlayRequest) onDone) {
    if (next != null) return;
    next = n;
    secondsLeft = seconds;
    notifyListeners();
    _timer = Timer.periodic(tick, (t) {
      if (--secondsLeft > 0) {
        notifyListeners();
        return;
      }
      t.cancel();
      cancel(notify: false);
      onDone(n);
    });
  }

  void cancel({bool notify = true}) {
    _timer?.cancel();
    _timer = null;
    final was = next != null;
    next = null;
    secondsLeft = 0;
    if (notify && was) notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
