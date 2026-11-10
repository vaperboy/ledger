import Foundation
import GameCore
import Businesses

public enum NativeSaveFormat {
    public static let formatName = "ledger-native"
    public static let currentVersion = 2
}

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

public extension NativeSaveFormat {
    static func check(_ envelope: [String: JSONValue]) throws {
        let v = envelope["version"]?.int ?? 0
        if v > currentVersion { throw SaveError.newerThanThisApp(v) }
        if v < currentVersion { throw SaveError.unreadable("saved by an older version of the game") }
    }
}

public enum LegacyImporter {
    static func upgrade(_ s: inout [String: JSONValue]) {
        var v = s["v"]?.int ?? 3
        while v < GameState.legacyVersion {
            if v == 4 || v == 3 {
                if v == 3 {
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

    public static func importText(_ text: String) throws -> GameState {
        guard let json = LZString.jsonText(fromSaveText: text), !json.isEmpty, let data = json.data(using: .utf8) else { throw SaveError.unreadable("could not unpack the text") }
        guard var root = (try? JSONDecoder().decode(JSONValue.self, from: data))?.object else { throw SaveError.unreadable("not valid JSON") }
        guard root["cos"] != nil, root["week"] != nil else { throw SaveError.notAGameSave }
        if (root["v"]?.int ?? 3) > GameState.legacyVersion { throw SaveError.newerThanThisApp(root["v"]?.int ?? 0) }
        upgrade(&root)
        LegacyIds.migrate(&root)
        root["dmode"] = 1
        let patched = try JSONEncoder().encode(JSONValue.object(root))
        do {
            var state = try JSONDecoder().decode(GameState.self, from: patched)
            Budget.migrate(&state)
            return state
        } catch { throw SaveError.unreadable("\(error)") }
    }
}
