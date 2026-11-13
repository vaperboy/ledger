import Foundation
import GameCore
import Businesses

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

    public func summary(of state: GameState, trades: any TradeCatalogProviding, now: Date = Date()) -> SaveSummary {
        SaveSummary(playerName: state.player.name, countryCode: state.homeCountryCode, week: state.week,
                    netWorth: state.netWorthHistory.last ?? 0, companies: state.liveCompanies.count, savedAt: now)
    }

    public func save(_ state: GameState, slot: String = "current", summary: SaveSummary) throws {
        let envelope = SaveEnvelope(format: NativeSaveFormat.formatName, version: NativeSaveFormat.currentVersion,
                                    savedAt: ISO8601DateFormatter().string(from: summary.savedAt), summary: summary, state: state)
        let data = try JSONEncoder().encode(envelope)
        let target = url(slot: slot)
        let temp = directory.appendingPathComponent(".\(slot).writing")
        try data.write(to: temp, options: .atomic)
        if fm.fileExists(atPath: target.path) {
            try? fm.removeItem(at: previousURL(slot: slot))
            try fm.copyItem(at: target, to: previousURL(slot: slot))
        }
        if rename(temp.path, target.path) != 0 { throw SaveError.unreadable("could not replace the save file") }
    }

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

    static func read(data: Data) throws -> (GameState, SaveSummary?) {
        guard let env = (try? JSONDecoder().decode(JSONValue.self, from: data))?.object, env["format"]?.string == NativeSaveFormat.formatName else { throw SaveError.notAGameSave }
        try NativeSaveFormat.check(env)
        let stateData = try JSONEncoder().encode(env["state"] ?? .null)
        var state = try JSONDecoder().decode(GameState.self, from: stateData)
        Budget.migrate(&state)
        let summary = try? JSONDecoder().decode(SaveSummary.self, from: JSONEncoder().encode(env["summary"] ?? .null))
        return (state, summary)
    }

    public func load(slot: String = "current") throws -> GameState {
        do { return try Self.read(data: Data(contentsOf: url(slot: slot))).0 }
        catch {
            if fm.fileExists(atPath: previousURL(slot: slot).path) { return try Self.read(data: Data(contentsOf: previousURL(slot: slot))).0 }
            throw error
        }
    }

    public func slots() -> [(slot: String, summary: SaveSummary?)] {
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "ledgersave" && !$0.lastPathComponent.contains(".previous.") }
            .map { f in (f.deletingPathExtension().lastPathComponent, Self.summary(at: f)) }
            .sorted { $0.slot < $1.slot }
    }

    /// Reads only the summary of a save file, without decoding the whole game state.
    static func summary(at file: URL) -> SaveSummary? {
        guard let data = try? Data(contentsOf: file), let head = try? JSONDecoder().decode(SaveHead.self, from: data),
              head.format == NativeSaveFormat.formatName, head.version == NativeSaveFormat.currentVersion else { return nil }
        return head.summary
    }

    public static func cleanSlotName(_ raw: String) -> String? {
        let kept = raw.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }.trimmingCharacters(in: .whitespaces)
        let name = String(kept.prefix(24)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    public func delete(slot: String) throws {
        guard slot != "current", Self.cleanSlotName(slot) == slot else { return }
        for u in [url(slot: slot), previousURL(slot: slot)] where fm.fileExists(atPath: u.path) { try fm.removeItem(at: u) }
    }

    @discardableResult
    public func renameSlot(_ slot: String, to raw: String) throws -> Bool {
        guard slot != "current", let name = Self.cleanSlotName(raw), name != "current", !hasSave(slot: name), hasSave(slot: slot) else { return false }
        try fm.moveItem(at: url(slot: slot), to: url(slot: name))
        if fm.fileExists(atPath: previousURL(slot: slot).path) { try fm.moveItem(at: previousURL(slot: slot), to: previousURL(slot: name)) }
        return true
    }

    /// Moves the current career into a named slot, so it exists once and continues from where it stopped.
    @discardableResult
    public func park(as raw: String) throws -> String? {
        guard hasSave(), let base = Self.cleanSlotName(raw), base != "current" else { return nil }
        var name = base, n = 2
        while hasSave(slot: name) || name == "current" { name = Self.cleanSlotName("\(base.prefix(20)) \(n)") ?? "\(n)"; n += 1 }
        try fm.moveItem(at: url(slot: "current"), to: url(slot: name))
        try? fm.removeItem(at: previousURL(slot: "current"))
        return name
    }

    /// Makes a parked career the current one again. The slot file is moved, not copied, so no older copy stays behind.
    @discardableResult
    public func unpark(_ slot: String) throws -> Bool {
        guard slot != "current", !hasSave(), hasSave(slot: slot) else { return false }
        try fm.moveItem(at: url(slot: slot), to: url(slot: "current"))
        try? fm.removeItem(at: previousURL(slot: slot))
        return true
    }

    @discardableResult
    public func keepUnreadable(slot: String = "current", now: Date = Date()) -> Bool {
        let dir = directory.appendingPathComponent("Unreadable", isDirectory: true)
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else { return false }
        var kept = false
        for (u, tag) in [(url(slot: slot), "main"), (previousURL(slot: slot), "previous")] where fm.fileExists(atPath: u.path) {
            let dest = dir.appendingPathComponent("\(slot)-\(tag)-\(stamp).ledgersave")
            if (try? fm.copyItem(at: u, to: dest)) != nil { kept = true }
        }
        return kept
    }

    public func hasSave(slot: String = "current") -> Bool { fm.fileExists(atPath: url(slot: slot).path) }

    @discardableResult
    public func importLegacy(text: String, now: Date = Date()) throws -> GameState {
        let state = try LegacyImporter.importText(text)
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        try text.write(to: importsDirectory.appendingPathComponent("original-\(stamp).txt"), atomically: true, encoding: .utf8)
        return state
    }
}

private struct SaveEnvelope: Encodable {
    var format: String
    var version: Int
    var savedAt: String
    var summary: SaveSummary
    var state: GameState
}

private struct SaveHead: Decodable {
    var format: String?
    var version: Int?
    var summary: SaveSummary?
}

extension JSONValue {
    static func fromEncodable<T: Encodable>(_ v: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(v))
    }
}
