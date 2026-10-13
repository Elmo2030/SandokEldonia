import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/app_database.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/core/search.dart';
import 'package:iptvmac/core/user_data.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support.dart';

void main() {
  test('fts5 is kept in sync with items', () {
    final (db, aid) = makeDB();
    addItem(db, aid, 'Hello World');
    expect(count(db, "SELECT count(*) FROM item_fts WHERE item_fts MATCH 'hello'"), 1);
    db.write((d) => d.execute('DELETE FROM item'));
    expect(count(db, "SELECT count(*) FROM item_fts WHERE item_fts MATCH 'hello'"), 0);
  });

  test('the search index uses the unicode61 tokenizer without diacritics', () {
    final (db, _) = makeDB();
    final sql = db.read((d) => d.select("SELECT sql FROM sqlite_master WHERE name='item_fts'").first['sql'] as String);
    expect(sql, contains("tokenize='unicode61 remove_diacritics 2'"));
  });

  test('duplicate streamId is rejected', () {
    final (db, aid) = makeDB();
    addItem(db, aid, 'A', sid: '1');
    expect(() => addItem(db, aid, 'B', sid: '1'), throwsA(isA<SqliteException>()));
  });

  test('sync keeps a type that came back empty and other types are replaced', () {
    final (db, a) = makeDB();
    db.write((d) {
      for (final (t, id) in [(ItemType.live, '1'), (ItemType.movie, '2')]) {
        Item(accountId: a, type: t, name: 'n$id', streamId: id).insert(d);
      }
    });
    // exercised through the same SQL as SyncService: only the types present in the new list are marked stale
    db.write((d) {
      d.execute("UPDATE item SET stale = 1 WHERE accountId = ? AND type IN ('movie')", [a]);
      d.execute('DELETE FROM item WHERE accountId = ? AND stale = 1', [a]);
    });
    expect(db.read((d) => Item.all(d).map((i) => i.type).toList()), [ItemType.live]);
  });

  test('continue watching shows a series whose episode was started', () {
    final (db, a) = makeDB();
    db.write((d) {
      Item(accountId: a, type: ItemType.series, name: 'Show', streamId: 'S1').insert(d);
      Episode(accountId: a, seriesId: 'S1', season: 1, number: 1, title: 'Pilot', streamId: '501').insert(d);
      UserData.saveProgress(d, accountId: a, type: ItemType.series, streamId: 'ep:501', position: 600, duration: 2700);
    });
    final items = db.read((d) => UserData.continueWatching(d, accountId: a, type: ItemType.series));
    expect(items.map((i) => i.name), ['Show']);
  });

  test('file database uses WAL and keeps private permissions', () {
    final dir = tempDir('db');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/t.sqlite';
    final db = AppDatabase.open(path);
    addTearDown(db.close);
    expect(db.read((d) => d.select('PRAGMA journal_mode').first.values.first), 'wal');
    db.write((d) => Account(name: 'x', kind: AccountKind.m3u, url: 'http://h/l.m3u').insert(d));
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('$path$suffix');
      if (f.existsSync() && !Platform.isWindows) {
        expect(f.statSync().mode & 0x3F, 0, reason: '$suffix must not be readable by others');
      }
    }
    // the FTS trigger now only fires on a name change but must still keep the index right
    db.write((d) {
      Item(accountId: 1, type: ItemType.live, name: 'Alpha', streamId: '1').insert(d);
      d.execute("UPDATE item SET icon = 'x' WHERE streamId = '1'");
      d.execute("UPDATE item SET name = 'Bravo' WHERE streamId = '1'");
    });
    expect(db.read((d) => Search.run(d, const SearchRequest(accountId: 1, text: 'bra'))).length, 1);
    expect(db.read((d) => Search.run(d, const SearchRequest(accountId: 1, text: 'alp'))).length, 0);
  });

  test('a corrupt database file is moved aside, not deleted', () {
    final dir = tempDir('db');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/t.sqlite';
    File(path).writeAsBytesSync([...'this is not a database, just text that is long enough to look like a header'.codeUnits, ...List.filled(4096, 0)]);
    final r = AppDatabase.openRecovering(path);
    addTearDown(r.db.close);
    expect(r.movedAside, isNotNull);
    expect(File(r.movedAside!).existsSync(), isTrue);
    expect(r.db.read((d) => Account.all(d)), isEmpty);
  });

  test('icon urls pointing at the local network are not fetched', () {
    Uri? icon(String s) => Item(accountId: 1, type: ItemType.live, name: 'x', streamId: '1', icon: s).iconURL;
    expect(icon('https://cdn.example.com/logo.png'), isNotNull);
    for (final bad in [
      'http://192.168.1.1/cgi-bin/reboot', 'http://10.0.0.5/x.png', 'http://172.20.1.1/x.png', 'http://localhost:8123/api/webhook/x',
      'http://homeassistant.local:8123/x', 'http://169.254.1.1/x', 'file:///etc/passwd', 'data:text/html,hi',
    ]) {
      expect(icon(bad), isNull, reason: bad);
    }
  });

  test('deleting a playlist cascades to its rows', () {
    final (db, a) = makeDB();
    addItem(db, a, 'X');
    db.write((d) => d.execute('DELETE FROM account WHERE id = ?', [a]));
    expect(count(db, 'SELECT count(*) FROM item'), 0);
  });

  test('a database from before the info cache upgrades and keeps its data', () {
    final dir = tempDir('mig');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/old.sqlite';
    final old = sqlite3.open(path); // an existing install: migrations up to v3 only
    AppDatabase.migrate(old, upTo: 'v3-fts-trigger');
    old.execute("INSERT INTO account (id,name,kind,server,username) VALUES (1,'p','xtream','http://h','u')");
    old.execute("INSERT INTO item (accountId,type,name,streamId) VALUES (1,'movie','Keep me','10')");
    expect(old.select("SELECT 1 FROM sqlite_master WHERE name='item_info'"), isEmpty);
    old.close();

    final db = AppDatabase.open(path);
    addTearDown(db.close);
    expect(count(db, "SELECT count(*) FROM sqlite_master WHERE name='item_info'"), 1);
    expect(count(db, 'SELECT count(*) FROM item'), 1);
    expect(File('$path.bak').existsSync(), isTrue); // the backup-before-migration happens
    // and the search index of the old data still works
    expect(db.read((d) => Search.run(d, const SearchRequest(accountId: 1, text: 'keep')).length), 1);
  });
}
