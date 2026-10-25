import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptvmac/app/sync_worker.dart';
import 'package:iptvmac/core/app_database.dart';
import 'package:iptvmac/core/models.dart';

import '../core/support.dart';

/// The app's real runner: the sync runs in a background isolate against the database FILE and tells the UI isolate how far it is.
void main() {
  test('the isolate sync loads the playlist, reports progress through the port, and the UI isolate sees the rows', () async {
    final dir = tempDir('isolate-sync');
    addTearDown(() => dir.deleteSync(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((r) {
      final body = switch (r.uri.queryParameters['action']) {
        'get_live_categories' => '[{"category_id":"5","category_name":"News"}]',
        'get_live_streams' => '[{"stream_id":1,"name":"News 24","category_id":"5"},{"stream_id":2,"name":"Sport","category_id":"5"}]',
        'get_vod_categories' || 'get_series_categories' || 'get_vod_streams' || 'get_series' => '[]',
        _ => '{"user_info":{"auth":1},"server_info":{}}',
      };
      r.response
        ..headers.contentType = ContentType.json
        ..add(utf8.encode(body));
      r.response.close();
    });
    final path = '${dir.path}/test.db';
    final db = AppDatabase.open(path);
    addTearDown(db.close);
    final a = db.write((d) => Account(name: 'x', kind: AccountKind.xtream, server: 'http://127.0.0.1:${server.port}', username: 'u').insert(d));

    final seen = <double>[];
    final error = await isolateSyncRunner(path)(a, 'p', seen.add);

    expect(error, isNull);
    expect(seen, isNotEmpty);
    expect(seen, [...seen]..sort(), reason: 'forward only');
    expect(seen.last, 1.0);
    expect(count(db, 'SELECT count(*) FROM item'), 2, reason: 'written by the other isolate, read here');
  });
}
