import Foundation

/// The Mac Steam app's own installs, read from its appmanifests the same way a bottle's are:
/// `~/Library/Application Support/Steam/steamapps` plus every library folder it lists in
/// `libraryfolders.vdf` (an external drive, say). Read only.
///
/// A game installed there is played through Steam for Mac with `steam://run/<appid>`, and one
/// that isn't is handed to it with `steam://install/<appid>`: bottles run with winemenubuilder
/// disabled, so Wine's Steam registers no macOS URL handler and steam:// reaches the Mac app.
public enum MacSteam {
    public static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Steam")
    }

    /// Every `steamapps` folder the Mac client installs into, the default one first.
    public static func steamappsDirectories(root: URL = root) -> [URL] {
        var libraries = [root.standardizedFileURL]
        if let text = try? String(contentsOf: root.appending(path: "steamapps/libraryfolders.vdf"), encoding: .utf8) {
            let pattern = #/"path"\s+"((?:\\.|[^"\\])*)"/#
            for match in text.matches(of: pattern) {
                let path = String(match.1).replacingOccurrences(of: #"\\"#, with: #"\"#)
                    .replacingOccurrences(of: #"\""#, with: "\"")
                let url = URL(fileURLWithPath: path).standardizedFileURL
                if !libraries.contains(url) { libraries.append(url) }
            }
        }
        return libraries.map { $0.appending(path: "steamapps") }
    }

    /// Games fully installed by Steam for Mac. Nothing when it isn't installed or signed in.
    public static func installedGames(root: URL = root) -> [SteamGame] {
        var seen = Set<Int>()
        return steamappsDirectories(root: root)
            .flatMap { dir in
                ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                    .filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
            }
            .compactMap { SteamLibrary.parseManifest($0) }
            .filter { $0.isReady && $0.appid != 228980 && seen.insert($0.appid).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
