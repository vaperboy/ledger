import Foundation
import GameCore
import Countries
import Finance
import Businesses

public struct StarterTrade: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var line: String
    public var startUpCost: Double?
}

public extension GameEngine {
    static let starterTradeIDs: [String] = ["cafe", "barber", "foodtruck", "cleaning", "handy", "webdev", "photo", "kiosk", "bakery", "gym", "boutique", "carclean"]

    static func countriesBySize() -> [Country] {
        let all: [Country] = (try? CountryBook.bundled().countries) ?? []
        return all.sorted { (a: Country, b: Country) -> Bool in
            a.populationMillions != b.populationMillions ? a.populationMillions > b.populationMillions : a.name < b.name
        }
    }

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

    static func firstSentence(_ text: String) -> String {
        guard let r = text.range(of: ". ") else { return text }
        return String(text[..<r.lowerBound]) + "."
    }

    static func suggestedCompanyName(countryCode: String, tradeID: String) -> String {
        guard let data = try? GameData.bundled() else { return "" }
        let word: String = data.catalog[tradeID]?.name ?? "Company"
        let starts: [String] = data.countries[countryCode]?.companyNameStarts ?? []
        guard let start = starts.randomElement() else { return word }
        return start + " " + word
    }

    static func startingCash(countryCode: String, tradeID: String) -> Double? {
        guard let e = try? GameEngine.newGame(countryCode: countryCode, playerName: "Preview", seed: 1, story: .fresh, tradeID: tradeID) else { return nil }
        return e.state.rest["start"]?["cash"].double
    }
}
