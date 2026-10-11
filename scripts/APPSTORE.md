# Mac App Store build (Phase 0)

A second build of the same app for the Mac App Store: compiled with `-DAPPSTORE` (no self-updater), running under the App Sandbox, signed with
the Team's Apple Distribution certificate and packaged as a signed `.pkg` for App Store Connect. The direct-download build (`scripts/make-app.sh`,
DMG, `install.sh`, in-app updater) is unchanged.

| File | What it is |
|---|---|
| `scripts/make-appstore.sh` | Builds `build-appstore/IPTVMac.app` and, with the installer identity, `build-appstore/IPTVMac-<version>-<build>.pkg`. With no variables set it makes an ad-hoc signed, sandboxed app and runs `--selftest` and `--sandbox-probe` on it. |
| `scripts/upload-appstore.sh` | Uploads the `.pkg` with `xcrun altool` and an App Store Connect API key. `DRY_RUN=1` prints the command. |
| `scripts/appstore.entitlements` | The four sandbox entitlements, each justified in a comment. No temporary-exception entitlements. |
| `scripts/APPSTORE_BUILD_NUMBER` | The next `CFBundleVersion` (integer, only goes up). The marketing version stays in `VERSION`. |
| `IPTVMac --sandbox-probe` | Hidden flag: prints one JSON line about what the process can and cannot do and exits. No window. Also in the direct build (it then says `sandbox:false`). |

## 1. Once: what you create in Apple's portals

You need a paid Apple Developer Program membership (its Team ID is the 10 characters in brackets of your certificate names).

1. **Bundle ID.** developer.apple.com > Certificates, Identifiers & Profiles > Identifiers > `+` > App IDs > App > platform macOS, explicit ID
   `io.github.goelir.IPTVMac`. No capabilities have to be ticked (the App Sandbox needs no portal switch). That ID is what the build uses; any
   unique reverse-DNS ID is accepted, App Review does not check that you own `github.io`. Decide now: the ID of an App Store Connect record can never be
   changed, and the planned iOS app would share it for a universal purchase. If you prefer an ID under a domain you control, change `BUNDLE_ID` in
   `scripts/make-appstore.sh` and `CFBundleIdentifier` in `scripts/make-app.sh` together (the direct build may keep its own ID).
2. **Two certificates** (Xcode > Settings > Accounts > your team > Manage Certificates > `+` does both; or the portal with a CSR from Keychain Access):
   - **Apple Distribution** (signs the app and its libraries). In the keychain it is named `Apple Distribution: Your Name (TEAMID)`.
   - **Mac Installer Distribution** (signs the `.pkg`). In the keychain it is usually named `3rd Party Mac Developer Installer: Your Name (TEAMID)`.
   Check both are in the login keychain with their private key: `security find-identity -v | grep -E "Distribution|Installer"`. Use the exact names as
   the two identities below. (Developer ID certificates, used for the DMG, are a different pair and do not work for the store.)
3. **Provisioning profile.** Profiles > `+` > Distribution > **Mac App Store Connect** (older name: Mac App Store) > App ID `io.github.goelir.IPTVMac`
   > the Apple Distribution certificate > name it `IPTVMac Mac App Store` > download `IPTVMac_Mac_App_Store.provisionprofile` to a folder outside the repository.
   The script reads the Team ID and the app identifier from it and refuses a profile of another app, a development profile and an expired one. A profile expires
   after a year; make a new one then.
4. **App Store Connect record.** appstoreconnect.apple.com > Apps > `+` > New App: platform macOS, name, primary language, the bundle ID above, a SKU
   (any text, for example `iptvmac`), user access Full. Then the store listing (texts and screenshots: the store-listing work, `appstore/`), the privacy policy URL, the support URL,
   the age rating questionnaire, the category (Entertainment, same as `LSApplicationCategoryType`), price, and the export compliance answer (section 4).
5. **App Store Connect API key** (no password is ever used). App Store Connect > Users and Access > Integrations > App Store Connect API > Team Keys > `+`,
   role **App Manager** (check Apple's role table if a different role is offered). Download the `.p8` **once** (Apple does not keep it), keep it outside the repository,
   `chmod 600` it. Note the **Key ID** and, above the key list, the **Issuer ID**.

## 2. Environment variables

Put them in your shell profile or a file you `source` that is NOT in the repository. Nothing here is ever printed or committed by the scripts.

```sh
export IPTVMAC_APPSTORE_IDENTITY="Apple Distribution: Your Name (TEAMID)"
export IPTVMAC_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Your Name (TEAMID)"
export IPTVMAC_PROVISIONING_PROFILE="$HOME/AppleSigning/IPTVMac_Mac_App_Store.provisionprofile"
export IPTVMAC_COPYRIGHT="Copyright © 2026 Your Name"            # the default is a generic text: set your own
export IPTVMAC_ASC_KEY_ID="ABC123DEFG"
export IPTVMAC_ASC_ISSUER_ID="00000000-0000-0000-0000-000000000000"
export IPTVMAC_ASC_KEY_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_ABC123DEFG.p8"
```

Optional: `IPTVMAC_BUILD_NUMBER` (one-off build number), `IPTVMAC_NON_EXEMPT_ENCRYPTION=1` (section 4), `IPTVMAC_APPSTORE_HARDENED=1` (hardened runtime, section 7),
`IPTVMAC_SKIP_PROBE=1`, `DRY_RUN=1`, `VALIDATE_ONLY=1`, `WAIT=1` (upload script).

## 3. Commands

```sh
# a) Local sandbox test, needs no certificate: ad-hoc signed, sandboxed, then --selftest and --sandbox-probe (fails loudly if the sandbox is not on)
env -u IPTVMAC_APPSTORE_IDENTITY -u IPTVMAC_INSTALLER_IDENTITY -u IPTVMAC_PROVISIONING_PROFILE scripts/make-appstore.sh

# b) The store build and package (version from VERSION, build number from scripts/APPSTORE_BUILD_NUMBER)
scripts/make-appstore.sh                      # -> build-appstore/IPTVMac-0.9.1-1.pkg

# c) Look at the upload command first, then check the package against App Store Connect without creating a build, then upload
DRY_RUN=1 scripts/upload-appstore.sh
VALIDATE_ONLY=1 scripts/upload-appstore.sh
scripts/upload-appstore.sh                    # raises scripts/APPSTORE_BUILD_NUMBER by one on success: commit it
```

`altool` is the tool on this Mac (`xcrun altool --upload-package <pkg> --api-key <id> --api-issuer <uuid> --p8-file-path <key>`; the script checks the installed
`altool` knows these options first). The Transporter app (Mac App Store) uploads the same `.pkg` by drag and drop with your Apple ID if `altool` ever refuses.

A release of the store build: bump `VERSION` (marketing version, shared with the direct build), keep `scripts/APPSTORE_BUILD_NUMBER` as the script left it, run b) and c).
Build numbers must never repeat for one version; the script raises the number only after a real upload.

## 4. TestFlight, then review

1. After the upload App Store Connect processes the build (minutes to an hour; `WAIT=1` waits). An email arrives; errors (`ITMS-...`) come by email too.
2. App Store Connect > your app > TestFlight > the build appears under macOS builds. Answer the **export compliance** question if it is asked
   (the build carries `ITSAppUsesNonExemptEncryption`, so normally it is not).
3. Internal testing: TestFlight > Internal Testing > `+` group > add testers who are users of your App Store Connect team > assign the build. They get
   an email and install it with the TestFlight app on a Mac. External testers need a first "Beta App Review".
4. Test the build from TestFlight (add a source, play, download into a folder, subtitles, backup export/import, quit and reopen: the downloads folder must come back).
5. App Store tab > the version > select the build > fill "App Review Information" (below) > Submit for Review.

**Encryption.** The scripts declare `ITSAppUsesNonExemptEncryption = false`. The app uses HTTPS through macOS (exempt) and through mbedTLS inside libmpv. Apple's
questionnaire treats standard TLS limited to talking to servers as exempt, but "third-party library instead of the OS" is the grey zone (the
feasibility report, section 5, marks it unverified). It is your legal declaration: read Apple's "Determine your export compliance requirements" page; if the answer is
"not exempt", build with `IPTVMAC_NON_EXEMPT_ENCRYPTION=1` and supply the compliance code App Store Connect asks for.

### App Review notes (paste into App Review Information, adapt)

> IPTVMac is a player for IPTV sources that the user adds (an Xtream Codes login or an M3U/M3U8 link from the user's own provider). The app contains no channels,
> playlists, or links to any, and does not suggest sources. To test it: Settings > Playlists > add a source with the test account below, then pick a channel or movie.
> Demo source: *(the owner fills in: a legal test playlist, with its username and password, valid for the whole review)*.
>
> App Transport Security: the app sets NSAllowsArbitraryLoads. Providers of IPTV services overwhelmingly serve their API and streams over plain `http://host:port`
> addresses (often a bare IP address and a custom port) that the user types in; the app connects only to addresses the user has entered, never to a fixed host
> of ours, and cannot know them in advance, so a per-domain exception is impossible. HTTPS sources are verified (certificate verification is on in the player and in URLSession).
>
> Entitlements: App Sandbox, network client (connections to the user's sources), user-selected read/write files (the downloads folder the user chooses, subtitle files,
> settings backup), app-scoped bookmarks (to remember the chosen downloads folder). No temporary exceptions.
>
> The app has no update mechanism of its own; the Mac App Store updates it.

## 5. What this build verified here (ad-hoc, no certificates) and what it cannot

Verified on this Mac by `make-appstore.sh` (ad-hoc signature with the real entitlements, which is how the sandbox is switched on without a profile):

- The sandbox is on (`APP_SANDBOX_CONTAINER_ID` set, entitlements read back from the process), the home folder is closed (a file cannot be created in it), the container is writable.
- URLSession reaches `https://example.com` (network.client), libmpv loads and plays the generated WAV, mpv verifies HTTPS against `/etc/ssl/cert.pem` (readable in the sandbox)
  and also against the bundled copy, and refuses a self-signed server unless verification is switched off.
- The database opens and migrates inside the container, with the 0700 folder / 0600 file permissions.
- A security-scoped bookmark of a folder round-trips (make, resolve, start access, write, stop), also through `FolderBookmark`, the code the downloads use.
- The built `.app` has no updater code at all (`strings` finds no `hdiutil`, `github.com`, `releases/download`), a CFBundleVersion that is the build number, and the Info.plist keys listed in section 6.
- `productbuild` packages the app and `altool` parses the package (then asks for credentials). The profile checks (team, bundle id, expiry, not a development profile) were run against a synthetic profile.

**Not verified, because it needs your certificates, the real profile or Apple's servers:**

- Signing with `Apple Distribution` and `productbuild --sign` with the installer certificate (the commands are standard; a wrong identity name fails loudly in `codesign`/`productbuild`).
- That the app launches with the embedded profile and the `com.apple.application-identifier` / `com.apple.developer.team-identifier` entitlements the script adds from it. Test the first
  signed build by installing the `.pkg` (double click) and starting it from /Applications.
- The upload itself, App Store Connect's validation of the bundle (`ITMS-` errors). Things it may ask for that Xcode adds automatically and a hand-assembled bundle lacks (`DTSDKName`, `DTXcode`...),
  or a complaint about the SwiftPM resource bundle `Contents/Resources/IPTVMac_IPTVMac.bundle`: `VALIDATE_ONLY=1 scripts/upload-appstore.sh` reports these before a real upload; fix the Info.plist in `make-appstore.sh`.
- The real flow with a user-chosen folder: the open panel can not be driven headless. The bookmark API and `FolderBookmark` are tested; the panel -> bookmark -> quit -> relaunch -> download path
  and playing a downloaded file need one manual run (section 4, step 4). Same for dropping a subtitle file on the player.
- The hardened-runtime variant with a real Team ID signature, TestFlight, and App Review.

## 6. Behaviour differences, direct build vs App Store build

| Area | Direct build (DMG, `install.sh`) | App Store build |
|---|---|---|
| Updates | Checks GitHub every 6 h, banner, "Check for updates" and two toggles in Settings, installs from a DMG (hdiutil, a swap script on quit) | None of it: the code is compiled out (`#if !APPSTORE` in `Updater.swift`, `ReleaseSignature.swift`, `UpdateBanner.swift`, `AppModel`, `SettingsView`, `RootView`, `IPTVMacApp`). The Mac App Store updates the app. Settings still shows "Current version". The `update.*` strings stay in the language files, unused |
| Sandbox | None | App Sandbox: only the user-chosen folders and files are reachable |
| Where data lives | `~/Library/Application Support/IPTVMac/iptv.sqlite`, `~/Library/Preferences/io.github.goelir.IPTVMac.plist` | `~/Library/Containers/io.github.goelir.IPTVMac/Data/...` (database and preferences). The direct build's data is NOT migrated (the sandbox cannot read it): Settings > Backup > Export in the old app, Import in the new one |
| Downloads folder | A path string; asked at the first download | A security-scoped bookmark (also in the direct build now: an existing path is converted once). Asked at the first download; a folder that is gone, in the Trash or no longer reachable is asked again, also on Resume. In the store build only the current folder is reachable: if the folder is changed, files in the old one can still be shown in Finder, but not trashed or played from inside the app. The destination of a queued download is the folder chosen when it finishes |
| Subtitles | Picker and drag and drop | Same. A subtitle that needs a sibling file (VobSub `.idx` + `.sub`) cannot load the sibling in the sandbox |
| Player TLS | Verifies HTTPS against `/etc/ssl/cert.pem` | Same file (readable in the sandbox). If it ever is not, a copy bundled as `Contents/Resources/cacert.pem` is used. Verification is never switched off |
| Info.plist | `CFBundleVersion` = version | `CFBundleVersion` = build number (integer), `ITSAppUsesNonExemptEncryption`, `LSApplicationCategoryType` = entertainment, `NSHumanReadableCopyright`. `NSAppTransportSecurity` is the same (arbitrary loads: users add http sources) |
| Signing | Ad-hoc, or Developer ID + hardened runtime + notarization | Apple Distribution + sandbox entitlements + embedded profile, then a Mac Installer Distribution signed `.pkg`. No notarization (the store does its own checks). Hardened runtime off unless `IPTVMAC_APPSTORE_HARDENED=1` |
| Entitlements | None (empty file for the hardened runtime) | `app-sandbox`, `network.client`, `files.user-selected.read-write`, `files.bookmarks.app-scope`. NOT requested: `files.downloads.read-write` (the user picks the folder in a panel), `network.server`, any `temporary-exception` |
| External links | Release notes / manual download links in the update banner | None. There are no links to free or public playlists anywhere in either build (onboarding and all strings were checked: the only URLs are the `http://host:8080` placeholders); the banner links go with the updater. Movie trailers still open the provider's YouTube link in the browser |
| Distribution | GitHub release, DMG | `.pkg` via App Store Connect |
| Hidden flags | `--selftest`, `--sandbox-probe` | the same two |

## 7. Decisions and details

- **Hardened runtime**: not required for the Mac App Store (it is a notarization requirement) and the sandbox is the containment the store relies on. It also cannot be tested with an
  ad-hoc signature (library validation needs a Team ID), so the default is off; `IPTVMAC_APPSTORE_HARDENED=1` turns it on for the owner to try with the real identity.
- **Signing order**: every `.dylib` in `Contents/Frameworks`, then the app with the entitlements; no `--deep`. The entitlements file is merged with the team and application identifiers read from the profile.
- **Build number file**: `scripts/APPSTORE_BUILD_NUMBER` (not in `appstore/`, which belongs to the store texts). `make-appstore.sh` never changes it, so a rebuild gives the same package; `upload-appstore.sh` raises it after a successful upload.
- **Idempotent**: `build-appstore/` (gitignored) is rebuilt from the sources every run, with its own SwiftPM scratch folder, so the direct build's `.build` is not disturbed.
- **Tests** (`scripts/swift.sh test`) run against the direct build: `UpdaterTests` needs the updater, which the `-DAPPSTORE` build does not contain. The App Store build is checked by `make-appstore.sh` itself (compile, signature, `--selftest`, `--sandbox-probe`).
- **Local test leftovers**: running the ad-hoc build creates `~/Library/Containers/io.github.goelir.IPTVMac` (preferences and HTTP caches; the probe deletes its throwaway database). Delete it before your first real install if you want a clean container.

## 8. Reading `--sandbox-probe`

`build-appstore/IPTVMac.app/Contents/MacOS/IPTVMac --sandbox-probe` (exit code 0 = everything that must hold does). The keys that matter:

| Key | Direct build | Sandboxed build |
|---|---|---|
| `sandbox`, `entitlements.app-sandbox` | false | true |
| `writeInRealHome`, `writeInRealLibrary`, `listRealLibrary` | true | **false** |
| `writeInHome`, `writeInTemp` | true | true (inside the container) |
| `caFileReadable`, `mpvTLS.example` | true, `verified` | true, `verified` |
| `mpvTLS.selfSigned` (with `IPTVMAC_PROBE_SELFSIGNED_URL` set) | `rejected` | `rejected` |
| `database.dir` | `~/Library/Application Support/IPTVMac` | inside `~/Library/Containers/io.github.goelir.IPTVMac` |
| `bookmark.bookmarkOfUngrantedFolder` | made | **refused** (why a plain path from an earlier session cannot be kept) |
| `updaterCompiledIn`, `build` | true, `direct` | false, `appstore` |

If your network blocks example.com, set `IPTVMAC_PROBE_URL=https://some.other.host/` (any HTTPS page that is HTML) before running the probe.

To see that certificate verification is really on, run the probe against a local server with a self-signed certificate (in a throwaway folder, not the repository):

```sh
openssl req -x509 -newkey rsa:2048 -nodes -keyout k.pem -out c.pem -subj /CN=localhost -days 1
python3 -c "import wave; w=wave.open('test.wav','wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000); w.writeframes(bytes(96000)); w.close()"
python3 -c "
import http.server, ssl
class H(http.server.SimpleHTTPRequestHandler): protocol_version = 'HTTP/1.1'
s = http.server.ThreadingHTTPServer(('127.0.0.1', 18444), H)
c = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); c.load_cert_chain('c.pem', 'k.pem')
s.socket = c.wrap_socket(s.socket, server_side=True); s.serve_forever()" &
IPTVMAC_PROBE_SELFSIGNED_URL=https://127.0.0.1:18444/test.wav /path/to/IPTVMac.app/Contents/MacOS/IPTVMac --sandbox-probe
kill %1
```

`mpvTLS.selfSigned` must be `rejected` (the player refused the certificate) and `mpvTLS.selfSignedVerifyOff` `reached` (the same server plays once verification is switched off, so the
refusal was the certificate check and nothing else). A server that sends no Content-Length (`openssl s_server -www`) makes the second step time out: use the one above.
