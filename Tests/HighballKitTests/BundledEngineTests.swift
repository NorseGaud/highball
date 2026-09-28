import XCTest
@testable import HighballKit

/// Every engine manifest the app bundles must decode, and the ones with a purpose beyond the
/// default must carry the settings that purpose rests on: r6 exists to offer D3DMetal from
/// GPTK 4 on macOS 27 with its Metal 4 backend off (highball#85), and a manifest that lost any
/// of that would ship silently, since nothing else reads those fields before a user picks it.
final class BundledEngineTests: XCTestCase {
    private var engines: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "spike/engines")
    }

    private func manifests() throws -> [EngineManifest] {
        let files = try FileManager.default.contentsOfDirectory(at: engines, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertFalse(files.isEmpty, "no bundled manifests under spike/engines")
        return try files.map { try EngineManifest.load(from: $0) }
    }

    func testEveryBundledManifestDecodesWithAUniqueIdAndAFloor() throws {
        let all = try manifests()
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "duplicate engine ids among the bundled manifests")
        for m in all {
            XCTAssertFalse(m.minMacOS.isEmpty, "\(m.id) has no minMacOS")
            XCTAssertTrue(m.runs(onMacOS: "99.0"), "\(m.id): a floor nothing satisfies")
        }
    }

    func testR6CarriesGPTK4D3DMetalOnMacOS27WithTheMetal4BackendOff() throws {
        let r6 = try XCTUnwrap(try manifests().first { $0.id == "x64-sikarugir10.0_6-r6" }, "r6 manifest missing")
        XCTAssertEqual(r6.minMacOS, "27.0")
        XCTAssertFalse(r6.runs(onMacOS: "26.6.2"), "r6 was measured on 27 only and must not be offered below it")
        XCTAssertEqual(r6.baseEnv?["D3DM_MTL4"], "0", "the Metal 4 backend ends UE5 titles within a minute on 4.0b2")
        let d3dmetal = try XCTUnwrap(r6.components["d3dmetal"], "r6 has no d3dmetal component")
        XCTAssertEqual(d3dmetal.sha256, "96cbbe89b71cb07cc33bd761ae4b79452b9cdf3198593dfb779036caf85f07a9")
        XCTAssertEqual(d3dmetal.extract?.into, "renderers/d3dmetal", "rendererDir prefers the engine's own renderers/d3dmetal")
        XCTAssertEqual(d3dmetal.license, "apple-gptk-license-2023-08-17", "same licence text as GPTK 3, same gate")
    }

    /// Frame generation left Highball on 2026-09-27 at its author's request (itsOwen's lsfg-metal,
    /// highball#171): no engine may ship the component any more. The revisions since are their
    /// bases (r5 on the main line, r6 on the GPTK 4 line) with one component swapped: DXMT, which
    /// moved from upstream's v0.80 release to Highball's own build on 2026-09-28, because v0.80's
    /// D3DKMT adapter lookup fails on this Wine and every shared texture then died at creation
    /// (ContractVille, highball#202). Everything else is byte-identical, so it is not downloaded
    /// again, and the DXMT archive comes from Highball's own release page (a component URL has
    /// to be ours to stay immutable, #27/#28).
    func testNoEngineShipsFrameGenerationAndTheCurrentRevisionsAreTheirBasesPlusOurDXMT() throws {
        let all = try manifests() + [try EngineManifest.load(from: engines.deletingLastPathComponent().appending(path: "engine-manifest.json"))]
        for m in all {
            XCTAssertNil(m.components["lsfg"], "\(m.id) still ships the lsfg component")
            for (name, c) in m.components {
                XCTAssertFalse(c.url.absoluteString.lowercased().contains("lsfg"), "\(m.id)/\(name) still points at an lsfg archive")
            }
        }
        func one(_ id: String) throws -> EngineManifest { try XCTUnwrap(all.first { $0.id == id }, "\(id) missing") }
        for (current, baseID) in [("x64-sikarugir10.0_6-r13", "x64-sikarugir10.0_6-r5"), ("x64-sikarugir10.0_6-r14", "x64-sikarugir10.0_6-r6")] {
            let r = try one(current), base = try one(baseID)
            XCTAssertEqual(r.minMacOS, base.minMacOS, "\(current) must keep \(baseID)'s floor")
            XCTAssertEqual(r.baseEnv?["D3DM_MTL4"], base.baseEnv?["D3DM_MTL4"], "\(current) must keep \(baseID)'s Metal 4 setting")
            XCTAssertEqual(Set(r.components.keys), Set(base.components.keys), "\(current) has exactly \(baseID)'s components")
            for (name, component) in base.components where name != "dxmt" {
                XCTAssertEqual(r.components[name]?.sha256, component.sha256, "\(name) drifted from \(baseID), so its download is not reused")
            }
            let dxmt = try XCTUnwrap(r.components["dxmt"])
            XCTAssertTrue(dxmt.url.absoluteString.hasPrefix("https://github.com/gauthierpiarrette/highball-engine/releases/download/dxmt-highball-"),
                          "\(current)'s DXMT must be Highball's own build from its release page: \(dxmt.url)")
            XCTAssertNotEqual(dxmt.sha256, base.components["dxmt"]?.sha256, "\(current) must not carry \(baseID)'s v0.80 DXMT")
        }
        XCTAssertEqual(all.last?.id, "x64-sikarugir10.0_6-r13", "r13 is the default engine")
    }
}
