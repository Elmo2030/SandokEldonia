import Foundation
import Security
import IPTVCore
import IPTVPlayer

/// `IPTVMac --sandbox-probe`: prints ONE JSON line describing what this process can and cannot do, then exits (0 = every check that
/// must hold did). No window, no UI. Run it on the direct build (sandbox=false) and on the ad-hoc signed App Store build
/// (scripts/make-appstore.sh, sandbox=true) to see what the App Sandbox changes. See scripts/APPSTORE.md.
/// Optional: IPTVMAC_PROBE_URL=https://host/ replaces https://example.com/ (a network that blocks it); the page must be HTML, not media.
/// Optional: IPTVMAC_PROBE_SELFSIGNED_URL=https://127.0.0.1:PORT/file.wav (a local server with a self-signed certificate that serves a media file
/// with a Content-Length, see scripts/APPSTORE.md section 8): checks that mpv refuses it while verification is on, and plays it with
/// verification off (the server is fine, verification is what refuses).
enum SandboxProbe {
    static func run() -> Never {
        var r: [String: Any] = [:]
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        let publicURL = env["IPTVMAC_PROBE_URL"] ?? "https://example.com/"
        let sandbox = env["APP_SANDBOX_CONTAINER_ID"] != nil
        r["sandbox"] = sandbox
        r["containerId"] = env["APP_SANDBOX_CONTAINER_ID"] ?? NSNull()
        r["build"] = {
            #if APPSTORE
            "appstore"
            #else
            "direct"
            #endif
        }()
        r["updaterCompiledIn"] = {
            #if APPSTORE
            false
            #else
            true
            #endif
        }()
        let info = Bundle.main.infoDictionary ?? [:]
        r["version"] = "\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))"
        r["entitlements"] = entitlements()

        // Folders. NSHomeDirectory() is the container's data folder inside the sandbox; the real home comes from the user database.
        r["home"] = NSHomeDirectory()
        r["realHome"] = realHome
        r["writeInHome"] = canCreateFile(in: NSHomeDirectory())
        r["writeInRealHome"] = canCreateFile(in: realHome)                  // must be false in the sandbox
        r["writeInRealLibrary"] = canCreateFile(in: realHome + "/Library/Application Support")   // must be false in the sandbox
        r["writeInTemp"] = canCreateFile(in: fm.temporaryDirectory.path)
        r["listRealLibrary"] = (try? fm.contentsOfDirectory(atPath: realHome + "/Library/Preferences")) != nil   // must be false in the sandbox
        // (Documents, Desktop and Downloads are left alone on purpose: touching them can pop up a privacy prompt on the direct build.)
        r["statRealLibrary"] = fm.fileExists(atPath: realHome + "/Library")     // metadata: the downloads list checks files this way

        // TLS roots: readable by the sandboxed process? (mpv verifies HTTPS against this file.)
        let ca = "/etc/ssl/cert.pem"
        r["caFileReadable"] = fm.isReadableFile(atPath: ca)
        r["caFileBytes"] = (try? Data(contentsOf: URL(fileURLWithPath: ca)).count) ?? -1
        r["caFileBundled"] = Bundle.main.path(forResource: "cacert", ofType: "pem") != nil

        // Network client entitlement: a plain URLSession HTTPS request.
        r["urlSession"] = httpsGET(publicURL)

        // Database: opens in the (container) Application Support folder, migrates, keeps the owner-only permissions.
        r["database"] = database()

        // libmpv: loads and plays the generated WAV (the --selftest check), then TLS verification inside mpv.
        let play = SelfTest.playWAV()
        r["mpv"] = ["version": play.version, "timePos": play.pos, "plays": play.pos > 0.5] as [String: Any]
        r["mpvTLS"] = mpvTLS(publicURL, selfSigned: env["IPTVMAC_PROBE_SELFSIGNED_URL"])

        r["bookmark"] = bookmarkRoundTrip()

        // What must hold. In the sandbox the home folder must be closed; everywhere the app's own needs must work.
        func b(_ v: Any?) -> Bool { v as? Bool == true }
        let db = r["database"] as? [String: Any] ?? [:], bm = r["bookmark"] as? [String: Any] ?? [:]
        let tls = r["mpvTLS"] as? [String: Any] ?? [:]
        let ok = b(r["writeInHome"]) && b(r["writeInTemp"]) && b(r["caFileReadable"])
            && b((r["urlSession"] as? [String: Any])?["ok"]) && b(db["ok"]) && play.pos > 0.5 && b(bm["ok"])
            && tls["example"] as? String == "verified" && (tls["selfSigned"] as? String ?? "rejected") == "rejected"
            && (tls["selfSignedVerifyOff"] as? String ?? "reached") == "reached"
            && (!sandbox || (!b(r["writeInRealHome"]) && !b(r["writeInRealLibrary"]) && !b(r["listRealLibrary"])))
        r["ok"] = ok
        let data = (try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        print(String(decoding: data, as: UTF8.self))
        exit(ok ? 0 : 1)
    }

    /// The user's real home folder (NSHomeDirectory() is the container's data folder inside the sandbox).
    private static let realHome = String(cString: getpwuid(getuid()).pointee.pw_dir)

    private static func entitlements() -> [String: Bool] {
        guard let task = SecTaskCreateFromSelf(nil) else { return [:] }
        var out: [String: Bool] = [:]
        for k in ["app-sandbox", "network.client", "files.user-selected.read-write", "files.bookmarks.app-scope", "files.downloads.read-write",
                  "network.server", "device.camera", "device.audio-input"] {
            out[k] = SecTaskCopyValueForEntitlement(task, "com.apple.security.\(k)" as CFString, nil) as? Bool ?? false
        }
        return out
    }

    /// Creates and removes a file; false when the sandbox (or permissions) refuse.
    private static func canCreateFile(in dir: String) -> Bool {
        let path = dir + "/.iptvmac-probe-\(UUID().uuidString)"
        guard FileManager.default.createFile(atPath: path, contents: Data("x".utf8)) else { return false }
        try? FileManager.default.removeItem(atPath: path)
        return true
    }

    private static func httpsGET(_ url: String) -> [String: Any] {
        var out: [String: Any] = ["ok": false]
        let done = DispatchSemaphore(value: 0)
        var req = URLRequest(url: URL(string: url)!); req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let h = resp as? HTTPURLResponse { out = ["ok": (200..<400).contains(h.statusCode), "status": h.statusCode, "bytes": data?.count ?? 0] }
            else { out = ["ok": false, "error": err?.localizedDescription ?? "no response"] }
            done.signal()
        }.resume()
        if done.wait(timeout: .now() + 20) == .timedOut { return ["ok": false, "error": "timeout"] }
        return out
    }

    /// Same folder as the real database, but a throwaway file: the user's data is never opened.
    private static func database() -> [String: Any] {
        var out: [String: Any] = ["ok": false]
        do {
            let real = try AppDatabase.defaultPath()
            let dir = (real as NSString).deletingLastPathComponent
            out["dir"] = dir
            let path = dir + "/probe-\(UUID().uuidString).sqlite"
            defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + s) } }
            let db = try AppDatabase(path: path)
            let migrated = try db.dbQueue.read { try $0.tableExists("account") && $0.tableExists("item_fts") }
            func mode(_ p: String) -> Int { ((try? FileManager.default.attributesOfItem(atPath: p))?[.posixPermissions] as? Int) ?? -1 }
            out["fileMode"] = String(mode(path), radix: 8); out["dirMode"] = String(mode(dir), radix: 8)
            out["migrated"] = migrated
            out["ok"] = migrated && mode(path) == 0o600 && mode(dir) == 0o700
        } catch { out["error"] = "\(error)" }
        return out
    }

    /// mpv's own HTTPS check. A page that is not media ends with "unrecognized file format" AFTER a successful TLS handshake, media starts
    /// playing, and a refused certificate ends with "loading failed": that tells the cases apart.
    private static func mpvTLS(_ publicURL: String, selfSigned: String?) -> [String: Any] {
        func open(_ url: String, verify: Bool = true, caFile: String? = nil) -> String {
            let p = MPVPlayer(subLang: nil, audioLang: nil)
            defer { p.shutdown() }
            p.setProperty("vo", "null")
            if !verify { p.setProperty("tls-verify", "no") }
            if let caFile { p.setProperty("tls-ca-file", caFile) }
            p.load(url, start: 0)
            for _ in 0..<250 {
                Thread.sleep(forTimeInterval: 0.1)
                if (p.double("time-pos") ?? 0) > 0.1 { return verify ? "verified" : "reached" }
                if let e = p.lastError { return e == "unrecognized file format" ? (verify ? "verified" : "reached") : e == "loading failed" ? "rejected" : e }
            }
            return "timeout"
        }
        let p = MPVPlayer(subLang: nil, audioLang: nil)
        var out: [String: Any] = ["caFile": p.string("options/tls-ca-file") ?? "", "verify": p.string("options/tls-verify") ?? ""]
        p.shutdown()
        out["example"] = open(publicURL)
        if let bundled = Bundle.main.path(forResource: "cacert", ofType: "pem") { out["exampleWithBundledCA"] = open(publicURL, caFile: bundled) }
        if let selfSigned {
            out["selfSigned"] = open(selfSigned)
            out["selfSignedVerifyOff"] = open(selfSigned, verify: false)
        }
        return out
    }

    /// Security-scoped bookmark of a folder created in a temporary location: make, resolve, start access, write, stop; then the same
    /// through FolderBookmark (the code the downloads use).
    private static func bookmarkRoundTrip() -> [String: Any] {
        var out: [String: Any] = ["ok": false]
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("iptvmac-probe-folder-\(UUID().uuidString)", isDirectory: true)
        let suite = "iptvmac-probe-\(UUID().uuidString)"
        defer { try? fm.removeItem(at: dir); UserDefaults.standard.removePersistentDomain(forName: suite) }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try dir.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            let scoped = url.startAccessingSecurityScopedResource()
            let wrote = fm.createFile(atPath: url.appendingPathComponent("a.txt").path, contents: Data("x".utf8))
            if scoped { url.stopAccessingSecurityScopedResource() }
            // A folder this process was never granted (the real home): the sandbox refuses to bookmark it. This is why a plain path saved in an
            // earlier session cannot be turned into a bookmark afterwards, and why the downloads folder has to be remembered as a bookmark.
            out["bookmarkOfUngrantedFolder"] = (try? URL(fileURLWithPath: realHome)
                .bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)) != nil ? "made" : "refused"
            out["made"] = true; out["resolved"] = url.resolvingSymlinksInPath().path == dir.resolvingSymlinksInPath().path; out["stale"] = stale
            out["scoped"] = scoped; out["wrote"] = wrote

            let folder = FolderBookmark(defaults: UserDefaults(suiteName: suite)!)
            try folder.choose(dir)
            let viaClass = folder.withAccess { fm.createFile(atPath: $0.appendingPathComponent("b.txt").path, contents: Data("y".utf8)) } ?? false
            out["viaFolderBookmark"] = viaClass
            out["ok"] = wrote && viaClass && out["resolved"] as? Bool == true
        } catch { out["error"] = "\(error)" }
        return out
    }
}
