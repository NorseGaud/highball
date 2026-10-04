import XCTest
@testable import HighballKit

/// Steam keeps more than one library folder, the second often on an external disk, and lists
/// them in libraryfolders.vdf as Windows paths. A game installed there was invisible to Highball
/// until highball-db#316 (Bloody Spell in a library on /Volumes/MEDIA_DEV).
final class SteamLibraryFoldersTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appending(path: "hb-libfolders-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func manifest(_ appid: Int, _ name: String, dir: String) -> String {
        "\"AppState\"\n{\n\t\"appid\"\t\t\"\(appid)\"\n\t\"name\"\t\t\"\(name)\"\n\t\"StateFlags\"\t\t\"4\"\n\t\"installdir\"\t\t\"\(dir)\"\n}\n"
    }

    func testGamesInASecondLibraryFolderOnAnotherDriveAreFound() throws {
        let bottle = tmp.appending(path: "bottle", directoryHint: .isDirectory)
        let external = tmp.appending(path: "Disk/SteamLibrary", directoryHint: .isDirectory)
        let steam = bottle.appending(path: "drive_c/Program Files (x86)/Steam", directoryHint: .isDirectory)
        try write("", to: steam.appending(path: "steam.exe"))
        try write(manifest(400, "Portal", dir: "Portal"), to: steam.appending(path: "steamapps/appmanifest_400.acf"))
        try write(manifest(992300, "Bloody Spell", dir: "BloodySpell"), to: external.appending(path: "steamapps/appmanifest_992300.acf"))
        try write(manifest(400, "Portal (copy)", dir: "Portal2"), to: external.appending(path: "steamapps/appmanifest_400.acf"))
        let dosdevices = bottle.appending(path: "dosdevices", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dosdevices, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: dosdevices.appending(path: "c:").path, withDestinationPath: "../drive_c")
        try FileManager.default.createSymbolicLink(atPath: dosdevices.appending(path: "d:").path, withDestinationPath: tmp.appending(path: "Disk").path)
        try write("""
        "libraryfolders"
        {
        \t"0"
        \t{
        \t\t"path"\t\t"C:\\\\Program Files (x86)\\\\Steam"
        \t\t"label"\t\t""
        \t}
        \t"1"
        \t{
        \t\t"path"\t\t"D:\\\\SteamLibrary"
        \t}
        \t"2"
        \t{
        \t\t"path"\t\t"E:\\\\Gone"
        \t}
        }
        """, to: steam.appending(path: "steamapps/libraryfolders.vdf"))

        let folders = SteamLibrary.libraryFolders(steamRoot: steam, bottleURL: bottle)
        XCTAssertEqual(folders.map(\.standardizedFileURL.path), [steam.standardizedFileURL.path, external.standardizedFileURL.path],
                       "the environment's own library first, then the external one; the unmapped drive is skipped")

        let games = SteamLibrary.games(steamRoot: steam, bottleURL: bottle)
        XCTAssertEqual(games.map(\.appid), [992300, 400])
        XCTAssertEqual(games.first { $0.appid == 400 }?.installdir, "Portal", "the environment's own copy wins over a second manifest of the same game")
        XCTAssertEqual(games.first { $0.appid == 992300 }?.installFolder?.standardizedFileURL.path,
                       external.appending(path: "steamapps/common/BloodySpell").standardizedFileURL.path)
    }

    func testWindowsPathsGoThroughTheBottlesDriveLetters() throws {
        let bottle = tmp.appending(path: "b", directoryHint: .isDirectory)
        XCTAssertEqual(SteamLibrary.unixURL(windowsPath: "C:\\Games\\X", bottleURL: bottle)?.standardizedFileURL.path,
                       bottle.appending(path: "drive_c/Games/X").standardizedFileURL.path, "c: is drive_c even before dosdevices exists")
        XCTAssertEqual(SteamLibrary.unixURL(windowsPath: "Z:\\Volumes\\MEDIA_DEV\\roms\\steam", bottleURL: bottle)?.path, "/Volumes/MEDIA_DEV/roms/steam")
        XCTAssertNil(SteamLibrary.unixURL(windowsPath: "Q:\\Nowhere", bottleURL: bottle), "a letter the bottle does not map")
        XCTAssertNil(SteamLibrary.unixURL(windowsPath: "not a windows path", bottleURL: bottle))
        XCTAssertEqual(SteamLibrary.libraryPaths(in: #""path"        "D:\\SteamLibrary""#), ["D:\\SteamLibrary"])
    }
}
