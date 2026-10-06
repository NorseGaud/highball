import XCTest
@testable import HighballKit

/// A shortcut's icon comes from the program itself when it has one (ux-plan item 8).
final class PEIconTests: XCTestCase {
    func testDIBIconBecomesPNGWithTheRowsTheRightWayUp() throws {
        // A 2x2 32-bit icon: bottom row first in the file (blue, green), then the top row (red, opaque white).
        var dib = Data(count: 40)
        func put32(_ v: UInt32, _ o: Int) { for i in 0..<4 { dib[o + i] = UInt8((v >> (8 * i)) & 0xFF) } }
        put32(40, 0); put32(2, 4); put32(4, 8)   // header size, width 2, height 2*2
        dib[12] = 1; dib[14] = 32                 // planes, bits
        let bottom: [UInt8] = [255, 0, 0, 255,   0, 255, 0, 255]   // BGRA: blue, green
        let top: [UInt8]    = [0, 0, 255, 255,   255, 255, 255, 255] // red, white
        dib.append(contentsOf: bottom); dib.append(contentsOf: top); dib.append(contentsOf: [0, 0, 0, 0])   // AND mask
        let png = try XCTUnwrap(PEIcon.pngFromDIB(dib))
        XCTAssertEqual([UInt8](png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil)), 0, nil))
        XCTAssertEqual(image.width, 2); XCTAssertEqual(image.height, 2)
        // Top-left must be red: the file stores rows bottom-up and the converter flips them.
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 2, height: 2))
        let px = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual([px[0], px[1], px[2]], [255, 0, 0], "top-left is red")   // CGContext row 0 is the top
    }

    func testRejectsWhatItDoesNotUnderstand() {
        XCTAssertNil(PEIcon.png(fromPE: Data("not a program".utf8)))
        XCTAssertNil(PEIcon.pngFromDIB(Data(count: 39)))
    }

    func testBestExecutableIsTheLargestThatIsNotAnInstaller() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "hb-exe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appending(path: "bin"), withIntermediateDirectories: true)
        try Data(count: 10).write(to: dir.appending(path: "game.exe"))
        try Data(count: 5000).write(to: dir.appending(path: "unins000.exe"))
        try Data(count: 3000).write(to: dir.appending(path: "bin/Game-Win64-Shipping.exe"))
        try Data(count: 9000).write(to: dir.appending(path: "UnityCrashHandler64.exe"))
        XCTAssertEqual(PEIcon.bestExecutable(in: dir)?.lastPathComponent, "Game-Win64-Shipping.exe")
    }

    /// highball#156: Counter-Strike 2 keeps its program at game/bin/win64/cs2.exe, four levels
    /// down. Nothing was found, so the game's page hid its per-program settings (Display mode).
    func testAProgramFourLevelsDownIsFoundWhenNothingShallowerIs() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "hb-exe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appending(path: "game/bin/win64"), withIntermediateDirectories: true)
        try Data(count: 100).write(to: dir.appending(path: "game/bin/win64/cs2.exe"))
        try Data(count: 900).write(to: dir.appending(path: "game/bin/win64/steamerrorreporter64.exe"))
        XCTAssertEqual(PEIcon.bestExecutable(in: dir)?.lastPathComponent, "cs2.exe")
        // A program within three levels still wins, as before: the deeper search only runs when
        // the usual one finds nothing, so no game that had a program changes it.
        try Data(count: 10).write(to: dir.appending(path: "start.exe"))
        XCTAssertEqual(PEIcon.bestExecutable(in: dir)?.lastPathComponent, "start.exe")
    }

    /// A game folder that is a symlink (a game moved to another disk and linked back) used to
    /// enumerate as empty, so the program was never found (0.10.9 release pass, 2026-10-06).
    func testAProgramIsFoundThroughASymlinkedGameFolderAndNamedUnderIt() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "hb-exe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appending(path: "elsewhere/ForzaHorizon6")
        try FileManager.default.createDirectory(at: real.appending(path: "bin"), withIntermediateDirectories: true)
        try Data(count: 3000).write(to: real.appending(path: "bin/game.exe"))
        try Data(count: 10).write(to: real.appending(path: "tool.exe"))
        let common = base.appending(path: "steamapps/common")
        try FileManager.default.createDirectory(at: common, withIntermediateDirectories: true)
        let link = common.appending(path: "ForzaHorizon6")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let found = try XCTUnwrap(PEIcon.bestExecutable(in: link), "nothing found through the link")
        XCTAssertEqual(found.path, link.appending(path: "bin/game.exe").path, "named under the folder the caller gave")
        XCTAssertTrue(FileManager.default.fileExists(atPath: found.path))
        // A plain folder is unchanged.
        XCTAssertEqual(PEIcon.bestExecutable(in: real)?.path, real.appending(path: "bin/game.exe").path)
    }

    func testARealProgramOnThisMacWhenThereIsOne() throws {
        let candidates = [
            "Library/Application Support/Highball/bottles/Gaming/drive_c/highball/ahk/AutoHotkeyU64.exe",
            "Library/Application Support/Highball/bottles/Gaming/drive_c/Program Files (x86)/Steam/steamapps/common/Five Nights at Freddy's/FiveNightsatFreddys.exe",
        ].map { FileManager.default.homeDirectoryForCurrentUser.appending(path: $0) }
        guard let exe = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { throw XCTSkip("no Windows program with an icon on this Mac") }
        let png = try XCTUnwrap(PEIcon.png(from: exe), "\(exe.lastPathComponent) carries an icon")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertGreaterThanOrEqual(image.width, 32)
    }
}
