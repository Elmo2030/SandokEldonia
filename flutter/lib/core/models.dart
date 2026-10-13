import 'package:sqlite3/sqlite3.dart';

import 'remote_image.dart';

enum ItemType {
  live,
  movie,
  series;

  static ItemType? parse(Object? raw) {
    for (final t in values) {
      if (t.name == raw) return t;
    }
    return null;
  }
}

enum AccountKind {
  xtream,
  m3u;

  static AccountKind? parse(Object? raw) {
    for (final k in values) {
      if (k.name == raw) return k;
    }
    return null;
  }
}

ItemType _type(Object? raw) => ItemType.parse(raw) ?? ItemType.live;

class Account {
  Account({this.id, required this.name, required this.kind, this.server, this.username, this.url});

  /// Null until inserted.
  int? id;
  String name;
  AccountKind kind;
  String? server, username, url;

  factory Account.fromRow(Row r) => Account(
        id: r['id'] as int,
        name: r['name'] as String,
        kind: AccountKind.parse(r['kind']) ?? AccountKind.xtream,
        server: r['server'] as String?,
        username: r['username'] as String?,
        url: r['url'] as String?,
      );

  /// Inserts the account and sets [id].
  Account insert(Database db) {
    db.execute('INSERT INTO account (name,kind,server,username,url) VALUES (?,?,?,?,?)',
        [name, kind.name, server, username, url]);
    id = db.lastInsertRowId;
    return this;
  }

  static List<Account> all(Database db) =>
      [for (final r in db.select('SELECT * FROM account ORDER BY id')) Account.fromRow(r)];

  /// The playlist choice to open with, from the saved value ("all" or an account id). A deleted playlist falls back to the
  /// first, and All needs more than one playlist.
  static ({bool all, Account? account}) restore(String? saved, List<Account> accounts) {
    Account? found;
    for (final a in accounts) {
      if ('${a.id ?? 0}' == saved) {
        found = a;
        break;
      }
    }
    return (all: saved == 'all' && accounts.length > 1, account: found ?? (accounts.isEmpty ? null : accounts.first));
  }

  (int?, String, AccountKind, String?, String?, String?) get _t => (id, name, kind, server, username, url);
  @override
  bool operator ==(Object other) => other is Account && other._t == _t;
  @override
  int get hashCode => _t.hashCode;
}

class Category {
  Category({this.id, required this.accountId, required this.type, required this.remoteId, required this.name});

  int? id;
  final int accountId;
  final ItemType type;
  final String remoteId;
  final String name;

  factory Category.fromRow(Row r) => Category(
        id: r['id'] as int,
        accountId: r['accountId'] as int,
        type: _type(r['type']),
        remoteId: r['remoteId'] as String,
        name: r['name'] as String,
      );

  /// Inserts the category (an existing playlist+type+remoteId is left alone) and sets [id].
  Category insert(Database db) {
    db.execute('INSERT OR IGNORE INTO category (accountId,type,remoteId,name) VALUES (?,?,?,?)',
        [accountId, type.name, remoteId, name]);
    if (db.updatedRows > 0) id = db.lastInsertRowId;
    return this;
  }

  static List<Category> all(Database db) => [for (final r in db.select('SELECT * FROM category ORDER BY id')) Category.fromRow(r)];

  (int?, int, ItemType, String, String) get _t => (id, accountId, type, remoteId, name);
  @override
  bool operator ==(Object other) => other is Category && other._t == _t;
  @override
  int get hashCode => _t.hashCode;
}

class Item {
  Item({
    this.id,
    required this.accountId,
    required this.type,
    required this.name,
    required this.streamId,
    this.categoryId,
    this.icon,
    this.rating,
    this.containerExt,
    this.directURL,
    this.tvArchive = false,
    this.archiveDays = 0,
    this.epgChannelId,
  });

  int? id;
  final int accountId;
  final ItemType type;
  final String name;
  final String streamId;
  final String? categoryId, icon, rating, containerExt, directURL, epgChannelId;
  final bool tvArchive;
  final int archiveDays;

  factory Item.fromRow(Row r) => Item(
        id: r['id'] as int,
        accountId: r['accountId'] as int,
        type: _type(r['type']),
        name: r['name'] as String,
        streamId: r['streamId'] as String,
        categoryId: r['categoryId'] as String?,
        icon: r['icon'] as String?,
        rating: r['rating'] as String?,
        containerExt: r['containerExt'] as String?,
        directURL: r['directURL'] as String?,
        tvArchive: r['tvArchive'] == 1,
        archiveDays: r['archiveDays'] as int,
        epgChannelId: r['epgChannelId'] as String?,
      );

  static List<Item> fromRows(Iterable<Row> rows) => [for (final r in rows) Item.fromRow(r)];

  /// Plain insert (throws on a duplicate playlist+type+streamId). Bulk loading goes through `SyncService`.
  Item insert(Database db) {
    db.execute(
        'INSERT INTO item (accountId,type,name,categoryId,icon,rating,streamId,containerExt,directURL,tvArchive,archiveDays,epgChannelId) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
        [accountId, type.name, name, categoryId, icon, rating, streamId, containerExt, directURL, tvArchive, archiveDays, epgChannelId]);
    id = db.lastInsertRowId;
    return this;
  }

  static List<Item> all(Database db) => fromRows(db.select('SELECT * FROM item ORDER BY id'));

  /// The logo/poster URL is provider-controlled and fetched without a click: see [safeImageUrl].
  Uri? get iconURL => safeImageUrl(icon);

  (int?, int, ItemType, String, String, String?, String?, String?, String?, String?, bool, int, String?) get _t =>
      (id, accountId, type, name, streamId, categoryId, icon, rating, containerExt, directURL, tvArchive, archiveDays, epgChannelId);
  @override
  bool operator ==(Object other) => other is Item && other._t == _t;
  @override
  int get hashCode => _t.hashCode;
}

class Episode {
  Episode({
    this.id,
    required this.accountId,
    required this.seriesId,
    required this.season,
    required this.number,
    required this.title,
    required this.streamId,
    this.containerExt,
  });

  int? id;
  final int accountId;
  final String seriesId;
  final int season, number;
  final String title, streamId;
  final String? containerExt;

  factory Episode.fromRow(Row r) => Episode(
        id: r['id'] as int,
        accountId: r['accountId'] as int,
        seriesId: r['seriesId'] as String,
        season: r['season'] as int,
        number: r['number'] as int,
        title: r['title'] as String,
        streamId: r['streamId'] as String,
        containerExt: r['containerExt'] as String?,
      );

  Episode insert(Database db) {
    db.execute('INSERT INTO episode (accountId,seriesId,season,number,title,streamId,containerExt) VALUES (?,?,?,?,?,?,?)',
        [accountId, seriesId, season, number, title, streamId, containerExt]);
    id = db.lastInsertRowId;
    return this;
  }

  (int?, int, String, int, int, String, String, String?) get _t => (id, accountId, seriesId, season, number, title, streamId, containerExt);
  @override
  bool operator ==(Object other) => other is Episode && other._t == _t;
  @override
  int get hashCode => _t.hashCode;
}

/// One program of the guide.
class EPGEntry {
  const EPGEntry({required this.title, required this.start, required this.end});

  final String title;
  final DateTime start, end;

  @override
  bool operator ==(Object other) => other is EPGEntry && other.title == title && other.start == start && other.end == end;
  @override
  int get hashCode => Object.hash(title, start, end);
  @override
  String toString() => 'EPGEntry($title, $start - $end)';
}
