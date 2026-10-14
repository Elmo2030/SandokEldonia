import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/downloads/download_entry.dart';

DownloadEntry entry() => DownloadEntry(id: 'a', accountId: 1, type: ItemType.movie, streamId: '1', title: 't', ext: 'mp4', path: '/x', status: DownloadStatus.running, total: 1000);

void main() {
  final t0 = DateTime(2026, 1, 1);
  test('the time left comes from the speed seen over at least a second', () {
    final e = entry()..bytes = 0;
    e.sample(t0);
    expect(e.eta, isNull); // no speed yet
    e.bytes = 100;
    e.sample(t0.add(const Duration(milliseconds: 500)));
    expect(e.eta, isNull); // too soon to trust
    e.sample(t0.add(const Duration(seconds: 2)));
    expect(e.speed, 50);
    expect(e.eta, const Duration(seconds: 18)); // 900 bytes left at 50 B/s
  });

  test('a pause or a restart clears the speed', () {
    final e = entry()..bytes = 0;
    e.sample(t0);
    e.bytes = 200;
    e.sample(t0.add(const Duration(seconds: 2)));
    expect(e.eta, isNotNull);
    e.status = DownloadStatus.paused;
    e.sample(t0.add(const Duration(seconds: 3)));
    expect(e.eta, isNull);
    e.status = DownloadStatus.running;
    e.bytes = 0; // starts again from zero
    e.sample(t0.add(const Duration(seconds: 4)));
    expect(e.speed, 0);
  });
}
