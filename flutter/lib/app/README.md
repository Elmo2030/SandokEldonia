# lib/app and lib/ui: the app shell

State and navigation of the Android app (everything except the video player). The platform-neutral core is `lib/core`; the
player is `lib/player` (another branch). Strings come from `AppLocalizations` (`lib/l10n`); the few that do not exist in the
Apple files are English literals in `lib/ui/missing_strings.dart`.

## Structure

| File | What |
|---|---|
| `main.dart` | Opens the database (`getApplicationSupportDirectory()/iptv.sqlite`, `openRecovering`; an in-memory one if the disk fails), builds the `LibraryModel`, `await model.loadAccounts()` before the first frame, `runApp(IptvApp)`, then `model.start()`. |
| `app/app.dart` | `IptvApp`: `ChangeNotifierProvider<LibraryModel>.value`, Material 3 light/dark/system, localizations (31 languages, RTL mirrors by itself). |
| `app/library_model.dart` | `LibraryModel` (ChangeNotifier), port of `IPTVAppKit/LibraryModel.swift`. API below. |
| `app/sync_worker.dart` | `SyncRunner` (`Future<String?> Function(Account, String password)`: null = ok, else a message). `isolateSyncRunner(dbPath)` runs the whole sync in `Isolate.run` with its own `AppDatabase.open(path)` (WAL: the UI keeps reading). `inlineSyncRunner(db, client:)` for tests and the in-memory fallback. `describeError` cuts URLs (they hold the password) out of library exceptions. |
| `app/secure_secret_store.dart` | `SecretStore` on `flutter_secure_storage` (Android Keystore). The model also keeps the passwords in memory (loaded at start) because the player host needs stream URLs synchronously. |
| `app/player_host.dart` | `ShellPlayerHost implements PlayerHost` (see below). |
| `app/watch_progress.dart` | Continue-watching entries, per-episode progress, `upNext`, channel zapping (ports of `WatchProgress.swift` / `PlayerQueues.swift`). |
| `app/source_draft.dart` | The add-source form as data, validation, pasted-link handling (port of `SourceDraft.swift`). |
| `app/prefs.dart` | `SharedPreferences` keys (same names as the Apple apps: `playlist`, `refreshHours`, `hiddenCategoryWords`, `appearance`, `recentSearches`). |
| `app/epg_cache.dart` | Now/next per live channel: 5 min cache, 4 requests at a time. |
| `app/demo_seed.dart` | Debug builds with `--dart-define=DEMO_SEED=true`: favorites and resume points for screenshots. |
| `ui/root.dart` | `RootScreen`: onboarding when there is no source, else five sections (bottom `NavigationBar`; a `NavigationRail` when width >= 600 dp or height < 480 dp). Also the password dialog and the "database was damaged" notice. |
| `ui/browse_screen.dart` | Live / Movies / Series: search field, scope chips, category chips, results (channel list, poster grid, grouped results for "Everywhere"), pull to refresh, empty states, skeleton. |
| `ui/item_views.dart` | `ChannelRow` (logo, now/next, star), `PosterCell`/`PosterGridSliver` (columns adapt to width and font size), `ContinueShelf`. |
| `ui/details_sheet.dart`, `ui/series_screen.dart` | Movie details bottom sheet (ItemInfo: poster, plot, year, rating, Play/Resume, star, trailer); series screen (seasons, episodes, resume, up next). |
| `ui/library_screen.dart`, `ui/settings_screen.dart`, `ui/about_screens.dart`, `ui/source_form.dart`, `ui/onboarding.dart` | The rest of the screens. Acknowledgements are `assets/Acknowledgements.md` (a copy of `ios/Resources/Acknowledgements.md`: copy it again when the iOS one changes). |
| `ui/artwork.dart` | `artUri()` is the only way provider image addresses reach `cached_network_image`: it is `safeImageUrl` (debug builds with `--dart-define=DEMO_IMAGES=true` also let the local demo provider through). Monogram placeholder like the iOS app. |
| `ui/theme.dart` | Colours from `ios/Sources/UI/Theme.swift` and the asset catalog (fill violet 6F59E6, text violet 5B3DE0 / A496FF, canvas, surface, raised). |

## LibraryModel API

State (read in widgets with `context.watch<LibraryModel>()` / `select`): `accounts`, `account`, `allPlaylists`, `playlist`, `tab`
(`ItemType`), `categories`, `selectedCategory` (`__all`, `__fav`, `__hist` or a category tag, see `categoryTag`), `searchText`,
`scope` (`SearchScope.category|type|everywhere`), `results`, `syncing`, `syncMessage`, `passwordPrompt`, `favoriteKeys`,
`favoriteItems`, `continueMovies`, `continueSeries`, `lastPlayedId`, `prefs`.

Actions: `loadAccounts()`, `start()` (refresh timer every 60 s + sync of the shown playlist), `selectPlaylist(Account?)` (null = all),
`setTab`, `selectCategory`, `setSearchText` (100 ms debounce), `setScope`, `sync([accounts])`, `savePassword`, `addAccount` (returns
false if it could not be saved; the first sync is started, not awaited), `updateAccount`, `deleteAccount` (also its favorites,
history and password), `toggleFavorite`, `setHiddenWords`, `setRefreshHours`, `setAppearance`, `backupJson()`,
`importBackup(bytes)`, `clear(ClearKind)`, `testConnection(...)`, `loadInfo/cachedInfo/hasInfo`, `loadEpisodes`, `episodeProgress`,
`loadEpgNow/epgPrograms`, `requestFor(Item)` and `episodeRequest(Episode, series)` (build `PlayRequest`s).

Constructor: `LibraryModel(db:, secrets:, prefs:, dbPath:, syncRunner:, client:, autoRefresh:, searchDebounce:, onClearImages:)`.
Tests pass an in-memory `AppDatabase`, `MemorySecretStore`, `inlineSyncRunner(db, client: MockClient)`, `autoRefresh: false`.

Reads and the small writes (favorites, progress) run on the UI isolate. A write waits behind a running catalog sync for at most
the sync's insert transaction (about 1 s for 100k items; `busy_timeout` is 5 s).

## How the player contract is wired

`ui/play.dart`: a tap goes through `openItem` (series: `SeriesScreen`; movie: details sheet; channel/direct link: play) and
`playItem`/`openPlayer`, which build `ShellPlayerHost(model, zapList:, onClose:)` and push
`MaterialPageRoute(builder: (_) => PlayerScreen(request: r, host: host))` (through `playerBuilder`, which tests replace).

- `request`: `model.requestFor(item)`: movies and episodes carry the resume position in `start` (0 for live), `item` is the library
  item (the series for an episode), `subtitle` is the episode title or the guide entry now. Only http(s), rtmp(s), rtsp, udp, rtp, mms
  URLs are accepted for M3U entries (`LibraryModel.safeStreamUrl`).
- `saveProgress`: `UserData.saveProgress` for the movie, or as `ep:<episodeId>` for an episode (the model remembers which episode a
  URL is). Never for live. 0/0 does not overwrite a resume point.
- `isFavorite/toggleFavorite`: the same favorites as the lists.
- `zap`: the neighbour channel in `zapList` (the list the user came from), wrapping.
- `nextEpisode`: `EpisodeQueue.next` over the cached episodes, across seasons.
- `liveProgramme`: the EPG title now (and starts a refresh in the background).
- `closePlayer`: pops the player route (once) and reloads the continue-watching shelves.

`lib/player/player_screen.dart` in this branch is a STUB (title, URL, close button); the player branch replaces it.

## Tests

`flutter test test/app`: `app_flow_test.dart` (widget tests: onboarding to library, wrong password, paste, EPG, search, categories,
favorites, details sheet, the PlayerHost contract for movies/episodes/live, settings deletes, RTL + large text), `model_test.dart`,
`source_draft_test.dart`, `secure_secret_store_test.dart`. In widget tests the model's futures need real event-loop turns: use
`settle`/`go` from `test/app/harness.dart`.
