# lib/core: the platform-neutral core (Dart port of `Sources/IPTVCore`)

Pure Dart: no Flutter plugin is imported here (`sqlite3`, `http`, `dart:io` only), so everything runs in plain `flutter test`
on the host. The Swift code is the specification; the Swift tests are ported 1:1 in `test/core/`. Import with
`package:iptvmac/core/<file>.dart`.

## Conventions

- **Synchronous database, async network.** `package:sqlite3` is synchronous, so database functions are plain functions that take
  a `Database` (from `package:sqlite3/sqlite3.dart`); only HTTP-using code (`SyncService`, `XtreamClient`) is `Future`-based.
- **`AppDatabase`** (`app_database.dart`): `AppDatabase.open(path)` / `.memory()` / `.openRecovering(path)`;
  `db.read((d) => ...)`, `db.write((d) => ...)` (one transaction: BEGIN IMMEDIATE .. COMMIT, rollback on throw), `db.close()`.
  The file is WAL, `foreign_keys=ON`, migrated on open (tables `account category item item_fts episode favorite history secret
  item_info`, same names/columns/migrations v1..v4 as the Apple apps, tracked in `grdb_migrations`). Dates are stored as
  `yyyy-MM-dd HH:mm:ss.SSS` UTC (`dbDate` / `parseDbDate` in `json_util.dart`).
- **Errors:** `IPTVError` (`http(code)`, `badResponse`, `badConfig`, `badCredentials`, `emptyResponse`, `accountInactive`;
  compare with `==`). Network failures are the client's own exceptions (`TimeoutException`, `ClientException`, `SocketException`).
- **Networking:** every class that talks to the network takes an optional `http.Client` (tests use `MockClient`).
  `apiGet` (`api_session.dart`): 600 s overall and 60 s idle timeout, `Accept-Encoding: identity`, `Cache-Control: no-store`,
  non-2xx = `IPTVError.http`, body over 300 MB = `badResponse`.
- Passwords are never stored by the core: pass them in (`sync(account, password: ...)`), get them from your `SecretStore`.

## Public API

| File | What |
|---|---|
| `models.dart` | `ItemType {live, movie, series}`, `AccountKind {xtream, m3u}`, `Account`, `Category`, `Item`, `Episode`, `EPGEntry`. Rows: `X.fromRow(row)`, `Account.all(db)`, `Item.all(db)`, `Category.all(db)`, `account.insert(db)` (sets `id`). `Item.iconURL` is the safe logo URL. `Account.restore(saved, accounts)` picks the playlist to open ("all" or an id). |
| `remote_image.dart` | `safeImageUrl(String?)`: http(s) only, never a LAN/localhost host. |
| `m3u.dart` | `M3UParser().feed(line)` returns an `M3UEntry?` per URL line; `M3UClassifier.type(url:, group:)`. |
| `xtream_urls.dart` | `XtreamURLs.parse(server:, username:, password:)` (null if unusable) then `.live(id)`, `.movie(id, ext)`, `.series(id, ext)`, `.stream(type, id, ext)`, `.timeshift(id, start, minutes, utcOffset:)`, `.api(action, params)`. Accepts pasted `get.php?...` links. |
| `xtream_client.dart` | `XtreamClient(urls, client:)`: `authenticate()`, `epgNow(id)`, `epgShort(id, limit)`, `epgArchive(id)`, `vodInfo(id)`, `seriesInfo(id)`, `serverTimeZoneName()`, plus `array(action)` / `rawSeriesInfo(id)` used by the sync. |
| `sync_service.dart` | `SyncService(db, client:)`: `sync(account, password:)` (Xtream live/VOD/series + categories, or M3U; everything in ONE transaction; a type that comes back empty keeps its old items; no items at all = `emptyResponse`), `episodes(account, password:, seriesId:)` (fetch, store, offline fallback), `info(account, password:, type:, streamId:, refresh:)` (title details, 14-day cache). |
| `search.dart` | `Search.run(db, SearchRequest(accountId:, text:, type:, categoryId:, limit: 5000))`: every word a quoted prefix term, max 8 words, `ORDER BY rank`; empty text browses by id; `accountId: null` = all playlists (each gets an equal share when browsing). |
| `user_data.dart` | `UserData`: `toggleFavorite`, `favorites`, `favoriteKeys`, `favoriteKey`, `saveProgress`, `progress` (resume position or null), `continueWatching`, `clearHistory`, `clearFavorites`. |
| `category_filter.dart` | `CategoryFilter(csv)`: `hides(name)`, `visibleCategories(list)`, `visible(items, db)`. |
| `refresh_schedule.dart` | `RefreshSchedule.isDue(hours:, lastSync:, now:)`. |
| `episode_queue.dart` | `EpisodeQueue.next(streamId, episodes)`. |
| `backup.dart` | `Backup.make(db)`, `.encoded()` (JSON text), `.write(File)`, `Backup.decode(bytes)`, `Backup.read(File)`, `backup.merge(db)` (returns the added accounts: they still need a sync and a password). Throws `BackupError.{invalid, unsupportedVersion, tooLarge}`. Same JSON as the Apple apps. |
| `item_info.dart` | `ItemInfo` (title details, untrusted input sanitised), `ItemInfoStore.cached/save`. |
| `secret_store.dart` | `abstract interface class SecretStore` (async `password`, `setPassword`, `deletePassword`) and `MemorySecretStore` for tests. The shell implements it with the platform keystore. |

Typical start-up in the shell:

```dart
final db = AppDatabase.openRecovering('${dir.path}/iptv.sqlite').db;
final svc = SyncService(db);
final acc = db.write((d) => Account(name: 'x', kind: AccountKind.xtream, server: 'http://panel.test', username: 'u').insert(d));
await svc.sync(acc, password: await secrets.password(acc.id!));
final hits = db.read((d) => Search.run(d, SearchRequest(accountId: acc.id, text: 'news', type: ItemType.live)));
```

## Threading

`sync` decodes the JSON and inserts the rows on the calling isolate (100k items: about 1.1 s on the Mac host, in the debug VM).
In the app, run it in a background isolate that opens its own `AppDatabase.open(path)` of the same file (WAL: the UI isolate keeps
reading while it writes). An `AppDatabase` object itself cannot cross isolates.

## Not ported, or different (on purpose)

- `Updater`, `ReleaseSignature`, `FolderBookmark`, `DownloadNaming`, `FullscreenSync`: not needed on Android v1.
- `DatabaseSecretStore` (passwords in the `secret` table): the task asks for an abstract `SecretStore` only. The `secret` table is
  still created (migration v2) so the file matches the Apple one. The interface is async (Swift's is sync) because keystore
  plugins are async.
- `AppDatabase.defaultPath()`: needs `path_provider` (a Flutter plugin); the shell passes the path.
- Time zones: Swift's `serverTimeZone()` returned a validated `TimeZone`; Dart has no time zone database in the SDK, so
  `XtreamClient.serverTimeZoneName()` returns the raw `server_info.timezone` string (not validated) and
  `XtreamURLs.timeshift` takes the zone's UTC offset as a `Duration`. The shell resolves the offset (e.g. with the `timezone`
  package).
- Backup/db file permissions (0600) are applied with `chmod` through `Process.runSync` (best effort, skipped on Windows). On
  Android the app-private directory is the real protection.
- `apiSession`'s "no URL cache" is inherent in `package:http` (no cache), so the Swift test became a header/timeout test.
- `LibraryModel`, `SourceDraft`, `WatchProgress`, `PlayerQueues` (Sources/IPTVAppKit) are app-shell/state code and are not in
  this phase.
- Search tokenising: Swift used GRDB's `FTS5Pattern(matchingAllPrefixesIn:)`; here `Search.prefixPattern` splits on non
  letter/number/mark characters and quotes each token, which the unicode61 tokenizer then treats the same way. Hebrew niqqud and
  Arabic tashkeel are not folded (same as the Apple apps, see `flutter/PLAN.md`).
- Small hardening on purpose: ids and extensions in stream URLs are percent-encoded (Swift would crash on a space in an id).
