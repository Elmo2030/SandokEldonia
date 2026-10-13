/// What the queue logic needs from a download engine. The real one is `background_download_engine.dart` (the
/// `background_downloader` package: WorkManager, notifications, resume); tests use `test/downloads/fake_download_engine.dart`.
///
/// The job id is the id of the download in [DownloadsModel] (random, no title, no URL).
enum EngineState { queued, running, paused, done, failed, canceled }

enum EngineError { noSpace, notFound, other }

/// A state change and/or progress of one job. [bytes] and [total] are -1 when unknown.
class EngineUpdate {
  const EngineUpdate(this.id, {this.state, this.bytes = -1, this.total = -1, this.error});
  final String id;
  final EngineState? state;
  final int bytes, total;
  final EngineError? error;
}

class EngineJob {
  const EngineJob({required this.id, required this.url, required this.path, required this.title});
  final String id;

  /// Holds the account password: only the engine's private storage may keep it.
  final Uri url;
  final String path;

  /// The only text a notification shows.
  final String title;
}

abstract class DownloadEngine {
  /// Updates of all jobs. Listen before [start].
  Stream<EngineUpdate> get updates;

  /// Wakes the engine: updates that happened while the app was closed are delivered now.
  Future<void> start();

  /// False if the engine refused the job.
  Future<bool> enqueue(EngineJob job);

  Future<bool> pause(String id);

  /// False when the engine no longer knows the job (the caller enqueues it again).
  Future<bool> resume(String id);

  Future<void> cancel(String id);

  /// What the engine remembers (one update per job with the last state), to reconcile at startup.
  Future<Map<String, EngineUpdate>> known();
}
