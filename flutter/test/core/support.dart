import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptvmac/core/app_database.dart';
import 'package:iptvmac/core/models.dart';

/// An in-memory database with one Xtream account; returns the database and the account id.
(AppDatabase, int) makeDB() {
  final db = AppDatabase.memory();
  final id = db.write((d) => Account(name: 't', kind: AccountKind.xtream, server: 'http://h', username: 'u').insert(d).id!);
  return (db, id);
}

int addAccount(AppDatabase db, String name) =>
    db.write((d) => Account(name: name, kind: AccountKind.m3u, url: 'http://h/$name.m3u').insert(d).id!);

void addItem(AppDatabase db, int aid, String name, {ItemType type = ItemType.live, String? cat = '1', String? sid}) {
  db.write((d) => Item(accountId: aid, type: type, name: name, streamId: sid ?? name, categoryId: cat).insert(d));
}

String actionOf(http.BaseRequest r) => r.url.queryParameters['action'] ?? '';

int count(AppDatabase db, String sql) => db.read((d) => d.select(sql).first.values.first as int);

/// A fresh temporary directory, deleted by the caller.
Directory tempDir(String prefix) => Directory.systemTemp.createTempSync('iptvmac-$prefix-');

/// A `MockClient` whose answer a test can change between requests (like the Swift tests' global handler), counting calls.
class FakeServer {
  FakeServer([this.handler]);
  http.Response Function(http.Request r)? handler;
  int calls = 0;

  /// Answers every request with this status and body.
  void reply(int code, String body) => handler = (_) => http.Response(body, code);

  late final MockClient client = MockClient((r) async {
    calls++;
    return handler!(r);
  });
}
