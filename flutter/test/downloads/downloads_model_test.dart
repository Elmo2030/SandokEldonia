import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/downloads/download_engine.dart';
import 'package:iptvmac/downloads/download_entry.dart';
import 'package:iptvmac/downloads/downloads_model.dart';

import 'fake_download_engine.dart';

// A provider that does not exist. The login is in the URL the engine gets, and must not be anywhere else.
Uri? panelUrl(DownloadEntry e) => e.isEpisode
    ? Uri.parse('http://panel.test/series/user1/secretpw/${e.episodeId}.${e.ext}')
    : Uri.parse('http://panel.test/movie/user1/secretpw/${e.streamId}.${e.ext}');

void main() {
  late Directory tmp;
  late File store;
  late FakeDownloadEngine engine;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dl_test');
    store = File('${tmp.path}/state/downloads.json');
    engine = FakeDownloadEngine();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<DownloadsModel> open({DownloadUrlResolver? url}) async {
    final m = DownloadsModel(engine: engine, store: store, dir: '${tmp.path}/Downloads', resolveUrl: url ?? panelUrl);
    await m.load();
    return m;
  }

  Future<AddResult> addMovie(DownloadsModel m, {String id = '10', String title = 'Big Movie', String ext = 'mkv'}) =>
      m.add(accountId: 1, type: ItemType.movie, streamId: id, title: title, ext: ext);

  test('enqueue gives the engine the URL with the login and a safe file path, and lists it as queued', () async {
    final m = await open();
    expect(await addMovie(m, title: 'A/B: Movie?'), AddResult.started);
    final e = m.entries.single, job = engine.jobs[e.id]!;
    expect(job.url.toString(), 'http://panel.test/movie/user1/secretpw/10.mkv');
    expect(job.title, 'A/B: Movie?'); // what a notification shows
    expect(job.path, '${tmp.path}/Downloads/A-B- Movie-.mkv');
    expect(e.status, DownloadStatus.queued);
    expect(m.activeCount, 1);
  });

  test('the same movie twice is refused, the same title gets (2)', () async {
    final m = await open();
    await addMovie(m);
    expect(await addMovie(m), AddResult.exists);
    expect(await addMovie(m, id: '11'), AddResult.started);
    expect(m.entries.map((e) => File(e.path).uri.pathSegments.last), ['Big Movie.mkv', 'Big Movie (2).mkv']);
  });

  test('without a URL (no password) nothing is queued', () async {
    final m = await open(url: (_) => null);
    expect(await addMovie(m), AddResult.noUrl);
    expect(m.entries, isEmpty);
    expect(engine.jobs, isEmpty);
  });

  test('progress, then done: size is the file size', () async {
    final m = await open();
    await addMovie(m);
    final id = engine.lastId;
    engine.emit(EngineUpdate(id, state: EngineState.running));
    engine.progress(id, 40, 100);
    expect(m.entries.single.status, DownloadStatus.running);
    expect((m.entries.single.bytes, m.entries.single.total), (40, 100));
    expect(m.entries.single.fraction, 0.4);
    engine.complete(id, size: 123);
    final e = m.entries.single;
    expect((e.status, e.bytes, e.total), (DownloadStatus.done, 123, 123));
    expect(m.doneBytes, 123);
    expect(m.activeCount, 0);
  });

  test('a done report without a file on the disk is a failure, not a finished download', () async {
    final m = await open();
    await addMovie(m);
    engine.emit(EngineUpdate(engine.lastId, state: EngineState.done));
    expect((m.entries.single.status, m.entries.single.error), (DownloadStatus.failed, 'file'));
  });

  test('pause and resume go through the engine', () async {
    final m = await open();
    await addMovie(m);
    final id = engine.lastId;
    await m.pause(id); // queued: nothing to pause yet
    expect(engine.calls.where((c) => c.startsWith('pause')), isEmpty);
    engine.emit(EngineUpdate(id, state: EngineState.running));
    await m.pause(id);
    expect(m.entries.single.status, DownloadStatus.paused);
    await m.resume(id);
    expect(engine.calls, contains('resume $id'));
    expect(m.entries.single.status, DownloadStatus.queued);
    engine.emit(EngineUpdate(id, state: EngineState.running));
    expect(m.entries.single.status, DownloadStatus.running);
  });

  test('resume of a job the engine forgot enqueues it again with a rebuilt URL', () async {
    final m = await open();
    await addMovie(m);
    final id = engine.lastId;
    engine.emit(EngineUpdate(id, state: EngineState.paused));
    engine.forgetsOnResume = true;
    engine.jobs.clear();
    await m.resume(id);
    expect(engine.jobs[id]!.url.toString(), contains('secretpw'));
    expect(m.entries.single.status, DownloadStatus.queued);
  });

  test('cancel removes the entry and tells the engine', () async {
    final m = await open();
    await addMovie(m);
    final id = engine.lastId;
    await m.remove(id);
    expect(m.entries, isEmpty);
    expect(engine.calls, contains('cancel $id'));
    engine.progress(id, 5, 10); // a late update of a removed job changes nothing
    expect(m.entries, isEmpty);
  });

  test('a cancel from the notification shows as canceled and can be restarted', () async {
    final m = await open();
    await addMovie(m);
    final id = engine.lastId;
    engine.emit(EngineUpdate(id, state: EngineState.canceled));
    expect(m.entries.single.status, DownloadStatus.canceled);
    await m.resume(id);
    expect(m.entries.single.status, DownloadStatus.queued);
    expect(engine.jobs.containsKey(id), isTrue);
  });

  test('failures keep their reason; not enough space is its own reason; retry works', () async {
    final m = await open();
    await addMovie(m);
    final id = engine.lastId;
    engine.fail(id, EngineError.noSpace);
    expect((m.entries.single.status, m.entries.single.error), (DownloadStatus.failed, 'noSpace'));
    await m.resume(id);
    expect((m.entries.single.status, m.entries.single.error), (DownloadStatus.queued, null));
    engine.fail(id, EngineError.notFound);
    expect(m.entries.single.error, 'notFound');
  });

  test('an engine that refuses the job leaves a failed entry', () async {
    final m = await open();
    engine.refuse = true;
    expect(await addMovie(m), AddResult.refused);
    expect(m.entries.single.status, DownloadStatus.failed);
  });

  test('a failed one is replaced when the same movie is added again', () async {
    final m = await open();
    await addMovie(m);
    engine.fail(engine.lastId);
    expect(await addMovie(m), AddResult.started);
    expect(m.entries, hasLength(1));
  });

  test('episodes carry season, number and the series key', () async {
    final m = await open();
    await m.add(
        accountId: 1, type: ItemType.series, streamId: '20', episodeId: '101', season: 1, number: 2, episodeTitle: 'Second', title: 'The Show S01E02 Second', ext: 'mp4');
    final e = m.entries.single;
    expect(e.label, 'S01E02');
    expect(engine.jobs[e.id]!.url.toString(), 'http://panel.test/series/user1/secretpw/101.mp4');
    expect(e.key, '1|series|20|101');
  });

  test('the list on disk has no URL, host, user name or password, and survives a restart', () async {
    final m = await open();
    await addMovie(m);
    engine.complete(engine.lastId, size: 50);
    await addMovie(m, id: '11', title: 'Other');
    final text = store.readAsStringSync();
    for (final secret in ['secretpw', 'user1', 'panel.test', 'http']) {
      expect(text.contains(secret), isFalse, reason: secret);
    }
    final again = await open();
    expect(again.entries.map((e) => e.title), ['Big Movie', 'Other']);
    expect(again.entries.first.status, DownloadStatus.done);
    expect(again.entries.first.bytes, 50);
  });

  group('restart reconcile', () {
    test('what the engine finished or progressed while the app was closed is adopted', () async {
      final m = await open();
      await addMovie(m);
      await addMovie(m, id: '11', title: 'Two');
      await addMovie(m, id: '12', title: 'Three');
      final ids = m.entries.map((e) => e.id).toList();
      final first = File(engine.jobs[ids[0]]!.path);
      first.parent.createSync(recursive: true);
      first.writeAsBytesSync([1, 2, 3]);
      engine.remembered[ids[0]] = EngineUpdate(ids[0], state: EngineState.done);
      engine.remembered[ids[1]] = EngineUpdate(ids[1], state: EngineState.running, bytes: 7, total: 70);
      engine.remembered.remove(ids[2]);
      final again = await open();
      expect(again.byId(ids[0])!.status, DownloadStatus.done);
      expect(again.byId(ids[1])!.status, DownloadStatus.running);
      expect(again.byId(ids[1])!.bytes, 7);
      // forgotten by the engine and no file: lost, can be started again
      expect((again.byId(ids[2])!.status, again.byId(ids[2])!.error), (DownloadStatus.failed, 'lost'));
      await again.resume(ids[2]);
      expect(again.byId(ids[2])!.status, DownloadStatus.queued);
    });

    test('a forgotten job whose file is there counts as done', () async {
      final m = await open();
      await addMovie(m);
      final e = m.entries.single;
      File(e.path).writeAsBytesSync([1, 2]);
      engine.remembered.clear();
      expect((await open()).entries.single.status, DownloadStatus.done);
    });

    test('a finished file that was deleted outside the app shows as missing and can be removed', () async {
      final m = await open();
      await addMovie(m);
      engine.complete(engine.lastId);
      final path = m.entries.single.path;
      File(path).deleteSync();
      final again = await open();
      expect(again.entries.single.status, DownloadStatus.done);
      expect(again.entries.single.missing, isTrue);
      expect(again.doneBytes, 0);
      await again.remove(again.entries.single.id);
      expect(again.entries, isEmpty);
      expect((await open()).entries, isEmpty);
    });

    test('a missing one can be downloaded again', () async {
      final m = await open();
      await addMovie(m);
      engine.complete(engine.lastId);
      File(m.entries.single.path).deleteSync();
      m.refreshFiles();
      expect(m.entries.single.missing, isTrue);
      expect(await addMovie(m), AddResult.started);
      expect(m.entries, hasLength(1));
      expect(m.entries.single.missing, isFalse);
    });

    test('a damaged list file starts empty instead of crashing', () async {
      store.parent.createSync(recursive: true);
      store.writeAsStringSync('{not json');
      expect((await open()).entries, isEmpty);
    });
  });

  test('remove of a finished one deletes the file; delete all keeps unfinished ones', () async {
    final m = await open();
    await addMovie(m);
    engine.complete(engine.lastId);
    await addMovie(m, id: '11', title: 'Running');
    final done = m.entries.first.path;
    expect(File(done).existsSync(), isTrue);
    await m.removeAllDone();
    expect(File(done).existsSync(), isFalse);
    expect(m.entries.single.title, 'Running');
    expect(m.hasDone, isFalse);
  });

  test('disabled model does nothing', () async {
    final m = DownloadsModel.disabled();
    await m.load();
    expect(m.enabled, isFalse);
    expect(await addMovie(m), AddResult.refused);
  });
}
