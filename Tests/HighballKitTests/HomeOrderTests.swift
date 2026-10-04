import XCTest
@testable import HighballKit

/// The Home row (highball#252): installed games only, the ones played most recently first, then
/// the rest by title. Owned-but-not-installed games stay in the grid.
final class HomeOrderTests: XCTestCase {
    private func item(_ title: String, installed: Bool, played: Date? = nil) -> HighballKit.LibraryItem {
        HighballKit.LibraryItem(source: .steam, id: "steam:\(title.hashValue)", title: title, bottleName: installed ? "Games" : nil,
                    installed: installed, installedOnMac: false, steamAppID: abs(title.hashValue % 100000), epicAppName: nil,
                    pinID: nil, artworkTall: nil, lastPlayed: played)
    }

    func testRecentlyPlayedComeFirstThenTheRestByTitle() {
        let now = Date()
        let items = [
            item("Zed", installed: true),
            item("Alpha", installed: true),
            item("Mid", installed: true, played: now.addingTimeInterval(-3600)),
            item("Newest", installed: true, played: now),
            item("Owned only", installed: false, played: now),
        ]
        XCTAssertEqual(LibraryIndex.installedForHome(items).map(\.title), ["Newest", "Mid", "Alpha", "Zed"])
    }

    func testNothingInstalledMeansAnEmptyRow() {
        XCTAssertTrue(LibraryIndex.installedForHome([item("Owned only", installed: false)]).isEmpty)
    }
}
