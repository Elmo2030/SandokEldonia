import 'package:iptvmac/core/models.dart';

enum DownloadStatus { queued, running, paused, done, failed, canceled }

/// One saved (or saving) movie or episode. Everything here is safe to write to disk: no URL, no host, no login.
/// The URL is rebuilt from the library (account id + stream id + extension) whenever it is needed.
class DownloadEntry {
  DownloadEntry({
    required this.id,
    required this.accountId,
    required this.type,
    required this.streamId,
    this.episodeId,
    this.season,
    this.number,
    this.episodeTitle,
    required this.title,
    required this.ext,
    required this.path,
    this.status = DownloadStatus.queued,
    this.bytes = 0,
    this.total = 0,
    this.error,
  });

  final String id;

  /// The library item: a movie, or the series for an episode.
  final int accountId;
  final ItemType type;
  final String streamId;

  /// Set for an episode (its stream id); [season], [number] and [episodeTitle] rebuild the `Episode` for offline playback.
  final String? episodeId;
  final int? season, number;
  final String? episodeTitle;

  /// What lists and notifications show.
  final String title;
  final String ext;
  final String path;
  DownloadStatus status;
  int bytes, total;

  /// Why it failed: an [EngineError] name, or `lost` (the engine forgot the job), `file` (not saved).
  String? error;

  /// Set at startup and when listing: a finished file that is no longer on the disk.
  bool missing = false;

  bool get isEpisode => episodeId != null;
  bool get active => status == DownloadStatus.queued || status == DownloadStatus.running;
  double get fraction => total > 0 ? (bytes / total).clamp(0.0, 1.0) : 0;

  /// "S01E02" for an episode.
  String? get label => season == null || number == null ? null : 'S${season.toString().padLeft(2, '0')}E${number.toString().padLeft(2, '0')}';

  /// The same movie or episode: what the download button looks up.
  String get key => keyOf(accountId, type, streamId, episodeId);
  static String keyOf(int accountId, ItemType type, String streamId, String? episodeId) => '$accountId|${type.name}|$streamId|${episodeId ?? ''}';

  Map<String, Object?> toJson() => {
        'id': id,
        'accountId': accountId,
        'type': type.name,
        'streamId': streamId,
        'episodeId': episodeId,
        'season': season,
        'number': number,
        'episodeTitle': episodeTitle,
        'title': title,
        'ext': ext,
        'path': path,
        'status': status.name,
        'bytes': bytes,
        'total': total,
        'error': error,
      };

  static DownloadEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return DownloadEntry(
        id: j['id'] as String,
        accountId: j['accountId'] as int,
        type: ItemType.values.byName(j['type'] as String),
        streamId: j['streamId'] as String,
        episodeId: j['episodeId'] as String?,
        season: j['season'] as int?,
        number: j['number'] as int?,
        episodeTitle: j['episodeTitle'] as String?,
        title: j['title'] as String,
        ext: j['ext'] as String,
        path: j['path'] as String,
        status: DownloadStatus.values.byName(j['status'] as String),
        bytes: j['bytes'] as int? ?? 0,
        total: j['total'] as int? ?? 0,
        error: j['error'] as String?,
      );
    } catch (_) {
      return null; // one damaged row must not lose the others
    }
  }
}
