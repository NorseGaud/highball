import XCTest
@testable import HighballKit

/// Steam's "controller recommended" notice is recorded as seen before a D3DMetal launch, the way
/// Steam's own web UI records it, and nothing else in the file moves.
final class SteamLaunchNoticeTests: XCTestCase {
    private let base = """
    "UserLocalConfigStore"
    {
    \t"Software"
    \t{
    \t\t"Valve"
    \t\t{
    \t\t}
    \t}
    \t"WebStorage"
    \t{
    \t\t"SomethingElse"\t\t"1"
    \t}
    \t"friends"
    \t{
    \t}
    }
    """

    func testAFirstGameAddsTheThreeValuesInsideWebStorage() throws {
        let out = try XCTUnwrap(SteamLaunchNotice.markingSeen(in: base, appID: 2483190))
        let lines = out.components(separatedBy: "\n")
        let ws = try XCTUnwrap(lines.firstIndex(of: "\t\"WebStorage\""))
        let close = try XCTUnwrap(lines[ws...].firstIndex(of: "\t}"))
        let block = lines[ws..<close].joined(separator: "\n")
        XCTAssertTrue(block.contains("\t\t\"Deck_ConfiguratorInterstitialApps_GamepadRecommended\"\t\t\"[2483190]\""))
        XCTAssertTrue(block.contains("\"Deck_ConfiguratorInterstitialsVersionSeen_GamepadRecommended\"\t\t\"1\""))
        XCTAssertTrue(block.contains("\"Deck_ConfiguratorInterstitialsCheckbox_GamepadRecommended\"\t\t\"0\""))
        XCTAssertTrue(block.contains("\"SomethingElse\""), "the block's own values stay")
        XCTAssertEqual(lines.count, base.components(separatedBy: "\n").count + 3, "three lines added, nothing removed")
        XCTAssertTrue(out.hasSuffix("\t\"friends\"\n\t{\n\t}\n}"), "what follows the block is untouched")
    }

    func testASecondGameJoinsTheListAndAGameAlreadyThereChangesNothing() throws {
        let first = try XCTUnwrap(SteamLaunchNotice.markingSeen(in: base, appID: 2483190))
        XCTAssertNil(SteamLaunchNotice.markingSeen(in: first, appID: 2483190), "already recorded")
        let second = try XCTUnwrap(SteamLaunchNotice.markingSeen(in: first, appID: 1551360))
        XCTAssertTrue(second.contains("\"Deck_ConfiguratorInterstitialApps_GamepadRecommended\"\t\t\"[2483190,1551360]\""))
        XCTAssertEqual(second.components(separatedBy: "VersionSeen").count, 2, "the fixed values are not added twice")
    }

    func testWindowsLineEndingsSurviveAndNoWebStorageMeansNoEdit() throws {
        let crlf = base.replacingOccurrences(of: "\n", with: "\r\n")
        let out = try XCTUnwrap(SteamLaunchNotice.markingSeen(in: crlf, appID: 7))
        XCTAssertFalse(out.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "every line ends with CRLF again")
        let noStorage = "\"UserLocalConfigStore\"\n{\n\t\"friends\"\n\t{\n\t}\n}"
        XCTAssertNil(SteamLaunchNotice.markingSeen(in: noStorage, appID: 7), "nothing is invented in a file without the block")
    }

    func testEveryUserFileUnderTheSteamFolderIsMarked() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "steam-notice-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for user in ["111", "222"] {
            let dir = root.appending(path: "userdata/\(user)/config")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try base.write(to: dir.appending(path: "localconfig.vdf"), atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(SteamLaunchNotice.markSeen(steamRoot: root, appID: 2483190), 2)
        XCTAssertEqual(SteamLaunchNotice.markSeen(steamRoot: root, appID: 2483190), 0, "a second call finds it done")
    }
}
