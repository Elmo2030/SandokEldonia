import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/app_database.dart';
import 'package:iptvmac/core/errors.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/core/sync_service.dart';

import 'support.dart';

const playlist = '\u{FEFF}#EXTM3U\r\n'
    '#EXTINF:-1 tvg-id="n" group-title="News" tvg-logo="http://l/1.png",News One\r\n'
    'http://h/live/1.ts\r\n'
    '#EXTINF:-1 group-title="Movies",Big Film\r\n'
    '#EXTVLCOPT:network-caching=1000\r\n'
    'http://h/movie/u/p/9.mkv\r\n'
    '#EXTINF:-1 group-title="Series",Show S01E01\r\n'
    'http://h/series/u/p/5.mp4\r\n';

Account m3uAccount(AppDatabase db) => db.write((d) => Account(name: 'm', kind: AccountKind.m3u, url: 'http://h/list.m3u').insert(d));

void main() {
  late AppDatabase db;
  late FakeServer server;
  late SyncService svc;
  late Account a;

  setUp(() {
    db = AppDatabase.memory();
    a = m3uAccount(db);
    server = FakeServer();
    svc = SyncService(db, client: server.client);
  });

  test('imports, classifies and builds categories', () async {
    server.reply(200, playlist);
    await svc.sync(a);
    final items = db.read((d) => Item.all(d));
    expect(items.length, 3);
    Item byName(String n) => items.firstWhere((i) => i.name == n);
    expect(byName('News One').type, ItemType.live);
    expect(byName('News One').icon, 'http://l/1.png');
    expect(byName('News One').epgChannelId, 'n');
    expect(byName('Big Film').type, ItemType.movie);
    expect(byName('Show S01E01').type, ItemType.series);
    expect(byName('Big Film').directURL, 'http://h/movie/u/p/9.mkv');
    expect(db.read((d) => Category.all(d)).map((c) => c.name).toSet(), {'News', 'Movies', 'Series'});
  });

  test('an HTML error page is rejected and the cache kept', () async {
    server.reply(200, playlist);
    await svc.sync(a);
    server.reply(200, '<html>Access denied</html>');
    await expectLater(svc.sync(a), throwsA(IPTVError.badResponse));
    server.reply(403, '');
    await expectLater(svc.sync(a), throwsA(IPTVError.http(403)));
    expect(count(db, 'SELECT count(*) FROM item'), 3);
  });

  test('an invalid link is a config error', () async {
    final bad = db.write((d) => Account(name: 'm', kind: AccountKind.m3u, url: 'not a url').insert(d));
    await expectLater(svc.sync(bad), throwsA(IPTVError.badConfig));
  });

  test('the same URL in two groups is imported once, under the first group', () async {
    server.reply(200, '#EXTM3U\n#EXTINF:-1 group-title="A",One\nhttp://h/1.ts\n#EXTINF:-1 group-title="B",One again\nhttp://h/1.ts\n');
    await svc.sync(a);
    final items = db.read((d) => Item.all(d));
    expect(items.map((i) => (i.name, i.categoryId)), [('One', 'A')]);
  });

  test('the catch-up attribute does not show a catch-up button', () async {
    server.reply(200, '#EXTM3U\n#EXTINF:-1 catchup-days="3" group-title="News",One\nhttp://h/live/1.ts\n');
    await svc.sync(a);
    expect(db.read((d) => Item.all(d)).first.tvArchive, isFalse); // catch-up URLs can only be built for Xtream accounts
  });

  test('an empty playlist keeps the saved data', () async {
    server.reply(200, playlist);
    await svc.sync(a);
    server.reply(200, '#EXTM3U\n');
    await expectLater(svc.sync(a), throwsA(IPTVError.emptyResponse));
    expect(count(db, 'SELECT count(*) FROM item'), 3);
  });
}
