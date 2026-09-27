import Foundation

/// A native macOS build of a game on Steam: the same purchase the player already made, which the
/// Mac Steam app installs and runs without Wine. Only Steam builds count; a native edition sold
/// elsewhere (Death Stranding's on the Mac App Store) is a different purchase and isn't marked.
///
/// Two sources, curated first:
/// - the database row's `nativeMac`, when its `where` names Steam; a row can also say
///   `"available": false` for a port that no longer runs;
/// - otherwise the Steam store's `platforms.mac` for the appid. The store page is what Valve and
///   publishers keep current: Steam's own appinfo still lists macOS for Portal, whose 32-bit Mac
///   build stopped running with Catalina, while the store page for 400 no longer does
///   (checked 2026-09-24).
public enum MacSteamBuild: Equatable, Sendable {
    /// Steam for Mac has it installed (MacSteam): no need to ask anyone.
    case installed
    /// The database row says so (and may carry requirements in its note).
    case inDatabase
    /// Steam's store page lists macOS.
    case onStore

    /// Pure. nil: no Mac build on Steam known, or the store hasn't been asked yet.
    public static func resolve(entry: GameDBEntry?, storeMac: Bool?, installedOnMac: Bool = false) -> MacSteamBuild? {
        if installedOnMac { return .installed }
        if let native = entry?.nativeMac {
            guard native.available else { return nil }
            // A list ("Steam, Mac App Store, GOG, Epic" for Cyberpunk 2077) counts when Steam is in it.
            let stores = (native.where ?? "Steam").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if stores.contains("steam") { return .inDatabase }
        }
        return storeMac == true ? .onStore : nil
    }
}

/// The row field: `"nativeMac": {"available": true, "where": "Steam", "note": "…", "url": "…"}`.
public struct NativeMacInfo: Codable, Sendable, Equatable {
    public var available: Bool
    public var `where`: String?
    public var note: String?
    public var url: String?
}

/// Store `platforms.mac` flags, cached in `mac-flags.json` for two weeks. Only Steam games whose
/// appinfo lists macOS are asked about (worthAsking), one request each: the store API takes one
/// appid per `platforms` request and allows about 200 requests per five minutes. A failed or
/// refused request is "don't know", never "no Mac version", so it's asked again next time.
public struct MacFlagStore: Sendable {
    public struct Record: Codable, Sendable, Equatable {
        public var mac: Bool
        public var checked: Date
    }

    public static let maxAge: TimeInterval = 14 * 24 * 3600
    public let file: URL

    public init(paths: HighballPaths = HighballPaths()) {
        file = paths.home.appending(path: "mac-flags.json")
    }

    public init(file: URL) { self.file = file }

    /// Tolerant load: missing or corrupt file is an empty cache.
    public func load(now: Date = Date()) -> [Int: Bool] {
        guard let data = try? Data(contentsOf: file),
              let records = try? JSONDecoder().decode([Int: Record].self, from: data) else { return [:] }
        return records.filter { now.timeIntervalSince($0.value.checked) < Self.maxAge }.mapValues(\.mac)
    }

    func save(_ flags: [Int: Bool], now: Date = Date()) {
        var records = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([Int: Record].self, from: $0) } ?? [:]
        for (appid, mac) in flags { records[appid] = Record(mac: mac, checked: now) }
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// The Steam games to ask the store about: the ones whose appinfo lists macOS, and any the
    /// owned library can't speak for yet (an installed game before the client's cache has it).
    /// A game appinfo doesn't list for macOS has no Mac build on Steam, so a library of hundreds
    /// costs a handful of requests.
    public static func worthAsking(_ appids: [Int], listsMac: [Int: Bool]) -> [Int] {
        appids.filter { listsMac[$0] ?? true }
    }

    /// Asks the store about the appids not cached yet and returns every known flag.
    public func refresh(_ appids: [Int], now: Date = Date()) async -> [Int: Bool] {
        var known = load(now: now)
        let missing = appids.filter { known[$0] == nil }
        guard !missing.isEmpty else { return known }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: cfg)
        var fetched: [Int: Bool] = [:]
        for appid in missing {
            if Task.isCancelled { break }
            let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appid)&filters=platforms")!
            guard let (data, response) = try? await session.data(from: url) else { continue }
            let status = (response as? HTTPURLResponse)?.statusCode
            if status == 429 || status == 403 { break }   // rate limited: the rest wait for next session
            guard status == 200, let mac = Self.parse(data) else { continue }
            fetched[appid] = mac
        }
        if !fetched.isEmpty { save(fetched, now: now) }
        known.merge(fetched) { $1 }
        return known
    }

    /// `{"400":{"success":true,"data":{"platforms":{"windows":true,"mac":false,"linux":false}}}}`.
    /// nil when the store has no page for the appid (delisted, region-locked): that isn't a no.
    static func parse(_ data: Data) -> Bool? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let app = json.values.first as? [String: Any],
              app["success"] as? Bool == true,
              let platforms = (app["data"] as? [String: Any])?["platforms"] as? [String: Any] else { return nil }
        return platforms["mac"] as? Bool
    }
}
