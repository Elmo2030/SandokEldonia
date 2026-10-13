import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/app_database.dart';
import 'package:iptvmac/core/item_info.dart';
import 'package:iptvmac/core/json_util.dart';
import 'package:iptvmac/core/models.dart';

import 'support.dart';

// The info cache: 14-day TTL, one row per (playlist, type, stream id), gone with its playlist, added by a new migration.

ItemInfo sample([String plot = 'A plot.']) =>
    ItemInfo.fromResponse({'info': {'plot': plot, 'rating': '7.5', 'youtube_trailer': 'dQw4w9WgXcQ'}});
final t0 = DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000, isUtc: true);
const day = Duration(days: 1);

ItemInfo? get(AppDatabase db, int a, {ItemType type = ItemType.movie, String sid = '10', DateTime? at, Duration? maxAge = ItemInfoStore.ttl}) =>
    db.read((d) => ItemInfoStore.cached(d, accountId: a, type: type, streamId: sid, now: at ?? t0, maxAge: maxAge));

void put(AppDatabase db, int a, ItemInfo info, {ItemType type = ItemType.movie, String sid = '10', DateTime? at}) =>
    db.write((d) => ItemInfoStore.save(d, accountId: a, type: type, streamId: sid, info: info, now: at ?? t0));

void main() {
  test('info is served from the cache for fourteen days', () {
    final (db, a) = makeDB();
    expect(get(db, a), isNull);
    put(db, a, sample());
    expect(get(db, a), sample());
    expect(get(db, a, at: t0.add(day * 14 - const Duration(minutes: 1))), sample()); // just inside the TTL
    expect(get(db, a, at: t0.add(day * 14 + const Duration(minutes: 1))), isNull); // expired
    expect(get(db, a, at: t0.add(day * 400), maxAge: null), sample()); // a stale copy is still usable when the network fails
    expect(ItemInfoStore.ttl, day * 14);
  });

  test('the cache is keyed by playlist, type and stream id', () {
    final (db, a) = makeDB();
    final b = addAccount(db, 'other');
    put(db, a, sample('one'));
    expect(get(db, b), isNull); // same id in another playlist
    expect(get(db, a, type: ItemType.series), isNull); // same id, other type
    expect(get(db, a, sid: '11'), isNull);
    put(db, a, sample('two')); // saving again replaces
    expect(get(db, a)?.plot, 'two');
    expect(count(db, 'SELECT count(*) FROM item_info'), 1);
  });

  test('saving drops rows that are already expired', () {
    final (db, a) = makeDB();
    put(db, a, sample('old'), sid: '1');
    put(db, a, sample('new'), sid: '2', at: t0.add(day * 20));
    expect(count(db, 'SELECT count(*) FROM item_info'), 1);
    expect(get(db, a, sid: '2', at: t0.add(day * 20))?.plot, 'new');
  });

  test('a corrupt row is treated as missing', () {
    final (db, a) = makeDB();
    db.write((d) => d.execute('INSERT INTO item_info (accountId,type,streamId,json,fetched) VALUES (?,?,?,?,?)',
        [a, 'movie', '10', 'not json', dbDate(t0)]));
    expect(get(db, a), isNull);
  });

  test('deleting a playlist deletes its cached info', () {
    final (db, a) = makeDB();
    final b = addAccount(db, 'keep');
    put(db, a, sample());
    put(db, b, sample());
    db.write((d) => d.execute('DELETE FROM account WHERE id = ?', [a]));
    expect(get(db, a), isNull);
    expect(get(db, b), sample());
  });

  test('the cache holds only the parsed fields, never credentials', () {
    final (db, a) = makeDB();
    final info = ItemInfo.fromResponse({
      'info': {'plot': 'p', 'username': 'u1', 'password': 'pw1', 'url': 'http://h/movie/u1/pw1/10.mp4'},
      'user_info': {'username': 'u1', 'password': 'pw1'},
      'movie_data': {'container_extension': 'mkv'},
    });
    put(db, a, info);
    final stored = db.read((d) => d.select('SELECT json FROM item_info').first['json'] as String);
    expect(stored, contains('"plot"'));
    for (final secret in ['pw1', 'u1', 'password', 'username', 'movie/']) {
      expect(stored, isNot(contains(secret)), reason: secret);
    }
  });

  test('image links in a cached row are checked again when it is read', () {
    final (db, a) = makeDB();
    // as an older version or a tampered file could have left it
    const json = '{"plot":"p","posterURL":"http://192.168.1.1/reboot","backdropURL":"https://cdn.example.com/b.jpg","trailerID":"x/../evil"}';
    db.write((d) => d.execute('INSERT INTO item_info (accountId,type,streamId,json,fetched) VALUES (?,?,?,?,?)',
        [a, 'movie', '10', json, dbDate(t0)]));
    final i = get(db, a)!;
    expect(i.plot, 'p');
    expect(i.posterURL, isNull);
    expect(i.backdropURL?.host, 'cdn.example.com');
    expect(i.trailerID, isNull);
    expect(i.trailerURL, isNull);
  });

  test('dates are stored the way the Apple apps store them', () {
    expect(dbDate(DateTime.utc(2026, 10, 7, 10, 1, 2, 3)), '2026-10-07 10:01:02.003');
    expect(parseDbDate('2026-10-07 10:01:02.003'), DateTime.utc(2026, 10, 7, 10, 1, 2, 3));
    expect(parseDbDate('2026-10-07 10:01:02'), DateTime.utc(2026, 10, 7, 10, 1, 2));
  });
}
