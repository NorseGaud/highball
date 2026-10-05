import Foundation

/// Steam's "controller recommended" notice, which a D3DMetal launch cannot show.
///
/// Before the first start of a game tagged "gamepad recommended", Steam's launch stops at
/// `ShowInterstitials` and its web UI draws a notice saying a controller is recommended. Once it
/// has been shown, the web UI records the game in its storage, which Steam keeps in the user's
/// `localconfig.vdf` under `UserLocalConfigStore/WebStorage`:
///
///     "Deck_ConfiguratorInterstitialsVersionSeen_GamepadRecommended"   "1"
///     "Deck_ConfiguratorInterstitialsCheckbox_GamepadRecommended"      "0"
///     "Deck_ConfiguratorInterstitialApps_GamepadRecommended"           "[2483190]"
///
/// and never stops that game's launch for it again. A client started with the D3DMetal stack
/// cannot draw the notice (its browser helpers fail to present under D3DMetal, and on D3DMetal 4
/// they die on `setDisplaySyncEnabled:`), so the launch waits on a dialog that never appears.
/// Forza Horizon 6 stood at `ShowInterstitials` for good on its first Play in a fresh
/// environment on an M4 (2026-10-05); with these three values written first, Steam answered
/// itself within a second and started the game.
///
/// The notice only informs, and the player cannot see it in that mode anyway, so recording it
/// as seen before a D3DMetal launch takes nothing away. Steam keeps the file in memory while it
/// runs and writes it back on exit, so this has to happen while no client runs: the caller
/// does it right before a cold start.
public enum SteamLaunchNotice {
    static let appsKey = "Deck_ConfiguratorInterstitialApps_GamepadRecommended"
    static let fixedKeys = [("Deck_ConfiguratorInterstitialsVersionSeen_GamepadRecommended", "1"),
                            ("Deck_ConfiguratorInterstitialsCheckbox_GamepadRecommended", "0")]

    /// Pure: the text of a `localconfig.vdf` with the notice recorded as seen for `appID`, or nil
    /// when nothing needs to change or the file has no `WebStorage` block to put it in (a client
    /// that has never shown its web UI; nothing is invented then).
    public static func markingSeen(in text: String, appID: Int) -> String? {
        let crlf = text.contains("\r\n")
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        func depth(_ l: String) -> Int { l.prefix { $0 == "\t" }.count }
        guard let ws = lines.indices.first(where: { lines[$0].trimmingCharacters(in: .whitespaces) == "\"WebStorage\"" && depth(lines[$0]) == 1 }),
              ws + 1 < lines.count, lines[ws + 1].trimmingCharacters(in: .whitespaces) == "{",
              var end = lines.indices.first(where: { $0 > ws + 1 && depth(lines[$0]) == 1 && lines[$0].trimmingCharacters(in: .whitespaces) == "}" })
        else { return nil }
        func pair(_ l: String) -> (key: String, value: String)? {
            let parts = l.trimmingCharacters(in: .whitespaces).components(separatedBy: "\"")
            guard parts.count >= 5, parts[0].isEmpty else { return nil }
            return (parts[1], parts[3])
        }
        func line(_ key: String, _ value: String) -> String { "\t\t\"\(key)\"\t\t\"\(value)\"" }
        var changed = false
        if let i = (ws + 2..<end).first(where: { pair(lines[$0])?.key == appsKey }) {
            let current = pair(lines[i])?.value ?? "[]"
            var apps = (try? JSONDecoder().decode([Int].self, from: Data(current.utf8))) ?? []
            if !apps.contains(appID) {
                apps.append(appID)
                lines[i] = line(appsKey, "[" + apps.map(String.init).joined(separator: ",") + "]")
                changed = true
            }
        } else {
            lines.insert(line(appsKey, "[\(appID)]"), at: end); end += 1; changed = true
        }
        for (key, value) in fixedKeys where !(ws + 2..<end).contains(where: { pair(lines[$0])?.key == key }) {
            lines.insert(line(key, value), at: end); end += 1; changed = true
        }
        guard changed else { return nil }
        let joined = lines.joined(separator: "\n")
        return crlf ? joined.replacingOccurrences(of: "\n", with: "\r\n") : joined
    }

    /// Records the notice as seen for `appID` in every Steam user's `localconfig.vdf` under
    /// `steamRoot`. Call it only while no Steam client runs in the environment. Returns how many
    /// files changed.
    @discardableResult
    public static func markSeen(steamRoot: URL, appID: Int) -> Int {
        let userdata = steamRoot.appending(path: "userdata")
        let users = (try? FileManager.default.contentsOfDirectory(at: userdata, includingPropertiesForKeys: nil)) ?? []
        var count = 0
        for user in users {
            let file = user.appending(path: "config/localconfig.vdf")
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  let updated = markingSeen(in: text, appID: appID),
                  (try? updated.write(to: file, atomically: true, encoding: .utf8)) != nil else { continue }
            count += 1
        }
        return count
    }
}
