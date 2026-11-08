import Foundation
import GameCore
import Businesses

/// Saves on disk, safely.
///
///  - A save is written to a temporary file and then swapped in, so a crash or a full disk can never leave a half-written save.
///  - The previous save of the slot is kept as `<slot>.previous.ledgersave`; the last `backupCount` month-end autosaves are kept too.
///  - Imported saves from the HTML game are copied untouched into `Imports/` first; the original text is never modified or deleted.
public final class SaveStore {
    public let directory: URL
    public let backupCount: Int
    private let fm = FileManager.default

    public init(directory: URL, backupCount: Int = 6) throws {
        self.directory = directory
        self.backupCount = backupCount
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try fm.createDirectory(at: importsDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
    }

    var importsDirectory: URL { directory.appendingPathComponent("Imports", isDirectory: true) }
    var backupsDirectory: URL { directory.appendingPathComponent("Backups", isDirectory: true) }
    func url(slot: String) -> URL { directory.appendingPathComponent("\(slot).ledgersave") }
    func previousURL(slot: String) -> URL { directory.appendingPathComponent("\(slot).previous.ledgersave") }

    // MARK: Writing

    public func summary(of state: GameState, trades: any TradeCatalogProviding, now: Date = Date()) -> SaveSummary {
        SaveSummary(playerName: state.player.name, countryCode: state.homeCountryCode, week: state.week,
                    netWorth: state.netWorthHistory.last ?? 0, companies: state.liveCompanies.filter { $0.type != "hold" }.count, savedAt: now)
    }

    public func save(_ state: GameState, slot: String = "current", summary: SaveSummary) throws {
        let envelope: JSONValue = .object([
            "format": .string(NativeSaveFormat.formatName), "version": .number(Double(NativeSaveFormat.currentVersion)),
            "savedAt": .string(ISO8601DateFormatter().string(from: summary.savedAt)),
            "summary": try JSONValue.fromEncodable(summary), "state": try JSONValue.fromEncodable(state),
        ])
        let data = try JSONEncoder().encode(envelope)
        let target = url(slot: slot)
        let temp = directory.appendingPathComponent(".\(slot).writing")
        try data.write(to: temp, options: .atomic)
        // Verify what we wrote can be read back before it replaces anything.
        _ = try Self.read(data: data)
        if fm.fileExists(atPath: target.path) {
            try? fm.removeItem(at: previousURL(slot: slot))
            try fm.copyItem(at: target, to: previousURL(slot: slot))
        }
        // rename() replaces the target in one step: readers see either the old save or the new one, never half of one.
        if rename(temp.path, target.path) != 0 { throw SaveError.unreadable("could not replace the save file") }
    }

    /// A rolling backup, normally written at month end.
    public func backup(_ state: GameState, summary: SaveSummary) throws {
        let name = "backup-week\(summary.week).ledgersave"
        let tmpSlot = "backup-tmp"
        try save(state, slot: tmpSlot, summary: summary)
        let dest = backupsDirectory.appendingPathComponent(name)
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: url(slot: tmpSlot), to: dest)
        try? fm.removeItem(at: previousURL(slot: tmpSlot))
        let all = try fm.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for old in all.dropFirst(backupCount) { try? fm.removeItem(at: old) }
    }

    // MARK: Reading

    static func read(data: Data) throws -> (GameState, SaveSummary?) {
        guard let env = (try? JSONDecoder().decode(JSONValue.self, from: data))?.object, env["format"]?.string == NativeSaveFormat.formatName else { throw SaveError.notAGameSave }
        try NativeSaveFormat.check(env)
        let stateData = try JSONEncoder().encode(env["state"] ?? .null)
        var state = try JSONDecoder().decode(GameState.self, from: stateData)
        Budget.migrate(&state)   // saves from before the one budget keep their managers' authority as the nearest preset
        let summary = try? JSONDecoder().decode(SaveSummary.self, from: JSONEncoder().encode(env["summary"] ?? .null))
        return (state, summary)
    }

    public func load(slot: String = "current") throws -> GameState {
        do { return try Self.read(data: Data(contentsOf: url(slot: slot))).0 }
        catch {
            // The main file is damaged: fall back on the previous save of the slot.
            if fm.fileExists(atPath: previousURL(slot: slot).path) { return try Self.read(data: Data(contentsOf: previousURL(slot: slot))).0 }
            throw error
        }
    }

    public func slots() -> [(slot: String, summary: SaveSummary?)] {
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "ledgersave" && !$0.lastPathComponent.contains(".previous.") }
            .map { f in (f.deletingPathExtension().lastPathComponent, (try? Self.read(data: Data(contentsOf: f)))?.1) }
            .sorted { $0.slot < $1.slot }
    }

    /// A slot name as it may sit in a file name: letters, digits, spaces, dashes, at most 24 characters; nil when nothing is left.
    public static func cleanSlotName(_ raw: String) -> String? {
        let kept = raw.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }.trimmingCharacters(in: .whitespaces)
        let name = String(kept.prefix(24)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Removes a named slot and its previous copy. The `current` slot is the game being played and is never removed.
    public func delete(slot: String) throws {
        guard slot != "current", Self.cleanSlotName(slot) == slot else { return }
        for u in [url(slot: slot), previousURL(slot: slot)] where fm.fileExists(atPath: u.path) { try fm.removeItem(at: u) }
    }

    /// Renames a named slot (not `current`). Returns false when the new name is unusable or taken.
    @discardableResult
    public func renameSlot(_ slot: String, to raw: String) throws -> Bool {
        guard slot != "current", let name = Self.cleanSlotName(raw), name != "current", !hasSave(slot: name), hasSave(slot: slot) else { return false }
        try fm.moveItem(at: url(slot: slot), to: url(slot: name))
        if fm.fileExists(atPath: previousURL(slot: slot).path) { try fm.moveItem(at: previousURL(slot: slot), to: previousURL(slot: name)) }
        return true
    }

    public func hasSave(slot: String = "current") -> Bool { fm.fileExists(atPath: url(slot: slot).path) }

    // MARK: Importing from the HTML game

    /// Keep the original text safe, then convert it. The original is stored byte for byte in Imports/.
    @discardableResult
    public func importLegacy(text: String, now: Date = Date()) throws -> GameState {
        let state = try LegacyImporter.importText(text)
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        try text.write(to: importsDirectory.appendingPathComponent("original-\(stamp).txt"), atomically: true, encoding: .utf8)
        return state
    }
}

extension JSONValue {
    static func fromEncodable<T: Encodable>(_ v: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(v))
    }
}
