# IPTVMac on the Mac App Store: owner checklist

Everything to fill in App Store Connect (ASC), in the order you meet it, and where the text lives. Nothing here is legal advice (privacy, export, content and licence questions are marked; ask a lawyer where it matters).

How facts are marked: **(read)** = I fetched the Apple page on 2026-10-11 and the text says it. **(memory)** = from my knowledge of ASC, not re-read today: check it on screen. The App Review Guidelines I read are dated "Last Updated: June 8, 2026".

Files in `appstore/`: `en-US/` and `localizations/<locale>/` (name, subtitle, promotional-text, description, keywords), `category.txt`, `age-rating.txt`, `copyright.txt`, `screenshots.txt`, `app-preview.txt`, `privacy-nutrition-label.txt`, `export-compliance.txt`, `content-rights.txt`, `review-notes.txt`, and two checkers: `check-listing.py` (limits and metadata rules) and `check-review-playlist.py` (the review playlist, `--online` re-tests the URLs). Public pages: `docs/privacy/`, `docs/support/` (and `docs/he/...`), the review playlist `docs/review/ReviewPlaylist.m3u`.

## 0. Decide first (only you can)

| # | Decision | My recommendation | Why |
|---|----------|-------------------|-----|
| 1 | **A public email address** on the Support page | Set `CONTACT_EMAIL` in `scripts/site/build.py`, run `python3 scripts/site/build.py`, commit. A dedicated address, not a personal one. | ASC help for the Support URL (read): it "must lead to actual contact information (legal address, email address, telephone number)". Guideline 1.5 (read): the Support URL needs "an easy way to contact you". The pages now offer only GitHub issues, which needs a GitHub account. |
| 2 | Ship **Downloads** in the App Store build? | Ship it only if you accept the 5.2.3 conversation (see section 4). The safest build omits it. | 5.2.3 (read): no "ability to save, convert, or download media from third-party sources ... without explicit authorization". Our answer (the user's own provider, nothing from public sites) is honest, but it is the feature most likely to get an IPTV player a question. |
| 3 | **Age rating** | Literal questionnaire answers (4+ calculated) plus *Override to Higher Age Rating* 18+ (16+ at least). | `age-rating.txt`. The app has no content but plays any source; 2.3.6 (read) makes mis-rating the developer's problem. `review-notes.txt` says 18+: edit it if you choose differently. |
| 4 | **Export compliance** path (A or B) | Read `export-compliance.txt`, then decide with a lawyer or BIS text. Do not put `ITSAppUsesNonExemptEncryption = NO` just to skip the questions. | The bundled mbedTLS/AES is not the OS's encryption. |
| 5 | **Copyright line** | `2026 Eli Friedman` unless your Apple seller name differs. | `copyright.txt`. |
| 6 | **GPL-3.0 and the App Store** | Take advice before the first submission. | See "Open source and the App Store" below. |
| 7 | **Merge and deploy this branch** | The privacy URL, support URL and review playlist exist only after `docs/` is on GitHub Pages. | Check with `curl -sI` (200 each) and `python3 appstore/check-review-playlist.py https://goelir.github.io/IPTVMac/review/ReviewPlaylist.m3u --online`. 2.1 (a) (read): "fully functional URLs ... empty websites ... should be scrubbed". |

## 1. Must be true in the submitted build (the other branch, `appstore-build`, owns the code; I did not touch it)

- [ ] App Sandbox on, with outgoing network and user-selected read/write files (download folder, backup export/import). 2.4.5 (i) (read).
- [ ] **No self-updater.** `UpdateChecker`, `UpdateInstaller`, `updateLoop` and the "Check for updates" toggles in Settings must be absent. 2.4.5 (vii) (read): "They must use the Mac App Store to distribute updates; other update mechanisms are not allowed." The privacy policy and review notes both say the App Store build has none.
- [ ] No code downloaded or executed at run time (2.4.5 (iv), 2.5.2 (read)); no `Process`/shell helper left running (2.4.5 (iii)); no license screen at launch (2.4.5 (vi)); one self-contained bundle with all 31 localizations (2.4.5 (ii), (ix)).
- [ ] **A privacy-policy link inside the app**, easy to find (Help menu or Settings): 5.1.1 (i) (read) "within the app in an easily accessible manner". There is none today (`IPTVMacApp.swift`, `SettingsView.swift` have no link). URL: `https://goelir.github.io/IPTVMac/privacy/`.
- [ ] Recommended: one line in the first-run guide, "IPTVMac includes no content. Use only sources you are authorized to access." (supports 5.2.1/5.2.2 and the content-rights answer).
- [ ] Credits/licence notices for the bundled libraries (libmpv and FFmpeg LGPL, GRDB.swift MIT) somewhere in the app (About or a Settings page).
- [ ] Info.plist: category `public.app-category.video` (memory) to match `category.txt`; `ITSAppUsesNonExemptEncryption` only after decision 4; ATS `NSAllowsArbitraryLoads` is what the review notes explain (change the notes if the build narrows it).
- [ ] Password storage: the policy says the Xtream password is in the local database, not in the Keychain, readable only by the user's account. If the App Store build moves it to the Keychain, change the sentence in `scripts/site/legal.py` (privacy "Passwords") in the same commit. Worth considering: with a stable Apple signing identity the old reason for dropping the Keychain (prompts on every new ad-hoc build, `SecretStore.swift`) no longer applies, and 1.6 (read) asks for "appropriate security measures" for user information.
- [ ] The hidden `--selftest` command-line switch (`SelfTest.swift`) is harmless, but 2.3.1 (a) (read) wants "no hidden, dormant, or undocumented features": either leave it out of the App Store build or mention it in the notes.
- [ ] IPv6-only networks (2.5.5, read): hostnames work, literal IPv4 provider addresses depend on the provider.

## 2. App Store Connect, in order

Sections 2.1 to 2.9 follow the ASC screens (names from memory: check the labels).

### 2.1 Before the app record
1. Apple Developer: accept the *Free Apps* agreement in "Agreements, Tax, and Banking" (memory). No bank or tax data is needed for a free app (memory).
2. Certificates and the app identifier for the Mac App Store, the upload method (Xcode or Transporter): the other branch's packaging notes (`scripts/APPSTORE.md`, named in my brief; not in this branch).

### 2.2 My Apps, New App
| Field | Value | Source |
|-------|-------|--------|
| Platform | macOS | |
| Name | `IPTVMac: IPTV Player` (20/30). Must be unique on the store. If taken: `IPTVMac Player`, then `IPTVMac for Mac` | `en-US/name.txt` |
| Primary language | English (U.S.) | |
| Bundle ID, SKU | from the build branch; the SKU cannot be changed later (read) | |
| User access | Full access | |

### 2.3 App Information
| Field | Value | Source |
|-------|-------|--------|
| Subtitle | `M3U playlists, instant search` (29/30) | `en-US/subtitle.txt` |
| Category | Primary Video, secondary Utilities. Not Entertainment (Korean GRAC regional rating, read) | `category.txt` |
| Content Rights | Yes, it accesses third-party content; Yes, use is permitted (explained) | `content-rights.txt` |
| Age Ratings | Set Up Age Ratings: all None/No; then Override to Higher 18+ | `age-rating.txt` |
| License Agreement | Apple's standard EULA (leave the default) | see "Open source and the App Store" |
| Privacy Policy URL | `https://goelir.github.io/IPTVMac/privacy/` | `privacy-nutrition-label.txt` |

### 2.4 Pricing and Availability
Free, no in-app purchase (3.1 does not apply: nothing is sold or unlocked). Availability: all regions is fine; the export-compliance France note (`export-compliance.txt`) and Korea (category) are the two regional items.

### 2.5 App Privacy
Answer **No** to "Do you or your third-party partners collect data from this app?" -> "Data Not Collected". Justification and the code evidence: `privacy-nutrition-label.txt`. Tracking: none.

### 2.6 The version page (macOS 1.0)
| Field | Value | Source |
|-------|-------|--------|
| Screenshots | 1 to 10, 16:10 (1280x800, 1440x900, 2560x1600 or 2880x1800), no alpha (read). Fast path from `docs/screenshots`, better a retake at 2880x1800 | `screenshots.txt` |
| App Preview | optional, 15 to 30 s, 1920x1080 for Mac (read). The existing demo (80 s, 720p) cannot be uploaded as is | `app-preview.txt` |
| Promotional Text | 145/170, can change without a new review | `en-US/promotional-text.txt` |
| Description | 2556/4000 | `en-US/description.txt` |
| Keywords | 97/100 **bytes** (read: bytes, not characters) | `en-US/keywords.txt` |
| Support URL | `https://goelir.github.io/IPTVMac/support/` (needs the email, decision 1) | |
| Marketing URL | `https://goelir.github.io/IPTVMac/` | |
| Version | e.g. 1.0 (the direct-download build is 0.9.x; the two can differ) | build branch |
| Copyright | `2026 Eli Friedman` (no (c) sign: read) | `copyright.txt` |
| What's New | not asked for the first version; template for later | `en-US/whats-new.txt` |
| Build | choose the uploaded build (appears after processing) | build branch |
| Export compliance | answer the encryption questions (or the Info.plist key) | `export-compliance.txt` |

### 2.7 App Review Information
| Field | Value |
|-------|-------|
| Sign-in required | untick (there is no account) |
| Contact | your name, phone, email (Apple's contact, not public) |
| Notes | paste PART 1 of `review-notes.txt` (3015 bytes; the limit is 4000 bytes, memory) |
| Attachment | optional: a short screen recording of the three steps |

### 2.8 Localizations (12 languages, AI-assisted drafts, see section 5)
Add each language in ASC (Add Language) and paste its five files. Screenshots are scaled for every language (read), so upload them once for English; retake two for Hebrew and Arabic if you like.

| Folder | ASC language (memory) | Support / privacy URL for that store |
|--------|-----------------------|--------------------------------------|
| `localizations/he` | Hebrew | `.../he/support/`, `.../he/privacy/` |
| `localizations/ar-SA` | Arabic | English pages (no Arabic pages exist) |
| `localizations/es-ES` | Spanish (Spain); reuse for Spanish (Mexico) | English pages |
| `localizations/fr-FR` | French | English pages |
| `localizations/de-DE` | German | English pages |
| `localizations/ru` | Russian | English pages |
| `localizations/tr` | Turkish | English pages |
| `localizations/pt-BR` | Portuguese (Brazil); European Portuguese needs a separate review | English pages |
| `localizations/it` | Italian | English pages |
| `localizations/zh-Hans` | Chinese (Simplified) | English pages |
| `localizations/ja` | Japanese | English pages |
| `localizations/ko` | Korean | English pages |

Descriptions of non-Hebrew stores link to the English policy and support pages. The Hebrew description links to the Hebrew pages. Support and privacy URLs can be localized per language in ASC (read: Support URL "can be localized").

### 2.9 Submit
1. Add for Review, choose "Manually release" if you want to hold the release after approval.
2. If a rejection arrives: answer in the Resolution Center with the templates in `review-notes.txt` Part 2; Appeals exist (read, "After You Submit").

Before pressing submit run: `python3 appstore/check-listing.py` (all limits), `python3 appstore/check-review-playlist.py --online`, `python3 scripts/site/build.py && python3 scripts/site/check.py`.

## 3. Pre-submission self-review against the App Review Guidelines (text read 2026-10-11)

Status: OK = true from what I read in this repository; OPEN = something to do; RISK = a real chance of a question.

| Section | What it asks | IPTVMac | Status |
|---------|--------------|---------|--------|
| 1.1 Objectionable content | no offensive content | The app has none. User sources can show anything; age override 18+. | OK / see 2.3.6 |
| 1.2 User-generated content | filtering, reporting, blocking, contact | No UGC, no posting, no accounts. | OK |
| 1.5 Developer information | Support URL with an easy way to contact | GitHub issues only for now. | **OPEN** (decision 1) |
| 1.6 Data security | appropriate security for user information | Passwords stored in a 0600 database, plain text, not the Keychain (`SecretStore.swift`). | **RISK**, see section 1 |
| 2.1 (a) App completeness | final build, working URLs, demo account if login, no placeholders | No login in the app; review playlist replaces a demo account; URLs live only after deploy. | **OPEN** (decision 7) |
| 2.3.1 (a) Hidden features | no hidden or undocumented features; describe features in Notes | Everything is listed in the notes; `--selftest` switch noted. | OPEN (small) |
| 2.3.3 Screenshots | show the app in use | Real-app frames on a neutral playlist. | OK after resizing |
| 2.3.4 Previews | screen captures of the app only | Needs a new 1080p, 15 to 30 s recording. | optional |
| 2.3.5 Category | most appropriate | Video + Utilities. | OK |
| 2.3.6 Age rating | answer honestly | literal answers + 18+ override. | OK if you accept the override |
| 2.3.7 Name, keywords | 30 characters, no trademarks, popular app names, prices or irrelevant phrases; subtitles must not reference other apps or make unverifiable claims | `check-listing.py` tests this: no brand or price word in name, subtitle or keywords. `Xtream Codes` appears only in descriptions as the name of a login type. | OK; see note below the table |
| 2.3.8 Metadata 4+ | icons, screenshots and previews suitable for 4+ | Invented titles, animation footage. | OK |
| 2.3.9 Rights to screenshots | hold rights; fictional account data | Invented titles; Sintel CC BY with credit. | OK |
| 2.3.10 Other platforms | no other platforms' names | `check-listing.py` checks the description. | OK |
| 2.3.12 What's New | describe changes | template given. | OK |
| 2.4.5 (i)-(ix) Mac App Store | sandbox, Xcode packaging, no login items, no other updates, no license screen, localizations in one bundle | build branch | **OPEN** (section 1) |
| 2.5.1 / 2.5.2 | public APIs only; self-contained; no downloaded code | The app uses AppKit/SwiftUI. I did not audit for private API use; libmpv is bundled. | OPEN: confirm with the build |
| 2.5.5 | works on IPv6-only networks | see section 1 | note |
| 3.1 Payments | in-app purchase for unlocks | free, nothing unlocked | OK |
| 4.1 (a)-(c) Copycats | own idea; no other brand in name or icon | own name and icon | OK |
| 4.2 Minimum functionality | more than a repackaged website; 4.2.2 not primarily a collection of links or a content aggregator | native player, local database, search, PiP | OK |
| 4.3 (a)/(b) Spam | one bundle ID; not indistinguishable from others | one app; differences listed in the notes | RISK (crowded category) |
| 5.1.1 (i) Privacy policy | link in ASC and in the app; what data, retention/deletion, revoking consent | policy page covers all three; in-app link missing | **OPEN** (section 1) |
| 5.1.1 (ii)-(iv) Consent, minimization, access | | no permissions requested, no data collected | OK |
| 5.1.1 (v) Account sign-in | account deletion if accounts are created | the app creates no account; provider credentials are the user's own | OK |
| 5.1.2 Data use and sharing | no sharing without permission | nothing shared | OK |
| 5.2.1 / 5.2.2 Third-party material and services | only content you created or license; permission from services; "Authorization must be provided upon request" | `content-rights.txt` | answered, keep documents |
| 5.2.3 Audio/video downloading | no downloading from third-party sources without authorization | Downloads of the user's own provider stream | **RISK** (decision 2) |
| 5.2.4 / 5.2.5 Apple endorsement / products | no implied endorsement; no confusion with Apple apps | none | OK |
| 5.6 Developer Code of Conduct | respectful replies, no manipulation | use the calm templates | OK |

Note on "Xtream": the protocol name appears in the description (and in the app's own labels, which the reviewer sees). It is the established name of a login type, but it is also the name of a former company, so I kept it out of name, subtitle and keywords (2.3.7 and 5.2.1). If you want zero exposure, replace it in the descriptions with "server address, username and password".

## 4. Facts behind the privacy policy (what I checked in the code; all paths from the repository root)

| Policy statement | Evidence |
|------------------|----------|
| No account, no analytics, no ads, no tracking, no third-party SDK | `Package.swift`: one dependency (GRDB.swift, local SQLite). No analytics, telemetry, crash-reporting or tracking identifiers in `Sources/` (searched). |
| Nothing is sent to the developer | Every `URLSession`/`URLRequest` in `Sources/`: `XtreamClient.swift` (`apiSession`: user's server), `SyncService.swift` (M3U fetch: the user's link), `Downloads.swift` (user's provider), `OnboardingView.swift` (test connection to the entered address), `Updater.swift` (github.com / api.github.com, direct build only). No other fixed address. |
| Talks only to servers the user adds, and the image/stream addresses they return | as above; images through `URLCache.shared` (`IPTVMacApp.swift:72`, 512 MB disk cache); `RemoteImage.safeURL` (`Models.swift:75`) refuses private-network addresses |
| Playlists, favorites, watch history, download settings stored locally | `AppDatabase.swift` (`iptv.sqlite` in Application Support, folder 0700, file 0600, lines 18-47), `UserDefaults` for the download folder and the finished-downloads list (`Downloads.swift`) |
| Password in the local database, not the Keychain, not encrypted, readable only by the user's account | `SecretStore.swift:18-19` ("plain text, owner-only file permissions ... not encrypted at rest; the Keychain was dropped on purpose"); `AppDatabase.swift:23` (0600 on the file and its `-wal`, `-shm`) |
| Update checks only in the direct-download build | `Updater.swift`, `AppModel.swift:507-532`, toggle `SettingsView.swift:20`. **Not yet gated in this branch**: the App Store build must remove it (2.4.5 (vii)). |
| Backup written only on export; never contains Xtream passwords | `Backup.swift:16-21` (fields: name, kind, server, username, url, favorites, history), `Backup.swift:52-57` (0600). **M3U links can carry a login and are saved as typed**: the policy says so (and `backup.warn` in the app says it). Your brief said "never contain passwords": true for Xtream passwords, not for logins inside an M3U link. |
| Trailer opens the browser | `ItemInfo.swift:31-34`, `AppModel+Data.swift:43` (`NSWorkspace.shared.open`, address built by the app from a validated id) |
| Seek thumbnails opt-in, second connection | `SettingsView.swift:89,108-109` (default `false`), `PlayerModel.swift:94` |
| Delete a source removes its lists, favorites, history, password | `AppDatabase.swift` (5 `onDelete: .cascade` tables), `AppModel.swift:303-312` (`deleteAccount`), `AppModel+Data.swift:61-63` (clear history, favorites, image cache) |
| Website: no cookies, no analytics, no external requests | `docs/*.html`, `docs/he/`, `docs/guides/`, `docs/privacy/`, `docs/support/`: no `<script src>`, `<link>` or image pointing to another host (grep); fonts are self-hosted in `docs/assets/fonts`; `site.js` uses `localStorage` for the theme only (`site.js:13`); the only YouTube strings are plain links and a JSON-LD `embedUrl`, no `<iframe>` (grep). GitHub Pages is the host. |
| Effective date | `scripts/site/legal.py`, `EFFECTIVE = "2026-10-11"` |

## 5. What is machine-written, what to review

- **Translations (AI-assisted, 12 languages: he, ar, es, fr, de, ru, tr, pt-BR, it, zh-Hans, ja, ko)** and the Hebrew privacy and support pages were written by an AI. Names, subtitles and keywords were checked for length and rules by script, not by a native speaker. You read Hebrew: read those; have a native speaker look at the others or ship only the languages you trust. The app UI labels quoted in the steps are the app's own strings from `Sources/IPTVMac/Resources/<lang>.lproj`.
- **Keywords** are my guess at useful words, not keyword-research data. Apple's text (read): names of other apps or companies are not allowed; 100 bytes; each keyword longer than two characters (I allowed two-character Chinese, Japanese and Korean words: drop one if ASC rejects it).
- Privacy, export, content-rights and licence answers are explanations of the facts, not legal advice.

## 6. Open source and the App Store (ask a lawyer)

- `LICENSE` is GPL-3.0. A copyright holder can distribute their own code under Apple's terms as well, but only for code they own. The git history shows two author names (`Eli Friedman`, `Goelir`) that I assume are you; any outside contribution would need its author's agreement.
- The bundled libmpv and FFmpeg are LGPL builds (README: `-Dgpl=false`, `--enable-version3` without `--enable-gpl`). LGPL asks that users can replace the library and that notices are kept. A sandboxed, signed App Store app limits replacing a dylib. Whether that is acceptable under LGPL-3.0 is a legal question; the in-app credits and the source offer (`https://github.com/Goelir/IPTVMac`) are the minimum.
- Apple's standard EULA applies to the App Store build unless you supply a custom one; saying "open source" in the description is true of the source repository.

## 7. Things I could not verify

- I never ran the app (instruction). The review steps use the exact labels from the code, the playlist was parsed with the app's own `M3U.swift` (compiled stand-alone) and the URLs were played in headless Homebrew `mpv`, not in the bundled libmpv inside the sandboxed app.
- The playlist URL on GitHub Pages does not exist until deploy.
- ASC screen names and field limits marked (memory) above.
- The Elephants Dream licence version.
