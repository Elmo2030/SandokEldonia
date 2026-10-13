import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/app_database.dart';
import 'package:iptvmac/core/category_filter.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/core/search.dart';
import 'package:iptvmac/core/user_data.dart';

import 'support.dart';

(AppDatabase, int, int) seed() {
  final (db, a) = makeDB();
  final b = addAccount(db, 'second');
  db.write((d) {
    for (final (aid, type, rid, name) in [
      (a, ItemType.live, '1', 'News'),
      (a, ItemType.live, '2', 'Adult'),
      (a, ItemType.movie, '2', 'Action'),
      (b, ItemType.live, '2', 'Sports'),
    ]) {
      Category(accountId: aid, type: type, remoteId: rid, name: name).insert(d);
    }
  });
  addItem(db, a, 'Channel', cat: '1', sid: 'c1');
  addItem(db, a, 'Hidden channel', cat: '2', sid: 'c2');
  addItem(db, a, 'Film', type: ItemType.movie, cat: '2', sid: 'm1'); // remote id 2, but the movie category "Action"
  addItem(db, a, 'No category', cat: null, sid: 'c3');
  addItem(db, a, 'Unknown category', cat: '99', sid: 'c4');
  addItem(db, b, 'Other playlist', cat: '2', sid: 'c2'); // same remote id in another playlist: "Sports"
  return (db, a, b);
}

void main() {
  test('hidden words are trimmed, lowercased and empty ones ignored', () {
    expect(CategoryFilter('  Adult , XXX,, ,\n18+ ').words, ['adult', 'xxx', '18+']);
    expect(CategoryFilter('كبار،xxx, adult').words, ['كبار', 'xxx', 'adult']); // the Arabic comma too
    expect(CategoryFilter('').isEmpty, isTrue);
    expect(CategoryFilter(' , ,, ').isEmpty, isTrue);
  });

  test('category names are matched by substring ignoring case', () {
    final f = CategoryFilter('adult, חדשות');
    expect(f.hides('XXX ADULT 18+'), isTrue);
    expect(f.hides('Hot adults'), isTrue);
    expect(f.hides('ערוצי חדשות'), isTrue);
    expect(f.hides('Movies'), isFalse);
    expect(CategoryFilter('').hides('anything'), isFalse);
  });

  test('hidden categories disappear from the category list', () {
    final cats = [
      Category(accountId: 1, type: ItemType.live, remoteId: '1', name: 'News'),
      Category(accountId: 1, type: ItemType.live, remoteId: '2', name: 'Adult'),
    ];
    expect(CategoryFilter('adult').visibleCategories(cats).map((c) => c.name), ['News']);
    expect(CategoryFilter('').visibleCategories(cats).length, 2);
  });

  test('items of hidden categories are removed per playlist and type', () {
    final (db, _, _) = seed();
    final all = db.read((d) => Item.all(d));
    final shown = db.read((d) => CategoryFilter('adult').visible(all, d)).map((i) => i.name);
    expect(shown, ['Channel', 'Film', 'No category', 'Unknown category', 'Other playlist']);
  });

  test('an empty filter returns everything', () {
    final (db, _, _) = seed();
    final all = db.read((d) => Item.all(d));
    expect(db.read((d) => CategoryFilter(' , ').visible(all, d)), all);
  });

  test('hiding applies to favorites, continue watching and search results', () {
    final (db, a, _) = seed();
    db.write((d) {
      for (final sid in ['c1', 'c2']) {
        UserData.toggleFavorite(d, accountId: a, type: ItemType.live, streamId: sid);
        UserData.saveProgress(d, accountId: a, type: ItemType.live, streamId: sid, position: 10, duration: 100);
      }
    });
    final f = CategoryFilter('adult');
    final (favs, hist, found) = db.read((d) => (
          f.visible(UserData.favorites(d, type: ItemType.live), d).map((i) => i.name).toList(),
          f.visible(UserData.continueWatching(d, type: ItemType.live), d).map((i) => i.name).toList(),
          f.visible(Search.run(d, const SearchRequest(text: 'channel', type: ItemType.live)), d).map((i) => i.name).toList(),
        ));
    expect(favs, ['Channel']);
    expect(hist, ['Channel']);
    expect(found, ['Channel']);
  });
}
