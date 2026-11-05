import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// What the start screen reads before any game exists: the countries by size, the starter trades, a suggested company name
/// and the money a player starts with. Pure reads over bundled data; nothing here changes a game.
public struct StarterTrade: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// The first sentence of the trade's blurb.
    public var line: String
    /// The start-up cost in the player's first city (nil: the trade cannot be started there).
    public var startUpCost: Double?
}

public extension GameEngine {
    /// The twelve trades shown first.
    static let starterTradeIDs: [String] = ["cafe", "barber", "foodtruck", "cleaning", "handy", "webdev", "photo", "kiosk", "bakery", "gym", "boutique", "carclean"]

    /// The countries, largest first (by population).
    static func countriesBySize() -> [Country] {
        let all: [Country] = (try? CountryBook.bundled().countries) ?? []
        return all.sorted { (a: Country, b: Country) -> Bool in
            a.populationMillions != b.populationMillions ? a.populationMillions > b.populationMillions : a.name < b.name
        }
    }

    /// The trades the player can start in this country with their start-up cost: the starter twelve, or all of them (cheapest first).
    static func startableTrades(countryCode: String, all: Bool) -> [StarterTrade] {
        guard let preview = try? GameEngine.newGame(countryCode: countryCode, playerName: "Preview", seed: 1) else { return [] }
        let rows: [TradePickerRow] = preview.tradePickerRows()
        var costs: [String: Double] = [:]
        for r in rows where r.blocked == nil { if let c = r.startUpCost { costs[r.tradeID] = c } }
        let ids: [String] = all ? rows.map { $0.tradeID } : starterTradeIDs
        var out: [StarterTrade] = []
        for id in ids {
            guard let bd = preview.data.catalog[id], SpecialFamilies.isStartable(bd), let cost = costs[id] else { continue }
            out.append(StarterTrade(id: id, name: bd.name, line: firstSentence(bd.blurb), startUpCost: cost))
        }
        return all ? out.sorted { ($0.startUpCost ?? 0) < ($1.startUpCost ?? 0) } : out
    }

    /// The first sentence of a blurb, with its full stop.
    static func firstSentence(_ text: String) -> String {
        guard let r = text.range(of: ". ") else { return text }
        return String(text[..<r.lowerBound]) + "."
    }

    /// A company name made from a local name start and the trade ("Nordvik Café").
    static func suggestedCompanyName(countryCode: String, tradeID: String) -> String {
        guard let data = try? GameData.bundled() else { return "" }
        let word: String = data.catalog[tradeID]?.name ?? "Company"
        let starts: [String] = data.countries[countryCode]?.companyNameStarts ?? []
        guard let start = starts.randomElement() else { return word }
        return start + " " + word
    }

    /// The money a player starts with in this country and trade (start-up cost plus eight weeks of costs, rounded up to 1,000); nil if the trade cannot start there.
    static func startingCash(countryCode: String, tradeID: String) -> Double? {
        guard let e = try? GameEngine.newGame(countryCode: countryCode, playerName: "Preview", seed: 1, story: .fresh, tradeID: tradeID) else { return nil }
        return e.state.rest["start"]?["cash"].double
    }
}
