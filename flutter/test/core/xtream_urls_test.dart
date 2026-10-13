import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/xtream_urls.dart';

XtreamURLs urls(String server, [String user = 'u', String pass = 'p']) =>
    XtreamURLs.parse(server: server, username: user, password: pass)!;

void main() {
  test('normalizes messy server input', () {
    expect(urls('  example.com:8080/ ').live('12').toString(), 'http://example.com:8080/live/u/p/12.ts');
    expect(urls('https://h.tv///').movie('3', 'mkv').toString(), 'https://h.tv/movie/u/p/3.mkv');
    expect(XtreamURLs.parse(server: '   ', username: 'u', password: 'p'), isNull);
  });

  test('credentials with special characters are percent-encoded', () {
    expect(urls('h', 'us er', 'p@ss/w').live('1').toString(), 'http://h/live/us%20er/p%40ss%2Fw/1.ts');
  });

  test('missing extension defaults', () {
    final u = urls('h');
    expect(u.movie('1', null).toString().endsWith('/1.mp4'), isTrue);
    expect(u.series('1', '').toString().endsWith('/1.mp4'), isTrue);
  });

  test('timeshift format', () {
    final url = urls('h').timeshift('5', DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true), 60);
    expect(url.toString(), 'http://h/timeshift/u/p/60/2023-11-14:22-13/5.ts');
    final paris = urls('h').timeshift('5', DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true), 60,
        utcOffset: const Duration(hours: 1));
    expect(paris.toString(), 'http://h/timeshift/u/p/60/2023-11-14:23-13/5.ts');
  });

  test('api query encodes reserved characters', () {
    final u = urls('h', 'u', 'a&b+c');
    expect(u.api('get_live_streams').toString(), 'http://h/player_api.php?username=u&password=a%26b%2Bc&action=get_live_streams');
    expect(u.api(null).toString(), 'http://h/player_api.php?username=u&password=a%26b%2Bc');
  });

  test('tolerates pasted API links and whitespace', () {
    final u = XtreamURLs.parse(
        server: ' http://h:8080/get.php?username=u&password=p&type=m3u_plus \n', username: ' user\n', password: 'pw ')!;
    expect(u.api('x').toString(), 'http://h:8080/player_api.php?username=user&password=pw&action=x');
    expect(urls('h.example/player_api.php?username=a').live('5').toString(), 'http://h.example/live/u/p/5.ts');
    expect(urls('https://h.example/panel/c/').live('5').toString(), 'https://h.example/panel/live/u/p/5.ts');
  });
}
