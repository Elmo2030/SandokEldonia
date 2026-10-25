import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_session.dart';
import 'app_database.dart';
import 'errors.dart';
import 'item_info.dart';
import 'json_util.dart';
import 'm3u.dart';
import 'models.dart';
import 'sync_meter.dart';
import 'xtream_client.dart';
import 'xtream_urls.dart';

/// Loads a playlist into the database, and the per-title data (episodes, details). Pass an `http.Client` to inject a fake in
/// tests. The password is not stored on the account: the caller gets it from its `SecretStore`.
///
/// The JSON is decoded and the rows are inserted on the calling isolate: on a phone call `sync` from a background isolate
/// (with its own `AppDatabase.open` of the same file) so the UI stays smooth.
class SyncService {
  SyncService(this.db, {http.Client? client}) : _client = client ?? http.Client();

  final AppDatabase db;
  final http.Client _client;

  /// [onProgress] is told how far the sync is, 0..1 and never backwards: the login 5%, each of the three Xtream lists 20% (an M3U
  /// download 50%), the decoded rows 70%, then the last 30% is the writing, counted in rows.
  Future<void> sync(Account account, {String? password, void Function(double fraction)? onProgress}) async {
    final aid = account.id;
    if (aid == null) throw IPTVError.badConfig;
    final meter = SyncMeter(onProgress);
    final (cats, items) = switch (account.kind) {
      AccountKind.xtream => await _fetchXtream(account, aid, password ?? '', meter),
      AccountKind.m3u => await _fetchM3U(account, aid, meter),
    };
    meter.reach(0.7);
    if (items.isEmpty) throw IPTVError.emptyResponse; // expired subscription / overloaded panel / nothing there: keep what we have
    // Only the types that came back with items are replaced: a panel that answers [] for one section while it rebuilds its
    // cache must not wipe that section (and the favorites that point into it).
    final typeList = items.map((i) => i.type).toSet().map((t) => "'${t.name}'").join(','); // our own enum, not user input
    final had = db.read((d) => d.select('SELECT DISTINCT type FROM item WHERE accountId = ?', [aid])).map((r) => r['type']).toSet();
    db.write((d) {
      d.execute('UPDATE item SET stale = 1 WHERE accountId = ? AND type IN ($typeList)', [aid]);
      d.execute('DELETE FROM category WHERE accountId = ? AND type IN ($typeList)', [aid]);
      for (final c in cats) {
        c.insert(d);
      }
      final st = d.prepare('''
        INSERT INTO item (accountId,type,name,categoryId,icon,rating,streamId,containerExt,directURL,tvArchive,archiveDays,epgChannelId,stale)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,0)
        ON CONFLICT(accountId,type,streamId) DO UPDATE SET
          name=excluded.name, categoryId=excluded.categoryId, icon=excluded.icon, rating=excluded.rating,
          containerExt=excluded.containerExt, directURL=excluded.directURL, tvArchive=excluded.tvArchive,
          archiveDays=excluded.archiveDays, epgChannelId=excluded.epgChannelId, stale=0
        ''');
      try {
        var n = 0;
        for (final i in items) {
          st.execute([aid, i.type.name, i.name, i.categoryId, i.icon, i.rating, i.streamId, i.containerExt, i.directURL,
              i.tvArchive, i.archiveDays, i.epgChannelId]);
          if (++n % 2000 == 0) meter.reach(0.7 + 0.3 * n / items.length);
        }
      } finally {
        st.close();
      }
      d.execute('DELETE FROM item WHERE accountId = ? AND stale = 1', [aid]);
    });
    meter.reach(1);
    // The rest is stored; tell the user that a section that used to be there came back empty (a provider that is rebuilding or limiting).
    if (had.any((t) => !items.any((i) => i.type.name == t))) throw IPTVError.partialResponse;
  }

  // Xtream

  Future<(List<Category>, List<Item>)> _fetchXtream(Account account, int aid, String password, SyncMeter meter) async {
    final urls = XtreamURLs.parse(server: account.server ?? '', username: account.username ?? '', password: password);
    if (urls == null) throw IPTVError.badConfig;
    final client = XtreamClient(urls, client: _client);
    await client.authenticate();
    meter.reach(0.05);
    final lists = await Future.wait([for (final t in ItemType.values) _fetchType(client, t, meter)]);
    final cats = <Category>[], items = <Item>[];
    for (final (type, rawCats, rawStreams) in lists) {
      for (final c in rawCats) {
        final id = str(c['category_id']);
        if (id == null) continue;
        cats.add(Category(accountId: aid, type: type, remoteId: id, name: str(c['category_name']) ?? id));
      }
      final idKey = type == ItemType.series ? 'series_id' : 'stream_id';
      for (final d in rawStreams) {
        final sid = str(d[idKey]);
        if (sid == null) continue;
        items.add(Item(
          accountId: aid,
          type: type,
          name: str(d['name']) ?? sid,
          streamId: sid,
          categoryId: str(d['category_id']),
          icon: str(type == ItemType.series ? d['cover'] : d['stream_icon']),
          rating: str(d['rating']),
          containerExt: str(d['container_extension']),
          tvArchive: intOf(d['tv_archive']) == 1,
          archiveDays: intOf(d['tv_archive_duration']) ?? 0,
          epgChannelId: str(d['epg_channel_id']),
        ));
      }
    }
    return (cats, items);
  }

  Future<(ItemType, List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _fetchType(XtreamClient c, ItemType t, SyncMeter meter) async {
    final (ca, sa) = switch (t) {
      ItemType.live => ('get_live_categories', 'get_live_streams'),
      ItemType.movie => ('get_vod_categories', 'get_vod_streams'),
      ItemType.series => ('get_series_categories', 'get_series'),
    };
    final r = await Future.wait([c.array(ca), c.array(sa)]);
    meter.advance(0.2); // the three lists finish in any order
    return (t, r[0], r[1]);
  }

  // M3U

  // ponytail: whole playlist held in memory; switch to a streamed download if lists above ~100 MB show up.
  Future<(List<Category>, List<Item>)> _fetchM3U(Account account, int aid, SyncMeter meter) async {
    final url = Uri.tryParse(account.url?.trim() ?? '');
    if (url == null || !url.hasScheme || url.host.isEmpty) throw IPTVError.badConfig;
    final text = utf8.decode(await apiGet(_client, url), allowMalformed: true);
    meter.reach(0.5);
    var start = 0;
    while (start < text.length && (text[start].trim().isEmpty || text[start] == '﻿')) {
      start++;
    }
    if (!text.startsWith('#EXTM3U', start)) throw IPTVError.badResponse;

    final parser = M3UParser();
    final items = <Item>[], cats = <Category>[];
    final seenCats = <String>{}, seenItems = <String>{};
    for (final line in text.split(RegExp(r'\r\n|[\n\r\u0085  \u000B\u000C]'))) {
      final e = parser.feed(line);
      if (e == null) continue;
      // ponytail: no catch-up for M3U (timeshift URLs are Xtream-only); the attribute is ignored on purpose.
      final type = M3UClassifier.type(url: e.url, group: e.group);
      if (!seenItems.add('${type.name}|${e.url}')) continue; // same URL in two groups: the first group keeps it
      final g = e.group;
      if (g != null && seenCats.add('${type.name}|$g')) {
        cats.add(Category(accountId: aid, type: type, remoteId: g, name: g));
      }
      items.add(Item(accountId: aid, type: type, name: e.name, streamId: e.url, categoryId: g, icon: e.logo, directURL: e.url, epgChannelId: e.tvgId));
    }
    return (cats, items);
  }

  // Episodes

  Future<List<Episode>> episodes(Account account, {String? password, required String seriesId}) async {
    final aid = account.id;
    if (aid == null) throw IPTVError.badConfig;
    List<Episode> cached() => db.read((d) => [
          for (final r in d.select('SELECT * FROM episode WHERE accountId = ? AND seriesId = ? ORDER BY season, number', [aid, seriesId]))
            Episode.fromRow(r)
        ]);
    final urls = XtreamURLs.parse(server: account.server ?? '', username: account.username ?? '', password: password ?? '');
    if (urls == null) return cached();
    try {
      final info = await XtreamClient(urls, client: _client).rawSeriesInfo(seriesId);
      final raw = <Map<String, dynamic>>[];
      final eps = info['episodes'];
      if (eps is Map) {
        final keys = eps.keys.cast<String>().toList()..sort((a, b) => (parseInt(a) ?? 0).compareTo(parseInt(b) ?? 0));
        for (final k in keys) {
          raw.addAll(objectList(eps[k]) ?? const []);
        }
      } else if (eps is List && eps.every((s) => s is List)) {
        for (final s in eps.cast<List>()) {
          raw.addAll(s.whereType<Map>().map((m) => m.cast<String, dynamic>()));
        }
      } else {
        throw IPTVError.badResponse;
      }
      final found = <Episode>[];
      for (final d in raw) {
        final id = str(d['id']);
        if (id == null) continue;
        final n = intOf(d['episode_num']);
        found.add(Episode(
            accountId: aid, seriesId: seriesId, season: intOf(d['season']) ?? 1, number: n ?? 0,
            title: str(d['title']) ?? 'Episode ${n ?? 0}', streamId: id, containerExt: str(d['container_extension'])));
      }
      final details = ItemInfo.fromResponse(info); // the same response also carries the series details
      db.write((d) {
        if (details.hasContent) {
          ItemInfoStore.save(d, accountId: aid, type: ItemType.series, streamId: seriesId, info: details);
        }
        if (found.isNotEmpty) {
          // episodes the provider no longer lists must not be served from the cache
          d.execute('DELETE FROM episode WHERE accountId = ? AND seriesId = ? AND streamId NOT IN (SELECT value FROM json_each(?))',
              [aid, seriesId, jsonEncode([for (final e in found) e.streamId])]);
        }
        for (final e in found) {
          d.execute('''
            INSERT INTO episode (accountId,seriesId,season,number,title,streamId,containerExt) VALUES (?,?,?,?,?,?,?)
            ON CONFLICT(accountId,streamId) DO UPDATE SET seriesId=excluded.seriesId, season=excluded.season,
              number=excluded.number, title=excluded.title, containerExt=excluded.containerExt
            ''', [e.accountId, e.seriesId, e.season, e.number, e.title, e.streamId, e.containerExt]);
        }
      });
      return cached();
    } catch (_) {
      final c = cached();
      if (c.isEmpty) rethrow;
      return c;
    }
  }

  // Details

  /// What the provider says about a movie or series (Xtream only; M3U has nothing): from the cache for 14 days, else
  /// fetched. A failed fetch falls back to an older cached copy. An answer without details is not cached, so reopening
  /// tries again.
  Future<ItemInfo> info(Account account,
      {String? password, required ItemType type, required String streamId, DateTime? now, bool refresh = false}) async {
    final aid = account.id;
    if (aid == null || account.kind != AccountKind.xtream || type == ItemType.live) return ItemInfo();
    ItemInfo? cached(Duration? maxAge) =>
        db.read((d) => ItemInfoStore.cached(d, accountId: aid, type: type, streamId: streamId, now: now, maxAge: maxAge));
    if (!refresh) {
      final hit = cached(ItemInfoStore.ttl);
      if (hit != null) return hit;
    }
    final urls = XtreamURLs.parse(server: account.server ?? '', username: account.username ?? '', password: password ?? '');
    if (urls == null) throw IPTVError.badConfig;
    try {
      final client = XtreamClient(urls, client: _client);
      final info = type == ItemType.movie ? await client.vodInfo(streamId) : await client.seriesInfo(streamId);
      if (info.hasContent) {
        db.write((d) => ItemInfoStore.save(d, accountId: aid, type: type, streamId: streamId, info: info, now: now));
      }
      return info;
    } catch (_) {
      final stale = cached(null);
      if (stale != null) return stale;
      rethrow;
    }
  }
}
