import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/app_database.dart';
import 'package:iptvmac/core/errors.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/core/search.dart';
import 'package:iptvmac/core/subscription_info.dart';
import 'package:iptvmac/core/sync_meter.dart';
import 'package:iptvmac/core/sync_service.dart';
import 'package:iptvmac/core/xtream_client.dart';
import 'package:iptvmac/core/xtream_urls.dart';

import 'support.dart';

const live1 =
    '[{"stream_id":1,"name":"News 24","stream_icon":"http://i/1.png","category_id":"5","tv_archive":1,"tv_archive_duration":"3","epg_channel_id":"n24"},{"stream_id":2,"name":"Sport","category_id":5}]';
const vod =
    '[{"stream_id":10,"name":"Big Movie","rating":"","category_id":"7","container_extension":"mkv"},{"stream_id":11,"name":"Other","rating":7.5,"category_id":null},{"name":"NoId"}]';
const seriesJSON = '[{"series_id":20,"name":"The Show","cover":"http://c/20.jpg","rating":null,"category_id":"8"}]';

String body(String action, {String? live}) => switch (action) {
      'get_live_categories' => '[{"category_id":"5","category_name":"News"}]',
      'get_vod_categories' => '[{"category_id":7,"category_name":"Action"}]',
      'get_series_categories' => '[{"category_id":"8","category_name":"Drama"}]',
      'get_live_streams' => live ?? live1,
      'get_vod_streams' => vod,
      'get_series' => seriesJSON,
      _ => '{"user_info":{"auth":1},"server_info":{}}',
    };

Account account(AppDatabase db) =>
    db.write((d) => Account(name: 'x', kind: AccountKind.xtream, server: 'http://h', username: 'u').insert(d));

XtreamClient client(FakeServer s) => XtreamClient(XtreamURLs.parse(server: 'h', username: 'u', password: 'p')!, client: s.client);

void main() {
  late AppDatabase db;
  late Account a;
  late FakeServer server;
  late SyncService svc;

  setUp(() {
    db = AppDatabase.memory();
    a = account(db);
    server = FakeServer((r) => res(200, body(actionOf(r))));
    svc = SyncService(db, client: server.client);
  });

  test('syncs mixed type JSON', () async {
    await svc.sync(a, password: 'p');
    final (n, cats, news) = db.read((d) => (Item.all(d), Category.all(d), Search.run(d, SearchRequest(accountId: a.id, text: 'news'))));
    expect(n.length, 5); // "NoId" skipped
    expect(cats.length, 3);
    expect(cats.firstWhere((c) => c.type == ItemType.movie).remoteId, '7');
    expect(news.first.tvArchive, isTrue);
    expect(news.first.archiveDays, 3);
    expect(n.firstWhere((i) => i.name == 'Sport').categoryId, '5');
    expect(n.firstWhere((i) => i.name == 'Big Movie').containerExt, 'mkv');
    expect(n.firstWhere((i) => i.name == 'Other').rating, '7.5');
  });

  test('resync drops removed items but keeps favorites', () async {
    await svc.sync(a, password: 'p');
    db.write((d) => d.execute("INSERT INTO favorite VALUES (?, 'live', '2')", [a.id]));
    const only1 = '[{"stream_id":1,"name":"News 24","category_id":"5"}]';
    server.handler = (r) => res(200, body(actionOf(r), live: only1));
    await svc.sync(a, password: 'p');
    final names = db.read((d) => Item.all(d).where((i) => i.type == ItemType.live).map((i) => i.name).toList());
    expect(names, ['News 24']);
    expect(count(db, 'SELECT count(*) FROM favorite'), 1);
  });

  test('resync keeps the search index right when a name changes', () async {
    await svc.sync(a, password: 'p');
    server.handler = (r) => res(200, body(actionOf(r), live: '[{"stream_id":1,"name":"Weather Now","category_id":"5"}]'));
    await svc.sync(a, password: 'p');
    List<String> find(String t) => db.read((d) => Search.run(d, SearchRequest(accountId: a.id, text: t)).map((i) => i.name).toList());
    expect(find('weath'), ['Weather Now']);
    expect(find('news'), isEmpty);
  });

  test('failed sync leaves cache untouched', () async {
    await svc.sync(a, password: 'p');
    for (final (code, text) in [(500, 'oops'), (200, '<html>blocked</html>'), (200, '{"error":"x"}')]) {
      server.reply(code, text);
      await expectLater(svc.sync(a, password: 'p'), throwsA(anything));
    }
    expect(count(db, 'SELECT count(*) FROM item'), 5);
  });

  test('authenticate reports bad credentials', () async {
    server.reply(200, '{"user_info":{"auth":0}}');
    await expectLater(client(server).authenticate(), throwsA(IPTVError.badCredentials));
    server.reply(200, '{"user_info":{"auth":"1"}}');
    await client(server).authenticate();
  });

  test('authenticate reports an inactive subscription', () async {
    server.reply(200, '{"user_info":{"auth":1,"status":"Expired"}}');
    await expectLater(client(server).authenticate(), throwsA(IPTVError.accountInactive));
    server.reply(200, '[]');
    await expectLater(client(server).authenticate(), throwsA(IPTVError.badResponse));
  });

  test('the meter never goes backwards and only reports growth', () {
    final seen = <double>[];
    SyncMeter(seen.add)
      ..reach(0.2)
      ..reach(0.1)
      ..reach(0.2)
      ..advance(0.2)
      ..reach(0.3)
      ..reach(5)
      ..advance(1);
    expect(seen.length, 3);
    expect(seen[0], 0.2);
    expect(seen[1], closeTo(0.4, 1e-9));
    expect(seen[2], 1.0, reason: 'nothing passes 100%');
  });

  test('an Xtream sync reports progress forward up to 100%', () async {
    server.handler = (r) => res(200, switch (actionOf(r)) {
          'get_vod_categories' || 'get_series_categories' || 'get_vod_streams' || 'get_series' => '[]',
          final x => body(x),
        });
    final seen = <double>[];
    await svc.sync(a, password: 'p', onProgress: seen.add);
    expect(seen, [...seen]..sort(), reason: 'forward only');
    expect(seen.first, 0.05, reason: 'the login');
    expect(seen.any((v) => (v - 0.65).abs() < 1e-9), true, reason: 'the three lists, 20% each');
    expect(seen.last, 1.0);
  });

  test('writing many rows reports progress inside the write', () async {
    final m3u = StringBuffer('#EXTM3U\n');
    for (var i = 0; i < 5000; i++) {
      m3u.write('#EXTINF:-1 group-title="G",Channel $i\nhttp://h/live/$i.ts\n');
    }
    final b = db.write((d) => Account(name: 'm', kind: AccountKind.m3u, url: 'http://h/list.m3u').insert(d));
    server.reply(200, m3u.toString());
    final seen = <double>[];
    await svc.sync(b, onProgress: seen.add);
    expect(seen, [...seen]..sort());
    expect(seen.contains(0.5) && seen.contains(0.7), true, reason: 'downloaded, then decoded');
    expect(seen.where((v) => v > 0.7 && v < 1).length, greaterThanOrEqualTo(2), reason: 'the write is counted in rows: $seen');
    expect(seen.last, 1.0);
  });

  test('subscription reads the expiry and keeps what the panel leaves out', () async {
    server.reply(200, '{"user_info":{"auth":1,"status":"Active","exp_date":"1800864000","max_connections":"2"}}');
    final s = await client(server).subscription();
    expect(s.expires, DateTime.fromMillisecondsSinceEpoch(1800864000 * 1000));
    expect(s.maxConnections, 2);
    server.reply(200, '{"user_info":{"auth":1,"exp_date":null}}');
    expect(await client(server).subscription(), const SubscriptionInfo());
    server.reply(200, '{"user_info":{"auth":0}}');
    await expectLater(client(server).subscription(), throwsA(IPTVError.badCredentials));
  });

  test('EPG titles are base64 decoded', () async {
    final t = base64.encode(utf8.encode('Evening News'));
    server.reply(200, '{"epg_listings":[{"title":"$t","start_timestamp":"1700000000","stop_timestamp":"1700003600"}]}');
    final c = client(server);
    expect(await c.epgNow('1'), 'Evening News');
    expect((await c.epgShort('1', 3)).map((e) => e.title), ['Evening News']);
    expect(await c.epgArchive('1'), [
      EPGEntry(
          title: 'Evening News',
          start: DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
          end: DateTime.fromMillisecondsSinceEpoch(1700003600 * 1000, isUtc: true))
    ]);
  });

  test('EPG requests carry the stream id and the limit', () async {
    late Uri seen;
    server.handler = (r) {
      seen = r.url;
      return res(200, '{"epg_listings":[]}');
    };
    await client(server).epgShort('42', 3);
    expect(seen.queryParameters['action'], 'get_short_epg');
    expect(seen.queryParameters['stream_id'], '42');
    expect(seen.queryParameters['limit'], '3');
    expect(await client(server).epgNow('42'), isNull);
  });

  test('episodes are fetched, stored and served from the cache offline', () async {
    const info =
        '{"episodes":{"1":[{"id":"501","episode_num":1,"title":"Pilot","container_extension":"mkv","season":1},{"id":502,"episode_num":"2","title":"Two","season":1}],"2":[{"id":"601","episode_num":1,"title":"Back","season":2}]}}';
    server.reply(200, info);
    final eps = await svc.episodes(a, password: 'p', seriesId: '20');
    expect(eps.map((e) => e.title), ['Pilot', 'Two', 'Back']);
    server.reply(500, '');
    final cached = await svc.episodes(a, password: 'p', seriesId: '20');
    expect(cached.length, 3);
  });

  test('episodes may come as a list of seasons and ones the provider dropped are removed', () async {
    server.reply(200, '{"episodes":[[{"id":"1","episode_num":1,"season":1},{"id":"2","episode_num":2,"season":1}]]}');
    expect((await svc.episodes(a, password: 'p', seriesId: '20')).map((e) => e.title), ['Episode 1', 'Episode 2']);
    server.reply(200, '{"episodes":[[{"id":"2","episode_num":2,"season":1}]]}');
    expect((await svc.episodes(a, password: 'p', seriesId: '20')).map((e) => e.streamId), ['2']);
  });

  test('episodes without a cache throw the error', () async {
    server.reply(500, '');
    await expectLater(svc.episodes(a, password: 'p', seriesId: '20'), throwsA(IPTVError.http(500)));
  });

  // Final-review fixes

  test('sync reports bad credentials when auth is zero', () async {
    server.handler = (r) => actionOf(r).isEmpty ? res(200, '{"user_info":{"auth":0}}') : res(200, body(actionOf(r)));
    await expectLater(svc.sync(a, password: 'wrong'), throwsA(IPTVError.badCredentials));
  });

  test('an empty server response does not wipe the existing cache', () async {
    await svc.sync(a, password: 'p');
    server.handler = (r) => actionOf(r).isEmpty ? res(200, '{"user_info":{"auth":1}}') : res(200, '[]');
    await expectLater(svc.sync(a, password: 'p'), throwsA(IPTVError.emptyResponse));
    expect(count(db, 'SELECT count(*) FROM item'), 5);
  });

  test('a section that comes back null or false keeps its old items and is reported as partial', () async {
    await svc.sync(a, password: 'p');
    server.handler = (r) => switch (actionOf(r)) {
          'get_vod_streams' || 'get_vod_categories' => res(200, 'null'),
          'get_series' || 'get_series_categories' => res(200, 'false'),
          'get_live_streams' => res(200, live1),
          'get_live_categories' => res(200, '[]'),
          _ => res(200, '{"user_info":{"auth":1}}'),
        };
    await expectLater(svc.sync(a, password: 'p'), throwsA(IPTVError.partialResponse)); // stored, but the user is told
    expect(count(db, "SELECT count(*) FROM item WHERE type='movie'"), 2); // kept
    expect(count(db, "SELECT count(*) FROM item WHERE type='series'"), 1);
  });

  test('a bad server address is a config error', () async {
    final bad = db.write((d) => Account(name: 'b', kind: AccountKind.xtream, server: '  ', username: 'u').insert(d));
    await expectLater(svc.sync(bad, password: 'p'), throwsA(IPTVError.badConfig));
    await expectLater(svc.sync(Account(name: 'n', kind: AccountKind.xtream)), throwsA(IPTVError.badConfig)); // never saved
  });

  test('server time zone is read from server_info', () async {
    server.reply(200, '{"user_info":{"auth":1},"server_info":{"timezone":"Europe/Paris"}}');
    expect(await client(server).serverTimeZoneName(), 'Europe/Paris');
    server.reply(200, '{"user_info":{"auth":1},"server_info":{}}');
    expect(await client(server).serverTimeZoneName(), isNull);
    server.reply(500, '');
    expect(await client(server).serverTimeZoneName(), isNull);
  });
}
