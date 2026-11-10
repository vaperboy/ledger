import Foundation
import GameCore
import Countries
import Finance

public enum PlaceMarket {
    public enum Category: String, CaseIterable, Sendable {
        case offices, shops, retail
        public var title: String {
            switch self {
            case .offices: return "Offices"
            case .shops: return "Shops"
            case .retail: return "Retail and storage"
            }
        }
    }

    public struct Offer: Identifiable, Equatable {
        public var id: String
        public var originCompanyID: Int
        public var listing: CompanySetup.Listing
        public var placeKind: String
        public var category: Category
        public var buildingType: String
        public var cityID: String
        public var cityName: String
        public var canBuy: Bool
        public var title: String = ""
        public var photoSlot: Int = 0
    }

    public struct Candidate: Identifiable, Equatable {
        public var id: Int { companyID }
        public var companyID: Int
        public var name: String
        public var cash: Double
        public var monthlyRent: Double
        public var upfrontRent: Double
        public var upfrontBuy: Double
        public var canRent: Bool
        public var canBuy: Bool
        public var hasPlace: Bool
    }

    public struct Rented: Identifiable, Equatable {
        public var id: Int { companyID }
        public var companyID: Int
        public var companyName: String
        public var placeName: String
        public var landlord: String
        public var squareMetres: Double
        public var buildingType: String
        public var cityName: String
        public var category: Category
        public var owned: Bool
        public var monthlyRent: Double
        public var deposit: Double
        public var atHome: Bool
        public var isHomeTrade: Bool
        public var title: String = ""
        public var photoSlot: Int = 0
    }

    public static func placeKind(_ co: Company, _ bd: Trade) -> String? {
        guard bd.family != "rent", let k = bd.premisesKind, k != "none" else { return nil }
        return k == "home" ? PremisesExtras.placeKind(bd) : k
    }

    public static func category(kind: String, squareMetres: Double) -> Category {
        switch kind {
        case "office", "clinic": return .offices
        case "shop", "kitchen", "hotel", "gym": return squareMetres >= 400 ? .retail : .shops
        default: return .retail
        }
    }

    static func eligible(_ s: GameState, data: GameData) -> [Company] {
        s.companies.filter { co in
            guard co.status.isLive, let bd = data.catalog[co.type] else { return false }
            return placeKind(co, bd) != nil
        }
    }

    public static func offers(_ s: GameState, data: GameData) -> [Offer] {
        let w = World(state: s, data: data)
        var seen = Set<String>()
        var out: [Offer] = []
        for co in eligible(s, data: data) {
            guard let bd = data.catalog[co.type], let kind = placeKind(co, bd) else { continue }
            let group = co.type + "|" + co.cityID
            if seen.contains(group) { continue }
            seen.insert(group)
            let cityName = data.countries.city(co.cityID, preferring: co.countryCode)?.city.name ?? co.cityID
            let typeName = data.catalog.tables.premises[kind]?.name ?? "Premises"
            let country = w.country(co)
            for l in CompanySetup.listings(for: co, bd, w) {
                let title = PlaceNames.title(seed: s.seed, country: country, cityID: co.cityID, cityName: cityName, tier: l.index, group: group, week: s.week, kind: kind)
                out.append(Offer(id: "\(co.id):\(l.index)", originCompanyID: co.id, listing: l, placeKind: kind, category: category(kind: kind, squareMetres: l.squareMetres),
                                 buildingType: typeName, cityID: co.cityID, cityName: cityName, canBuy: kind != "slope",
                                 title: title, photoSlot: PlaceNames.photoSlot(seed: s.seed, group: group + ":" + String(s.week / 26), index: l.index)))
            }
        }
        return out
    }

    public static func candidates(_ s: GameState, offer: Offer, data: GameData) -> [Candidate] {
        let w = World(state: s, data: data)
        var out: [Candidate] = []
        for co in eligible(s, data: data) {
            guard let bd = data.catalog[co.type], placeKind(co, bd) == offer.placeKind, co.cityID == offer.cityID,
                  let t = CompanySetup.premisesTerms(co, offer.listing, data: data, world: w) else { continue }
            let rentUp = t.deposit + t.fitOut
            let buyUp = t.downPayment + t.fitOut
            let prem = co.value("prem")
            let refund = prem["dep"].double > 0 && !prem["owned"].bool ? prem["dep"].double : 0
            out.append(Candidate(companyID: co.id, name: co.name, cash: co.cash, monthlyRent: t.monthlyRent, upfrontRent: rentUp, upfrontBuy: buyUp,
                                 canRent: co.cash + refund >= rentUp, canBuy: offer.canBuy && co.cash + refund >= buyUp, hasPlace: prem["m2"].double > 0))
        }
        return out
    }

    public static func rented(_ s: GameState, data: GameData) -> [Rented] {
        var out: [Rented] = []
        for co in eligible(s, data: data) {
            guard let bd = data.catalog[co.type], let kind = placeKind(co, bd) else { continue }
            let prem = co.value("prem")
            let m2 = prem["m2"].double
            let cityName = data.countries.city(co.cityID, preferring: co.countryCode)?.city.name ?? co.cityID
            let home = PremisesExtras.isAtHome(co, bd)
            if m2 <= 0 && !PremisesExtras.isHomeTrade(bd) { continue }
            let placeKindNow = prem["kind"].isNull ? kind : prem["kind"].string
            let typeName = data.catalog.tables.premises[placeKindNow]?.name ?? "Premises"
            let shownName: String = !prem["ltitle"].string.isEmpty ? prem["ltitle"].string : (prem["lname"].string.isEmpty ? typeName : prem["lname"].string)
            let slot: Int = prem["lslot"].isNull ? PlaceNames.photoSlot(seed: s.seed, group: "rented:" + String(co.id), index: 0) : prem["lslot"].int
            out.append(Rented(companyID: co.id, companyName: co.name, placeName: shownName, landlord: prem["landlord"].string,
                              squareMetres: m2, buildingType: typeName, cityName: cityName, category: category(kind: placeKindNow, squareMetres: m2),
                              owned: prem["owned"].bool, monthlyRent: prem["owned"].bool ? 0 : prem["rent"].double * m2 / 12, deposit: prem["dep"].double,
                              atHome: home, isHomeTrade: PremisesExtras.isHomeTrade(bd), title: shownName, photoSlot: slot))
        }
        return out
    }

    public static func targets(_ s: GameState, from companyID: Int, data: GameData) -> [Candidate] {
        guard let from = s.company(companyID), let fbd = data.catalog[from.type], let kind = placeKind(from, fbd) else { return [] }
        let prem = from.value("prem")
        guard prem["m2"].double > 0, !prem["owned"].bool else { return [] }
        let rent = prem["rent"].double * prem["m2"].double / 12
        let deposit = prem["dep"].double
        var out: [Candidate] = []
        for co in eligible(s, data: data) where co.id != companyID && co.cityID == from.cityID {
            guard let bd = data.catalog[co.type], placeKind(co, bd) == kind else { continue }
            let own = co.value("prem")
            if own["owned"].bool { continue }
            let back = own["m2"].double > 0 && own["dep"].double > 0 ? own["dep"].double : 0
            out.append(Candidate(companyID: co.id, name: co.name, cash: co.cash, monthlyRent: rent, upfrontRent: deposit, upfrontBuy: 0,
                                 canRent: co.cash + back >= deposit, canBuy: false, hasPlace: own["m2"].double > 0))
        }
        return out
    }

    public struct RentOutcome: Equatable {
        public var result: CompanySetup.PremisesResult
        public var reference: String
        public init(result: CompanySetup.PremisesResult, reference: String) { self.result = result; self.reference = reference }
    }

    @discardableResult
    public static func take(_ s: inout GameState, companyID: Int, offer: Offer, buy: Bool, receiptCompanyID: Int, data: GameData) -> RentOutcome {
        guard let i = s.companyIndex(companyID), s.companyIndex(receiptCompanyID) != nil,
              candidates(s, offer: offer, data: data).contains(where: { $0.companyID == companyID }),
              let t = CompanySetup.premisesTerms(s.companies[i], offer.listing, data: data, world: World(state: s, data: data)) else {
            return RentOutcome(result: .bad, reference: "")
        }
        if buy && !offer.canBuy { return RentOutcome(result: .bad, reference: "") }
        let result = CompanySetup.setPremises(&s, companyID: companyID, listing: offer.listing, buy: buy, data: data)
        guard result == .ok else { return RentOutcome(result: result, reference: "") }
        let id = s.makeID()
        let ref = Receipts.reference(prefix: "AS", year: GameCalendar.year(week: s.week), id: id)
        let now = buy ? t.downPayment + t.fitOut : t.deposit + t.fitOut
        let payer = s.companies[i].name
        let what = buy ? "Purchase" : "Lease"
        Receipts.add(&s, receiptCompanyID: receiptCompanyID, number: ref, kind: "lease", title: what + ": " + (offer.title.isEmpty ? offer.listing.name : offer.title),
                     detail: payer + " \u{00B7} " + String(Int(offer.listing.squareMetres)) + " m² \u{00B7} " + offer.listing.landlord + " \u{00B7} " + offer.cityName, amount: now, payer: payer)
        var prem = s.companies[i].value("prem")
        prem["ref"] = .string(ref)
        prem["rc"] = .number(Double(receiptCompanyID))
        if !offer.title.isEmpty { prem["ltitle"] = .string(offer.title); prem["lslot"] = .number(Double(offer.photoSlot)) }
        s.companies[i].set("prem", prem)
        return RentOutcome(result: .ok, reference: ref)
    }

    public enum MoveResult: Equatable { case ok, notRented, notPossible, notEnoughCash }

    public static func reassign(_ s: inout GameState, from: Int, to: Int, data: GameData) -> MoveResult {
        guard from != to, let fi = s.companyIndex(from), let ti = s.companyIndex(to),
              let fbd = data.catalog[s.companies[fi].type], let tbd = data.catalog[s.companies[ti].type],
              let fk = placeKind(s.companies[fi], fbd), let tk = placeKind(s.companies[ti], tbd), s.companies[ti].status.isLive else { return .notPossible }
        let prem = s.companies[fi].value("prem")
        guard prem["m2"].double > 0, !prem["owned"].bool else { return .notRented }
        guard fk == tk, s.companies[fi].cityID == s.companies[ti].cityID, s.companies[fi].value("landlord").isNull else { return .notPossible }
        let toPrem = s.companies[ti].value("prem")
        if toPrem["owned"].bool { return .notPossible }
        let deposit = prem["dep"].double
        let refundTo = toPrem["m2"].double > 0 && toPrem["dep"].double > 0 ? toPrem["dep"].double : 0
        if s.companies[ti].cash + refundTo < deposit { return .notEnoughCash }
        if refundTo > 0 { Payments.companyReceives(&s, companyID: to, amount: refundTo, category: nil, label: "Lease deposit returned") }
        if deposit > 0 {
            Payments.companyReceives(&s, companyID: from, amount: deposit, category: nil, label: "Lease deposit returned")
            Payments.companyPays(&s, companyID: to, amount: deposit, category: nil, label: "Lease deposit (moved from \(s.companies[fi].name))")
        }
        var moved = prem
        moved["kind"] = .string(tk)
        s.companies[ti].set("prem", moved)
        var fromEq = s.companies[fi].value("eq")
        if !fromEq["fit"].isNull {
            var toEq = s.companies[ti].value("eq")
            toEq["fit"] = fromEq["fit"]
            s.companies[ti].set("eq", toEq)
            fromEq = .object(fromEq.object.filter { $0.key != "fit" })
            s.companies[fi].set("eq", fromEq)
        }
        let leftKind = fbd.premisesKind ?? "none"
        s.companies[fi].set("prem", .object(["kind": .string(leftKind), "m2": 0, "rent": 0, "owned": false, "val": 0, "loan": 0]))
        s.note("\(s.companies[ti].name) took over the lease of \(!prem["ltitle"].string.isEmpty ? prem["ltitle"].string : (prem["lname"].string.isEmpty ? "the place" : prem["lname"].string)) from \(s.companies[fi].name).", tone: "n", companyID: to)
        return .ok
    }
}
