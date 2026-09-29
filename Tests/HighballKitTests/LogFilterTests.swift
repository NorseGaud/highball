import XCTest
@testable import HighballKit

/// highball#224: one msync warning repeated millions of times made a 1.4 GB log. Repeats are
/// collapsed into a count, and a runaway log stops at a cap and says so.
final class LogFilterTests: XCTestCase {
    func testRepeatedLinesCollapseIntoACount() {
        var f = LogFilter(progressEvery: 1000)
        var out: [String] = []
        out += f.feed("start")
        for _ in 0..<5 { out += f.feed("msync: warn: node memory pool exhausted") }
        out += f.feed("err: something else")
        out += f.finish()
        XCTAssertEqual(out, ["start", "msync: warn: node memory pool exhausted",
                             "# the line above repeated 4 more times", "err: something else"])
    }

    func testALongRunOfRepeatsReportsProgressAndTheRemainderAtTheEnd() {
        var f = LogFilter(progressEvery: 3)
        var out: [String] = []
        for _ in 0..<8 { out += f.feed("x") }
        out += f.finish()
        XCTAssertEqual(out, ["x", "# the line above repeated 3 more times so far",
                             "# the line above repeated 6 more times so far",
                             "# the line above repeated 7 more times"])
    }

    func testTheLogStopsAtTheCapAndSaysSoOnce() {
        var f = LogFilter(capBytes: 20)
        var out: [String] = []
        for i in 0..<10 { out += f.feed("line \(i)") }
        XCTAssertEqual(out.first, "line 0")
        XCTAssertTrue(out.last?.hasPrefix("# log capped at") ?? false)
        XCTAssertEqual(out.filter { $0.hasPrefix("# log capped") }.count, 1)
        XCTAssertTrue(f.feed("more").isEmpty)
    }

    func testDistinctLinesPassThroughUnchanged() {
        var f = LogFilter()
        let lines = ["# gin header", "a", "b", "a", "b"]
        XCTAssertEqual(lines.flatMap { f.feed($0) } + f.finish(), lines)
    }
}
