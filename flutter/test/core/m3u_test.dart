import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/m3u.dart';
import 'package:iptvmac/core/models.dart';

void main() {
  test('parses attributes and name', () {
    final p = M3UParser();
    expect(p.feed('#EXTM3U'), isNull);
    expect(p.feed('#EXTINF:-1 tvg-id="a.b" tvg-logo="http://x/l.png" group-title="News",Channel One'), isNull);
    final e = p.feed('http://h/live/1.ts');
    expect(e, const M3UEntry(name: 'Channel One', url: 'http://h/live/1.ts', group: 'News', logo: 'http://x/l.png', tvgId: 'a.b'));
  });

  test('tolerates BOM, CRLF and missing attributes', () {
    final p = M3UParser();
    expect(p.feed('\u{FEFF}#EXTM3U\r'), isNull);
    expect(p.feed('#EXTINF:-1,Plain\r'), isNull);
    final e = p.feed('http://h/a\r');
    expect(e?.name, 'Plain');
    expect(e?.group, isNull);
    expect(e?.url, 'http://h/a');
  });

  test('comma inside quoted attribute does not split name', () {
    final p = M3UParser();
    p.feed('#EXTINF:-1 group-title="A, B",Name, Part2');
    final e = p.feed('http://h/a');
    expect(e?.group, 'A, B');
    expect(e?.name, 'Name, Part2');
  });

  test('ignores other directives and blank lines', () {
    final p = M3UParser();
    p.feed('#EXTINF:-1,X');
    expect(p.feed('#EXTVLCOPT:http-user-agent=foo'), isNull);
    expect(p.feed(''), isNull);
    expect(p.feed('http://h/x')?.name, 'X');
  });

  test('url without EXTINF uses last path component as name', () {
    expect(M3UParser().feed('http://h/path/movie.mkv')?.name, 'movie.mkv');
  });

  test('catchup days are parsed', () {
    final p = M3UParser();
    p.feed('#EXTINF:-1 catchup-days="3",Y');
    expect(p.feed('http://h/y')?.catchupDays, 3);
  });

  test('classifier uses path, then group, then extension', () {
    expect(M3UClassifier.type(url: 'http://h/movie/u/p/1.mkv'), ItemType.movie);
    expect(M3UClassifier.type(url: 'http://h/series/u/p/1.mkv'), ItemType.series);
    expect(M3UClassifier.type(url: 'http://h/1.ts', group: 'VOD Action'), ItemType.movie);
    expect(M3UClassifier.type(url: 'http://h/1.ts', group: 'סדרות ישראליות'), ItemType.series);
    expect(M3UClassifier.type(url: 'http://h/1.mp4'), ItemType.movie);
    expect(M3UClassifier.type(url: 'http://h/1.ts', group: 'News'), ItemType.live);
  });

  test('never uses the URL with credentials as the title', () {
    final p = M3UParser();
    expect(p.feed('http://host:80/live/USER/PASS/1.ts')?.name, '1.ts');
    p.feed('#EXTINF:-1 group-title="G",'); // empty title after the comma
    expect(p.feed('http://host/live/USER/PASS/77.ts?token=abc')?.name, '77.ts');
    final huge = '#EXTINF:-1 ${'a' * 200000}';
    expect(p.feed(huge), isNull); // an oversized attribute line is ignored, quickly
  });
}
