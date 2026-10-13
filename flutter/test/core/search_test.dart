import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/app_database.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/core/search.dart';

import 'support.dart';

List<String> run(AppDatabase db, SearchRequest r) => db.read((d) => Search.run(d, r).map((i) => i.name).toList());

void main() {
  test('prefix search matches every token', () {
    final (db, a) = makeDB();
    addItem(db, a, 'Game of Thrones', type: ItemType.series);
    addItem(db, a, 'Gamer Girl', type: ItemType.movie);
    expect(run(db, SearchRequest(accountId: a, text: 'gam')).length, 2);
    expect(run(db, SearchRequest(accountId: a, text: 'game thr')), ['Game of Thrones']);
  });

  test('scopes narrow results', () {
    final (db, a) = makeDB();
    addItem(db, a, 'Alpha One', cat: '1');
    addItem(db, a, 'Alpha Two', cat: '2');
    addItem(db, a, 'Alpha Film', type: ItemType.movie, cat: '9');
    expect(run(db, SearchRequest(accountId: a, text: 'alpha')).length, 3);
    expect(run(db, SearchRequest(accountId: a, text: 'alpha', type: ItemType.live)).length, 2);
    expect(run(db, SearchRequest(accountId: a, text: 'alpha', type: ItemType.live, categoryId: '2')), ['Alpha Two']);
  });

  test('empty text browses in insertion order', () {
    final (db, a) = makeDB();
    for (final n in ['Zeta', 'Alpha', 'Mid']) {
      addItem(db, a, n, cat: '1');
    }
    expect(run(db, SearchRequest(accountId: a, text: '  ', type: ItemType.live, categoryId: '1')), ['Zeta', 'Alpha', 'Mid']);
  });

  test('fts5 syntax characters never throw', () {
    final (db, a) = makeDB();
    addItem(db, a, 'Rock and Roll');
    for (final q in ['"', 'rock*', '-rock', 'rock AND', '(rock', 'NEAR(', 'rock OR', "'", 'a"b']) {
      run(db, SearchRequest(accountId: a, text: q));
    }
    expect(run(db, SearchRequest(accountId: a, text: '"*-')), isEmpty);
  });

  test('accents and Hebrew prefix match', () {
    final (db, a) = makeDB();
    addItem(db, a, 'Café Society', type: ItemType.movie);
    addItem(db, a, 'שלום עולם', type: ItemType.movie);
    expect(run(db, SearchRequest(accountId: a, text: 'cafe')), ['Café Society']);
    expect(run(db, SearchRequest(accountId: a, text: 'שלו')), ['שלום עולם']);
  });

  test('other accounts are invisible', () {
    final (db, a) = makeDB();
    addItem(db, a, 'Mine');
    expect(run(db, SearchRequest(accountId: a + 1, text: 'mine')), isEmpty);
  });

  test('null account searches every playlist and a single account stays isolated', () {
    final (db, a) = makeDB();
    final b = addAccount(db, 'second');
    addItem(db, a, 'Alpha One', sid: '1');
    addItem(db, b, 'Alpha Two', sid: '1'); // same streamId in both playlists
    expect(run(db, const SearchRequest(text: 'alpha'))..sort(), ['Alpha One', 'Alpha Two']);
    expect(run(db, SearchRequest(accountId: a, text: 'alpha')), ['Alpha One']);
    expect(run(db, SearchRequest(accountId: b, text: 'alpha')), ['Alpha Two']);
    expect(run(db, const SearchRequest(type: ItemType.live, categoryId: '1')).length, 2);
  });

  test('browsing every playlist gives each one a share of the limit', () {
    final (db, a) = makeDB();
    final b = addAccount(db, 'second');
    for (var i = 0; i < 20; i++) {
      addItem(db, a, 'A$i');
    }
    for (var i = 0; i < 20; i++) {
      addItem(db, b, 'B$i');
    }
    final names = run(db, const SearchRequest(type: ItemType.live, limit: 10));
    expect(names.length, 10);
    expect(names.where((n) => n.startsWith('A')).length, 5);
    expect(names.where((n) => n.startsWith('B')).length, 5);
  });

  test('a playlist without that type does not take a share of the limit', () {
    final (db, a) = makeDB();
    final b = addAccount(db, 'live only');
    for (var i = 0; i < 20; i++) {
      addItem(db, a, 'Film $i', type: ItemType.movie);
    }
    addItem(db, b, 'Channel');
    expect(run(db, const SearchRequest(type: ItemType.movie, limit: 10)).length, 10);
  });

  test('only the first 8 words are searched', () {
    final (db, a) = makeDB();
    addItem(db, a, 'a1 b2 c3 d4 e5 f6 g7 h8');
    // the 9th word would not match, but is ignored
    expect(run(db, SearchRequest(accountId: a, text: 'a b c d e f g h zzz')), ['a1 b2 c3 d4 e5 f6 g7 h8']);
  });

  test('prefix pattern quotes every word', () {
    expect(Search.prefixPattern('Game thr'), '"Game"* "thr"*');
    expect(Search.prefixPattern('a-b'), '"a"* "b"*');
    expect(Search.prefixPattern('"*-'), isNull);
  });

  group('100k items', () {
    // The target of the Swift tests: a search stays under 250 ms. The sync-and-search test is in performance_test.dart.
    late AppDatabase db;
    late int a, b;
    setUpAll(() {
      final r = makeDB();
      db = r.$1;
      a = r.$2;
      b = addAccount(db, 'second');
      db.write((d) {
        final st = d.prepare('INSERT INTO item (accountId,type,name,categoryId,streamId) VALUES (?,?,?,?,?)');
        for (var i = 0; i < 100000; i++) {
          st.execute([i.isEven ? a : b, 'live', 'Channel $i ${i % 7 == 0 ? 'Sport' : 'News'}', '${i % 50}', '$i']);
        }
        st.close();
      });
    });

    int ms(void Function() f) {
      final sw = Stopwatch()..start();
      f();
      return sw.elapsedMilliseconds;
    }

    test('search stays fast', () {
      late List<String> hits;
      final t = ms(() => hits = run(db, SearchRequest(accountId: a, text: 'spor 99')));
      expect(hits, isNotEmpty);
      expect(t, lessThan(250), reason: 'search took $t ms');
    });

    test('all-playlists search and browse stay fast', () {
      for (final r in const [SearchRequest(text: 'spor 99'), SearchRequest(type: ItemType.live)]) {
        late List<String> hits;
        final t = ms(() => hits = run(db, r));
        expect(hits, isNotEmpty);
        expect(t, lessThan(250), reason: 'search "${r.text}" took $t ms');
      }
    });
  });
}
