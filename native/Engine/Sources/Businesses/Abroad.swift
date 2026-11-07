import Foundation
import GameCore
import Countries
import Finance

/// Opening a subsidiary of a company in another country. Original: `expandAbroad`, `foreignCountries`, `deskFor`
/// (engine/world/abroad.js) and the tab `CT.abroad`, actions `abrset`, `abrgo` (ui/company/deals.js).
public enum Abroad {
    public enum Failure: Error, Equatable, Sendable { case notOpen, unknownCountry, brandTooWeak, banned(String), cannotStart(CompanySetup.StartError) }

    public struct Option: Equatable, Sendable {
        public var countryCode: String
        public var name: String
        public var estimatedStartCost: Double
        public var registrationWeeks: Double
        public var hasDesk: Bool
    }

    /// Does the head office have a compliance desk for this country? Original: `deskFor`.
    public static func hasDesk(_ s: GameState, country: String) -> Bool { s.hasHeadOffice("cd_" + country) }

    /// Countries this company may expand to (the trade is allowed there), with the estimate the tab shows.
    public static func options(_ s: GameState, companyID: Int, data: GameData) -> [Option] {
        guard let co = s.company(companyID), co.status == .open, !co.value("franchise")["fran"].bool else { return [] }
        var out: [Option] = []
        for c in data.countries.countries where c.code != co.countryCode && CompanySetup.banReason(co.type, country: c) == nil {
            let est = CompanySetup.estimate(tradeID: co.type, cityID: c.cities.first?.id ?? "", form: .limited, size: 1, countryCode: c.code, state: s, data: data)
            let doc = Documents.definition("foreign_entity", country: c, tables: data.catalog.tables)?.weeks ?? 3
            let desk = hasDesk(s, country: c.code)
            out.append(Option(countryCode: c.code, name: c.name, estimatedStartCost: est?.total ?? 0,
                              registrationWeeks: (Double(doc) * c.bureaucracy * (desk ? 0.6 : 1.4)).rounded(.up), hasDesk: desk))
        }
        return out
    }

    /// Countries where you run something, other than home. Original: `foreignCountries`.
    public static func foreignCountries(_ s: GameState) -> [String] {
        var out: [String] = []
        for c in s.companies where c.status.isLive {
            if c.countryCode != s.homeCountryCode, !out.contains(c.countryCode) { out.append(c.countryCode) }
            for m in c.value("fr")["masters"].array where m["c"].string != s.homeCountryCode && !out.contains(m["c"].string) { out.append(m["c"].string) }
        }
        return out
    }

    /// Create the foreign subsidiary. It starts with part of the brand and still has to register and open. Original: `expandAbroad`.
    public static func expand(_ s: inout GameState, companyID: Int, country code: String, cityID: String? = nil, data: GameData, context: FinanceContext) -> Result<Int, Failure> {
        guard let co = s.company(companyID), co.status == .open else { return .failure(.notOpen) }
        guard let C = data.countries[code], code != co.countryCode else { return .failure(.unknownCountry) }
        if co.reputation < 35 { return .failure(.brandTooWeak) }
        if let why = CompanySetup.banReason(co.type, country: C) { return .failure(.banned(why)) }
        let r = CompanySetup.create(&s, tradeID: co.type, cityID: cityID ?? (C.cities.first?.id ?? ""), form: .limited, name: co.name + " " + C.name,
                                    countryCode: code, data: data, context: context)
        switch r {
        case .failure(let e): return .failure(.cannotStart(e))
        case .success(let id):
            guard let n = s.companyIndex(id) else { return .failure(.unknownCountry) }
            s.companies[n].set("foreignOf", companyID)
            s.companies[n].reputation = max(s.companies[n].reputation, jsRound(co.reputation * 0.55))
            s.companies[n].awareness = max(s.companies[n].awareness, jsRound(co.awareness * 0.4))
            s.companies[n].set("wom", max(s.companies[n].num("wom"), jsRound(co.awareness * 0.2)))
            s.note("\(s.companies[n].name) is registered in \(C.name). Complete the foreign registration and local permits before opening.", companyID: id)
            return .success(id)
        }
    }

    /// Monthly, after the exchange rates move: each country where you operate may issue new rules. Without a head-office
    /// country desk the late compliance is fined on one open company there. Original: `regulationMonth` (country part).
    public static func regulationMonth(_ s: inout GameState, data: GameData) {
        for k in foreignCountries(s) {
            guard let c = data.countries[k] else { continue }
            if !s.random.chance(0.1 * c.bureaucracy) { continue }
            let desk = hasDesk(s, country: k)
            let target = s.companies.first(where: { $0.status == .open && $0.countryCode == k })
                ?? s.companies.first(where: { $0.status == .open && $0.value("fr")["masters"].array.contains { $0["c"].string == k } })
            guard let t = target else { continue }
            let what = s.random.pick(["new data and labelling rules", "a stricter permit regime", "higher local reporting duties", "a changed employment regulation"])
            if desk {
                s.note("Your \(c.name) desk handled \(what) with no trouble.", tone: "good", companyID: t.id)
                continue
            }
            let cur = Currency(country: c, rates: ExchangeRates(drift: s.exchangeRates.values))
            let fine = cur.scaledPrice(s.random.range(8000, 30000).rounded() * c.bureaucracy)
            Payments.companyPays(&s, companyID: t.id, amount: fine, category: "fine", label: "Late compliance with \(what) in \(c.name)")
            s.addMessage(kind: "info", from: c.name + " authorities", title: "New rules in \(c.name)",
                         body: "You missed \(what) and were fined \(cur.display(fine)). An HQ country desk for \(c.name) would have caught it.",
                         companyID: t.id, tone: "bad", status: "done")
        }
    }
}
