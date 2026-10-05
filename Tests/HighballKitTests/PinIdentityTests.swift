import XCTest
import AppKit
@testable import HighballKit

/// A program's cover and name survive a rename of its environment (highball#258): the library id
/// carries the environment's name, the program's uuid does not change.
final class PinIdentityTests: XCTestCase {
    private var home: URL!
    private let uuid = "6F9619FF-8B86-D011-B42D-00CF4FC964FF"

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "hb-pinid-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    private func png() throws -> URL {
        let url = home.appending(path: "src.png")
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 30, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    func testACoverFollowsTheProgramAcrossAnEnvironmentRename() throws {
        let store = CoverStore(paths: HighballPaths(home: home))
        try store.setCover(for: "pin:Games:\(uuid)", from: try png())
        XCTAssertNotNil(store.coverURL(for: "pin:Games_:\(uuid)"), "the environment was renamed, the program's cover stays")
        XCTAssertNil(store.coverURL(for: "pin:Games_:\(UUID().uuidString)"), "another program does not get it")
        XCTAssertNil(store.coverURL(for: "steam:400"), "only programs fall back")
        store.clearCover(for: "pin:Games_:\(uuid)")
        XCTAssertNil(store.coverURL(for: "pin:Games:\(uuid)"), "Reset cover removes the copy kept under the old name")
    }

    func testANameFollowsTheProgramAndAResetReallyResets() throws {
        let store = NameStore(paths: HighballPaths(home: home))
        try store.setName("Bloody Spell", for: "pin:Games:\(uuid)")
        XCTAssertEqual(store.name(for: "pin:Sandbox:\(uuid)"), "Bloody Spell")
        try store.setName(nil, for: "pin:Sandbox:\(uuid)")
        XCTAssertNil(store.name(for: "pin:Sandbox:\(uuid)"), "a reset after the rename does not bring the old name back")
        XCTAssertNil(store.name(for: "pin:Games:\(uuid)"))
        XCTAssertNil(NameStore.name(for: "steam:400", in: ["pin:Games:\(uuid)": "x"]))
    }
}
