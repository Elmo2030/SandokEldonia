import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iptvmac/player/engine.dart';
import 'package:iptvmac/player/track_label.dart';

/// A scriptable engine: tests set the snapshot fields and call [fail]; commands are recorded.
class FakeEngine implements PlaybackEngine {
  final _failures = StreamController<String>.broadcast(sync: true);
  final loads = <(String, double)>[];
  final commands = <String>[];
  bool disposed = false;

  @override
  String? lastError;
  @override
  double position = 0;
  @override
  double duration = 0;
  @override
  bool paused = false;
  @override
  bool buffering = false;
  @override
  bool atEof = false;
  @override
  double speed = 1;
  @override
  List<Track> tracks = [];

  @override
  Stream<String> get failures => _failures.stream;

  void fail([String reason = 'loading failed']) {
    lastError = reason;
    _failures.add(reason);
  }

  @override
  void load(String source, {double start = 0}) {
    loads.add((source, start));
    position = 0;
    atEof = false;
  }

  @override
  void setPaused(bool p) {
    commands.add(p ? 'pause' : 'play');
    paused = p;
  }

  @override
  void seekTo(double s) {
    commands.add('seekTo $s');
    position = s;
  }

  @override
  void seekBy(double s) {
    commands.add('seekBy $s');
    position += s;
  }

  @override
  void setSpeed(double s) {
    commands.add('speed $s');
    speed = s;
  }

  @override
  void selectSubtitle(int id) => commands.add('sub $id');
  @override
  void selectAudio(int id) => commands.add('audio $id');
  @override
  void addSubtitle(String path) => commands.add('addsub $path');
  @override
  void setSubtitleStyle({required double scale, required double delay}) => commands.add('substyle $scale $delay');
  @override
  void setVolume(double v) => commands.add('volume $v');
  @override
  void setBuffer(int maxBytes, int readaheadSecs) => commands.add('buffer $maxBytes');

  @override
  Widget buildVideo(BoxFit fit) => ColoredBox(color: Colors.black, key: ValueKey('video-$fit'));

  @override
  void dispose() {
    disposed = true;
    _failures.close();
  }
}
