import XCTest
@testable import HighballKit

/// Emulated display mode changes are one registry value per program, the same one the Five
/// Nights at Freddy's fix writes; the toggle reads and writes nothing else.
final class DisplayModeEmulationTests: XCTestCase {
    func testKeyIsThePerProgramX11DriverKey() {
        let exe = URL(fileURLWithPath: "/b/drive_c/Program Files (x86)/Steam/steamapps/common/Five Nights at Freddy's/FiveNightsatFreddys.exe")
        XCTAssertEqual(DisplayModeEmulation.key(forExecutable: exe), "HKCU\\Software\\Wine\\AppDefaults\\FiveNightsatFreddys.exe\\X11 Driver")
    }

    func testReadsTheValueTheRecipeWrites() {
        let reg = """
        [Software\\\\Wine\\\\AppDefaults\\\\DarkOmen.exe\\\\X11 Driver] 1789674692
        #time=1dd46ddf05dfeaa
        "EmulateModeset"="y"

        [Software\\\\Wine\\\\AppDefaults\\\\deskjob.exe\\\\DllOverrides] 1787678145
        "d3d9"="native,builtin"

        [Software\\\\Wine\\\\AppDefaults\\\\Other.exe\\\\X11 Driver] 1789141270
        "EmulateModeset"="n"
        """
        XCTAssertTrue(DisplayModeEmulation.isOn(userReg: reg, executableName: "DarkOmen.exe"))
        XCTAssertTrue(DisplayModeEmulation.isOn(userReg: reg, executableName: "darkomen.exe"), "the registry is case-insensitive")
        XCTAssertFalse(DisplayModeEmulation.isOn(userReg: reg, executableName: "Other.exe"), "an explicit n is off")
        XCTAssertFalse(DisplayModeEmulation.isOn(userReg: reg, executableName: "deskjob.exe"), "a program with other AppDefaults only")
        XCTAssertFalse(DisplayModeEmulation.isOn(userReg: reg, executableName: "Missing.exe"))
    }

    func testAMissingRegistryIsOff() {
        let bottle = Bottle(url: URL(fileURLWithPath: "/tmp/hb-no-such-bottle-\(UUID().uuidString)"), settings: BottleSettings(name: "t", engineID: "e"))
        XCTAssertFalse(DisplayModeEmulation.isOn(in: bottle, executable: URL(fileURLWithPath: "/x/Game.exe")))
    }
}

extension DisplayModeEmulationTests {
    /// The real Gaming bottle on this Mac: the FNAF recipe set the value, PEAK never had it.
    func testTheRealBottleReadsTheRecipeValue() throws {
        let home = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support/Highball/bottles/Gaming")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: home.appending(path: "user.reg").path), "no Gaming bottle here")
        let bottle = Bottle(url: home, settings: BottleSettings(name: "Gaming", engineID: "e"))
        XCTAssertTrue(DisplayModeEmulation.isOn(in: bottle, executable: URL(fileURLWithPath: "/x/FiveNightsatFreddys.exe")))
        XCTAssertFalse(DisplayModeEmulation.isOn(in: bottle, executable: URL(fileURLWithPath: "/x/PEAK.exe")))
    }
}

/// highball#67 (Five Nights at Freddy's) and #103 (Dead Rising 3): the game comes up small in a
/// corner and the mouse lands away from what it draws, and every graphics mode does the same,
/// because the fullscreen size it asked for is one the Mac never switched to.
final class UnswitchedDisplayModeTests: XCTestCase {
    private func log(_ attempts: Int) -> String {
        (["# gin x64-sikarugir10.0_6-r3 bottle=Games renderer=dxvk"]
         + (0..<attempts).map { "00d\($0):err:system:display_mode_changed Failed to get primary source current display settings." }
         + ["# exit=0 after 934s"]).joined(separator: "\n")
    }

    func testRepeatedFailedModeChangesAreTheTell() {
        XCTAssertTrue(DisplayModeEmulation.looksUnswitched(inLog: log(3)))
        XCTAssertTrue(DisplayModeEmulation.looksUnswitched(inLog: log(2)))
    }

    func testOneFailureIsNotEnough() {
        // A screen waking up or a monitor being plugged in fails the same read once.
        XCTAssertFalse(DisplayModeEmulation.looksUnswitched(inLog: log(1)))
    }

    func testAnOrdinaryLogSaysNothing() {
        let ordinary = """
        # gin x64-sikarugir10.0_6-r3 bottle=Games renderer=dxmt
        0164:err:environ:init_peb starting L"C:\\\\Program Files (x86)\\\\Steam\\\\steam.exe" in experimental wow64 mode
        0138:err:ole:com_get_class_object apartment not initialised
        # exit=0 after 120s
        """
        XCTAssertFalse(DisplayModeEmulation.looksUnswitched(inLog: ordinary))
    }

    // The list builder (explorer.exe) keeps the value while any other program has it on, so
    // turning one game off does not take the low-resolution modes away from another.
    func testTheListBuilderStaysOnWhileAnotherProgramHasIt() {
        let reg = """
        [Software\\Wine\\AppDefaults\\DarkOmen.exe\\X11 Driver] 1759750000
        "EmulateModeset"="y"

        [Software\\Wine\\AppDefaults\\explorer.exe\\X11 Driver] 1759750000
        "EmulateModeset"="y"

        [Software\\Wine\\AppDefaults\\FNAF.exe\\X11 Driver] 1759750000
        "EmulateModeset"="y"
        """
        XCTAssertTrue(DisplayModeEmulation.othersOn(userReg: reg, except: "DarkOmen.exe"), "FNAF still has it")
        XCTAssertTrue(DisplayModeEmulation.othersOn(userReg: reg, except: "fnaf.exe"), "Dark Omen still has it, names in any case")
        let alone = """
        [software\\wine\\appdefaults\\POP3.EXE\\X11 Driver] 1759750000
        "EmulateModeset"="y"

        [Software\\Wine\\AppDefaults\\explorer.exe\\X11 Driver] 1759750000
        "EmulateModeset"="y"

        [Software\\Wine\\AppDefaults\\Other.exe\\Direct3D] 1759750000
        "EmulateModeset"="y"
        """
        XCTAssertFalse(DisplayModeEmulation.othersOn(userReg: alone, except: "POP3.EXE"),
                       "the builder itself and a value under another driver key do not count")
        XCTAssertTrue(DisplayModeEmulation.othersOn(userReg: alone, except: "Unrelated.exe"), "a key written in lower case still counts")
    }
}
