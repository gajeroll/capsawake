import CapsAwakeCore
import Foundation

/// Remembers what the machine was set to before CapsAwake changed it.
///
/// This lives on disk rather than in the daemon's memory because the daemon is
/// demand-launched: it can exit and be relaunched while an override is still in
/// place, and a value read at that point would record the setting *we* imposed as
/// the one to go back to. For the Energy Mode that would lose the user's mode. For
/// `SleepDisabled` it is worse — the daemon would then answer every "put it back"
/// with "it was already on", and the Mac would never sleep again.
///
/// Both baselines therefore live in one file, written by root, and each is cleared
/// as soon as the setting it describes has been restored. An absent baseline means
/// CapsAwake has nothing to undo, which is what makes restore safe to call
/// unconditionally.
struct PrivilegedBaselineStore {
    static let shared = PrivilegedBaselineStore()

    /// What the machine had before CapsAwake touched it. A `nil` field means that
    /// setting is not currently overridden.
    struct Baseline: Codable, Equatable {
        var sleepDisabled: Bool?
        var energyModes: [String: String]?

        var isEmpty: Bool { sleepDisabled == nil && (energyModes?.isEmpty ?? true) }
    }

    /// Where the daemon keeps it. Injectable so the tests can exercise the migration
    /// and the record/restore/clear cycle without being root.
    private let directory: URL
    /// Whether the directory and file must be owned by root to be trusted. Off in
    /// tests, where nothing runs as root and the temporary directory is the user's.
    private let requiresRootOwnership: Bool

    init(
        directory: URL = URL(
            fileURLWithPath: "/Library/Application Support/CapsAwake",
            isDirectory: true
        ),
        requiresRootOwnership: Bool = true
    ) {
        self.directory = directory
        self.requiresRootOwnership = requiresRootOwnership
    }

    private var file: URL { directory.appending(path: "baseline.plist") }
    /// Written by versions that only recorded the Energy Mode, as a bare
    /// `[String: String]`. Folded into the new file on first read.
    private var legacyEnergyModeFile: URL {
        directory.appending(path: "energy-mode-baseline.plist")
    }

    // MARK: - Sleep

    func sleepDisabled() -> Bool? {
        load().sleepDisabled
    }

    /// Records the value to go back to, if one is not recorded already.
    ///
    /// Returns whether a baseline is now on disk. A caller that gets `false` must
    /// not go on to change the setting: without a baseline there is no way to put
    /// it back, and an override nobody can undo is the one outcome worse than not
    /// overriding at all.
    func recordSleepDisabled(_ value: Bool) -> Bool {
        var baseline = load()
        guard baseline.sleepDisabled == nil else { return true }
        baseline.sleepDisabled = value
        return save(baseline)
    }

    func clearSleepDisabled() {
        var baseline = load()
        baseline.sleepDisabled = nil
        _ = save(baseline)
    }

    // MARK: - Energy Mode

    func energyModes() -> [PowerSource: EnergyMode]? {
        guard let raw = load().energyModes, !raw.isEmpty else { return nil }
        var modes: [PowerSource: EnergyMode] = [:]
        for (key, value) in raw {
            guard let source = PowerSource(rawValue: key),
                let mode = EnergyMode(rawValue: value)
            else { continue }
            modes[source] = mode
        }
        return modes.isEmpty ? nil : modes
    }

    /// Records the modes to go back to, if they are not recorded already. Returns
    /// whether a baseline is now on disk; see `recordSleepDisabled(_:)`.
    func recordEnergyModes(_ modes: [PowerSource: EnergyMode]) -> Bool {
        var baseline = load()
        guard baseline.energyModes?.isEmpty ?? true else { return true }
        baseline.energyModes = Dictionary(
            uniqueKeysWithValues: modes.map { ($0.key.rawValue, $0.value.rawValue) }
        )
        return save(baseline)
    }

    func clearEnergyModes() {
        var baseline = load()
        baseline.energyModes = nil
        _ = save(baseline)
    }

    // MARK: - Storage

    private func load() -> Baseline {
        if let data = readWithoutFollowingSymlinks(file),
            let baseline = try? PropertyListDecoder().decode(Baseline.self, from: data)
        {
            return baseline
        }
        return migratedLegacyBaseline()
    }

    /// Folds a baseline written by a version that only recorded the Energy Mode into
    /// the current file, so upgrading does not lose the mode to go back to.
    private func migratedLegacyBaseline() -> Baseline {
        guard let data = readWithoutFollowingSymlinks(legacyEnergyModeFile),
            let raw = try? PropertyListDecoder().decode([String: String].self, from: data),
            !raw.isEmpty
        else {
            return Baseline()
        }
        let baseline = Baseline(sleepDisabled: nil, energyModes: raw)
        if save(baseline) {
            try? FileManager.default.removeItem(at: legacyEnergyModeFile)
        }
        return baseline
    }

    /// Writes the baseline, or removes the file once there is nothing left to undo.
    /// Returns whether the file on disk now says what it should.
    private func save(_ baseline: Baseline) -> Bool {
        guard !baseline.isEmpty else {
            try? FileManager.default.removeItem(at: file)
            return true
        }
        guard prepareDirectory(),
            let data = try? PropertyListEncoder().encode(baseline)
        else {
            return false
        }
        do {
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: file.path
            )
            return true
        } catch {
            return false
        }
    }

    /// Makes sure our directory exists and is ours.
    ///
    /// `/Library/Application Support` is group-writable by `admin`, so the directory
    /// is created without following intermediates and is checked to be a real
    /// directory owned by root before anything is written into it.
    private func prepareDirectory() -> Bool {
        let manager = FileManager.default
        if !manager.fileExists(atPath: directory.path) {
            try? manager.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o755]
            )
        }
        var info = stat()
        guard lstat(directory.path, &info) == 0 else { return false }
        guard info.st_mode & S_IFMT == S_IFDIR else { return false }
        return !requiresRootOwnership || info.st_uid == 0
    }

    /// Reads a real, root-owned file, never following a symlink.
    ///
    /// Without `O_NOFOLLOW` an admin user could pre-create our directory, drop a
    /// symlink where the baseline goes, and aim the root daemon's reads — and, on the
    /// next write, its writes — at a file of their choosing.
    private func readWithoutFollowingSymlinks(_ url: URL) -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        guard !requiresRootOwnership || info.st_uid == 0 else { return nil }
        return FileHandle(fileDescriptor: descriptor).readDataToEndOfFile()
    }
}
