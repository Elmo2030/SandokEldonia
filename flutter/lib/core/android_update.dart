import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_session.dart';

/// GitHub's own feed of the releases: plain github.com, so none of the 60-requests-an-hour limit of the API that made the Mac updater
/// switch to release.txt. The Android releases are published as "not the latest", so `releases/latest` cannot be used for them.
const androidReleasesFeed = 'https://github.com/Goelir/IPTVMac/releases.atom';

final _tag = RegExp(r'/releases/tag/android-v(\d{1,4})\.(\d{1,4})\.(\d{1,4})(?=["\s<])');

/// The newest stable Android version the feed names, e.g. "1.0.2", or null. The Mac releases and the pre-releases
/// ("android-v0.1.0-beta.1") do not match. Only three numbers are taken from the feed, never a link.
String? newestAndroidVersion(String feed) {
  List<int>? best;
  for (final m in _tag.allMatches(feed)) {
    final v = [for (var i = 1; i <= 3; i++) int.parse(m[i]!)];
    if (best == null || _compare(v, best) > 0) best = v;
  }
  return best?.join('.');
}

List<int>? _parse(String v) {
  final m = RegExp(r'^(\d{1,4})\.(\d{1,4})\.(\d{1,4})').firstMatch(v);
  return m == null ? null : [for (var i = 1; i <= 3; i++) int.parse(m[i]!)];
}

int _compare(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return 0;
}

/// [candidate] is a higher version than [current] ("1.0.3" vs "1.0.2"; a build suffix like "+5" is ignored). False when either is not a version.
bool isNewerVersion(String candidate, String current) {
  final a = _parse(candidate), b = _parse(current);
  return a != null && b != null && _compare(a, b) > 0;
}

/// The page of a release, built from a version that passed [newestAndroidVersion]: the app never opens an address taken from the feed.
Uri androidReleasePage(String version) {
  if (_parse(version) == null || _parse(version)!.join('.') != version) throw ArgumentError.value(version, 'version');
  return Uri.https('github.com', '/Goelir/IPTVMac/releases/tag/android-v$version');
}

/// Asks the feed. Throws on a network failure.
Future<String?> fetchNewestAndroidVersion(http.Client client) async {
  final bytes = await apiGet(client, Uri.parse(androidReleasesFeed), timeout: const Duration(seconds: 30), idleTimeout: const Duration(seconds: 20), maxBytes: 2000000);
  return newestAndroidVersion(utf8.decode(bytes, allowMalformed: true));
}
