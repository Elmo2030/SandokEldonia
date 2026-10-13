import 'package:iptvmac/app/library_model.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/core/user_data.dart';

/// Screenshots only (debug builds with `--dart-define=DEMO_SEED=true`): favorites and resume points on the invented demo
/// provider, so the library, the shelves and the series screen have something to show. Does nothing once favorites exist.
Future<void> seedDemo(LibraryModel m) async {
  final a = m.accounts.firstOrNull;
  if (a == null || m.favoriteKeys.isNotEmpty) return;
  final items = m.db.read((d) => Item.all(d));
  List<Item> pick(ItemType t, List<int> idx) {
    final l = items.where((i) => i.type == t).toList();
    return [for (final i in idx) if (i < l.length) l[i]];
  }

  final live = pick(ItemType.live, [0, 2, 6]), movies = pick(ItemType.movie, [1, 4, 9, 13]), series = pick(ItemType.series, [0, 2, 4]);
  for (final s in series.take(2)) {
    final eps = await m.loadEpisodes(s);
    if (eps.length > 2) {
      final first = s.id == series[0].id;
      m.db.write((d) {
        UserData.saveProgress(d, accountId: a.id!, type: ItemType.series, streamId: 'ep:${eps[0].streamId}', position: first ? 2650 : 1800, duration: 2700);
        UserData.saveProgress(d, accountId: a.id!, type: ItemType.series, streamId: 'ep:${eps[1].streamId}', position: first ? 1100 : 20, duration: 2700);
      });
    }
  }
  m.db.write((d) {
    for (final (i, mv) in movies.take(3).indexed) {
      UserData.saveProgress(d, accountId: a.id!, type: ItemType.movie, streamId: mv.streamId, position: [1500.0, 4200.0, 600.0][i], duration: 6000);
    }
    for (final i in [...live, ...movies.take(2), ...series.take(2)]) {
      UserData.toggleFavorite(d, accountId: a.id!, type: i.type, streamId: i.streamId);
    }
  });
  m.loadFavorites();
  m.reloadContinue();
  m.scheduleSearch(immediate: true);
}
