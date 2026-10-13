import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/app_database.dart';
import 'package:iptvmac/core/backup.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/core/secret_store.dart';
import 'package:iptvmac/core/user_data.dart';

import 'support.dart';

/// An Xtream playlist ("t", http://h, u) and an M3U one with a favorite and a resume point each.
({AppDatabase db, int xtream, int m3u}) seeded() {
  final (db, x) = makeDB();
  final m = addAccount(db, 'list');
  db.write((d) {
    UserData.toggleFavorite(d, accountId: x, type: ItemType.live, streamId: '7');
    UserData.toggleFavorite(d, accountId: m, type: ItemType.movie, streamId: 'http://h/m.mp4');
    UserData.saveProgress(d, accountId: x, type: ItemType.movie, streamId: '9', position: 120, duration: 600);
    UserData.saveProgress(d, accountId: m, type: ItemType.series, streamId: 'ep:3', position: 30, duration: 100);
  });
  return (db: db, xtream: x, m3u: m);
}

Backup snapshot(AppDatabase db) => db.read(Backup.make);
int accountCount(AppDatabase db) => count(db, 'SELECT count(*) FROM account');
Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
Uint8List encoded(Backup b) => bytes(b.encoded());

void main() {
  test('backup round trips playlists, favorites and history into a fresh database', () {
    final src = seeded().db;
    final restored = Backup.decode(encoded(snapshot(src)));
    final dst = AppDatabase.memory();
    final added = dst.write(restored.merge);
    expect(added.length, 2);
    final b = snapshot(dst);
    expect(b.playlists.map((p) => p.name), ['t', 'list']);
    expect(b.playlists[0].kind, AccountKind.xtream);
    expect(b.playlists[0].server, 'http://h');
    expect(b.playlists[0].username, 'u');
    expect(b.playlists[1].kind, AccountKind.m3u);
    expect(b.playlists[1].url, 'http://h/list.m3u');
    expect(b.playlists.map((p) => p.favorites), restored.playlists.map((p) => p.favorites));
    expect(b.playlists[0].favorites, [const BackupFavorite(ItemType.live, '7')]);
    expect(b.playlists[0].history.map((h) => h.streamId), ['9']);
    expect(b.playlists[0].history[0].position, 120);
    expect(b.playlists[0].history[0].duration, 600);
    expect(b.playlists[1].history.map((h) => h.streamId), ['ep:3']);
  });

  test('importing the same backup again adds nothing', () {
    final src = seeded().db;
    final backup = Backup.decode(encoded(snapshot(src)));
    final dst = AppDatabase.memory();
    for (var i = 0; i < 2; i++) {
      dst.write(backup.merge);
    }
    expect(accountCount(dst), 2);
    expect(snapshot(dst).playlists.map((p) => p.favorites.length), [1, 1]);
    expect(snapshot(dst).playlists.map((p) => p.history.length), [1, 1]);
    final again = src.write(backup.merge); // into the database it came from
    expect(again, isEmpty);
    expect(accountCount(src), 2);
  });

  test('import matches an existing playlist by source and merges its user data', () {
    final src = seeded().db;
    final backup = Backup.decode(encoded(snapshot(src)));
    backup.playlists[0] = backup.playlists[0].copyWith(
        name: 'Renamed', server: 'HTTP://H/', favorites: [...backup.playlists[0].favorites, const BackupFavorite(ItemType.live, '8')]);
    final (dst, x) = makeDB();
    dst.write((d) => UserData.toggleFavorite(d, accountId: x, type: ItemType.live, streamId: '1'));
    final added = dst.write(backup.merge);
    expect(added.map((a) => a.name), ['list']); // the Xtream playlist was matched, the M3U one is new
    final b = snapshot(dst);
    expect(b.playlists.map((p) => p.name), ['t', 'list']); // the existing playlist keeps its name
    expect(b.playlists[0].favorites.map((f) => f.streamId), ['1', '7', '8']); // merged, nothing lost
  });

  test('import keeps the newer resume point', () {
    final (db, a) = makeDB();
    final day = DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000, isUtc: true);
    Backup backup(double pos, DateTime updated) => Backup([
          BackupPlaylist(name: 't', kind: AccountKind.xtream, server: 'http://h', username: 'u', favorites: const [], history: [
            BackupWatched(ItemType.movie, '9', pos, 600, updated),
          ])
        ]);
    db.write((d) {
      backup(100, day).merge(d);
      backup(50, day.subtract(const Duration(days: 1))).merge(d); // older: ignored
    });
    expect(db.read((d) => UserData.progress(d, accountId: a, type: ItemType.movie, streamId: '9')), 100);
    db.write(backup(300, day.add(const Duration(days: 1))).merge);
    expect(db.read((d) => UserData.progress(d, accountId: a, type: ItemType.movie, streamId: '9')), 300);
  });

  test('backup never contains passwords', () async {
    final s = seeded();
    final secrets = MemorySecretStore();
    await secrets.setPassword(s.xtream, 's3cr3t-pw');
    final text = snapshot(s.db).encoded();
    expect(text, isNot(contains('s3cr3t-pw')));
    final root = jsonDecode(text) as Map<String, dynamic>;
    expect(root.keys.toSet(), {'version', 'created', 'playlists'});
    final p = (root['playlists'] as List).first as Map<String, dynamic>;
    expect(p.keys.toSet(), {'name', 'kind', 'server', 'username', 'favorites', 'history'}); // no password, no url for Xtream
  });

  test('garbage, empty and wrong shaped files are rejected', () {
    for (final bad in ['not json', '', '[]', '{}', '{"version":1}', '{"version":1,"created":"x","playlists":[{"name":"a"}]}']) {
      expect(() => Backup.decode(bytes(bad)), throwsA(BackupError.invalid), reason: bad);
    }
  });

  test('other versions are rejected', () {
    for (final v in [0, 2, 99, -1]) {
      final json = '{"version":$v,"created":"2026-10-07T10:00:00Z","playlists":[]}';
      expect(() => Backup.decode(bytes(json)), throwsA(BackupError.unsupportedVersion), reason: '$v');
    }
  });

  test('oversized files are rejected before parsing', () {
    final data = encoded(snapshot(seeded().db));
    expect(() => Backup.decode(data, maxBytes: data.length - 1), throwsA(BackupError.tooLarge));
    Backup.decode(data, maxBytes: data.length);
    final dir = tempDir('bk');
    addTearDown(() => dir.deleteSync(recursive: true));
    final big = File('${dir.path}/big.json')..writeAsBytesSync(Uint8List(Backup.maxBytes + 1));
    expect(() => Backup.read(big), throwsA(BackupError.tooLarge));
  });

  test('playlists with unsafe or missing sources are rejected', () {
    void decode(BackupPlaylist p) => Backup.decode(encoded(Backup([p])));
    BackupPlaylist list(String? url) => BackupPlaylist(name: 'a', kind: AccountKind.m3u, url: url, favorites: const [], history: const []);
    BackupPlaylist xt(String? server, String? user) =>
        BackupPlaylist(name: 'x', kind: AccountKind.xtream, server: server, username: user, favorites: const [], history: const []);
    decode(list('https://h/a.m3u'));
    for (final u in ['file:///etc/passwd', 'file://localhost/etc/hosts', 'ftp://h/a.m3u', 'h/a.m3u', '', null]) {
      expect(() => decode(list(u)), throwsA(BackupError.invalid), reason: '$u');
    }
    expect(() => decode(xt(null, 'u')), throwsA(BackupError.invalid));
    expect(() => decode(xt('file:///x', 'u')), throwsA(BackupError.invalid));
    decode(xt('host.example:8080', 'u'));
  });

  test('a resume point without a duration is rejected', () {
    final p = BackupPlaylist(name: 'a', kind: AccountKind.m3u, url: 'http://h/a.m3u', favorites: const [], history: [
      BackupWatched(ItemType.movie, '1', 5, 0, DateTime.utc(2026)),
    ]);
    expect(() => Backup.decode(encoded(Backup([p]))), throwsA(BackupError.invalid));
  });

  test('the exported file is owner only and overwrites completely', () {
    final backup = snapshot(seeded().db);
    final dir = tempDir('bk');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/backup.json')..writeAsBytesSync(Uint8List(1000000)..fillRange(0, 1000000, 65)); // existing, longer
    if (!Platform.isWindows) Process.runSync('chmod', ['644', file.path]);
    backup.write(file);
    if (!Platform.isWindows) expect(file.statSync().mode & 0x1FF, 384); // 0600
    expect(Backup.read(file), backup);
    expect(file.readAsStringSync(), backup.encoded()); // no tail of the old, longer file
  });

  test('the file is the format of the Apple apps (sorted keys, whole-second ISO dates)', () {
    final b = Backup([
      BackupPlaylist(name: 'a', kind: AccountKind.m3u, url: 'http://h/a.m3u', favorites: const [BackupFavorite(ItemType.movie, '1')], history: [
        BackupWatched(ItemType.movie, '1', 5, 10, DateTime.utc(2026, 10, 7, 10)),
      ])
    ], created: DateTime.utc(2026, 10, 7, 10, 0, 0, 999));
    final j = jsonDecode(b.encoded()) as Map<String, dynamic>;
    expect(j['created'], '2026-10-07T10:00:00Z');
    expect(((j['playlists'] as List).first as Map)['history'][0]['updated'], '2026-10-07T10:00:00Z');
    expect(b.encoded().indexOf('"created"'), lessThan(b.encoded().indexOf('"playlists"')));
  });
}
