import 'package:iptvmac/app/library_model.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/core/user_data.dart';
import 'package:iptvmac/downloads/download_entry.dart';
import 'package:iptvmac/downloads/download_naming.dart';
import 'package:iptvmac/downloads/downloads_model.dart';
import 'package:iptvmac/player/play_request.dart';

/// What the downloads need from the library: which items can be saved, their URLs, and the offline [PlayRequest].
extension LibraryDownloads on LibraryModel {
  /// A movie whose stream is one file: an Xtream movie with a video container (or none: .mp4), or an M3U entry whose
  /// http(s) address ends in a video extension. Live channels, series and playlists (.m3u8, .mpd) are not.
  bool canDownload(Item item) {
    if (item.type != ItemType.movie) return false;
    final d = item.directURL;
    if (d == null) return DownloadNaming.isDirectFile(item.containerExt, orEmpty: true);
    final u = Uri.tryParse(d.trim());
    if (u == null || !const ['http', 'https'].contains(u.scheme.toLowerCase()) || u.host.isEmpty) return false;
    final name = u.pathSegments.isEmpty ? '' : u.pathSegments.last;
    return name.contains('.') && DownloadNaming.isDirectFile(name.split('.').last);
  }

  /// An episode (always Xtream: M3U has no series episodes).
  bool canDownloadEpisode(Episode e) => DownloadNaming.isDirectFile(e.containerExt, orEmpty: true);

  /// The URL for a saved entry, built the way playback builds it. Null when the source or its password is gone.
  Uri? downloadUrl(DownloadEntry e) {
    final a = accountById(e.accountId);
    if (a == null || !hasPassword(a)) return null;
    if (e.isEpisode) return xtreamUrls(e.accountId)?.series(e.episodeId!, e.ext);
    if (a.kind == AccountKind.xtream) return xtreamUrls(e.accountId)?.movie(e.streamId, e.ext);
    final d = itemFor(e).directURL;
    final u = d == null ? null : LibraryModel.safeStreamUrl(d);
    return u != null && const ['http', 'https'].contains(u.scheme.toLowerCase()) ? u : null;
  }

  /// The library item of a download (the series for an episode); a plain stand-in when the catalogue no longer has it, so
  /// favorites and resume points still use the same key.
  Item itemFor(DownloadEntry e) {
    final rows = db.read((d) => d.select('SELECT * FROM item WHERE accountId = ? AND type = ? AND streamId = ?', [e.accountId, e.type.name, e.streamId]));
    if (rows.isNotEmpty) return Item.fromRow(rows.first);
    return Item(accountId: e.accountId, type: e.type, name: e.title, streamId: e.streamId);
  }

  /// Plays the saved file without the network: the file URL, the library item attached, resume under the same key as streaming.
  PlayRequest offlineRequest(DownloadEntry e) {
    final item = itemFor(e);
    final url = Uri.file(e.path);
    Episode? ep;
    if (e.isEpisode) {
      ep = Episode(accountId: e.accountId, seriesId: e.streamId, season: e.season ?? 0, number: e.number ?? 0, title: e.episodeTitle ?? '', streamId: e.episodeId!, containerExt: e.ext);
      rememberEpisode(url, ep);
    }
    lastPlayedId = item.id;
    final start = db.read((d) => UserData.progress(d, accountId: e.accountId, type: e.type, streamId: ep == null ? e.streamId : 'ep:${ep.streamId}'));
    return PlayRequest(title: item.name, url: url, isLive: false, item: item, start: start ?? 0, subtitle: ep?.title);
  }

  /// Starts the download of a movie ([canDownload] was checked).
  Future<AddResult> downloadMovie(DownloadsModel d, Item item) async {
    if (!ensurePassword(item.accountId)) return AddResult.noUrl;
    final direct = item.directURL;
    final ext = direct == null ? item.containerExt : Uri.tryParse(direct.trim())?.pathSegments.lastOrNull?.split('.').last;
    return d.add(accountId: item.accountId, type: item.type, streamId: item.streamId, title: item.name, ext: ext ?? 'mp4');
  }

  /// Starts the download of an episode of [series] ([canDownloadEpisode] was checked).
  Future<AddResult> downloadEpisode(DownloadsModel d, Item series, Episode e) async {
    if (!ensurePassword(series.accountId)) return AddResult.noUrl;
    String two(int n) => n.toString().padLeft(2, '0');
    return d.add(
        accountId: series.accountId,
        type: series.type,
        streamId: series.streamId,
        episodeId: e.streamId,
        season: e.season,
        number: e.number,
        episodeTitle: e.title,
        title: '${series.name} S${two(e.season)}E${two(e.number)} ${e.title}'.trim(),
        ext: e.containerExt ?? 'mp4');
  }
}
