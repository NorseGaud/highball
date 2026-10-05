import XCTest
@testable import HighballKit

/// The steps the engine switch page lists (highball#254).
final class EngineSwitchPlanTests: XCTestCase {
    func testAnInstalledEngineOfTheSameWineSkipsTheDownloadAndTheWindowsSetup() {
        XCTAssertEqual(EngineSwitchPlan(engineInstalled: true, refreshesWindows: false).steps, [.stopPrograms, .done])
    }

    func testANewWineBuildToDownloadListsEveryStep() {
        XCTAssertEqual(EngineSwitchPlan(engineInstalled: false, refreshesWindows: true).steps, [.download, .stopPrograms, .windowsSetup, .done])
    }
}
