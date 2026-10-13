import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/app/library_model.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/downloads/download_engine.dart';
import 'package:iptvmac/downloads/download_entry.dart';
import 'package:iptvmac/downloads/downloads_model.dart';
import 'package:iptvmac/downloads/library_downloads.dart';
import 'package:iptvmac/l10n/app_localizations.dart';
import 'package:iptvmac/player/play_request.dart';
import 'package:iptvmac/ui/details_sheet.dart';
import 'package:iptvmac/ui/play.dart' as play;
import 'package:provider/provider.dart';

import '../app/harness.dart';
import 'fake_download_engine.dart';

class Setup {
  Setup(this.h, this.engine, this.downloads, this.dir);
  final Harness h;
  final FakeDownloadEngine engine;
  final DownloadsModel downloads;
  final Directory dir;
}

Future<Setup> setup(WidgetTester tester) async {
  final h = await Harness.create(tester, withAccount: true, sync: true);
  final dir = Directory.systemTemp.createTempSync('dl_ui');
  addTearDown(() => dir.deleteSync(recursive: true));
  final engine = FakeDownloadEngine();
  final d = DownloadsModel(engine: engine, store: File('${dir.path}/downloads.json'), dir: '${dir.path}/Downloads', resolveUrl: h.model.downloadUrl);
  await tester.runAsync(d.load);
  return Setup(h, engine, d, dir);
}

/// A details sheet for [item] over a bare app (the item need not be in the catalogue lists).
Future<void> openSheet(WidgetTester tester, Setup s, Item item) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [ChangeNotifierProvider<LibraryModel>.value(value: s.h.model), ChangeNotifierProvider<DownloadsModel>.value(value: s.downloads)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => showItemDetails(c, item), child: const Text('open')))),
    ),
  ));
  await tester.tap(find.text('open'));
  await go(tester);
}

Item movie(Setup s, String name, String id, {String? ext, String? url}) =>
    Item(accountId: s.h.model.accounts.single.id!, type: ItemType.movie, name: name, streamId: id, containerExt: ext, directURL: url);

void main() {
  group('who can be downloaded', () {
    testWidgets('movies that are one file, not live, not series, not playlists', (tester) async {
      final s = await setup(tester);
      final m = s.h.model;
      final a = m.accounts.single.id!;
      expect(m.canDownload(movie(s, 'A', '1', ext: 'mkv')), isTrue);
      expect(m.canDownload(movie(s, 'A', '1')), isTrue); // Xtream asks for .mp4 when there is no extension
      expect(m.canDownload(movie(s, 'A', '1', ext: 'm3u8')), isFalse);
      expect(m.canDownload(movie(s, 'A', '1', ext: 'mpd')), isFalse);
      expect(m.canDownload(Item(accountId: a, type: ItemType.live, name: 'L', streamId: '2')), isFalse);
      expect(m.canDownload(Item(accountId: a, type: ItemType.series, name: 'S', streamId: '3')), isFalse);
      expect(m.canDownload(movie(s, 'A', 'x', url: 'http://panel.test/films/a.mp4?token=1')), isTrue);
      expect(m.canDownload(movie(s, 'A', 'x', url: 'http://panel.test/films/a.m3u8')), isFalse);
      expect(m.canDownload(movie(s, 'A', 'x', url: 'http://panel.test/films/12345')), isFalse); // no extension: cannot tell
      expect(m.canDownload(movie(s, 'A', 'x', url: 'rtmp://panel.test/a.mp4')), isFalse);
      expect(m.canDownload(movie(s, 'A', 'x', url: 'file:///sdcard/a.mp4')), isFalse);
      expect(m.canDownloadEpisode(Episode(accountId: a, seriesId: '3', season: 1, number: 1, title: 't', streamId: '9', containerExt: 'mp4')), isTrue);
      expect(m.canDownloadEpisode(Episode(accountId: a, seriesId: '3', season: 1, number: 1, title: 't', streamId: '9', containerExt: 'm3u8')), isFalse);
    });
  });

  testWidgets('a source without a stored password asks for it instead of starting', (tester) async {
    final s = await setup(tester);
    final b = s.h.db.write((d) => Account(name: 'B', kind: AccountKind.xtream, server: 'http://other.test', username: 'x').insert(d));
    await tester.runAsync(s.h.model.loadAccounts);
    final r = await tester.runAsync(() => s.h.model.downloadMovie(s.downloads, Item(accountId: b.id!, type: ItemType.movie, name: 'M', streamId: '1', containerExt: 'mp4')));
    expect(r, AddResult.noUrl);
    expect(s.h.model.passwordPrompt?.id, b.id);
    expect(s.engine.jobs, isEmpty);
  });

  group('the button', () {
    testWidgets('a movie sheet has it; tapping starts the download with the playback URL, then shows progress', (tester) async {
      final s = await setup(tester);
      await openSheet(tester, s, movie(s, 'Big Movie', '10', ext: 'mkv'));
      expect(find.byTooltip('Download'), findsOneWidget);
      await tester.tap(find.byTooltip('Download'));
      await settle(tester, 3); // the waiting ring spins for ever: no pumpAndSettle
      expect(s.engine.jobs.values.single.url.toString(), 'http://panel.test/movie/u/p/10.mkv');
      expect(s.engine.jobs.values.single.title, 'Big Movie');
      expect(find.byTooltip('Download'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets); // the waiting ring
    });

    testWidgets('a playlist movie (.m3u8) has no button', (tester) async {
      final s = await setup(tester);
      await openSheet(tester, s, movie(s, 'Stream Film', '31', ext: 'm3u8'));
      expect(find.text('Stream Film'), findsWidgets);
      expect(find.byTooltip('Download'), findsNothing);
    });

    testWidgets('an episode row has it, and so does Download season', (tester) async {
      final s = await setup(tester);
      await s.h.pumpApp(tester, downloads: s.downloads);
      await go(tester);
      await tester.tap(find.text('Series').last);
      await go(tester);
      await tester.tap(find.text('The Show'));
      await go(tester);
      expect(find.byTooltip('Download'), findsNWidgets(2)); // the two episodes of season 1
      await tester.tap(find.byTooltip('Download').first);
      await settle(tester, 3);
      expect(s.engine.jobs.values.single.url.toString(), 'http://panel.test/series/u/p/101.mp4');
      expect(s.downloads.entries.single.title, 'The Show S01E01 Pilot');
      expect(s.downloads.entries.single.label, 'S01E01');

      await tester.tap(find.byKey(const Key('download-season')));
      await settle(tester, 4);
      expect(s.downloads.entries.map((e) => e.episodeId), ['101', '102']); // the first was already there
    });

    testWidgets('no button when downloads are off', (tester) async {
      final h = await Harness.create(tester, withAccount: true, sync: true);
      await h.pumpApp(tester);
      await go(tester);
      await tester.tap(find.text('Movies').last);
      await go(tester);
      await tester.tap(find.text('Big Movie'));
      await go(tester);
      expect(find.text('Play'), findsOneWidget);
      expect(find.byTooltip('Download'), findsNothing);
      expect(find.byKey(const Key('download-season')), findsNothing);
    });
  });

  group('Downloads screen', () {
    Future<void> openScreen(WidgetTester tester, Setup s) async {
      await s.h.pumpApp(tester, downloads: s.downloads);
      await go(tester);
      await tester.tap(find.text('Library').last);
      await go(tester);
      await tester.tap(find.byKey(const Key('downloads-action')));
      await go(tester);
    }

    testWidgets('empty state', (tester) async {
      final s = await setup(tester);
      await openScreen(tester, s);
      expect(find.text('No downloads yet'), findsOneWidget);
    });

    testWidgets('progress, pause, resume, cancel', (tester) async {
      final s = await setup(tester);
      final d = s.downloads;
      await tester.runAsync(() => d.add(accountId: 1, type: ItemType.movie, streamId: '10', title: 'Big Movie', ext: 'mkv'));
      await tester.runAsync(() => d.add(accountId: 1, type: ItemType.movie, streamId: '11', title: 'Other Film', ext: 'mp4'));
      final first = d.entries.first.id, second = d.entries.last.id;
      s.engine.emit(EngineUpdate(first, state: EngineState.running));
      s.engine.progress(first, 400000, 1000000);
      await openScreen(tester, s);

      expect(find.text('Big Movie'), findsOneWidget);
      expect(find.text('400.0 KB / 1.0 MB'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget); // the second one
      expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.4);
      expect(find.byTooltip('Pause'), findsOneWidget);

      await tester.tap(find.byKey(Key('pause-$first')));
      await go(tester);
      expect(d.byId(first)!.status, DownloadStatus.paused);
      expect(find.byTooltip('Resume'), findsOneWidget);
      await tester.tap(find.byKey(Key('resume-$first')));
      await go(tester);
      expect(s.engine.calls, contains('resume $first'));

      await tester.tap(find.byKey(Key('cancel-$second')));
      await go(tester);
      expect(d.byId(second), isNull);
      expect(find.text('Other Film'), findsNothing);
      expect(s.engine.calls, contains('cancel $second'));
    });

    testWidgets('failure messages and the no-space message', (tester) async {
      final s = await setup(tester);
      await tester.runAsync(() => s.downloads.add(accountId: 1, type: ItemType.movie, streamId: '10', title: 'Big Movie', ext: 'mkv'));
      s.engine.fail(s.engine.lastId, EngineError.noSpace);
      await openScreen(tester, s);
      expect(find.text('Not enough free disk space'), findsOneWidget);
    });

    testWidgets('finished: size line, total, delete with confirmation, delete all', (tester) async {
      final s = await setup(tester);
      final d = s.downloads;
      await tester.runAsync(() => d.add(accountId: 1, type: ItemType.movie, streamId: '10', title: 'Big Movie', ext: 'mkv'));
      s.engine.complete(s.engine.lastId, size: 2500);
      await tester.runAsync(() => d.add(accountId: 1, type: ItemType.movie, streamId: '11', title: 'Other Film', ext: 'mp4'));
      s.engine.complete(s.engine.lastId, size: 1500);
      final big = d.entries.first;
      await openScreen(tester, s);
      expect(find.text('Done · 2.5 KB'), findsOneWidget);
      expect(find.text('Downloaded: 4.0 KB'), findsOneWidget);

      await tester.tap(find.byKey(Key('delete-${big.id}')));
      await go(tester);
      expect(find.text('The file is deleted from this device.'), findsOneWidget);
      await tester.tap(find.text('Cancel')); // not now
      await go(tester);
      expect(File(big.path).existsSync(), isTrue);
      await tester.tap(find.byKey(Key('delete-${big.id}')));
      await go(tester);
      await tester.tap(find.text('Delete file').last);
      await go(tester);
      expect(File(big.path).existsSync(), isFalse);
      expect(find.text('Big Movie'), findsNothing);

      await tester.tap(find.byKey(const Key('delete-all')));
      await go(tester);
      await tester.tap(find.text('Delete file').last);
      await go(tester);
      expect(d.entries, isEmpty);
      expect(find.text('No downloads yet'), findsOneWidget);
    });

    testWidgets('a file deleted outside the app shows as missing and can be removed', (tester) async {
      final s = await setup(tester);
      await tester.runAsync(() => s.downloads.add(accountId: 1, type: ItemType.movie, streamId: '10', title: 'Big Movie', ext: 'mkv'));
      s.engine.complete(s.engine.lastId);
      File(s.downloads.entries.single.path).deleteSync();
      await openScreen(tester, s); // opening the screen checks the files
      expect(find.text('The file is no longer on this device'), findsOneWidget);
      expect(find.byTooltip('Play'), findsNothing);
      await tester.tap(find.byTooltip('Remove from the list'));
      await go(tester);
      expect(s.downloads.entries, isEmpty);
    });

    testWidgets('right-to-left with large text lays out without errors', (tester) async {
      final s = await setup(tester);
      await tester.runAsync(() => s.downloads.add(accountId: 1, type: ItemType.movie, streamId: '10', title: 'סרט עם שם ארוך מאוד שצריך לרדת שורה ' * 3, ext: 'mkv'));
      s.engine.emit(EngineUpdate(s.engine.lastId, state: EngineState.running));
      s.engine.progress(s.engine.lastId, 400000000, 1400000000);
      await s.h.pumpApp(tester, downloads: s.downloads, locale: const Locale('he'), textScale: 2);
      await go(tester);
      await tester.tap(find.byIcon(Icons.bookmarks_outlined).last);
      await go(tester);
      await tester.tap(find.byKey(const Key('downloads-action')));
      await go(tester);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Library tab counts running downloads', (tester) async {
      final s = await setup(tester);
      await tester.runAsync(() => s.downloads.add(accountId: 1, type: ItemType.movie, streamId: '10', title: 'Big Movie', ext: 'mkv'));
      await s.h.pumpApp(tester, downloads: s.downloads);
      await go(tester);
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.byType(Badge)), findsOneWidget);
      expect(find.text('1'), findsWidgets);
    });
  });

  group('offline play', () {
    Future<(PlayRequest, PlayerHost)> playFirst(WidgetTester tester, Setup s) async {
      PlayRequest? request;
      PlayerHost? host;
      final saved = play.playerBuilder;
      play.playerBuilder = (r, hh) {
        request = r;
        host = hh;
        return const Scaffold(body: Text('player'));
      };
      addTearDown(() => play.playerBuilder = saved);
      await s.h.pumpApp(tester, downloads: s.downloads);
      await go(tester);
      await tester.tap(find.text('Library').last);
      await go(tester);
      await tester.tap(find.byKey(const Key('downloads-action')));
      await go(tester);
      s.h.provider.calls.clear();
      s.h.provider.fail = true; // offline
      await tester.tap(find.byTooltip('Play'));
      await go(tester);
      return (request!, host!);
    }

    testWidgets('a movie plays from the file with its library item, and the resume point has the online key', (tester) async {
      final s = await setup(tester);
      await tester.runAsync(() => s.downloads.add(accountId: 1, type: ItemType.movie, streamId: '10', title: 'Big Movie', ext: 'mkv'));
      s.engine.complete(s.engine.lastId);
      final e = s.downloads.entries.single;
      final (r, host) = await playFirst(tester, s);
      expect(r.url, Uri.file(e.path));
      expect(r.url.scheme, 'file');
      expect(r.isLive, isFalse);
      expect(r.item!.streamId, '10');
      expect(r.item!.name, 'Big Movie');
      expect(r.item!.id, isNotNull); // the real catalogue row
      expect(s.h.provider.calls, isEmpty); // no network
      host.saveProgress(r, 90, 6000);
      expect(s.h.model.progress(r.item!), 90); // the same key as streaming it
      expect(s.h.db.read((d) => d.select('SELECT streamId FROM history')).single['streamId'], '10');
      expect(host.isFavorite(r.item!), isFalse);
      await host.toggleFavorite(r.item!);
      expect(s.h.model.favoriteKeys, hasLength(1));
    });

    testWidgets('an episode plays from the file; progress is saved as ep:<id> and the series is attached', (tester) async {
      final s = await setup(tester);
      await tester.runAsync(() => s.downloads.add(
          accountId: 1, type: ItemType.series, streamId: '20', episodeId: '101', season: 1, number: 1, episodeTitle: 'Pilot', title: 'The Show S01E01 Pilot', ext: 'mp4'));
      s.engine.complete(s.engine.lastId);
      final (r, host) = await playFirst(tester, s);
      expect(r.url.scheme, 'file');
      expect(r.item!.name, 'The Show');
      expect(r.subtitle, 'Pilot');
      host.saveProgress(r, 600, 2700);
      expect(s.h.db.read((d) => d.select("SELECT streamId FROM history WHERE type='series'")).single['streamId'], 'ep:101');
      // and a second offline play resumes there
      expect(s.h.model.offlineRequest(s.downloads.entries.single).start, 600);
    });
  });
}
