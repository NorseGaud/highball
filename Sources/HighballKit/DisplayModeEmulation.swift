import Foundation

/// Wine's emulated display mode changes, per program. A game that asks Windows for a fullscreen
/// mode the Mac cannot switch to gets "success" while the display stays as it is, so it opens
/// small, off-centre, with black bars, or refuses to start; with EmulateModeset Wine pretends
/// the change happened and scales the window to the real screen. win32u reads the value under
/// `Software\Wine\X11 Driver` whatever the display driver (the Mac driver included, measured
/// in the engine's win32u.so), and `AppDefaults\<exe>` scopes it to one program, which is what
/// the Five Nights at Freddy's recipe writes and what was verified by eye. Never a default: games
/// that switch modes for real exist, so the value is set per program, by a recipe or by hand.
/// The bottle's registry is the only state; nothing is stored beside it.
public enum DisplayModeEmulation {
    public static let valueName = "EmulateModeset"

    /// What a fullscreen size the Mac never switched to leaves in a launch log: win32u gives up
    /// on the display it was told to change, once per attempt. The game then draws at the size it
    /// asked for inside a window that stayed the size it was, which is the corner window with the
    /// pointer landing somewhere other than what is drawn — highball#67 (Five Nights at Freddy's)
    /// and #103 (Dead Rising 3) are the same report, and switching graphics modes never moved it.
    public static let unswitchedMarker = "err:system:display_mode_changed"

    /// Whether a launch log shows a game asking for a mode change that never happened. Two
    /// sightings, not one: a lone failure can be a screen waking up or a monitor being plugged
    /// in, while a game that wants a mode the Mac will not give asks again on every attempt.
    public static func looksUnswitched(inLog text: String, atLeast: Int = 2) -> Bool {
        text.split(separator: "\n").filter { $0.contains(unswitchedMarker) }.count >= atLeast
    }

    /// The same question for a log on disk, read head-and-tail so a log of many megabytes — what
    /// a long session leaves — costs a bounded read.
    public static func looksUnswitched(log url: URL, atLeast: Int = 2) -> Bool {
        guard let text = BugReport.boundedText(of: url) else { return false }
        return looksUnswitched(inLog: text, atLeast: atLeast)
    }

    /// The per-program key, as `reg add` wants it.
    public static func key(forExecutable exe: URL) -> String {
        "HKCU\\Software\\Wine\\AppDefaults\\\(exe.lastPathComponent)\\X11 Driver"
    }

    /// Whether the bottle turns it on for `exe`, read from user.reg without running Wine.
    public static func isOn(in bottle: Bottle, executable exe: URL) -> Bool {
        guard let text = try? String(contentsOf: bottle.url.appending(path: "user.reg"), encoding: .utf8) else { return false }
        return isOn(userReg: text, executableName: exe.lastPathComponent)
    }

    /// Pure: the registry text says `"EmulateModeset"="y"` under the program's X11 Driver key.
    public static func isOn(userReg: String, executableName: String) -> Bool {
        let raw = RegistryText.value(in: userReg, key: "Software\\Wine\\AppDefaults\\\(executableName)\\X11 Driver", name: valueName) ?? ""
        return raw.lowercased() == "\"y\""
    }

    /// The program that builds the environment's list of display modes when it starts. Wine adds
    /// its virtual modes (640x480 and the other sizes a game may ask for) to that shared list only
    /// when the process building it emulates mode changes itself; a game with the setting alone
    /// validates its request against the Mac's real modes and gets "bad mode" for any the display
    /// does not list. Measured on an M4 with Warhammer: Dark Omen (640x480x16, engine r21,
    /// 2026-10-06): the game's own value alone, NtUserChangeDisplaySettings returned -2; with
    /// explorer.exe's too, the change went through and the window opened scaled to the screen.
    /// Prince of Persia: The Two Thrones (highball#128), Project IGI (#244) and Dead Rising 3 (#103)
    /// failed at the same refused change.
    public static let listBuilder = "explorer.exe"

    /// Whether any program other than `except` has it on, read from the registry text: the list
    /// builder's value stays while one does.
    public static func othersOn(userReg: String, except executableName: String) -> Bool {
        var current: String?
        for line in userReg.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("[") {
                // Keys are case-insensitive; reg.exe keeps whatever case it was given.
                let key = line.dropFirst().prefix { $0 != "]" }.replacingOccurrences(of: "\\\\", with: "\\").lowercased()
                let prefix = "software\\wine\\appdefaults\\", suffix = "\\x11 driver"
                if key.hasPrefix(prefix), key.hasSuffix(suffix) {
                    current = String(key.dropFirst(prefix.count).dropLast(suffix.count))
                } else { current = nil }
            } else if let program = current, program.lowercased() != executableName.lowercased(),
                      program.lowercased() != listBuilder, line.lowercased().hasPrefix("\"\(valueName.lowercased())\"=\"y\"") {
                return true
            }
        }
        return false
    }

    /// Turns it on or off for `exe` through the bottle's Wine, and keeps the list builder's value
    /// in step: on with the first program, off with the last. Programs read the registry when they
    /// start, and the list is rebuilt when the environment starts, so a change applies from the
    /// environment's next start.
    public static func set(_ on: Bool, in runner: WineRunner, executable exe: URL) async throws {
        let key = key(forExecutable: exe)
        let builder = Self.key(forExecutable: URL(fileURLWithPath: listBuilder))
        if on {
            try await runner.regAdd(key: key, name: valueName, type: "REG_SZ", data: "y")
            try await runner.regAdd(key: builder, name: valueName, type: "REG_SZ", data: "y")
        } else {
            try await runner.regDelete(key: key, name: valueName)
            let reg = (try? String(contentsOf: runner.bottle.url.appending(path: "user.reg"), encoding: .utf8)) ?? ""
            if !othersOn(userReg: reg, except: exe.lastPathComponent) {
                try? await runner.regDelete(key: builder, name: valueName)
            }
        }
    }
}
