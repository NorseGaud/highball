import Foundation

/// Keeps a launch log readable and bounded. A line repeated back to back is written once, then
/// summarised ("the line above repeated N more times"), with a running count every
/// `progressEvery` repeats so a log cut short still says what filled it. Past `capBytes` the
/// log stops growing and says so once.
///
/// highball#224: msync printed "node memory pool exhausted" millions of times and a single
/// My Summer Car session left a 1.4 GB log (a second one 2.4 GB), the cause buried in one line.
public struct LogFilter {
    public var progressEvery = 10_000
    public var capBytes = 256 * 1024 * 1024
    private var last: String?
    private var repeats = 0
    private var written = 0
    private var capped = false

    public init(progressEvery: Int = 10_000, capBytes: Int = 256 * 1024 * 1024) {
        self.progressEvery = progressEvery
        self.capBytes = capBytes
    }

    /// The lines to write for one line of output (none while it only repeats the previous one).
    public mutating func feed(_ line: String) -> [String] {
        if line == last {
            repeats += 1
            return repeats % progressEvery == 0 ? admit(["# the line above repeated \(repeats) more times so far"]) : []
        }
        var out: [String] = []
        if repeats > 0 { out.append("# the line above repeated \(repeats) more times") }
        out.append(line)
        last = line
        repeats = 0
        return admit(out)
    }

    /// Anything still owed at the end of the output.
    public mutating func finish() -> [String] {
        defer { repeats = 0 }
        return repeats > 0 ? admit(["# the line above repeated \(repeats) more times"]) : []
    }

    private mutating func admit(_ lines: [String]) -> [String] {
        if capped { return [] }
        var out: [String] = []
        for l in lines {
            written += l.utf8.count + 1
            if written > capBytes {
                capped = true
                out.append("# log capped at \(capBytes / (1024 * 1024)) MB, the rest of this session's output was not written")
                break
            }
            out.append(l)
        }
        return out
    }
}
