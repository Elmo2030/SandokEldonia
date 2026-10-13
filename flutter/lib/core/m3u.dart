import 'dart:convert';

import 'json_util.dart';
import 'models.dart';

class M3UEntry {
  const M3UEntry({required this.name, required this.url, this.group, this.logo, this.tvgId, this.catchupDays});

  final String name, url;
  final String? group, logo, tvgId;
  final int? catchupDays;

  (String, String, String?, String?, String?, int?) get _t => (name, url, group, logo, tvgId, catchupDays);
  @override
  bool operator ==(Object other) => other is M3UEntry && other._t == _t;
  @override
  int get hashCode => _t.hashCode;
}

/// Line by line: feed every line of the playlist, an entry comes back for each URL line.
class M3UParser {
  ({String name, Map<String, String> attrs})? _pending;
  static final _attr = RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');

  M3UEntry? feed(String raw) {
    var line = raw.trim();
    if (line.startsWith('﻿')) line = line.substring(1);
    if (line.isEmpty || line.startsWith('#EXTM3U')) return null;
    if (line.startsWith('#EXTINF')) {
      _pending = _parseInf(line);
      return null;
    }
    if (line.startsWith('#')) return null;
    final info = _pending;
    _pending = null;
    // Never use the URL itself as the title: it carries the account's username and password.
    final fallback = fallbackName(line);
    final attrs = info?.attrs ?? const <String, String>{};
    final name = info == null || info.name.isEmpty ? fallback : info.name;
    String? attr(String k) => attrs[k] == null || attrs[k]!.isEmpty ? null : attrs[k];
    return M3UEntry(
        name: name, url: line, group: attr('group-title'), logo: attr('tvg-logo'), tvgId: attr('tvg-id'),
        catchupDays: parseInt(attr('catchup-days')));
  }

  /// Last path component without query/userinfo, or a neutral label.
  static String fallbackName(String url) {
    final last = (Uri.tryParse(url)?.pathSegments ?? const <String>[]).where((s) => s.isNotEmpty).lastOrNull;
    return last ?? 'Channel';
  }

  static ({String name, Map<String, String> attrs}) _parseInf(String line) {
    // A crafted multi-hundred-KB "attribute" line makes the regex scan quadratic: real lines are far shorter.
    if (line.length > 2730 && utf8.encode(line).length > 8192) return (name: '', attrs: const {});
    var inQuote = false;
    var comma = -1;
    for (var i = 0; i < line.length; i++) {
      final c = line.codeUnitAt(i);
      if (c == 0x22) {
        inQuote = !inQuote;
      } else if (c == 0x2C && !inQuote) {
        comma = i;
        break;
      }
    }
    final head = comma < 0 ? line : line.substring(0, comma);
    final name = comma < 0 ? '' : line.substring(comma + 1).trim();
    return (name: name, attrs: {for (final m in _attr.allMatches(head)) m.group(1)!: m.group(2)!});
  }
}

abstract final class M3UClassifier {
  // ponytail: heuristic only, no per-category override in v1; add a settings override if misclassified lists show up.
  static ItemType type({required String url, String? group}) {
    final u = url.toLowerCase();
    if (u.contains('/movie/')) return ItemType.movie;
    if (u.contains('/series/')) return ItemType.series;
    final g = (group ?? '').toLowerCase();
    if (['series', 'tv show', 'סדר'].any(g.contains)) return ItemType.series;
    if (['vod', 'movie', 'film', 'סרט'].any(g.contains)) return ItemType.movie;
    if (['.mp4', '.mkv', '.avi'].any(u.endsWith)) return ItemType.movie;
    return ItemType.live;
  }
}
