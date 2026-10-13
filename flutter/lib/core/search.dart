import 'package:sqlite3/sqlite3.dart';

import 'models.dart';

class SearchRequest {
  const SearchRequest({this.accountId, this.text = '', this.type, this.categoryId, this.limit = 5000});

  /// Null = every playlist.
  final int? accountId;
  final String text;
  final ItemType? type;
  final String? categoryId;
  final int limit;

  SearchRequest _with({int? accountId, int? limit}) =>
      SearchRequest(accountId: accountId, text: text, type: type, categoryId: categoryId, limit: limit ?? this.limit);
}

abstract final class Search {
  static final _space = RegExp(r'\s+');
  static final _notToken = RegExp(r'[^\p{L}\p{N}\p{M}\p{Co}]+', unicode: true);

  /// Every word becomes a quoted prefix term (`"gam"* "thr"*`): quoting keeps FTS5 syntax characters in the user's text
  /// (`"`, `*`, `-`, `AND`, `(`) harmless. Null when nothing searchable is left.
  static String? prefixPattern(String text) {
    final tokens = [for (final t in text.split(_notToken)) if (t.isNotEmpty) t];
    return tokens.isEmpty ? null : tokens.map((t) => '"$t"*').join(' ');
  }

  static List<Item> run(Database db, SearchRequest r) {
    if (r.accountId == null && r.text.trim().isEmpty) {
      // Browsing every playlist: each gets an equal share, or the first one fills the limit.
      final ids = [
        for (final row in db.select(
            'SELECT DISTINCT accountId FROM item${r.type == null ? '' : ' WHERE type = ?'} ORDER BY accountId',
            [if (r.type != null) r.type!.name]))
          row['accountId'] as int
      ];
      if (ids.length > 1) {
        final share = r.limit ~/ ids.length;
        return [for (final id in ids) ...run(db, r._with(accountId: id, limit: share < 1 ? 1 : share))];
      }
    }
    // Every word is a prefix term; 180 of them take seconds on 100k rows and a running SQL statement cannot be cancelled.
    final trimmed = r.text.split(_space).where((w) => w.isNotEmpty).take(8).join(' ');
    final args = <Object?>[];
    var sql = 'SELECT item.* FROM item';
    if (trimmed.isNotEmpty) {
      final pattern = prefixPattern(trimmed);
      if (pattern == null) return const [];
      sql += ' JOIN item_fts ON item_fts.rowid = item.id AND item_fts MATCH ?';
      args.add(pattern);
    }
    final conds = <String>[];
    if (r.accountId != null) {
      conds.add('item.accountId = ?');
      args.add(r.accountId);
    }
    if (r.type != null) {
      conds.add('item.type = ?');
      args.add(r.type!.name);
    }
    if (r.categoryId != null) {
      conds.add('item.categoryId = ?');
      args.add(r.categoryId);
    }
    if (conds.isNotEmpty) sql += ' WHERE ${conds.join(' AND ')}';
    sql += trimmed.isEmpty ? ' ORDER BY item.id' : ' ORDER BY rank';
    sql += ' LIMIT ?';
    args.add(r.limit);
    return Item.fromRows(db.select(sql, args));
  }
}
