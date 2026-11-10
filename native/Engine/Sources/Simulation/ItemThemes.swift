import Foundation
import GameCore

public struct ItemTheme: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
}

public enum ItemThemes {
    public static let classicID = "classic"
    public static let founderID = "founder"

    public static let all: [ItemTheme] = ContentFile.load("themes", "item_themes")["themes"].array.map { (e: JSONValue) -> ItemTheme in
        ItemTheme(id: e["id"].string, name: e["name"].string)
    }

    public static func theme(_ id: String) -> ItemTheme? { all.first { $0.id == id } }
    public static func isKnown(_ id: String) -> Bool { theme(id) != nil }
    public static func name(_ id: String) -> String { theme(id)?.name ?? "Classic" }

    static func id(_ e: JSONValue, fallback: String = ItemThemes.classicID) -> String {
        e["theme"].isNull ? fallback : e["theme"].string
    }
}
