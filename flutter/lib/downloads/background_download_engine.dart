import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:iptvmac/downloads/download_engine.dart';

/// [DownloadEngine] on the `background_downloader` package: WorkManager on Android, so a download goes on with the app in the
/// background or closed, and resumes after a dropped connection. Not run on a device yet (see README).
///
/// The package keeps each task (with its URL, so with the login) in its own private storage: that is how it can resume.
/// This class drops those records as soon as a job has ended. Notifications show the title only.
class BackgroundDownloadEngine implements DownloadEngine {
  /// [partialDir]: where unfinished files wait. On the same volume as the final folder, so finishing is a rename and a big
  /// movie does not need its size twice.
  BackgroundDownloadEngine({required this.partialDir});

  final String partialDir;
  final _downloader = FileDownloader();
  final _updates = StreamController<EngineUpdate>.broadcast();
  StreamSubscription<TaskUpdate>? _sub;
  var _askedNotifications = false;

  @override
  Stream<EngineUpdate> get updates => _updates.stream;

  @override
  Future<void> start() async {
    Directory(partialDir).createSync(recursive: true);
    _sub ??= _downloader.updates.listen(_onUpdate);
    await _downloader.configure(
      globalConfig: [
        (Config.holdingQueue, (1, null, null)), // many providers allow a single connection
        (Config.runInForeground, Config.always), // no 9 minute limit, a better chance to survive in the background
        (Config.checkAvailableSpace, 1024), // fails with a file system error when less than 1 GB would stay free
      ],
      androidConfig: [(Config.tempFilePath, partialDir)],
    );
    _downloader.configureNotification(
      running: const TaskNotification('{displayName}', '{progress}'),
      complete: const TaskNotification('{displayName}', ''),
      error: const TaskNotification('{displayName}', ''),
      paused: const TaskNotification('{displayName}', ''),
      progressBar: true,
    );
    await _downloader.start(autoCleanDatabase: true);
  }

  @override
  Future<bool> enqueue(EngineJob job) async {
    if (!_askedNotifications) {
      _askedNotifications = true;
      try {
        final p = _downloader.permissions;
        if (await p.status(PermissionType.notifications) != PermissionStatus.granted) await p.request(PermissionType.notifications);
      } catch (_) {
        // a denied permission only hides the notification
      }
    }
    final f = File(job.path);
    return _downloader.enqueue(DownloadTask(
      taskId: job.id,
      url: job.url.toString(),
      baseDirectory: BaseDirectory.root,
      directory: f.parent.path,
      filename: f.uri.pathSegments.last,
      displayName: job.title,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 3,
    ));
  }

  Future<DownloadTask?> _task(String id) async {
    final t = await _downloader.taskForId(id) ?? (await _downloader.database.recordForId(id))?.task;
    return t is DownloadTask ? t : null;
  }

  @override
  Future<bool> pause(String id) async {
    final t = await _task(id);
    return t != null && await _downloader.pause(t);
  }

  @override
  Future<bool> resume(String id) async {
    final t = await _task(id);
    return t != null && await _downloader.resume(t);
  }

  @override
  Future<void> cancel(String id) async {
    await _downloader.cancelTaskWithId(id);
    await _forget(id);
  }

  @override
  Future<Map<String, EngineUpdate>> known() async {
    final out = <String, EngineUpdate>{};
    for (final r in await _downloader.database.allRecords()) {
      final u = _fromStatus(r.task.taskId, r.status, r.exception, r.progress, r.expectedFileSize);
      out[r.task.taskId] = u;
      if (u.state == EngineState.done || u.state == EngineState.failed || u.state == EngineState.canceled) await _forget(r.task.taskId);
    }
    return out;
  }

  void _onUpdate(TaskUpdate u) {
    final id = u.task.taskId;
    switch (u) {
      case TaskStatusUpdate():
        final e = _fromStatus(id, u.status, u.exception, -1, -1);
        _updates.add(e);
        if (u.status.isFinalState) Timer(const Duration(seconds: 3), () => _forget(id)); // after the package has written its own record
      case TaskProgressUpdate():
        if (u.progress < 0 || u.progress > 1) return; // the negative values are states, reported above
        final total = u.hasExpectedFileSize ? u.expectedFileSize : -1;
        _updates.add(EngineUpdate(id, bytes: total > 0 ? (u.progress * total).round() : -1, total: total));
    }
  }

  static EngineUpdate _fromStatus(String id, TaskStatus s, TaskException? ex, double progress, int total) {
    final bytes = total > 0 && progress >= 0 && progress <= 1 ? (progress * total).round() : -1;
    final state = switch (s) {
      TaskStatus.enqueued || TaskStatus.waitingToRetry => EngineState.queued,
      TaskStatus.running => EngineState.running,
      TaskStatus.paused => EngineState.paused,
      TaskStatus.complete => EngineState.done,
      TaskStatus.canceled => EngineState.canceled,
      TaskStatus.failed || TaskStatus.notFound => EngineState.failed,
    };
    final error = switch (s) {
      TaskStatus.notFound => EngineError.notFound,
      TaskStatus.failed => ex is TaskFileSystemException && ex.description.toLowerCase().contains('space') ? EngineError.noSpace : EngineError.other,
      _ => null,
    };
    return EngineUpdate(id, state: state, bytes: bytes, total: total, error: error);
  }

  Future<void> _forget(String id) async {
    try {
      await _downloader.database.deleteRecordWithId(id);
    } catch (_) {
      // nothing to forget
    }
  }
}
