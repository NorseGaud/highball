import XCTest
@testable import HighballKit

/// Steam's own window stays black under D3DMetal (highball#268: an environment set to D3DMetal for
/// Forza Horizon 4 on the Wine 11 engine, and Steam could not be signed in to or used).
final class SteamWindowRendererTests: XCTestCase {
    func testAD3DMetalEnvironmentOpensSteamsWindowWithDXMT() {
        XCTAssertEqual(SteamRestart.windowRenderer(shortcut: nil, environment: .d3dmetal, dxmtRuns: true), .dxmt)
    }

    func testEveryOtherModeIsLeftAsItIs() {
        for mode in Renderer.allCases where mode != .d3dmetal {
            XCTAssertNil(SteamRestart.windowRenderer(shortcut: nil, environment: mode, dxmtRuns: true), mode.rawValue)
        }
    }

    func testAModeSetOnTheSteamShortcutStands() {
        XCTAssertNil(SteamRestart.windowRenderer(shortcut: .d3dmetal, environment: .d3dmetal, dxmtRuns: true))
        XCTAssertNil(SteamRestart.windowRenderer(shortcut: .dxvk, environment: .d3dmetal, dxmtRuns: true))
    }

    func testAnEngineWithoutDXMTKeepsTheEnvironmentsMode() {
        XCTAssertNil(SteamRestart.windowRenderer(shortcut: nil, environment: .d3dmetal, dxmtRuns: false))
    }
}
