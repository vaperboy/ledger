import Foundation
import GameCore

/// How games are stored.
///
/// NATIVE FILE (`*.ledgersave`, JSON):
///   { "format": "ledger-native", "version": 1, "savedAt": "<ISO date>", "summary": {...}, "state": { ...game state... } }
/// `version` is the version of this *envelope*; `state` keeps the original game's field names (and its own `v`,
/// the original save version), so a save is also readable by the HTML game's importer.
/// When the format changes, add a step to `NativeMigrations` and raise `currentVersion`. Old saves are never
/// discarded: only a save from a NEWER app than this one is refused.
public enum NativeSaveFormat {
    public static let formatName = "ledger-native"
    public static let currentVersion = 1
}

/// A line about a save, shown in the save list without loading the whole game.
public struct SaveSummary: Codable, Equatable, Sendable {
    public var playerName: String
    public var countryCode: String
    public var week: Int
    public var netWorth: Double
    public var companies: Int
    public var savedAt: Date
}

public enum SaveError: Error, Equatable {
    case unreadable(String)
    case newerThanThisApp(Int)
    case notAGameSave
}

/// Changes to the envelope between app versions. Step n turns a version-n envelope into version n+1.
public enum NativeMigrations {
    static let steps: [Int: (inout [String: JSONValue]) -> Void] = [:]

    public static func upgrade(_ envelope: inout [String: JSONValue]) throws {
        var v = envelope["version"]?.int ?? 1
        if v > NativeSaveFormat.currentVersion { throw SaveError.newerThanThisApp(v) }
        while v < NativeSaveFormat.currentVersion {
            steps[v]?(&envelope)
            v += 1
            envelope["version"] = .number(Double(v))
        }
    }
}

/// Reads saves from the original HTML game: plain JSON, "LZ1:" or "LZ64:" text. Original: `deserializeCore`, `upgradeSave`.
public enum LegacyImporter {
    /// Upgrades from the original game's older save versions. Original: `UPGRADE` in engine/core/state.js.
    static func upgrade(_ s: inout [String: JSONValue]) {
        var v = s["v"]?.int ?? 3
        while v < GameState.legacyVersion {
            if v == 4 || v == 3 {
                if v == 3 {
                    // version 3 -> 4: staff have a pay basis and a date of their last raise
                    var cos = s["cos"]?.array ?? []
                    for i in cos.indices {
                        var staff = cos[i]["staff"].array
                        for k in staff.indices {
                            if staff[k]["basis"].isNull { staff[k]["basis"] = .string(staff[k]["hrs"].isNull || staff[k]["hrs"].double == 0 ? "fix" : "hour") }
                            if staff[k]["lr"].isNull { staff[k]["lr"] = .number(staff[k]["w0"].double) }
                        }
                        cos[i]["staff"] = .array(staff)
                    }
                    s["cos"] = .array(cos)
                }
            }
            v += 1
        }
        s["v"] = .number(Double(GameState.legacyVersion))
    }

    /// Turn a save text into a game. Throws if it is not a Ledger save or is from a newer game than this one.
    public static func importText(_ text: String) throws -> GameState {
        guard let json = LZString.jsonText(fromSaveText: text), !json.isEmpty, let data = json.data(using: .utf8) else { throw SaveError.unreadable("could not unpack the text") }
        guard var root = (try? JSONDecoder().decode(JSONValue.self, from: data))?.object else { throw SaveError.unreadable("not valid JSON") }
        guard root["cos"] != nil, root["week"] != nil else { throw SaveError.notAGameSave }
        if (root["v"]?.int ?? 3) > GameState.legacyVersion { throw SaveError.newerThanThisApp(root["v"]?.int ?? 0) }
        upgrade(&root)
        // The native game is always played day by day.
        root["dmode"] = 1
        let patched = try JSONEncoder().encode(JSONValue.object(root))
        do { return try JSONDecoder().decode(GameState.self, from: patched) } catch { throw SaveError.unreadable("\(error)") }
    }
}
