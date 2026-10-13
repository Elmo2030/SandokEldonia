import 'package:sqlite3/sqlite3.dart';

import 'models.dart';

/// "Hide categories": a plain name filter (not a parental lock). Built from the comma-separated preference (Arabic comma too).
class CategoryFilter {
  CategoryFilter(String csv)
      : words = [
          for (final w in csv.split(RegExp('[,،]')))
            if (w.trim().isNotEmpty) w.trim().toLowerCase()
        ];

  final List<String> words;

  bool get isEmpty => words.isEmpty;

  bool hides(String name) {
    final n = name.toLowerCase();
    return words.any(n.contains);
  }

  List<Category> visibleCategories(List<Category> categories) => [for (final c in categories) if (!hides(c.name)) c];

  /// Drops the items of hidden categories (a category is a playlist + type + remote id). Items without a category stay.
  List<Item> visible(List<Item> items, Database db) {
    if (isEmpty) return items;
    final hidden = {for (final c in Category.all(db)) if (hides(c.name)) _key(c.accountId, c.type, c.remoteId)};
    if (hidden.isEmpty) return items;
    return [for (final i in items) if (i.categoryId == null || !hidden.contains(_key(i.accountId, i.type, i.categoryId!))) i];
  }

  static String _key(int account, ItemType type, String remoteId) => '$account|${type.name}|$remoteId';
}
