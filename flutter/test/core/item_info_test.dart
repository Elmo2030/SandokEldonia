import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/core/item_info.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/core/remote_image.dart';

/// A provider response (`{"info": {...}}`) as the untyped map XtreamClient hands over.
ItemInfo response(String info) => ItemInfo.fromResponse(jsonDecode('{"info":$info}') as Map<String, dynamic>);

void main() {
  test('a typical movie response is parsed', () {
    final i = response('''
        {"movie_image":"https://img.example.com/p.jpg","backdrop_path":["https://img.example.com/b1.jpg","https://img.example.com/b2.jpg"],
         "plot":"A heist goes wrong.","cast":"Ann, Bob","director":"Cy","genre":"Action, Crime","releasedate":"2019-05-24",
         "rating":"7.5","duration":"01:45:00","duration_secs":6300,"youtube_trailer":"dQw4w9WgXcQ","name":"The Heist","country":"US","age":"16"}
        ''');
    expect(i.title, 'The Heist');
    expect(i.plot, 'A heist goes wrong.');
    expect(i.cast, 'Ann, Bob');
    expect(i.director, 'Cy');
    expect(i.genre, 'Action, Crime');
    expect(i.country, 'US');
    expect(i.year, 2019);
    expect(i.releaseDate, '2019-05-24');
    expect(i.rating, 7.5);
    expect(i.durationMinutes, 105);
    expect(i.trailerID, 'dQw4w9WgXcQ');
    expect(i.posterURL.toString(), 'https://img.example.com/p.jpg');
    expect(i.backdropURL.toString(), 'https://img.example.com/b1.jpg');
    expect(i.hasContent, isTrue);
  });

  test('a series response uses its own field names', () {
    final i = response(
        '{"name":"The Show","cover":"https://c.example.com/s.jpg","plot":"Town secrets.","cast":"X","director":"Y","genre":"Drama","releaseDate":"2021-02-01","rating":"8.1","backdrop_path":[],"youtube_trailer":"","episode_run_time":"45"}');
    expect(i.title, 'The Show');
    expect(i.posterURL.toString(), 'https://c.example.com/s.jpg');
    expect(i.year, 2021);
    expect(i.rating, 8.1);
    expect(i.durationMinutes, 45);
    expect(i.backdropURL, isNull);
    expect(i.trailerID, isNull);
  });

  test('numbers where strings are expected are accepted', () {
    final i = response('{"plot":12345,"rating":7.5,"duration_secs":"6300","year":2018,"cast":["Ann","Bob"],"genre":["Action","Crime"]}');
    expect(i.rating, 7.5);
    expect(i.durationMinutes, 105);
    expect(i.year, 2018);
    expect(i.plot, '12345');
    expect(i.cast, 'Ann, Bob');
    expect(i.genre, 'Action, Crime');
  });

  test('nulls, empty strings and empty arrays mean nothing to show', () {
    final empty = response(
        '{"plot":null,"cast":"","director":"  ","genre":[],"rating":"","backdrop_path":[],"movie_image":null,"youtube_trailer":null,"duration":"","releasedate":""}');
    expect(empty.hasContent, isFalse);
    expect(response('[]').hasContent, isFalse); // panels answer "info": [] for a title they know nothing about
    expect(response('null').hasContent, isFalse);
    expect(response('"oops"').hasContent, isFalse);
    expect(ItemInfo.fromResponse(const {}).hasContent, isFalse);
    expect(ItemInfo().hasContent, isFalse);
    expect(response('{"plot":"x"}').hasContent, isTrue);
  });

  test('a name alone is not details', () {
    expect(response('{"name":"Only a name"}').hasContent, isFalse);
  });

  test('backdrop path may be an array, a string or empty', () {
    expect(response('{"backdrop_path":["https://i.example.com/a.jpg"]}').backdropURL.toString(), 'https://i.example.com/a.jpg');
    expect(response('{"backdrop_path":"https://i.example.com/b.jpg"}').backdropURL.toString(), 'https://i.example.com/b.jpg');
    expect(response('{"backdrop_path":[]}').backdropURL, isNull);
    expect(response('{"backdrop_path":""}').backdropURL, isNull);
    expect(response('{"backdrop_path":null}').backdropURL, isNull);
    expect(response('{"backdrop_path":[null,"","http://192.168.1.1/x.jpg","https://i.example.com/c.jpg"]}').backdropURL.toString(),
        'https://i.example.com/c.jpg');
  });

  test('release dates in common formats give a year', () {
    const cases = <(String, int?)>[
      ('2019-05-24', 2019), ('2019-05-24 00:00:00', 2019), ('24/05/2019', 2019), ('24.05.2019', 2019), ('2019', 2019),
      ('May 24, 2019', 2019), ('', null), ('0000-00-00', null), ('soon', null), ('1558656000', null), ('3019-01-01', null),
    ];
    for (final (s, year) in cases) {
      expect(response('{"releasedate":"$s"}').year, year, reason: 'releasedate $s');
    }
    expect(response('{"release_date":"2020-01-02"}').year, 2020);
    expect(response('{"releaseDate":"2020-01-02"}').year, 2020);
    expect(response('{"year":"1999"}').year, 1999);
    expect(response('{"releasedate":"2019-05-24"}').releaseDate, '2019-05-24');
  });

  test('ratings are on a ten point scale', () {
    const cases = <(String, double?)>[
      ('"7.5"', 7.5), ('7.5', 7.5), ('"0"', null), ('0', null), ('""', null), ('null', null), ('"7,5"', 7.5), ('"N/A"', null),
      ('"8.25"', 8.3), ('10', 10), ('"85"', 8.5), ('150', null), ('-3', null), ('"7.5/10"', 7.5),
    ];
    for (final (raw, want) in cases) {
      expect(response('{"rating":$raw}').rating, want, reason: 'rating $raw');
    }
    expect(response('{"rating":"0","rating_5based":"3.5"}').rating, 7); // only the five-star value is filled
    expect(response('{"rating":"8","rating_5based":"3.5"}').rating, 8);
  });

  test('durations in the forms providers use', () {
    const cases = <(String, int?)>[
      ('"01:45:00"', 105), ('6300', 105), ('"6300"', 105), ('"105 min"', 105), ('"1h 45m"', 105), ('"2 hours"', 120), ('"45"', 45),
      ('"00:00:00"', null), ('""', null), ('0', null), ('9999999', null), ('"soon"', null), ('"01:30"', 90),
    ];
    for (final (raw, want) in cases) {
      expect(response('{"duration":$raw}').durationMinutes, want, reason: 'duration $raw');
    }
    expect(response('{"duration":"00:00:00","duration_secs":5400}').durationMinutes, 90); // seconds win over the text
    expect(response('{"runtime":"100"}').durationMinutes, 100);
    expect(response('{"episode_run_time":45}').durationMinutes, 45);
  });

  test('trailer is a YouTube id and nothing else', () {
    String? trailer(String s) => response('{"youtube_trailer":"$s"}').trailerID;
    expect(trailer('dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(trailer('a_b-c_d-e12'), 'a_b-c_d-e12');
    expect(trailer('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(trailer('https://youtu.be/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(trailer('https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=5'), 'dQw4w9WgXcQ');
    expect(trailer('https://evil.example/watch?v=dQw4w9WgXcQ'), isNull); // not a YouTube host
    expect(trailer('https://notyoutube.com/watch?v=dQw4w9WgXcQ'), isNull);
    expect(trailer('https://evil.example/dQw4w9WgXcQ'), isNull); // a valid-looking id on a foreign host is still a foreign link
    expect(trailer('https://www.youtube.com/user/dQw4w9WgXcQ'), isNull); // a YouTube page that is not a video
    expect(trailer('javascript:alert(1)'), isNull);
    expect(trailer('file:///etc/passwd'), isNull);
    expect(trailer('abc'), isNull); // too short
    expect(trailer('a' * 21), isNull); // too long
    expect(trailer('dQw4w9WgXcQ&x=<script>'), isNull);
    expect(trailer('dQw4w9 WgXcQ'), isNull);
    expect(trailer(''), isNull);
  });

  test('the trailer link is built by us from the validated id', () {
    expect(response('{"youtube_trailer":"https://youtu.be/dQw4w9WgXcQ?x=http://evil"}').trailerURL.toString(),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    final i = ItemInfo()..trailerID = 'dQw4w9WgXcQ';
    expect(i.trailerURL.toString(), 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    i.trailerID = 'x/../../evil'; // a tampered cache row
    expect(i.trailerURL, isNull);
    i.trailerID = null;
    expect(i.trailerURL, isNull);
  });

  test('hostile text is capped and stays plain text', () {
    String rep(String c) => c * 5000;
    final i = response(
        '{"plot":"${'a' * 100000}","cast":"${rep('b')}","director":"${rep('c')}","genre":"${rep('g')}","name":"${rep('n')}","country":"${rep('k')}"}');
    expect(i.plot!.runes.length, lessThanOrEqualTo(4000));
    expect(i.plot!.runes.length, greaterThan(3000));
    expect(i.cast!.runes.length, lessThanOrEqualTo(500));
    expect(i.director!.runes.length, lessThanOrEqualTo(200));
    expect(i.genre!.runes.length, lessThanOrEqualTo(200));
    expect(i.title!.runes.length, lessThanOrEqualTo(300));
    expect(i.country!.runes.length, lessThanOrEqualTo(100));

    const html = r'<script>alert(1)</script> <b>bold</b> **md** [click](https://evil.example) https://evil.example/x';
    // kept as typed: shown verbatim, never interpreted
    expect(response(jsonEncode({'plot': html})).plot, html);

    final tricky = response(r'{"plot":"line1\nline2\u0000\u202eevil\u2069\tend\n\n\n\n\nlast"}').plot;
    expect(tricky, 'line1\nline2evil\tend\n\nlast'); // control and bidi-override characters dropped, blank runs shortened
  });

  test('image urls from the provider must be safe', () {
    Uri? poster(String s) => response('{"movie_image":"$s"}').posterURL;
    expect(poster('https://cdn.example.com/p.jpg'), isNotNull);
    expect(poster('http://cdn.example.com/p.jpg'), isNotNull);
    for (final bad in [
      'http://192.168.1.1/cgi-bin/reboot', 'http://10.0.0.5/p.jpg', 'http://localhost:8123/api/webhook/x', 'http://printer.local/p.jpg',
      'http://[::1]/p.jpg', 'file:///etc/passwd', 'data:image/png;base64,AAAA', 'javascript:alert(1)', 'ftp://cdn.example.com/p.jpg',
    ]) {
      expect(poster(bad), isNull, reason: bad);
    }
    expect(response('{"cover_big":"https://cdn.example.com/big.jpg"}').posterURL, isNotNull); // other poster fields work too
    expect(response('{"movie_image":"http://10.0.0.5/x","cover_big":"https://cdn.example.com/big.jpg"}').posterURL?.host, 'cdn.example.com');
  });

  test('the shared image check behind Item.iconURL is the same one', () {
    expect(safeImageUrl('https://cdn.example.com/a.png'), isNotNull);
    expect(safeImageUrl(' https://cdn.example.com/a.png \n'), isNotNull);
    expect(safeImageUrl('http://192.168.0.9/a.png'), isNull);
    expect(safeImageUrl(null), isNull);
    expect(safeImageUrl(''), isNull);
    expect(Item(accountId: 1, type: ItemType.movie, name: 'x', streamId: '1', icon: 'http://172.16.0.1/a.png').iconURL, isNull);
  });

  test('item info survives the JSON round trip used by the cache', () {
    final i = response(
        '{"movie_image":"https://img.example.com/p.jpg","plot":"p","rating":"6.5","duration":"90","releasedate":"2001-01-01","youtube_trailer":"dQw4w9WgXcQ"}');
    expect(ItemInfo.fromJson(jsonDecode(jsonEncode(i.toJson())) as Map<String, dynamic>), i);
    expect(ItemInfo.fromJson(<String, dynamic>{}), ItemInfo()); // a row from an older version with fewer fields
  });
}
