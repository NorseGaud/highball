import Foundation

/// External Mac drives as Windows drive letters.
///
/// Wine gives a drive letter only to a volume macOS reports as removable media: its mount
/// manager adds any other volume without one (dlls/mountmgr.sys/diskarb.c). External SSDs and
/// hard drives report fixed media, so a Windows program reached them only through Z:\Volumes,
/// and Steam, which offers drive letters for its libraries, listed none of them (an external
/// exFAT drive, Discord, 2026-10-06). Before a program starts, each mounted external volume is
/// linked to a letter of its own in the environment's dosdevices. Wine reports such a letter as
/// a fixed disk, since the volume is local and not removable media (ntdll's get_device_info,
/// kernelbase's GetDriveTypeW), which is the kind Steam offers.
///
/// A drive keeps its letter, because Steam records a library by its path (D:\SteamLibrary):
/// while the drive is away its link is removed and the letter stays reserved for it, and the
/// same letter comes back when it is plugged in again, even at another mount point. Letters
/// Wine or the player made are never touched, and a volume one of them already reaches gets no
/// second letter.
public enum MacDrives {
    /// A mounted volume: its mount point and an identity that survives a remount.
    public struct Volume: Equatable, Sendable {
        public var path: String
        public var id: String
        public init(path: String, id: String) { self.path = path; self.id = id }
    }

    /// A letter Highball linked to a volume, as recorded in the environment's settings.
    public struct Mapping: Codable, Equatable, Sendable {
        /// Lowercase, without the colon: "d".
        public var letter: String
        public var id: String
        /// Where the link pointed when it was last made.
        public var path: String
        public init(letter: String, id: String, path: String) { self.letter = letter; self.id = id; self.path = path }
    }

    public struct Plan: Equatable, Sendable {
        /// Links to create, or to point at a new mount point.
        public var link: [Mapping] = []
        /// Letters whose link to an absent drive is removed.
        public var unlink: [String] = []
        /// What the settings record afterwards.
        public var mappings: [Mapping] = []
    }

    /// Letters offered, in order. A and B are the floppy letters Windows programs skip, C is the
    /// environment's own drive and Z is the Mac's root.
    static let letters = "defghijklmnopqrstuvwxy".map(String.init)

    /// Pure: the links that give every external volume a letter of its own. `existing` is each
    /// `dosdevices/x:` entry, its letter to the link's target ("" for an entry that is no link).
    public static func plan(volumes: [Volume], existing: [String: String], mappings: [Mapping]) -> Plan {
        func same(_ a: String?, _ b: String) -> Bool { a.map(normalized) == normalized(b) }
        var plan = Plan()
        var kept: [Mapping] = []
        var lettered = Set<String>()
        for m in mappings where !kept.contains(where: { $0.letter == m.letter }) {
            let volume = volumes.first { $0.id == m.id }
            let target = existing[m.letter]
            // Someone else's now (Wine for a removable disk, or the player): forget the record.
            guard target == nil || same(target, m.path) || (volume.map { same(target, $0.path) } ?? false) else { continue }
            if let volume {
                if !same(target, volume.path) { plan.link.append(Mapping(letter: m.letter, id: m.id, path: volume.path)) }
                kept.append(Mapping(letter: m.letter, id: m.id, path: volume.path))
                lettered.insert(m.id)
            } else {
                if target != nil { plan.unlink.append(m.letter) }
                kept.append(m)
            }
        }
        for volume in volumes where !lettered.contains(volume.id) {
            if existing.values.contains(where: { same($0, volume.path) }) { continue }
            guard let letter = letters.first(where: { l in existing[l] == nil && !kept.contains { $0.letter == l } }) else { break }
            let m = Mapping(letter: letter, id: volume.id, path: volume.path)
            plan.link.append(m)
            kept.append(m)
            lettered.insert(volume.id)
        }
        plan.mappings = kept
        return plan
    }

    static func normalized(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// Pure: whether a mounted volume is one Wine leaves without a letter and Highball links.
    /// An unknown value (nil) counts against it.
    public static func qualifies(path: String, isLocal: Bool?, isInternal: Bool?, isRemovable: Bool?,
                                 isBrowsable: Bool?, isRootFileSystem: Bool?) -> Bool {
        path.hasPrefix("/Volumes/") && isLocal == true && isInternal == false && isRemovable == false
            && isBrowsable == true && isRootFileSystem != true
    }

    /// The external volumes mounted now. HB_DEBUG_EXTERNAL_VOLUMES (mount points separated by
    /// colons) adds volumes to treat as external, so the path can be checked without such a drive.
    public static func mountedExternalVolumes() -> [Volume] {
        let keys: Set<URLResourceKey> = [.volumeIsLocalKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsBrowsableKey,
                                         .volumeIsRootFileSystemKey, .volumeUUIDStringKey, .volumeNameKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        var volumes: [Volume] = urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: keys),
                  qualifies(path: url.path, isLocal: v.volumeIsLocal, isInternal: v.volumeIsInternal, isRemovable: v.volumeIsRemovable,
                            isBrowsable: v.volumeIsBrowsable, isRootFileSystem: v.volumeIsRootFileSystem) else { return nil }
            return Volume(path: url.path, id: v.volumeUUIDString ?? "name:" + (v.volumeName ?? url.lastPathComponent))
        }
        for path in (ProcessInfo.processInfo.environment["HB_DEBUG_EXTERNAL_VOLUMES"] ?? "").split(separator: ":").map(String.init)
        where !path.isEmpty && !volumes.contains(where: { $0.path == path }) {
            volumes.append(Volume(path: path, id: "debug:" + path))
        }
        return volumes
    }
}

public extension Bottle {
    /// Links the environment's external drives to letters (see `MacDrives`) and records them.
    /// Returns the links made, so a launch can say which letter a drive got.
    @discardableResult
    func syncExternalDrives(volumes: [MacDrives.Volume] = MacDrives.mountedExternalVolumes()) -> [MacDrives.Mapping] {
        let dosdevices = url.appending(path: "dosdevices", directoryHint: .isDirectory)
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dosdevices.path) else { return [] }
        var existing: [String: String] = [:]
        for name in names where name.count == 2 && name.hasSuffix(":") {
            existing[String(name.prefix(1)).lowercased()] = (try? fm.destinationOfSymbolicLink(atPath: dosdevices.appending(path: name).path)) ?? ""
        }
        let plan = MacDrives.plan(volumes: volumes, existing: existing, mappings: settings.externalDrives)
        for letter in plan.unlink {
            let entry = dosdevices.appending(path: "\(letter):").path
            // Removed only while it is still the link this record made.
            guard let target = try? fm.destinationOfSymbolicLink(atPath: entry),
                  settings.externalDrives.contains(where: { $0.letter == letter && MacDrives.normalized($0.path) == MacDrives.normalized(target) })
            else { continue }
            try? fm.removeItem(atPath: entry)
        }
        var made: [MacDrives.Mapping] = []
        for m in plan.link {
            let entry = dosdevices.appending(path: "\(m.letter):").path
            if (try? fm.destinationOfSymbolicLink(atPath: entry)) != nil { try? fm.removeItem(atPath: entry) }
            if (try? fm.createSymbolicLink(atPath: entry, withDestinationPath: m.path)) != nil { made.append(m) }
        }
        let recorded = plan.mappings.filter { m in !plan.link.contains(m) || made.contains(m) }
        if recorded != settings.externalDrives, var fresh = try? Bottle.load(url) {
            fresh.settings.externalDrives = recorded
            try? fresh.save()
        }
        return made
    }
}
