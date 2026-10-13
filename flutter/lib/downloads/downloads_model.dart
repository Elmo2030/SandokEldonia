import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/downloads/download_engine.dart';
import 'package:iptvmac/downloads/download_entry.dart';
import 'package:iptvmac/downloads/download_naming.dart';

/// Rebuilds the stream URL (with the login) of an entry from the library; null when that is not possible (no password, source gone).
typedef DownloadUrlResolver = Uri? Function(DownloadEntry entry);

enum AddResult { started, exists, noUrl, refused }

/// The list of downloads and the rules around it. The engine moves the bytes; this keeps the list on disk
/// (`downloads.json` in the app support folder, never the SQLite file), maps engine updates onto it and rebuilds URLs on demand.
class DownloadsModel extends ChangeNotifier {
  DownloadsModel({required DownloadEngine this.engine, required File this.store, required this.dir, required this.resolveUrl});

  /// No downloads on this build or platform: the buttons and screens stay away.
  DownloadsModel.disabled()
      : engine = null,
        store = null,
        dir = '',
        resolveUrl = ((_) => null);

  final DownloadEngine? engine;
  final File? store;

  /// The folder of the files (the app's own external files directory, `Downloads/`).
  final String dir;
  final DownloadUrlResolver resolveUrl;

  bool get enabled => engine != null;
  List<DownloadEntry> _entries = [];
  List<DownloadEntry> get entries => List.unmodifiable(_entries);
  StreamSubscription<EngineUpdate>? _sub;
  var _disposed = false;

  int get activeCount => _entries.where((e) => e.active).length;
  bool get hasDone => _entries.any((e) => e.status == DownloadStatus.done);

  /// Bytes of the finished files that are still on the disk.
  int get doneBytes => _entries.where((e) => e.status == DownloadStatus.done && !e.missing).fold(0, (s, e) => s + e.bytes);

  DownloadEntry? find(String key) => _entries.where((e) => e.key == key).firstOrNull;
  DownloadEntry? byId(String id) => _entries.where((e) => e.id == id).firstOrNull;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }

  // ---- startup ----

  /// Reads the list, starts listening to the engine, and settles what happened while the app was closed.
  Future<void> load() async {
    final eng = engine;
    if (eng == null) return;
    _entries = _read();
    _sub = eng.updates.listen(_onUpdate);
    await eng.start();
    final known = await eng.known();
    for (final e in _entries) {
      switch (e.status) {
        case DownloadStatus.done:
          e.missing = !File(e.path).existsSync();
        case DownloadStatus.queued || DownloadStatus.running || DownloadStatus.paused:
          final k = known[e.id];
          if (k?.state != null) {
            _apply(e, k!);
          } else if (File(e.path).existsSync()) {
            _finish(e); // the engine finished and forgot it: the file is only moved to its name when complete
          } else {
            e.status = DownloadStatus.failed;
            e.error = 'lost';
          }
        case DownloadStatus.failed || DownloadStatus.canceled:
          break;
      }
    }
    _save();
    notifyListeners();
  }

  // ---- actions ----

  /// Saves a movie or an episode. The caller checked it is a direct file ([DownloadNaming.isDirectFile]).
  Future<AddResult> add({
    required int accountId,
    required ItemType type,
    required String streamId,
    String? episodeId,
    int? season,
    int? number,
    String? episodeTitle,
    required String title,
    required String ext,
  }) async {
    final eng = engine;
    if (eng == null) return AddResult.refused;
    final key = DownloadEntry.keyOf(accountId, type, streamId, episodeId);
    final old = find(key);
    if (old != null && old.status != DownloadStatus.failed && old.status != DownloadStatus.canceled && !old.missing) return AddResult.exists;
    if (old != null) _entries.remove(old); // a failed, canceled or missing one is replaced
    Directory(dir).createSync(recursive: true);
    final taken = {for (final e in _entries) File(e.path).uri.pathSegments.last.toLowerCase()};
    final name = DownloadNaming.fileName(
        title: title, ext: ext, taken: (n) => taken.contains(n.toLowerCase()) || File('$dir/$n').existsSync());
    final e = DownloadEntry(
      id: _newId(),
      accountId: accountId,
      type: type,
      streamId: streamId,
      episodeId: episodeId,
      season: season,
      number: number,
      episodeTitle: episodeTitle,
      title: title,
      ext: name.split('.').last,
      path: '$dir/$name',
    );
    if (resolveUrl(e) == null) return AddResult.noUrl;
    _entries.add(e);
    _save();
    notifyListeners();
    return await _start(e) ? AddResult.started : AddResult.refused;
  }

  Future<void> pause(String id) async {
    final e = byId(id);
    if (e != null && e.status == DownloadStatus.running) await engine?.pause(id); // the engine reports the new state
  }

  /// Continues a paused download; restarts a failed or canceled one (from the start: the engine keeps nothing of those).
  Future<void> resume(String id) async {
    final e = byId(id), eng = engine;
    if (e == null || eng == null) return;
    if (e.status == DownloadStatus.paused && await eng.resume(id)) {
      e.status = DownloadStatus.queued;
      _save();
      notifyListeners();
      return;
    }
    if (e.status == DownloadStatus.paused || e.status == DownloadStatus.failed || e.status == DownloadStatus.canceled) {
      await eng.cancel(id);
      e.bytes = 0;
      await _start(e);
    }
  }

  /// Cancels a running, queued or paused download, or removes a finished one together with its file.
  Future<void> remove(String id) async {
    final e = byId(id);
    if (e == null) return;
    _entries.remove(e);
    if (e.status != DownloadStatus.done) await engine?.cancel(id);
    _deleteFile(e);
    _save();
    notifyListeners();
  }

  /// Deletes every finished download and its file; unfinished ones stay.
  Future<void> removeAllDone() async {
    for (final e in _entries.where((e) => e.status == DownloadStatus.done).toList()) {
      _entries.remove(e);
      _deleteFile(e);
    }
    _save();
    notifyListeners();
  }

  // ---- engine ----

  Future<bool> _start(DownloadEntry e) async {
    final url = resolveUrl(e);
    var ok = false;
    if (url != null) {
      e.status = DownloadStatus.queued;
      e.error = null;
      notifyListeners();
      ok = await engine!.enqueue(EngineJob(id: e.id, url: url, path: e.path, title: e.title));
    }
    if (!ok) {
      e.status = DownloadStatus.failed;
      e.error = 'other';
    }
    _save();
    notifyListeners();
    return ok;
  }

  void _onUpdate(EngineUpdate u) {
    final e = byId(u.id);
    if (e == null) return;
    final before = e.status;
    _apply(e, u);
    if (e.status != before) _save();
    notifyListeners();
  }

  void _apply(DownloadEntry e, EngineUpdate u) {
    if (u.total > 0) e.total = u.total;
    if (u.bytes >= 0) e.bytes = u.bytes;
    switch (u.state) {
      case null:
        if (e.status == DownloadStatus.queued && u.bytes > 0) e.status = DownloadStatus.running;
      case EngineState.queued:
        e.status = DownloadStatus.queued;
      case EngineState.running:
        e.status = DownloadStatus.running;
      case EngineState.paused:
        e.status = DownloadStatus.paused;
      case EngineState.done:
        _finish(e);
      case EngineState.failed:
        e.status = DownloadStatus.failed;
        e.error = (u.error ?? EngineError.other).name;
      case EngineState.canceled:
        e.status = DownloadStatus.canceled;
    }
  }

  void _finish(DownloadEntry e) {
    final f = File(e.path);
    if (!f.existsSync()) {
      e.status = DownloadStatus.failed;
      e.error = 'file';
      return;
    }
    e.status = DownloadStatus.done;
    e.error = null;
    e.missing = false;
    e.bytes = e.total = f.lengthSync();
  }

  // ---- files ----

  /// Checks the finished files again (the user may have deleted one with a file manager).
  void refreshFiles() {
    for (final e in _entries.where((e) => e.status == DownloadStatus.done)) {
      e.missing = !File(e.path).existsSync();
    }
    notifyListeners();
  }

  void _deleteFile(DownloadEntry e) {
    if (e.status != DownloadStatus.done) return;
    try {
      final f = File(e.path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // in use or already gone: the entry is removed anyway
    }
  }

  List<DownloadEntry> _read() {
    final f = store;
    try {
      if (f == null || !f.existsSync()) return [];
      final rows = (jsonDecode(f.readAsStringSync()) as Map)['items'] as List;
      return [for (final r in rows) ?DownloadEntry.fromJson(r)];
    } catch (_) {
      return []; // an unreadable list starts empty; the files stay on the disk
    }
  }

  void _save() {
    final f = store;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      final tmp = File('${f.path}.tmp')..writeAsStringSync(jsonEncode({'version': 1, 'items': [for (final e in _entries) e.toJson()]}));
      tmp.renameSync(f.path);
    } catch (e) {
      debugPrint('downloads: the list could not be saved');
    }
  }

  static final _rng = Random.secure();
  static String _newId() => List.generate(16, (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
