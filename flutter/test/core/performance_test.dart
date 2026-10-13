import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:iptvmac/core/app_database.dart';
import 'package:iptvmac/core/models.dart';
import 'package:iptvmac/core/search.dart';
import 'package:iptvmac/core/sync_service.dart';

import 'support.dart';

/// 100000 live channels in the shape of an Xtream `get_live_streams` answer. A third are "Sport", the rest "News".
String liveJson(int n) {
  final b = StringBuffer('[');
  for (var i = 0; i < n; i++) {
    if (i > 0) b.write(',');
    b.write('{"num":$i,"name":"Channel $i ${i % 3 == 0 ? 'Sport' : 'News'} HD","stream_type":"live","stream_id":${i + 1},'
        '"stream_icon":"http://logos.test/$i.png","epg_channel_id":"ch$i","category_id":"${i % 50}","tv_archive":${i % 2},"tv_archive_duration":"3"}');
  }
  return (b..write(']')).toString();
}

void main() {
  test('100k items sync and a two word prefix search returning 5000 rows stays under 250 ms', () async {
    final live = utf8.encode(liveJson(100000));
    final server = FakeServer((r) {
      final body = switch (actionOf(r)) {
        'get_live_streams' => live,
        'get_live_categories' => utf8.encode('[${[for (var i = 0; i < 50; i++) '{"category_id":"$i","category_name":"Cat $i"}'].join(',')}]'),
        '' => utf8.encode('{"user_info":{"auth":1}}'),
        _ => utf8.encode('[]'),
      };
      return http.Response.bytes(body, 200);
    });
    final db = AppDatabase.memory();
    final a = db.write((d) => Account(name: 'big', kind: AccountKind.xtream, server: 'http://panel.test', username: 'u').insert(d));

    final sw = Stopwatch()..start();
    await SyncService(db, client: server.client).sync(a, password: 'p');
    final syncMs = sw.elapsedMilliseconds;
    expect(count(db, 'SELECT count(*) FROM item'), 100000);
    // ignore: avoid_print
    print('PERF sync of 100000 items (fetch, parse, insert, index): $syncMs ms');
    expect(syncMs, lessThan(5000));

    // a re-sync (every row is an upsert, names unchanged) must not be slower by an order of magnitude
    sw.reset();
    await SyncService(db, client: server.client).sync(a, password: 'p');
    final resyncMs = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print('PERF re-sync of 100000 items: $resyncMs ms');
    expect(resyncMs, lessThan(8000));
    expect(count(db, 'SELECT count(*) FROM item'), 100000);

    sw.reset();
    final hits = db.read((d) => Search.run(d, SearchRequest(accountId: a.id, text: 'chan spor')));
    final searchMs = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print('PERF two word prefix search, ${hits.length} rows: $searchMs ms');
    expect(hits.length, 5000);
    expect(searchMs, lessThan(250));

    sw.reset();
    final scoped = db.read((d) => Search.run(d, SearchRequest(accountId: a.id, text: 'chan 99', type: ItemType.live, categoryId: '9')));
    // ignore: avoid_print
    print('PERF scoped search, ${scoped.length} rows: ${sw.elapsedMilliseconds} ms');
    expect(sw.elapsedMilliseconds, lessThan(250));
  });
}
