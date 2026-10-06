import XCTest
@testable import HighballKit

/// External Mac drives get Windows drive letters of their own, keep them, and never take one
/// Wine or the player made (Discord, 2026-10-06: Steam listed no external drive).
final class MacDrivesTests: XCTestCase {
    private let base = ["c": "../drive_c", "z": "/"]

    func testANewExternalDriveGetsTheFirstFreeLetter() {
        var existing = base
        existing["d"] = "/Volumes/Installer"      // Wine's letter for a mounted disk image
        let plan = MacDrives.plan(volumes: [.init(path: "/Volumes/Games", id: "U1")], existing: existing, mappings: [])
        XCTAssertEqual(plan.link, [.init(letter: "e", id: "U1", path: "/Volumes/Games")])
        XCTAssertEqual(plan.mappings, plan.link)
        XCTAssertEqual(plan.unlink, [])
    }

    func testADriveKeepsItsLetterAndAnUpToDateLinkChangesNothing() {
        var existing = base
        existing["e"] = "/Volumes/Games"
        let mapped = [MacDrives.Mapping(letter: "e", id: "U1", path: "/Volumes/Games")]
        let plan = MacDrives.plan(volumes: [.init(path: "/Volumes/Games", id: "U1")], existing: existing, mappings: mapped)
        XCTAssertEqual(plan, MacDrives.Plan(link: [], unlink: [], mappings: mapped))
    }

    func testAnUnpluggedDriveLosesItsLinkButKeepsItsLetterForWhenItComesBack() {
        var existing = base
        existing["e"] = "/Volumes/Games"
        let mapped = [MacDrives.Mapping(letter: "e", id: "U1", path: "/Volumes/Games")]
        let away = MacDrives.plan(volumes: [.init(path: "/Volumes/Other", id: "U2")], existing: existing, mappings: mapped)
        XCTAssertEqual(away.unlink, ["e"])
        XCTAssertEqual(away.link, [.init(letter: "d", id: "U2", path: "/Volumes/Other")], "another drive does not take the reserved letter")
        XCTAssertEqual(away.mappings.first, mapped[0])
        // Back at another mount point (macOS names it "Games 1" when the name is taken).
        let back = MacDrives.plan(volumes: [.init(path: "/Volumes/Games 1", id: "U1")], existing: base, mappings: mapped)
        XCTAssertEqual(back.link, [.init(letter: "e", id: "U1", path: "/Volumes/Games 1")])
        XCTAssertEqual(back.mappings, back.link)
    }

    func testALetterSomeoneElseNowUsesIsLeftAloneAndTheDriveMovesOn() {
        var existing = base
        existing["e"] = "/Volumes/SomethingElse"   // the player pointed E: elsewhere
        let mapped = [MacDrives.Mapping(letter: "e", id: "U1", path: "/Volumes/Games")]
        let plan = MacDrives.plan(volumes: [.init(path: "/Volumes/Games", id: "U1")], existing: existing, mappings: mapped)
        XCTAssertEqual(plan.unlink, [], "not ours to remove")
        XCTAssertEqual(plan.link, [.init(letter: "d", id: "U1", path: "/Volumes/Games")])
        XCTAssertEqual(plan.mappings, plan.link, "the stale record is dropped")
    }

    func testADriveALetterAlreadyReachesGetsNoSecondOne() {
        var existing = base
        existing["k"] = "/Volumes/Games/"           // made by hand, with a trailing slash
        let plan = MacDrives.plan(volumes: [.init(path: "/Volumes/Games", id: "U1")], existing: existing, mappings: [])
        XCTAssertEqual(plan, MacDrives.Plan())
    }

    func testOnlyLocalExternalFixedBrowsableVolumesQualify() {
        func q(_ path: String = "/Volumes/Games", local: Bool? = true, inside: Bool? = false, removable: Bool? = false,
               browsable: Bool? = true, root: Bool? = false) -> Bool {
            MacDrives.qualifies(path: path, isLocal: local, isInternal: inside, isRemovable: removable,
                                isBrowsable: browsable, isRootFileSystem: root)
        }
        XCTAssertTrue(q(), "an external SSD or hard drive")
        XCTAssertFalse(q(removable: true), "removable media: Wine gives it a letter itself")
        XCTAssertFalse(q(inside: true), "the Mac's own disk")
        XCTAssertFalse(q(inside: nil), "unknown counts against it")
        XCTAssertFalse(q(local: false), "a network share")
        XCTAssertFalse(q(browsable: false), "a hidden system volume")
        XCTAssertFalse(q("/", root: true))
        XCTAssertFalse(q("/System/Volumes/Data"))
    }

    func testTheEnvironmentsLinksFollowTheDrives() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "hb-drives-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bottleURL = root.appending(path: "t")
        let dos = bottleURL.appending(path: "dosdevices")
        try FileManager.default.createDirectory(at: dos, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: dos.appending(path: "c:").path, withDestinationPath: "../drive_c")
        try FileManager.default.createSymbolicLink(atPath: dos.appending(path: "z:").path, withDestinationPath: "/")
        let bottle = Bottle(url: bottleURL, settings: BottleSettings(name: "t", engineID: "e"))
        try bottle.save()
        let drive = root.appending(path: "Games").path, again = root.appending(path: "Games 1").path

        let made = Bottle.loadOrFail(bottleURL).syncExternalDrives(volumes: [.init(path: drive, id: "U1")])
        XCTAssertEqual(made.map(\.letter), ["d"])
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: dos.appending(path: "d:").path), drive)
        XCTAssertEqual(Bottle.loadOrFail(bottleURL).settings.externalDrives, [.init(letter: "d", id: "U1", path: drive)], "recorded")
        XCTAssertEqual(Bottle.loadOrFail(bottleURL).syncExternalDrives(volumes: [.init(path: drive, id: "U1")]), [], "a second launch changes nothing")

        XCTAssertEqual(Bottle.loadOrFail(bottleURL).syncExternalDrives(volumes: []), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dos.appending(path: "d:").path), "unplugged, the link goes")
        XCTAssertEqual(Bottle.loadOrFail(bottleURL).settings.externalDrives.map(\.letter), ["d"], "and the letter stays reserved")

        XCTAssertEqual(Bottle.loadOrFail(bottleURL).syncExternalDrives(volumes: [.init(path: again, id: "U1")]).map(\.letter), ["d"])
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: dos.appending(path: "d:").path), again, "back on D:")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: dos.appending(path: "c:").path), "../drive_c", "C: untouched")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: dos.appending(path: "z:").path), "/", "Z: untouched")
    }
}

private extension Bottle {
    static func loadOrFail(_ url: URL) -> Bottle {
        do { return try Bottle.load(url) } catch { XCTFail("\(error)"); return Bottle(url: url, settings: BottleSettings(name: "t", engineID: "e")) }
    }
}
