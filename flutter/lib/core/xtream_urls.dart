import 'dart:convert';

import 'models.dart';

/// Builds every Xtream URL from what the user typed. `XtreamURLs.parse` returns null for an unusable server address.
class XtreamURLs {
  XtreamURLs._(this._base, this._user, this._pass);

  final String _base, _user, _pass;

  static const _tails = ['/player_api.php', '/get.php', '/xmltv.php', '/panel_api.php', '/c'];

  static XtreamURLs? parse({required String server, required String username, required String password}) {
    var s = server.trim();
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) s = 'http://$s';
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty) return null;
    // Users paste whatever the provider showed: ".../get.php?username=..&password=.." or ".../player_api.php?..": keep the
    // server only (no query, fragment or userinfo).
    var path = u.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    for (final tail in _tails) {
      if (path.toLowerCase().endsWith(tail)) {
        path = path.substring(0, path.length - tail.length);
        break;
      }
    }
    final host = u.host.contains(':') ? '[${u.host}]' : u.host;
    var base = '${u.scheme}://$host${u.hasPort ? ':${u.port}' : ''}$path';
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    // A trailing space or newline pasted with the credentials would make a correct login look wrong.
    return XtreamURLs._(base, _enc(username.trim()), _enc(password.trim()));
  }

  /// Percent-encodes everything but the unreserved characters (a password may hold `/`, `&`, `+`, `@`).
  static String _enc(String s) {
    final b = StringBuffer();
    for (final c in utf8.encode(s)) {
      final unreserved = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x2D || c == 0x2E || c == 0x5F || c == 0x7E;
      b.write(unreserved ? String.fromCharCode(c) : '%${c.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
    return b.toString();
  }

  static String _ext(String? ext) => ext == null || ext.isEmpty ? 'mp4' : _enc(ext);

  Uri live(String id, {String ext = 'ts'}) => Uri.parse('$_base/live/$_user/$_pass/${_enc(id)}.${_enc(ext)}');
  Uri movie(String id, String? ext) => Uri.parse('$_base/movie/$_user/$_pass/${_enc(id)}.${_ext(ext)}');
  Uri series(String id, String? ext) => Uri.parse('$_base/series/$_user/$_pass/${_enc(id)}.${_ext(ext)}');

  Uri stream(ItemType type, String id, String? ext) => switch (type) {
        ItemType.live => live(id),
        ItemType.movie => movie(id, ext),
        ItemType.series => series(id, ext),
      };

  /// Catch-up URL. The panel wants the start time in ITS time zone: pass that zone's UTC offset at [start] (the zone name
  /// is `XtreamClient.serverTimeZoneName`; resolving it to an offset needs a time zone database, which the shell has).
  Uri timeshift(String id, DateTime start, int minutes, {Duration utcOffset = Duration.zero}) {
    final t = start.toUtc().add(utcOffset);
    String p(int v) => v.toString().padLeft(2, '0');
    final stamp = '${t.year.toString().padLeft(4, '0')}-${p(t.month)}-${p(t.day)}:${p(t.hour)}-${p(t.minute)}';
    return Uri.parse('$_base/timeshift/$_user/$_pass/$minutes/$stamp/${_enc(id)}.ts');
  }

  Uri api(String? action, [Map<String, String> params = const {}]) {
    final q = StringBuffer('username=$_user&password=$_pass');
    if (action != null) q.write('&action=$action');
    for (final k in params.keys.toList()..sort()) {
      q.write('&$k=${_enc(params[k]!)}');
    }
    return Uri.parse('$_base/player_api.php?$q');
  }
}
