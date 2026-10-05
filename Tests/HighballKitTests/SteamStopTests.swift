import XCTest
@testable import HighballKit

/// Stopping Steam where none runs must not start one (gin-64's Forza Horizon 6 pass, 2026-10-06:
/// `steam.exe -shutdown` booted a client and the launch came 46 s later).
final class SteamStopTests: XCTestCase {
    func testStoppingSteamWhereNoneRunsStartsNothing() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "hb-steamstop-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let paths = HighballPaths(home: root.appending(path: "home"))
        let bottleURL = root.appending(path: "bottles/quiet")
        try FileManager.default.createDirectory(at: bottleURL.appending(path: "drive_c/Program Files (x86)/Steam"), withIntermediateDirectories: true)
        try Data().write(to: bottleURL.appending(path: "drive_c/Program Files (x86)/Steam/steam.exe"))
        let bottle = Bottle(url: bottleURL, settings: BottleSettings(name: "quiet", engineID: "x64-test-r1"))
        let engine = InstalledEngine(manifest: EngineManifest(id: "x64-test-r1", displayName: "test", arch: "x86_64", minMacOS: "14.0", components: [:]),
                                     root: root.appending(path: "engine"))
        let runner = WineRunner(paths: paths, engine: engine, bottle: bottle)
        XCTAssertFalse(runner.steamIsRunning())
        let start = Date()
        try await runner.stopSteam()
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        let logs = (try? FileManager.default.contentsOfDirectory(atPath: paths.logs.path)) ?? []
        XCTAssertFalse(logs.contains { $0.contains("steam-shutdown") }, "no steam.exe -shutdown run when no client runs")
    }
}
