import Foundation
import GameCore
import Countries

public struct RealCompany: Equatable, Sendable {
    public var name: String, owner: String, trade: String, city: String, countryCode: String, size: Double
    public init(name: String, owner: String, trade: String, city: String, countryCode: String, size: Double = 1) {
        self.name = name; self.owner = owner; self.trade = trade; self.city = city; self.countryCode = countryCode; self.size = size
    }
}

public enum RealRivals {
    public static func set(_ s: inout GameState, _ list: [RealCompany]) {
        let sorted = list.sorted { ($0.countryCode, $0.city, $0.trade, $0.name) < ($1.countryCode, $1.city, $1.trade, $1.name) }
        s.rest["real"] = .array(sorted.map {
            .object(["name": .string($0.name), "owner": .string($0.owner), "trade": .string($0.trade), "city": .string($0.city),
                     "cc": .string($0.countryCode), "size": .number($0.size)])
        })
    }

    static func matching(_ s: GameState, key: String, trade bd: Trade, countryCode: String, data: GameData) -> [RealCompany] {
        guard let list = s.rest["real"]?.array, !list.isEmpty else { return [] }
        let cityID = String(key.split(separator: "|", maxSplits: 1).last ?? "")
        guard let cityName = data.countries.city(cityID, preferring: countryCode)?.city.name else { return [] }
        return list.compactMap { j -> RealCompany? in
            guard j["cc"].string == countryCode, j["trade"].string.lowercased() == bd.name.lowercased(), j["city"].string.lowercased() == cityName.lowercased() else { return nil }
            return RealCompany(name: j["name"].string, owner: j["owner"].string, trade: j["trade"].string, city: j["city"].string, countryCode: countryCode,
                               size: j["size"].double > 0 ? j["size"].double : 1)
        }
    }
}
