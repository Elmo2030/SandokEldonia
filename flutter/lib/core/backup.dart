import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'json_util.dart';
import 'models.dart';

enum BackupError implements Exception { invalid, unsupportedVersion, tooLarge }

/// Playlists (no passwords: they stay in the keystore), favorites and watch history as one JSON file. Importing merges
/// into what is already there. The JSON is the same as the Apple apps write, so a backup moves between them.
class Backup {
  /// [created] is cut to whole seconds, as the file stores them.
  Backup(this.playlists, {DateTime? created, this.version = Backup.currentVersion})
      : created = DateTime.fromMillisecondsSinceEpoch((created ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000 * 1000, isUtc: true);

  static const currentVersion = 1;
  static const maxBytes = 10000000;

  final int version;
  final DateTime created;
  final List<BackupPlaylist> playlists;

  // Export

  static Backup make(Database db) => Backup([
        for (final a in Account.all(db))
          BackupPlaylist(
            name: a.name,
            kind: a.kind,
            server: a.server,
            username: a.username,
            url: a.url,
            favorites: [
              for (final r in db.select('SELECT type, streamId FROM favorite WHERE accountId = ? ORDER BY type, streamId', [a.id]))
                BackupFavorite(ItemType.parse(r['type']) ?? ItemType.live, r['streamId'] as String)
            ],
            history: [
              for (final r in db.select(
                  'SELECT type, streamId, position, duration, updated FROM history WHERE accountId = ? ORDER BY type, streamId', [a.id]))
                BackupWatched(ItemType.parse(r['type']) ?? ItemType.live, r['streamId'] as String, (r['position'] as num).toDouble(),
                    (r['duration'] as num).toDouble(), parseDbDate(r['updated'] as String))
            ],
          )
      ]);

  Map<String, dynamic> toJson() => {
        'created': _iso(created),
        'playlists': [for (final p in playlists) p.toJson()],
        'version': version,
      };

  /// Pretty printed with sorted keys, like the Apple apps.
  String encoded() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// The file holds playlist addresses (an M3U link can carry a login): owner-only, never readable while the mode is still
  /// the default (chmod is best effort, not on Windows).
  void write(File file) {
    final data = encoded();
    file.writeAsBytesSync(const []); // creates or empties the file first
    if (!Platform.isWindows) {
      try {
        Process.runSync('chmod', ['600', file.path]);
      } on ProcessException {
        // no chmod binary
      }
    }
    file.writeAsStringSync(data, flush: true);
  }

  // Import

  static Backup read(File file, {int maxBytes = Backup.maxBytes}) {
    if (file.lengthSync() > maxBytes) throw BackupError.tooLarge;
    return decode(file.readAsBytesSync(), maxBytes: maxBytes);
  }

  /// A file from outside is untrusted: size, version, shape, and playlist addresses (an M3U link must be http(s), never
  /// file://).
  static Backup decode(Uint8List data, {int maxBytes = Backup.maxBytes}) {
    if (data.length > maxBytes) throw BackupError.tooLarge;
    final Object? root;
    try {
      root = jsonDecode(utf8.decode(data));
    } on FormatException {
      throw BackupError.invalid;
    }
    if (root is! Map || root['version'] is! int) throw BackupError.invalid;
    if (root['version'] != currentVersion) throw BackupError.unsupportedVersion;
    try {
      final created = DateTime.tryParse(root['created'] as String);
      if (created == null) throw BackupError.invalid;
      final b = Backup([for (final p in root['playlists'] as List) BackupPlaylist.fromJson(p as Map)], created: created);
      if (!b.playlists.every((p) => p.isValid)) throw BackupError.invalid;
      return b;
    } on BackupError {
      rethrow;
    } catch (_) {
      throw BackupError.invalid; // a wrong type or a missing key
    }
  }

  /// Playlists are matched by source (Xtream: server + username, M3U: link), else added. Favorites are added; a resume
  /// point is replaced only by a newer one. Returns the playlists that were added (they still need a sync, and an Xtream
  /// password).
  List<Account> merge(Database db) {
    final known = Account.all(db), added = <Account>[];
    for (final p in playlists) {
      var account = known.where(p.isSource).firstOrNull;
      if (account == null) {
        account = (p.kind == AccountKind.xtream
                ? Account(name: p.name, kind: AccountKind.xtream, server: p.server, username: p.username)
                : Account(name: p.name, kind: AccountKind.m3u, url: p.url))
            .insert(db);
        known.add(account);
        added.add(account);
      }
      final aid = account.id!;
      for (final f in p.favorites) {
        db.execute('INSERT OR IGNORE INTO favorite (accountId,type,streamId) VALUES (?,?,?)', [aid, f.type.name, f.streamId]);
      }
      for (final h in p.history) {
        db.execute('''
          INSERT INTO history (accountId,type,streamId,position,duration,updated) VALUES (?,?,?,?,?,?)
          ON CONFLICT(accountId,type,streamId) DO UPDATE SET position=excluded.position, duration=excluded.duration, updated=excluded.updated
          WHERE excluded.updated > history.updated
          ''', [aid, h.type.name, h.streamId, h.position, h.duration, dbDate(h.updated)]);
      }
    }
    return added;
  }

  @override
  bool operator ==(Object other) => other is Backup && other.version == version && other.created == created && _listEq(other.playlists, playlists);
  @override
  int get hashCode => Object.hash(version, created, playlists.length);
}

class BackupPlaylist {
  const BackupPlaylist({
    required this.name,
    required this.kind,
    this.server,
    this.username,
    this.url,
    required this.favorites,
    required this.history,
  });

  final String name;
  final AccountKind kind;
  final String? server, username, url;
  final List<BackupFavorite> favorites;
  final List<BackupWatched> history;

  /// A copy with other fields (an import test edits a decoded backup).
  BackupPlaylist copyWith({String? name, String? server, List<BackupFavorite>? favorites}) => BackupPlaylist(
      name: name ?? this.name, kind: kind, server: server ?? this.server, username: username, url: url,
      favorites: favorites ?? this.favorites, history: history);

  factory BackupPlaylist.fromJson(Map j) => BackupPlaylist(
        name: j['name'] as String,
        kind: AccountKind.parse(j['kind']) ?? (throw const FormatException('kind')),
        server: j['server'] as String?,
        username: j['username'] as String?,
        url: j['url'] as String?,
        favorites: [for (final f in j['favorites'] as List) BackupFavorite.fromJson(f as Map)],
        history: [for (final h in j['history'] as List) BackupWatched.fromJson(h as Map)],
      );

  Map<String, dynamic> toJson() => {
        'favorites': [for (final f in favorites) f.toJson()],
        'history': [for (final h in history) h.toJson()],
        'kind': kind.name,
        'name': name,
        'server': ?server,
        'url': ?url,
        'username': ?username,
      };

  bool get isValid {
    final source = kind == AccountKind.xtream ? (username ?? '').isNotEmpty && _web(server, bare: true) : _web(url, bare: false);
    return source && history.every((h) => h.duration > 0 && h.position >= 0);
  }

  /// http(s) only. An Xtream server may be typed without a scheme (host:port); a playlist link may not.
  static bool _web(String? s, {required bool bare}) {
    var t = s?.trim() ?? '';
    if (t.isEmpty) return false;
    if (bare && !t.contains('://')) t = 'http://$t';
    final u = Uri.tryParse(t);
    return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
  }

  bool isSource(Account a) {
    if (a.kind != kind) return false;
    String trim(String? s) => (s ?? '').trim();
    String srv(String? s) => trim(s).replaceAll(RegExp(r'^/+|/+$'), '').toLowerCase();
    return kind == AccountKind.xtream ? srv(a.server) == srv(server) && trim(a.username) == trim(username) : trim(a.url) == trim(url);
  }

  (String, AccountKind, String?, String?, String?) get _t => (name, kind, server, username, url);
  @override
  bool operator ==(Object other) =>
      other is BackupPlaylist && other._t == _t && _listEq(other.favorites, favorites) && _listEq(other.history, history);
  @override
  int get hashCode => _t.hashCode;
}

class BackupFavorite {
  const BackupFavorite(this.type, this.streamId);

  final ItemType type;
  final String streamId;

  factory BackupFavorite.fromJson(Map j) =>
      BackupFavorite(ItemType.parse(j['type']) ?? (throw const FormatException('type')), j['streamId'] as String);

  Map<String, dynamic> toJson() => {'streamId': streamId, 'type': type.name};

  @override
  bool operator ==(Object other) => other is BackupFavorite && other.type == type && other.streamId == streamId;
  @override
  int get hashCode => Object.hash(type, streamId);
}

class BackupWatched {
  const BackupWatched(this.type, this.streamId, this.position, this.duration, this.updated);

  final ItemType type;
  final String streamId;
  final double position, duration;
  final DateTime updated;

  factory BackupWatched.fromJson(Map j) => BackupWatched(
        ItemType.parse(j['type']) ?? (throw const FormatException('type')),
        j['streamId'] as String,
        (j['position'] as num).toDouble(),
        (j['duration'] as num).toDouble(),
        DateTime.tryParse(j['updated'] as String) ?? (throw const FormatException('updated')),
      );

  Map<String, dynamic> toJson() =>
      {'duration': duration, 'position': position, 'streamId': streamId, 'type': type.name, 'updated': _iso(updated)};

  /// Dates in the file are whole seconds.
  (ItemType, String, double, double, int) get _t => (type, streamId, position, duration, updated.millisecondsSinceEpoch ~/ 1000);
  @override
  bool operator ==(Object other) => other is BackupWatched && other._t == _t;
  @override
  int get hashCode => _t.hashCode;
}

/// ISO 8601 UTC without fractions ("2026-10-07T10:00:00Z"), what the Apple apps read and write.
String _iso(DateTime d) => '${d.toUtc().toIso8601String().split('.').first}Z';

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
