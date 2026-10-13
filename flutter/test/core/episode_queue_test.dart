import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/episode_queue.dart';
import 'package:iptvmac/core/models.dart';

void main() {
  test('next episode follows season and number order', () {
    Episode ep(int s, int n, String id) => Episode(accountId: 1, seriesId: '9', season: s, number: n, title: 't', streamId: id);
    final all = [ep(2, 1, 'c'), ep(1, 2, 'b'), ep(1, 1, 'a'), ep(1, 10, 'z')]; // unsorted, with a gap in numbering
    expect(EpisodeQueue.next('a', all)?.streamId, 'b');
    expect(EpisodeQueue.next('b', all)?.streamId, 'z');
    expect(EpisodeQueue.next('z', all)?.streamId, 'c'); // next season starts
    expect(EpisodeQueue.next('c', all), isNull); // last episode
    expect(EpisodeQueue.next('nope', all), isNull);
    expect(EpisodeQueue.next('a', []), isNull);
  });
}
