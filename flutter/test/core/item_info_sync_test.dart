import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/app_database.dart';
import 'package:iptvmac/core/errors.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/core/sync_service.dart';
import 'package:iptvmac/core/xtream_client.dart';
import 'package:iptvmac/core/xtream_urls.dart';

import 'support.dart';

// Network side of the title details, with a fake client.

const vodJSON =
    '{"info":{"movie_image":"https://img.example.com/p.jpg","plot":"A heist.","genre":"Action","rating":"7.5","duration_secs":6300,"youtube_trailer":"dQw4w9WgXcQ"},"movie_data":{"stream_id":10,"name":"Heist"},"user_info":{"password":"pw"}}';
const seriesInfoJSON =
    '{"seasons":[],"info":{"name":"The Show","cover":"https://c.example.com/s.jpg","plot":"Secrets.","releaseDate":"2021-02-01","episode_run_time":"45"},"episodes":{"1":[{"id":"501","episode_num":1,"title":"Pilot","season":1}]}}';

XtreamClient client(FakeServer s) => XtreamClient(XtreamURLs.parse(server: 'h', username: 'u', password: 'p')!, client: s.client);

void main() {
  late AppDatabase db;
  late Account a;
  late FakeServer server;
  late SyncService svc;
  final now = DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000, isUtc: true);

  setUp(() {
    db = AppDatabase.memory();
    a = db.write((d) => Account(name: 'x', kind: AccountKind.xtream, server: 'http://h', username: 'u').insert(d));
    server = FakeServer();
    svc = SyncService(db, client: server.client);
  });

  test('vodInfo asks get_vod_info with the vod id', () async {
    late Map<String, String> seen;
    server.handler = (r) {
      seen = r.url.queryParameters;
      return res(200, vodJSON);
    };
    final i = await client(server).vodInfo('10');
    expect(seen['action'], 'get_vod_info');
    expect(seen['vod_id'], '10');
    expect(i.plot, 'A heist.');
    expect(i.rating, 7.5);
    expect(i.durationMinutes, 105);
    expect(i.trailerID, 'dQw4w9WgXcQ');
  });

  test('seriesInfo asks get_series_info with the series id', () async {
    late Map<String, String> seen;
    server.handler = (r) {
      seen = r.url.queryParameters;
      return res(200, seriesInfoJSON);
    };
    final i = await client(server).seriesInfo('20');
    expect(seen['action'], 'get_series_info');
    expect(seen['series_id'], '20');
    expect(i.title, 'The Show');
    expect(i.year, 2021);
    expect(i.durationMinutes, 45);
  });

  test('a title the provider knows nothing about is empty, not an error', () async {
    for (final body in ['[]', 'null', 'false', '{"info":[],"movie_data":[]}', '']) {
      server.reply(200, body);
      expect((await client(server).vodInfo('1')).hasContent, isFalse, reason: 'body $body');
    }
  });

  test('info request failures are errors', () async {
    server.reply(500, '');
    await expectLater(client(server).vodInfo('1'), throwsA(IPTVError.http(500)));
    server.reply(200, '<html>blocked</html>');
    await expectLater(client(server).seriesInfo('1'), throwsA(IPTVError.badResponse));
  });

  test('info is fetched once then served from the cache', () async {
    server.reply(200, vodJSON);
    final first = await svc.info(a, password: 'p', type: ItemType.movie, streamId: '10', now: now);
    expect(first.plot, 'A heist.');
    expect(server.calls, 1);

    server.reply(500, '');
    expect(await svc.info(a, password: 'p', type: ItemType.movie, streamId: '10', now: now.add(const Duration(days: 13))), first);
    expect(server.calls, 1); // cache hit: no request

    server.reply(200, vodJSON.replaceAll('A heist.', 'Newer.'));
    final later = now.add(const Duration(days: 15));
    expect((await svc.info(a, password: 'p', type: ItemType.movie, streamId: '10', now: later)).plot, 'Newer.');
    expect(server.calls, 2); // expired: fetched again
    expect((await svc.info(a, password: 'p', type: ItemType.movie, streamId: '10', now: later, refresh: true)).plot, 'Newer.');
    expect(server.calls, 3); // refresh ignores the cache
  });

  test('a failed fetch falls back to a stale copy but without one it throws', () async {
    server.reply(500, '');
    await expectLater(svc.info(a, password: 'p', type: ItemType.movie, streamId: '10', now: now), throwsA(IPTVError.http(500)));
    server.reply(200, vodJSON);
    final good = await svc.info(a, password: 'p', type: ItemType.movie, streamId: '10', now: now);
    server.reply(500, ''); // offline a month later
    expect(await svc.info(a, password: 'p', type: ItemType.movie, streamId: '10', now: now.add(const Duration(days: 30))), good);
  });

  test('empty answers are not cached so reopening tries again', () async {
    server.reply(200, '{"info":[]}');
    expect((await svc.info(a, password: 'p', type: ItemType.movie, streamId: '10')).hasContent, isFalse);
    expect((await svc.info(a, password: 'p', type: ItemType.movie, streamId: '10')).hasContent, isFalse);
    expect(server.calls, 2);
    expect(count(db, 'SELECT count(*) FROM item_info'), 0);
  });

  test('M3U and live items never touch the network or the cache', () async {
    final m3u = db.write((d) => Account(name: 'm', kind: AccountKind.m3u, url: 'http://h/l.m3u').insert(d));
    server.reply(200, vodJSON);
    expect((await svc.info(m3u, type: ItemType.movie, streamId: 'http://h/a.mp4')).hasContent, isFalse);
    expect((await svc.info(a, password: 'p', type: ItemType.live, streamId: '1')).hasContent, isFalse);
    expect(server.calls, 0);
    expect(count(db, 'SELECT count(*) FROM item_info'), 0);
  });

  test('the info request never carries credentials into the cache', () async {
    server.reply(200, vodJSON); // the response even echoes a password
    await svc.info(a, password: 'pw', type: ItemType.movie, streamId: '10');
    final stored = db.read((d) => d.select('SELECT json FROM item_info').first['json'] as String);
    expect(stored, isNot(contains('pw')));
    expect(stored, isNot(contains('password')));
  });

  test('loading episodes also fills the series info cache without a second request', () async {
    server.reply(200, seriesInfoJSON);
    final eps = await svc.episodes(a, password: 'p', seriesId: '20');
    expect(eps.length, 1);
    expect(server.calls, 1);
    final info = await svc.info(a, password: 'p', type: ItemType.series, streamId: '20');
    expect(info.plot, 'Secrets.');
    expect(info.year, 2021);
    expect(server.calls, 1); // the episodes request already carried it
  });
}
