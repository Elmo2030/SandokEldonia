import 'dart:async';
import 'dart:collection';

import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/core/xtream_client.dart';
import 'package:iptvmac/core/xtream_urls.dart';

/// "Now" and "next" per live channel (keyed by playlist and stream id): refreshed after 5 minutes, one request per channel at a
/// time and at most [parallel] at once (a screen of rows would otherwise open a dozen connections to the provider).
class EpgCache {
  EpgCache({this.parallel = 4, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final int parallel;
  final DateTime Function() _clock;
  final _entries = <String, List<EPGEntry>>{};
  final _stamp = <String, DateTime>{};
  final _inFlight = <String>{};
  final _waiting = Queue<Completer<void>>();
  var _active = 0;

  static String key(Item i) => '${i.accountId}:${i.streamId}';

  EPGEntry? now(Item i) => _entries[key(i)]?.firstOrNull;
  ({EPGEntry? now, EPGEntry? next}) programs(Item i) {
    final l = _entries[key(i)] ?? const [];
    return (now: l.firstOrNull, next: l.length > 1 ? l[1] : null);
  }

  /// Returns true when something new was stored (the caller then redraws).
  Future<bool> load(Item item, XtreamURLs? urls, XtreamClient Function(XtreamURLs) clientFor) async {
    final k = key(item);
    if (item.type != ItemType.live || urls == null || _inFlight.contains(k)) return false;
    final t = _stamp[k];
    if (t != null && _clock().difference(t) < const Duration(minutes: 5)) return false;
    _inFlight.add(k);
    try {
      if (_active >= parallel) {
        final c = Completer<void>();
        _waiting.add(c);
        await c.future;
      } else {
        _active++;
      }
      try {
        _entries[k] = await clientFor(urls).epgShort(item.streamId, 2);
      } catch (_) {
        _entries[k] = const [];
      }
      _stamp[k] = _clock();
      return true;
    } finally {
      _inFlight.remove(k);
      if (_waiting.isEmpty) {
        if (_active > 0) _active--;
      } else {
        _waiting.removeFirst().complete(); // hands its slot to the next waiting row
      }
    }
  }
}
