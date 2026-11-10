import Foundation
import GameCore

public enum LogoCatalogue {
    public enum Source: Equatable, Sendable {
        case free
        case level(Int)
        case box(String)
        case plan(String)
    }

    public struct Logo: Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var source: Source
        public var asset: String
    }

    public static let all: [Logo] = {
        guard let url = Bundle.module.url(forResource: "logo_catalogue", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return [] }
        return j["logos"].array.map { (e: JSONValue) -> Logo in
            Logo(id: e["id"].string, name: e["name"].string, source: parse(e["how"].string), asset: e["asset"].string)
        }
    }()

    static func parse(_ how: String) -> Source {
        let p = how.split(separator: ":").map(String.init)
        if p.count == 2, p[0] == "level", let n = Int(p[1]) { return .level(n) }
        if p.count == 2, p[0] == "box" { return .box(p[1]) }
        if p.count == 2, p[0] == "plan" { return .plan(p[1]) }
        return .free
    }

    public static func logo(_ id: String) -> Logo? { all.first { $0.id == id } }

    public static func isUnlocked(_ l: Logo, level: Int, ladderOn: Bool, owned: Set<String>, perks: Set<String> = []) -> Bool {
        switch l.source {
        case .free: return true
        case .level(let n): return !ladderOn || level >= n
        case .box: return owned.contains(l.id)
        case .plan(let perk): return perks.contains(perk)
        }
    }

    public static func how(_ l: Logo) -> String {
        switch l.source {
        case .free: return "Free"
        case .level(let n): return "Level \(n)"
        case .box(let rarity): return rarity.capitalized + " box"
        case .plan(let perk): return perk == "founder" ? "Founder's Edition" : perk.capitalized
        }
    }
}
