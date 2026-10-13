import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_session.dart';
import 'errors.dart';
import 'item_info.dart';
import 'json_util.dart';
import 'models.dart';
import 'xtream_urls.dart';

class XtreamClient {
  XtreamClient(this.urls, {http.Client? client}) : client = client ?? http.Client();

  final XtreamURLs urls;
  final http.Client client;

  /// The decoded JSON of an endpoint (null for an empty body).
  Future<Object?> json(Uri url) async {
    final data = await apiGet(client, url);
    if (data.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(data));
    } on FormatException {
      throw IPTVError.badResponse;
    }
  }

  /// A list endpoint. Panels answer `null`, `false` or an empty body for a section they do not have (e.g. no series).
  Future<List<Map<String, dynamic>>> array(String action, [Map<String, String> params = const {}]) async {
    final o = await json(urls.api(action, params));
    if (o == null || o is bool) return const [];
    return objectList(o) ?? (throw IPTVError.badResponse);
  }

  Future<void> authenticate() async {
    final o = await json(urls.api(null));
    final u = o is Map ? o['user_info'] : null;
    if (u is! Map) throw IPTVError.badResponse;
    if (intOf(u['auth']) != 1) throw IPTVError.badCredentials;
    final status = str(u['status'])?.toLowerCase();
    if (status == 'expired' || status == 'disabled' || status == 'banned') throw IPTVError.accountInactive;
  }

  /// The time zone name the panel uses for timeshift URLs (`server_info.timezone`, e.g. "Europe/Paris"), or null if
  /// unknown. Not validated here: there is no time zone database in the core (see `XtreamURLs.timeshift`).
  Future<String?> serverTimeZoneName() async {
    try {
      final o = await json(urls.api(null));
      final info = o is Map ? o['server_info'] : null;
      return info is Map ? str(info['timezone']) : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Object?>> _listings(String action, String id, [Map<String, String> extra = const {}]) async {
    final o = await json(urls.api(action, {'stream_id': id, ...extra}));
    if (o is! Map) throw IPTVError.badResponse;
    final l = o['epg_listings'];
    return l is List ? l : const [];
  }

  EPGEntry? _entry(Object? d) {
    if (d is! Map) return null;
    final t = str(d['title']);
    final s = intOf(d['start_timestamp']), e = intOf(d['stop_timestamp']);
    if (t == null || s == null || e == null) return null;
    final String title;
    try {
      title = utf8.decode(base64.decode(t));
    } on FormatException {
      return null;
    }
    return EPGEntry(
        title: title,
        start: DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true),
        end: DateTime.fromMillisecondsSinceEpoch(e * 1000, isUtc: true));
  }

  /// The current and upcoming programs of a live channel.
  Future<List<EPGEntry>> epgShort(String streamId, int limit) async =>
      [for (final d in await _listings('get_short_epg', streamId, {'limit': '$limit'})) ?_entry(d)];

  Future<String?> epgNow(String streamId) async => (await epgShort(streamId, 1)).firstOrNull?.title;

  Future<List<EPGEntry>> epgArchive(String streamId) async =>
      [for (final d in await _listings('get_simple_data_table', streamId)) ?_entry(d)];

  /// The whole `get_series_info` answer (episodes and details).
  Future<Map<String, dynamic>> rawSeriesInfo(String id) async {
    final o = await json(urls.api('get_series_info', {'series_id': id}));
    if (o is! Map) throw IPTVError.badResponse;
    return o.cast<String, dynamic>();
  }

  /// Panels answer `[]`, `null` or `false` for a title they know nothing about: that is "no details", not an error.
  Future<ItemInfo> _details(String action, Map<String, String> params) async {
    final o = await json(urls.api(action, params));
    return ItemInfo.fromResponse(o is Map ? o.cast<String, dynamic>() : const {});
  }

  Future<ItemInfo> vodInfo(String streamId) => _details('get_vod_info', {'vod_id': streamId});
  Future<ItemInfo> seriesInfo(String seriesId) => _details('get_series_info', {'series_id': seriesId});
}
