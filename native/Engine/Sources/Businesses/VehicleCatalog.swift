import Foundation
import GameCore

/// Fleet vehicles: every picture carries exactly one model name, and a vehicle model always uses the same pictures in the same order.
public enum VehicleCatalog {
    static let book: JSONValue = {
        guard let url = Bundle.module.url(forResource: "vehicle_art", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return .null }
        return json
    }()

    /// Picture keys of a vehicle model, in offer order. Empty for an unknown model.
    public static func artKeys(_ modelID: String) -> [String] { book["models"][modelID].array.map { (k: JSONValue) -> String in k.string } }

    /// The one model name of a picture.
    public static func modelName(artKey: String) -> String? {
        let n: JSONValue = book["names"][artKey]
        return n.isNull ? nil : n.string
    }

    /// Picture and model name of offer number `index` for a vehicle model.
    public static func variant(modelID: String, index: Int) -> (art: String, model: String)? {
        let keys: [String] = artKeys(modelID)
        guard !keys.isEmpty else { return nil }
        let key: String = keys[max(0, index) % keys.count]
        guard let name = modelName(artKey: key) else { return nil }
        return (key, name)
    }

    public static var allModelIDs: [String] { Array(book["models"].object.keys).sorted() }
    public static var allArtKeys: [String] { Array(book["names"].object.keys).sorted() }

    /// True for a picture key that has no picture yet.
    public static func isPlaceholder(_ artKey: String) -> Bool { artKey.hasPrefix("vehicle.") }
}
