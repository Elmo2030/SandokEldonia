# Signing and notarizing IPTVMac (so macOS opens it without a warning)

Needs a paid Apple Developer Program membership. Nothing here is secret: the certificate's private key stays in your login Keychain
and the notary credentials stay in a Keychain profile. Never paste passwords or keys into a chat or an issue.

## One-time setup

1. **Membership approved** (developer.apple.com/account shows your Team ID).
2. **Developer ID Application certificate.** In Xcode: Settings > Accounts > your team > Manage Certificates > + > *Developer ID Application*.
   (Or at developer.apple.com/account/resources/certificates: create one, download and double-click it.) Check:
   `security find-identity -v -p codesigning` lists `Developer ID Application: Your Name (TEAMID)`.
3. **Notary credentials.** Create an app-specific password at appleid.apple.com (Sign-In and Security > App-Specific Passwords), then run once, in Terminal:
   `xcrun notarytool store-credentials IPTVMac-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID`
   and type the app-specific password when asked (it is stored in the Keychain, not in any file).
4. **Check everything:** `bash scripts/notary-preflight.sh` (prints what is still missing).

## Every release

```
IPTVMAC_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/release.sh notes.md
```
`make-app.sh` signs every bundled dylib and the app with the hardened runtime, runs `--selftest`, `make-dmg.sh` has the app notarized and stapled,
builds and signs the DMG, has the DMG notarized and stapled, and only then does `release.sh` compute the SHA-256 and the release signature
(the checksum must be taken after stapling, because stapling changes the file). Without `IPTVMAC_SIGN_IDENTITY` nothing changes: ad-hoc build as before.

## Test the hardened runtime without a certificate
`IPTVMAC_HARDENED=1 scripts/make-app.sh` builds with the hardened runtime and an ad-hoc signature and runs `--selftest`.

## If something fails
- *Notarization "Invalid"*: `scripts/notarize.sh` prints Apple's log. Usual causes: a dylib not signed (all are re-signed by make-app.sh), missing secure timestamp, or an unsigned nested binary.
- *App crashes at launch only when signed*: read the crash report; add the one entitlement it names to `scripts/entitlements.plist`.
- The first notarized version is written as "0.9.1" in README.md, README.he.md, SECURITY.md and the install.sh header comment, and as `NOTARIZED_FROM` in scripts/site/build.py (the website, llms.txt and the FAQ read it from there; rebuild with `python3 scripts/site/build.py`). If the version number changes, update all of them (`grep -rn "0\.9\.1"` finds the text). `install.sh` keeps working.
