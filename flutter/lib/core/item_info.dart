import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'json_util.dart';
import 'models.dart';
import 'remote_image.dart';

/// What the provider says about a movie or series (`get_vod_info` / `get_series_info`). The server is untrusted: text is
/// plain, length-capped and stripped of control characters, images pass [safeImageUrl], the trailer is only a YouTube
/// video id.
class ItemInfo {
  ItemInfo();

  String? title, plot, cast, director, genre, country, releaseDate;
  int? year;

  /// 0...10 (null when the provider has none; panels send 0 or "" for "unrated").
  double? rating;
  int? durationMinutes;
  String? trailerID;
  Uri? posterURL, backdropURL;

  /// `response` is the whole answer; the details sit under `info` (a panel with nothing sends `"info": []`).
  factory ItemInfo.fromResponse(Map<String, dynamic> response) {
    final i = ItemInfo();
    final d = response['info'];
    if (d is! Map) return i;
    T? pick<T>(List<String> keys, T? Function(Object?) f) {
      for (final k in keys) {
        final r = f(d[k]);
        if (r != null) return r;
      }
      return null;
    }

    String? txt(List<String> keys, int max) => pick(keys, (v) => _text(v, max));
    i.title = txt(['name', 'o_name'], 300);
    i.plot = txt(['plot', 'description'], 4000);
    i.cast = txt(['cast', 'actors'], 500);
    i.director = txt(['director'], 200);
    i.genre = txt(['genre'], 200);
    i.country = txt(['country'], 100);
    final date = pick(['releasedate', 'release_date', 'releaseDate', 'year'], _date);
    if (date != null) {
      i.releaseDate = date.$1;
      i.year = date.$2;
    }
    i.rating = _rating(d);
    i.durationMinutes = _minutes(d);
    i.trailerID = pick(['youtube_trailer'], _trailer);
    i.posterURL = _image(['movie_image', 'cover_big', 'cover'], d);
    i.backdropURL = _image(['backdrop_path', 'backdrop'], d);
    return i;
  }

  /// The cache row. Keys and absent-when-null match the Apple apps' Codable output.
  Map<String, dynamic> toJson() => {
        'title': ?title,
        'plot': ?plot,
        'cast': ?cast,
        'director': ?director,
        'genre': ?genre,
        'country': ?country,
        'releaseDate': ?releaseDate,
        'year': ?year,
        'rating': ?rating,
        'durationMinutes': ?durationMinutes,
        'trailerID': ?trailerID,
        'posterURL': ?posterURL?.toString(),
        'backdropURL': ?backdropURL?.toString(),
      };

  /// Throws on a value of the wrong type (the caller treats that row as missing); missing keys are fine.
  factory ItemInfo.fromJson(Map<String, dynamic> j) {
    Uri? uri(String k) => j[k] == null ? null : Uri.parse(j[k] as String);
    return ItemInfo()
      ..title = j['title'] as String?
      ..plot = j['plot'] as String?
      ..cast = j['cast'] as String?
      ..director = j['director'] as String?
      ..genre = j['genre'] as String?
      ..country = j['country'] as String?
      ..releaseDate = j['releaseDate'] as String?
      ..year = j['year'] as int?
      ..rating = (j['rating'] as num?)?.toDouble()
      ..durationMinutes = j['durationMinutes'] as int?
      ..trailerID = j['trailerID'] as String?
      ..posterURL = uri('posterURL')
      ..backdropURL = uri('backdropURL');
  }

  /// Anything worth a details page. Images do not count: the list already shows the poster.
  bool get hasContent =>
      plot != null || cast != null || director != null || genre != null || country != null || year != null ||
      rating != null || durationMinutes != null || trailerID != null;

  /// Always built by us from the validated id, never taken from the provider.
  Uri? get trailerURL => trailerID != null && isVideoID(trailerID!) ? Uri.parse('https://www.youtube.com/watch?v=$trailerID') : null;

  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{6,20}$');
  static bool isVideoID(String s) => _videoId.hasMatch(s);

  // Tolerant readers (strings, numbers, arrays, null, booleans: whatever the panel sent).

  static String? _string(Object? v) {
    if (v is bool) return null;
    if (v is List) return v.take(50).map(_string).nonNulls.join(', ');
    final s = str(v);
    return s == null ? null : (s.length > 20000 ? s.substring(0, 20000) : s); // a hostile value never costs more than this
  }

  /// Plain text only: no control or bidi-override characters, blank runs shortened, capped. Shown verbatim, never
  /// interpreted.
  static String? _text(Object? v, int max) {
    final raw = _string(v);
    if (raw == null) return null;
    final out = StringBuffer();
    for (final c in _prefix(raw, max * 4).replaceAll('\r\n', '\n').runes) {
      if (c == 0x0A || c == 0x09) {
        out.writeCharCode(c);
      } else if (c == 0x0D || c == 0x2028 || c == 0x2029) {
        out.write('\n');
      } else if ((c >= 0x202A && c <= 0x202E) || (c >= 0x2066 && c <= 0x2069)) {
        continue;
      } else if (c < 0x20 || (c >= 0x7F && c <= 0x9F)) {
        continue; // Unicode "control" characters
      } else {
        out.writeCharCode(c);
      }
    }
    var s = out.toString().trim();
    while (s.contains('\n\n\n')) {
      s = s.replaceAll('\n\n\n', '\n\n');
    }
    if (s.runes.length > max) s = '${_prefix(s, max - 1).trim()}…';
    return s.isEmpty ? null : s;
  }

  static String _prefix(String s, int n) => s.length <= n ? s : String.fromCharCodes(s.runes.take(n));

  static final _number = RegExp(r'-?\d+(?:[.,]\d+)?');
  static double? _firstNumber(String? s) {
    final m = s == null ? null : _number.firstMatch(s);
    return m == null ? null : double.tryParse(m.group(0)!.replaceAll(',', '.'));
  }

  static final _yearPattern = RegExp(r'(?<!\d)(?:18|19|20)\d{2}(?!\d)');
  static (String, int)? _date(Object? v) {
    final s = _text(v, 40);
    final m = s == null ? null : _yearPattern.firstMatch(s);
    return m == null ? null : (s!, int.parse(m.group(0)!));
  }

  static double _round1(double x) => (x * 10).round() / 10;

  static double? _rating(Map d) {
    final r = _firstNumber(_string(d['rating']));
    if (r != null && r > 0 && r <= 100) return _round1(r <= 10 ? r : r / 10); // a few panels use 0-100
    final five = _firstNumber(_string(d['rating_5based']));
    if (five != null && five > 0 && five <= 5) return _round1(five * 2);
    return null;
  }

  /// Minutes from seconds, "01:45:00", "105 min", "1h 45m" or a bare number (more than 600 is seconds). Over 24 h is a
  /// broken value.
  static int? _minutes(Map d) {
    int? ok(double m) => m.isFinite && m >= 0.5 && m <= 1440 ? m.round() : null;
    int? count(RegExp pattern, String s) {
      final m = pattern.firstMatch(s);
      return m == null ? null : int.tryParse(m.group(0)!.replaceAll(RegExp(r'\D'), ''));
    }

    int? parse(String s) {
      if (s.contains(':')) {
        final p = [for (final x in s.split(':')) double.tryParse(x.trim())];
        if ((p.length != 2 && p.length != 3) || p.contains(null)) return null;
        final v = p.nonNulls.toList();
        return ok((v[0] * 3600 + v[1] * 60 + (v.length == 3 ? v[2] : 0)) / 60);
      }
      final h = count(RegExp(r'\d+\s*h'), s), m = count(RegExp(r'\d+\s*m'), s);
      if (h != null || m != null) return ok((h ?? 0) * 60.0 + (m ?? 0));
      final n = _firstNumber(s);
      return n == null ? null : ok(n > 600 ? n / 60 : n);
    }

    final secs = _firstNumber(_string(d['duration_secs']));
    final fromSecs = secs == null ? null : ok(secs / 60);
    if (fromSecs != null) return fromSecs;
    for (final k in ['duration', 'runtime', 'episode_run_time']) {
      final s = _string(d[k]);
      final r = s == null ? null : parse(s);
      if (r != null) return r;
    }
    return null;
  }

  /// A video id, or a link to one on YouTube (from which only the id is kept).
  static String? _trailer(Object? v) {
    final s = _string(v)?.trim();
    if (s == null || s.length > 300) return null;
    if (isVideoID(s)) return s;
    final u = Uri.tryParse(s);
    if (u == null || (u.scheme != 'http' && u.scheme != 'https')) return null;
    final path = u.pathSegments.where((p) => p.isNotEmpty).toList();
    String? id;
    switch (u.host.toLowerCase()) {
      case 'youtu.be':
        id = path.firstOrNull;
      case 'youtube.com' || 'www.youtube.com' || 'm.youtube.com':
        if (path.length == 1 && path[0] == 'watch') {
          try {
            id = u.queryParameters['v'];
          } on FormatException {
            id = null;
          }
        } else if (path.length == 2 && path[0] == 'embed') {
          id = path[1];
        }
    }
    return id != null && isVideoID(id) ? id : null;
  }

  /// The first safe link among the fields; a value may be a string or an array (`backdrop_path`), possibly empty.
  static Uri? _image(List<String> keys, Map d) {
    Iterable<String> links(Object? v) =>
        v is List ? v.take(20).expand(links) : [if (str(v) != null) str(v)!];
    for (final k in keys) {
      for (final l in links(d[k])) {
        final u = safeImageUrl(l);
        if (u != null) return u;
      }
    }
    return null;
  }

  (String?, String?, String?, String?, String?, String?, String?, int?, double?, int?, String?, Uri?, Uri?) get _t =>
      (title, plot, cast, director, genre, country, releaseDate, year, rating, durationMinutes, trailerID, posterURL, backdropURL);
  @override
  bool operator ==(Object other) => other is ItemInfo && other._t == _t;
  @override
  int get hashCode => _t.hashCode;
}

/// The cache behind `SyncService.info`: parsed details per (playlist, type, stream id), valid for 14 days.
abstract final class ItemInfoStore {
  static const ttl = Duration(days: 14);

  /// `maxAge: null` also returns an expired copy (for when the network fails). A row that cannot be read counts as missing.
  static ItemInfo? cached(Database db,
      {required int accountId, required ItemType type, required String streamId, DateTime? now, Duration? maxAge = ttl}) {
    final rows = db.select('SELECT json, fetched FROM item_info WHERE accountId=? AND type=? AND streamId=?',
        [accountId, type.name, streamId]);
    if (rows.isEmpty) return null;
    final fetched = parseDbDate(rows.first['fetched'] as String);
    if (maxAge != null && (now ?? DateTime.now()).difference(fetched) > maxAge) return null;
    final ItemInfo info;
    try {
      info = ItemInfo.fromJson((jsonDecode(rows.first['json'] as String) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
    // The row outlives the app version that wrote it: links and the video id are checked again, whatever the file says.
    info.posterURL = safeImageUrl(info.posterURL?.toString());
    info.backdropURL = safeImageUrl(info.backdropURL?.toString());
    if (info.trailerID != null && !ItemInfo.isVideoID(info.trailerID!)) info.trailerID = null;
    return info;
  }

  static void save(Database db,
      {required int accountId, required ItemType type, required String streamId, required ItemInfo info, DateTime? now}) {
    final t = now ?? DateTime.now();
    db.execute('DELETE FROM item_info WHERE fetched < ?', [dbDate(t.subtract(ttl))]); // titles nobody opens do not pile up
    db.execute('''
      INSERT INTO item_info (accountId,type,streamId,json,fetched) VALUES (?,?,?,?,?)
      ON CONFLICT(accountId,type,streamId) DO UPDATE SET json=excluded.json, fetched=excluded.fetched
      ''', [accountId, type.name, streamId, jsonEncode(info.toJson()), dbDate(t)]);
  }
}
