import 'models.dart';

abstract final class EpisodeQueue {
  /// The episode that follows [streamId] in watching order (season, then episode number), or null after the last one.
  static Episode? next(String streamId, List<Episode> episodes) {
    final ordered = [...episodes]..sort((a, b) => a.season != b.season ? a.season.compareTo(b.season) : a.number.compareTo(b.number));
    final i = ordered.indexWhere((e) => e.streamId == streamId);
    return i < 0 || i + 1 >= ordered.length ? null : ordered[i + 1];
  }
}
