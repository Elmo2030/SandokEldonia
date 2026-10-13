import 'dart:async';
import 'dart:io';

import 'package:iptvmac/downloads/download_engine.dart';

/// An engine that does nothing by itself: tests drive it with [emit], [progress], [complete], [fail].
class FakeDownloadEngine implements DownloadEngine {
  final jobs = <String, EngineJob>{};
  final remembered = <String, EngineUpdate>{};
  final calls = <String>[];
  var refuse = false;

  /// Makes [resume] answer false, like an engine that lost the job.
  var forgetsOnResume = false;
  final _c = StreamController<EngineUpdate>.broadcast(sync: true);

  @override
  Stream<EngineUpdate> get updates => _c.stream;

  @override
  Future<void> start() async => calls.add('start');

  @override
  Future<bool> enqueue(EngineJob job) async {
    calls.add('enqueue ${job.id}');
    if (refuse) return false;
    jobs[job.id] = job;
    emit(EngineUpdate(job.id, state: EngineState.queued));
    return true;
  }

  @override
  Future<bool> pause(String id) async {
    calls.add('pause $id');
    emit(EngineUpdate(id, state: EngineState.paused));
    return true;
  }

  @override
  Future<bool> resume(String id) async {
    calls.add('resume $id');
    if (forgetsOnResume) return false;
    emit(EngineUpdate(id, state: EngineState.running));
    return true;
  }

  @override
  Future<void> cancel(String id) async {
    calls.add('cancel $id');
    jobs.remove(id);
    remembered.remove(id);
  }

  @override
  Future<Map<String, EngineUpdate>> known() async => Map.of(remembered);

  void emit(EngineUpdate u) {
    if (u.state != null) remembered[u.id] = u;
    _c.add(u);
  }

  void progress(String id, int bytes, int total) => emit(EngineUpdate(id, bytes: bytes, total: total));

  /// Writes the file like the real engine does, then reports it done.
  void complete(String id, {int size = 10}) {
    final f = File(jobs[id]!.path)..writeAsBytesSync(List.filled(size, 7));
    emit(EngineUpdate(id, state: EngineState.done, bytes: f.lengthSync(), total: f.lengthSync()));
  }

  void fail(String id, [EngineError error = EngineError.other]) => emit(EngineUpdate(id, state: EngineState.failed, error: error));

  String get lastId => jobs.keys.last;
}
