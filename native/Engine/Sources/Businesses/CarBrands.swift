import Foundation
import GameCore
import Countries
import Finance

/// One model in a car brand's range. `factor` is its list price against the trade's average new-car ticket.
public struct CarModel: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var body: String
    public var factor: Double
    public var fuel: String
}

/// A car brand that sells through dealers (`Resources/car_brands.json`): its range, its dealer margin and what it demands of a dealership.
public struct CarBrand: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var origin: String
    public var segment: String
    public var markets: [String]
    /// 0 to 100: how much shoppers want the brand.
    public var strength: Double
    /// Dealer margin on the list price, built into the invoice price (0.065 = the dealer buys at 93.5 percent of list).
    public var margin: Double
    /// Extra share of the list price on a contract year's sales, paid after the yearly review when the volume target is met.
    public var bonus: Double
    public var termYears: Int
    /// Cars a year for a dealership of size 1.
    public var target: Double
    public var minSpaces: Int
    public var minSales: Int
    public var minSatisfaction: Double
    public var blurb: String
    public var models: [CarModel]

    public var averageFactor: Double { models.isEmpty ? 1 : models.map { $0.factor }.reduce(0, +) / Double(models.count) }
}

/// The brand and supplier data of the new-car dealership.
public enum CarBrands {
    static let book: JSONValue = {
        guard let url = Bundle.module.url(forResource: "car_brands", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return .null }
        return json
    }()

    public static let all: [CarBrand] = book["brands"].array.map { b in
        CarBrand(id: b["id"].string, name: b["name"].string, origin: b["origin"].string, segment: b["segment"].string,
                 markets: b["markets"].array.map { $0.string }, strength: b["strength"].double, margin: b["margin"].double, bonus: b["bonus"].double,
                 termYears: max(1, b["termYears"].int), target: b["target"].double, minSpaces: b["minSpaces"].int, minSales: b["minSales"].int,
                 minSatisfaction: b["minSat"].double, blurb: b["blurb"].string,
                 models: b["models"].array.map { CarModel(id: $0["id"].string, name: $0["name"].string, body: $0["body"].string, factor: $0["factor"].double, fuel: $0["fuel"].string) })
    }

    /// The brands on sale in a country.
    public static func forCountry(_ code: String) -> [CarBrand] { all.filter { $0.markets.contains(code) } }
    public static func brand(_ id: String) -> CarBrand? { all.first { $0.id == id } }

    /// The distributor's margin: lower than any brand's, because more of the chain is automated.
    public static var distributorMargin: Double { book["generic"]["margin"].double }
    public static var distributorName: String { book["generic"]["name"].string }
    /// Weeks a car takes to arrive: the distributor ships from its own stock, a brand builds to order.
    public static func leadWeeks(brandContract: Bool) -> (Int, Int) {
        let a = brandContract ? book["brand"]["leadWeeks"] : book["generic"]["leadWeeks"]
        return (max(1, a[0].int), max(1, a[1].int))
    }
}

/// A brand contract between a dealership and one brand. It replaces the generic distributor: while it runs, cars can only be ordered
/// from the brand. The brand reviews the dealership every contract year (volume against target, showroom, staff, customer satisfaction),
/// pays a volume bonus when the target is met, warns when it is not, and drops the dealership after a second warning. At the end of the
/// term it offers a renewal if it is happy, and otherwise lets the contract lapse. Leaving early costs a penalty.
///
/// Saved on the company as `cd.con` (only once a contract has been signed): b, start, end, margin, bonus, target, minSpaces, minSales,
/// minSat, yr (week the contract year began), sold, soldList (list value sold this year), warn, offer {margin, bonus, target, years, until},
/// last {w, ratio, sat, outcome, bonus}.
public enum CarBrandContract {
    public struct Standard: Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var need: String
        public var have: String
        public var ok: Bool
    }

    public struct Terms: Sendable, Equatable {
        public var brand: CarBrand
        public var years: Int
        public var margin: Double
        public var bonus: Double
        public var target: Int
        public var standards: [Standard]
        public var exitPenalty: Double
        public var allMet: Bool { standards.allSatisfy { $0.ok } }
        public var unmet: [Standard] { standards.filter { !$0.ok } }
    }

    public struct Active: Sendable, Equatable {
        public var brand: CarBrand
        public var start: Int
        public var end: Int
        public var margin: Double
        public var bonus: Double
        public var target: Int
        public var yearStart: Int
        public var sold: Int
        public var warnings: Int
        public var standards: [Standard]
        public var exitPenalty: Double
        public var weeksLeft: Int
        /// Cars sold this contract year against the target, scaled to the weeks gone (1 = on pace).
        public var pace: Double
        public var offer: Offer?
        public var last: Review?
    }

    public struct Offer: Sendable, Equatable {
        public var years: Int
        public var margin: Double
        public var bonus: Double
        public var target: Int
        public var until: Int
    }

    public struct Review: Sendable, Equatable {
        public var week: Int
        public var ratio: Double
        public var satisfaction: Double
        public var outcome: String
        public var bonus: Double
    }

    // MARK: Reading

    public static func isActive(_ co: Company) -> Bool { !co.value("cd")["con"].isNull }
    public static func brandID(_ co: Company) -> String? { isActive(co) ? co.value("cd")["con"]["b"].string : nil }

    public static func target(_ b: CarBrand, size: Double) -> Int { max(1, Int((b.target * max(0.4, size)).rounded())) }

    static func standards(_ b: CarBrand, minSpaces: Int, minSales: Int, minSat: Double, _ co: Company, _ bd: Trade) -> [Standard] {
        let spaces = CarDealer.spaces(co, bd)
        let sales = co.staff.filter { $0.role == "cardealer" }.count
        let sat = co.reputation
        return [
            Standard(id: "spaces", title: "Showroom and lot", need: "\(minSpaces) car spaces", have: "\(spaces)", ok: spaces >= minSpaces),
            Standard(id: "sales", title: "Salespeople", need: "\(minSales)", have: "\(sales)", ok: sales >= minSales),
            Standard(id: "sat", title: "Customer satisfaction", need: "\(Int(minSat)) of 100", have: "\(Int(sat.rounded()))", ok: sat >= minSat),
        ]
    }

    /// What it would cost to leave now: half a year of the brand margin on the target volume, for each year still to run.
    static func penalty(_ b: CarBrand, margin: Double, target: Int, weeksLeft: Int, listPrice: Double) -> Double {
        jsRound(Double(target) * listPrice * b.averageFactor * margin * 0.5 * max(0.25, Double(weeksLeft) / 52))
    }

    /// The terms a brand offers this company today (nil when the brand does not sell in its country).
    public static func terms(brandID: String, _ co: Company, _ s: GameState, _ data: GameData) -> Terms? {
        guard let b = CarBrands.brand(brandID), b.markets.contains(co.countryCode), let bd = data.catalog[CarDealer.tradeID] else { return nil }
        let t = target(b, size: co.size)
        let list = CarDealer.listTicket(co, bd, s, data)
        return Terms(brand: b, years: b.termYears, margin: b.margin, bonus: b.bonus, target: t,
                     standards: standards(b, minSpaces: b.minSpaces, minSales: b.minSales, minSat: b.minSatisfaction, co, bd),
                     exitPenalty: penalty(b, margin: b.margin, target: t, weeksLeft: b.termYears * 52, listPrice: list))
    }

    public static func active(_ co: Company, _ s: GameState, _ data: GameData) -> Active? {
        let c = co.value("cd")["con"]
        guard !c.isNull, let b = CarBrands.brand(c["b"].string), let bd = data.catalog[CarDealer.tradeID] else { return nil }
        let left = max(0, c["end"].int - s.week)
        let target = max(1, c["target"].int)
        let gone = Double(max(1, s.week - c["yr"].int))
        let pace = Double(c["sold"].int) / (Double(target) * min(1, gone / 52))
        let o = c["offer"]
        let l = c["last"]
        return Active(brand: b, start: c["start"].int, end: c["end"].int, margin: c["margin"].double, bonus: c["bonus"].double, target: target,
                      yearStart: c["yr"].int, sold: c["sold"].int, warnings: c["warn"].int,
                      standards: standards(b, minSpaces: c["minSpaces"].int, minSales: c["minSales"].int, minSat: c["minSat"].double, co, bd),
                      exitPenalty: penalty(b, margin: c["margin"].double, target: target, weeksLeft: left, listPrice: CarDealer.listTicket(co, bd, s, data)),
                      weeksLeft: left, pace: pace,
                      offer: o.isNull ? nil : Offer(years: o["years"].int, margin: o["margin"].double, bonus: o["bonus"].double, target: o["target"].int, until: o["until"].int),
                      last: l.isNull ? nil : Review(week: l["w"].int, ratio: l["ratio"].double, satisfaction: l["sat"].double, outcome: l["outcome"].string, bonus: l["bonus"].double))
    }

    // MARK: Actions

    /// Sign with a brand. Returns why not, or nil when signed. The brand's minimum standards must be met on the day.
    public static func sign(_ s: inout GameState, companyID: Int, brandID: String, data: GameData) -> String? {
        guard let i = s.companyIndex(companyID), s.companies[i].type == CarDealer.tradeID, s.companies[i].status == .open else { return "Only an open vehicle dealership can sign a brand contract." }
        guard !isActive(s.companies[i]) else { return "A brand contract is already running. Finish or leave it first." }
        guard let t = terms(brandID: brandID, s.companies[i], s, data) else { return "That brand does not sell in this country." }
        if !t.allMet { return "\(t.brand.name) requires: " + t.unmet.map { "\($0.title.lowercased()) \($0.need) (you have \($0.have))" }.joined(separator: "; ") + "." }
        var co = s.companies[i]
        var cd = co.value("cd")
        cd["con"] = .object(["b": .string(t.brand.id), "start": .number(Double(s.week)), "end": .number(Double(s.week + t.years * 52)),
                             "margin": .number(t.margin), "bonus": .number(t.bonus), "target": .number(Double(t.target)),
                             "minSpaces": .number(Double(t.brand.minSpaces)), "minSales": .number(Double(t.brand.minSales)), "minSat": .number(t.brand.minSatisfaction),
                             "yr": .number(Double(s.week)), "sold": 0, "soldList": 0, "warn": 0])
        co.set("cd", cd)
        s.companies[i] = co
        s.note("\(co.name) signed a \(t.years)-year dealer contract with \(t.brand.name).", tone: "good", companyID: co.id)
        return nil
    }

    /// Leave the contract early and pay the penalty. Returns the penalty paid, or nil when there is no contract or the cash is short.
    public static func exitEarly(_ s: inout GameState, companyID: Int, data: GameData) -> Double? {
        guard let i = s.companyIndex(companyID), let a = active(s.companies[i], s, data), s.companies[i].cash >= a.exitPenalty else { return nil }
        if a.exitPenalty > 0 {
            AccountingLedger.note(category: "fine", label: "Early exit penalty: \(a.brand.name) dealer contract")
            Ledger.moveRaw(&s, .company(companyID), -a.exitPenalty)
            var books = s.companies[i].books
            books.add("fine", a.exitPenalty)
            s.companies[i].books = books
        }
        end(&s, i, note: "\(s.companies[i].name) left the \(a.brand.name) dealer contract early.", tone: "warn")
        return a.exitPenalty
    }

    /// Take the renewal the brand offered. Returns why not, or nil when renewed.
    public static func renew(_ s: inout GameState, companyID: Int, data: GameData) -> String? {
        guard let i = s.companyIndex(companyID), let a = active(s.companies[i], s, data), let o = a.offer else { return "There is no renewal offer." }
        var cd = s.companies[i].value("cd")
        var c = cd["con"]
        c["end"] = .number(Double(max(a.end, s.week) + o.years * 52))
        c["margin"] = .number(o.margin); c["bonus"] = .number(o.bonus); c["target"] = .number(Double(o.target))
        c["yr"] = .number(Double(s.week)); c["sold"] = 0; c["soldList"] = 0; c["warn"] = 0
        c = without(c, "offer"); c = without(c, "asked"); c = without(c, "declined")
        cd["con"] = c
        s.companies[i].set("cd", cd)
        s.note("\(s.companies[i].name) renewed with \(a.brand.name) for \(o.years) years.", tone: "good", companyID: companyID)
        return nil
    }

    /// Turn the renewal down: the contract runs to its end and then the dealership is back on the generic distributor.
    public static func declineRenewal(_ s: inout GameState, companyID: Int) {
        guard let i = s.companyIndex(companyID), !s.companies[i].value("cd")["con"]["offer"].isNull else { return }
        var cd = s.companies[i].value("cd")
        cd["con"] = without(cd["con"], "offer")
        cd["con"]["declined"] = .bool(true)
        s.companies[i].set("cd", cd)
    }

    static func without(_ v: JSONValue, _ key: String) -> JSONValue {
        var o = v.object
        o.removeValue(forKey: key)
        return .object(o)
    }

    static func end(_ s: inout GameState, _ i: Int, note text: String, tone: String) {
        var cd = s.companies[i].value("cd")
        cd = without(cd, "con")
        s.companies[i].set("cd", cd)
        s.note(text, tone: tone, companyID: s.companies[i].id)
    }

    // MARK: Weekly: reviews, bonus, renewal, drop

    static func week(_ s: inout GameState, _ i: Int, _ bd: Trade, _ data: GameData) {
        guard let a = active(s.companies[i], s, data) else { return }
        let id = s.companies[i].id
        let name = s.companies[i].name
        var cd = s.companies[i].value("cd")
        var c = cd["con"]
        // Yearly review.
        if s.week - c["yr"].int >= 52 {
            let ratio = Double(c["sold"].int) / Double(max(1, a.target))
            let sat = s.companies[i].reputation
            let okStd = a.standards.allSatisfy { $0.ok }
            var bonus = 0.0
            var outcome = "No bonus: sales were below target."
            if okStd && ratio >= 1 { bonus = c["soldList"].double * a.bonus; outcome = "Target met: volume bonus paid." }
            else if okStd && ratio >= 0.85 { bonus = c["soldList"].double * a.bonus * 0.5; outcome = "Close to target: half the volume bonus paid." }
            var drop = false
            if ratio < 0.6 || !okStd {
                c["warn"] = .number(Double(c["warn"].int + 1))
                outcome = okStd ? "Warning: sales are far below target." : "Warning: the brand's standards are not met (\(a.standards.filter { !$0.ok }.map { $0.title.lowercased() }.joined(separator: ", ")))."
                if c["warn"].int >= 2 { drop = true; outcome = "Second warning: the brand ends the contract." }
            }
            if bonus > 0 {
                bonus = jsRound(bonus)
                AccountingLedger.note(category: "rev", label: "\(a.brand.name) volume bonus")
                Ledger.moveRaw(&s, .company(id), bonus)
                var books = s.companies[i].books
                books.add("rev", bonus)
                s.companies[i].books = books
            }
            c["last"] = .object(["w": .number(Double(s.week)), "ratio": .number(ratio), "sat": .number(sat), "outcome": .string(outcome), "bonus": .number(bonus)])
            c["yr"] = .number(Double(s.week)); c["sold"] = 0; c["soldList"] = 0
            cd["con"] = c
            s.companies[i].set("cd", cd)
            s.note("\(a.brand.name) review of \(name): \(outcome)", tone: drop ? "bad" : (bonus > 0 ? "good" : "warn"), companyID: id)
            if drop { end(&s, i, note: "\(a.brand.name) dropped \(name) as a dealer.", tone: "bad"); return }
        }
        guard let a2 = active(s.companies[i], s, data) else { return }
        cd = s.companies[i].value("cd")
        c = cd["con"]
        // Near the end: a renewal when the brand is happy (target met in the last review, no warnings, standards met), else it lets the contract lapse.
        if a2.weeksLeft <= 8 && a2.weeksLeft > 0 && c["offer"].isNull && !c["declined"].bool && !c["asked"].bool {
            c["asked"] = .bool(true)
            let happy = a2.warnings == 0 && a2.standards.allSatisfy { $0.ok } && (a2.last?.ratio ?? a2.pace) >= 0.9
            if happy {
                let better = (a2.last?.ratio ?? 1) >= 1.1
                let years = a2.brand.termYears
                c["offer"] = .object(["years": .number(Double(years)), "margin": .number(a2.margin + (better ? 0.003 : 0)), "bonus": .number(a2.bonus),
                                      "target": .number(Double(max(1, Int((Double(a2.target) * (better ? 1.1 : 1)).rounded())))), "until": .number(Double(a2.end))])
                s.note("\(a2.brand.name) is happy with \(name) and offers a \(years)-year renewal.", tone: "good", companyID: id)
            } else {
                s.note("\(a2.brand.name) is not happy with \(name) and will not renew the contract.", tone: "warn", companyID: id)
            }
            cd["con"] = c
            s.companies[i].set("cd", cd)
        }
        if s.week >= a2.end { end(&s, i, note: "The \(a2.brand.name) dealer contract of \(name) has ended.", tone: "warn") }
    }

    /// A sale of a car of the contract brand: counts towards the volume target.
    static func recordSale(_ co: inout Company, brand: String, list: Double) {
        guard co.value("cd")["con"]["b"].string == brand else { return }
        var cd = co.value("cd")
        cd["con"]["sold"] = .number(Double(cd["con"]["sold"].int + 1))
        cd["con"]["soldList"] = .number(cd["con"]["soldList"].double + list)
        co.set("cd", cd)
    }
}
