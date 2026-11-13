import Foundation
import GameCore

/// Work clothes by trade: which uniform layer an employee or manager wears over their portrait.
public enum Uniforms {
    public struct Uniform: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var detail: String
        /// Art file stem in Content/art: uniform.<id>.png, a transparent clothing layer.
        public var art: String { "uniform." + id }
    }

    struct Tables {
        var uniforms: [Uniform] = []
        var trades: [String: String] = [:]
        var families: [String: String] = [:]
        var officeRoles: Set<String> = []
    }

    static let tables: Tables = {
        var t = Tables()
        guard let url = Bundle.module.url(forResource: "uniforms", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return t }
        t.uniforms = j["uniforms"].array.map { (e: JSONValue) -> Uniform in Uniform(id: e["id"].string, title: e["title"].string, detail: e["detail"].string) }
        t.trades = j["trades"].object.mapValues { (v: JSONValue) -> String in v.string }
        t.families = j["families"].object.mapValues { (v: JSONValue) -> String in v.string }
        t.officeRoles = Set(j["officeRoles"].array.map { (v: JSONValue) -> String in v.string })
        return t
    }()

    public static var all: [Uniform] { tables.uniforms }
    public static func uniform(_ id: String) -> Uniform? { tables.uniforms.first { $0.id == id } }
    public static var tradeMap: [String: String] { tables.trades }

    /// The uniform id for a person with this role in a company of this trade; empty when they wear their own clothes.
    public static func id(trade: Trade?, role: String) -> String {
        guard let trade, !tables.officeRoles.contains(role) else { return "" }
        return tables.trades[trade.id] ?? tables.families[trade.family] ?? ""
    }
}
