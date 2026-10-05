import XCTest
@testable import HighballKit

/// A game installed in more than one environment (highball#264), and an environment that
/// already fits a game's engine (highball-db#318).
final class EnvironmentCopiesTests: XCTestCase {
    private func bottle(_ name: String) -> Bottle {
        Bottle(url: URL(fileURLWithPath: "/tmp/hb-copies-tests/bottles/\(name)"),
               settings: BottleSettings(name: name, engineID: "e"))
    }
    private func steam(_ appid: Int, _ name: String, ready: Bool = true, size: Int64 = 10) -> SteamGame {
        SteamGame(appid: appid, name: name, installdir: name, sizeOnDisk: size, stateFlags: ready ? 4 : 2, lastPlayed: nil)
    }

    // MARK: Where a shared game lives

    func testTheDefaultEnvironmentHoldsASharedGameBeforeOneSortedEarlierByName() {
        let clean = bottle("Clean"), games = bottle("Games")
        let both = ["Clean": [steam(1, "Streets of Rage 4")], "Games": [steam(1, "Streets of Rage 4")]]
        let byName = LibraryIndex.build(bottles: [clean, games], steamByBottle: both, epicOwned: [], epicInstalls: [:])
        XCTAssertEqual(byName.first?.bottleName, "Clean", "without a default, the name decides, as before")
        let items = LibraryIndex.build(bottles: [clean, games], steamByBottle: both, epicOwned: [], epicInstalls: [:],
                                       defaultBottle: "Games")
        XCTAssertEqual(items.first?.bottleName, "Games")
        XCTAssertEqual(items.first?.otherBottles, ["Clean"])
    }

    func testOwnedGamesNotInstalledAnywhereGoToTheDefaultEnvironment() {
        let clean = bottle("Clean"), games = bottle("Games")
        let owned = [OwnedSteamGame(appid: 9, name: "Hades")]
        let items = LibraryIndex.build(bottles: [clean, games], steamByBottle: [:],
                                       steamOwnedByBottle: ["Clean": owned, "Games": owned],
                                       epicOwned: [], epicInstalls: [:], defaultBottle: "Games")
        XCTAssertEqual(items.first { $0.id == "steam:9" }?.bottleName, "Games")
    }

    func testThePlayedEnvironmentStillWinsOverTheDefault() {
        let clean = bottle("Clean"), games = bottle("Games")
        let both = ["Clean": [steam(1, "Bloody Spell")], "Games": [steam(1, "Bloody Spell")]]
        let items = LibraryIndex.build(bottles: [clean, games], steamByBottle: both, epicOwned: [], epicInstalls: [:],
                                       plays: ["steam:1": .init(lastPlayedAt: Date(), bottle: "Clean")],
                                       defaultBottle: "Games")
        XCTAssertEqual(items.first?.bottleName, "Clean", "a game played from a second environment stays there")
    }

    // MARK: Counting what an environment holds

    func testAnEnvironmentCountsEveryGameInstalledInItNotJustTheTilesHomedThere() {
        let clean = bottle("Clean"), games = bottle("Games")
        let steamByBottle = ["Clean": [steam(1, "A"), steam(2, "B")],
                             "Games": [steam(1, "A"), steam(2, "B"), steam(3, "C", ready: false)]]
        let items = LibraryIndex.build(bottles: [clean, games], steamByBottle: steamByBottle,
                                       steamOwnedByBottle: ["Clean": (10..<130).map { OwnedSteamGame(appid: $0, name: "Owned \($0)") }],
                                       epicOwned: [], epicInstalls: [:])
        // Before: Clean showed 120 titles (owned, not installed) and Games almost none.
        let c = LibraryIndex.footprint(of: "Clean", items: items, steamGames: steamByBottle["Clean"]!)
        let g = LibraryIndex.footprint(of: "Games", items: items, steamGames: steamByBottle["Games"]!)
        XCTAssertEqual(c.count, 2)
        XCTAssertEqual(g.count, 2, "a half-downloaded game is not installed yet")
        XCTAssertEqual(c.bytes, 20)
    }

    func testProgramsCountInTheirOwnEnvironment() {
        var a = bottle("a")
        a.settings.pins = [Pin(name: "MyGame", path: "Games/my.exe")]
        let items = LibraryIndex.build(bottles: [a], steamByBottle: [:], epicOwned: [], epicInstalls: [:])
        XCTAssertEqual(LibraryIndex.footprint(of: "a", items: items, steamGames: []).count, 1)
        XCTAssertEqual(LibraryIndex.footprint(of: "b", items: items, steamGames: []).count, 0)
    }

    // MARK: A copy seen from another environment

    func testAGameHomedInAnotherEnvironmentThatHoldsACopyIsInstalledThere() {
        let item = LibraryItem(source: .steam, id: "steam:1", title: "A", bottleName: "Games", installed: true,
                               steamAppID: 1, otherBottles: ["Clean", "W11"], sizeOnDisk: 5)
        let there = item.homed(in: "W11")
        XCTAssertEqual(there.bottleName, "W11")
        XCTAssertTrue(there.installed)
        XCTAssertEqual(there.otherBottles, ["Clean", "Games"])
        XCTAssertEqual(there.id, item.id, "the same game, so plays and covers follow it")
        let notThere = item.homed(in: "Fresh")
        XCTAssertFalse(notThere.installed, "Install hands it to that environment's Steam")
        XCTAssertEqual(notThere.otherBottles, ["Clean", "Games", "W11"])
        XCTAssertEqual(item.homed(in: "Games"), item)
    }

    // MARK: An environment that already fits

    func testTheEnvironmentHoldingTheGameComesFirstThenTheOneWithTheFix() {
        let any = EnvironmentFit.Candidate(name: "Overwatch 2", holdsGame: false, hasFix: false)
        let fix = EnvironmentFit.Candidate(name: "Mirror's Edge Catalyst", holdsGame: false, hasFix: true)
        let game = EnvironmentFit.Candidate(name: "W11", holdsGame: true, hasFix: false)
        XCTAssertEqual(EnvironmentFit.best([any, fix, game])?.name, "W11")
        XCTAssertEqual(EnvironmentFit.best([any, fix])?.name, "Mirror's Edge Catalyst")
        XCTAssertEqual(EnvironmentFit.best([any])?.name, "Overwatch 2")
        XCTAssertNil(EnvironmentFit.best([]))
        let first = EnvironmentFit.Candidate(name: "A", holdsGame: false, hasFix: true)
        XCTAssertEqual(EnvironmentFit.best([first, fix])?.name, "A", "ties keep the app's order")
    }
}
