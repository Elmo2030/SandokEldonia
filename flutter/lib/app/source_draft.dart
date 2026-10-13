import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/core/xtream_urls.dart';

/// The add-source form as plain data (port of SourceDraft.swift): what is complete, what looks wrong while typing, and what
/// a pasted link means.
class SourceDraft {
  SourceDraft({this.kind = AccountKind.xtream, this.name = '', this.server = '', this.username = '', this.password = '', this.url = ''});

  AccountKind kind;
  String name, server, username, password, url;

  bool get isComplete =>
      name.trim().isNotEmpty && (kind == AccountKind.xtream ? server.isNotEmpty && username.isNotEmpty : url.isNotEmpty);

  /// An Xtream server the app cannot build addresses from (only judged once something is typed).
  bool get serverLooksWrong {
    final s = server.trim();
    return s.isNotEmpty && XtreamURLs.parse(server: s, username: 'u', password: 'p') == null;
  }

  /// A playlist link must be a full http(s) address (an Xtream server may be typed without the scheme, a link may not).
  bool get urlLooksWrong {
    final s = url.trim();
    return s.isNotEmpty && !isWebLink(s);
  }

  bool get canTest => isComplete && (kind == AccountKind.xtream ? !serverLooksWrong : !urlLooksWrong);

  static bool isWebLink(String s) {
    final u = Uri.tryParse(s.trim());
    return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
  }

  /// Providers hand out one link that holds the whole login: `http://host:8080/get.php?username=u&password=p&type=m3u_plus`.
  static ({String server, String username, String password})? xtreamLogin(String link) {
    final s = link.trim();
    if (!isWebLink(s)) return null;
    final u = Uri.parse(s);
    final path = u.path.toLowerCase();
    if (!path.endsWith('/get.php') && !path.endsWith('/player_api.php')) return null;
    final user = u.queryParameters['username'], pass = u.queryParameters['password'];
    if (user == null || user.isEmpty || pass == null) return null;
    return (server: '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}', username: user, password: pass);
  }

  /// A pasted provider link fills the form: the whole Xtream login when the link holds one, else the playlist link.
  void applyPasted(String pasted) {
    final s = pasted.trim();
    final login = xtreamLogin(s);
    if (login != null) {
      kind = AccountKind.xtream;
      server = login.server;
      username = login.username;
      password = login.password;
    } else if (isWebLink(s)) {
      kind = AccountKind.m3u;
      url = s;
    } else if (kind == AccountKind.xtream && server.isEmpty) {
      server = s;
    }
    if (name.isEmpty) {
      final host = Uri.tryParse(server.isEmpty ? url : server)?.host;
      if (host != null && host.isNotEmpty) name = host;
    }
  }

  /// The account to save and the password to keep apart from it (it never goes into the database row).
  ({Account account, String? password}) makeAccount() {
    final n = name.trim();
    return kind == AccountKind.xtream
        ? (account: Account(name: n, kind: AccountKind.xtream, server: server.trim(), username: username.trim()), password: password)
        : (account: Account(name: n, kind: AccountKind.m3u, url: url.trim()), password: null);
  }
}
