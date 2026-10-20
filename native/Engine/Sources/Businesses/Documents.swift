import Foundation
import GameCore
import Countries
import Finance

/// Licences, registrations and permits a business needs before it can open. Original: `docDef`, `docCost`,
/// `docNeeds`, `applyDoc`, `docsWeek` (engine/company/company.js, engine/countries/document_rules.js).
/// Names, fees and waiting times come from `tables.json` (the standard list) and each country's data file (overrides).
public enum Documents {
    public struct Definition: Equatable {
        public var name: String
        public var issuer: String
        public var cost: Double
        public var weeks: Int
        public var renewalCost: Double
        public var note: String
    }

    public static func definition(_ id: String, country: Country, tables: TradeTables) -> Definition? {
        var base = tables.raw["DOCS"][id]
        if base.isNull { base = Chains.extraDocuments[id] ?? .null }   // chain registration and franchise papers (Chains.swift)
        if base.isNull { return nil }
        let override = country.pack["documents"]["overrides"][id]
        func v(_ i: Int) -> JSONValue { (!override.isNull && !override[i].isNull) ? override[i] : base[i] }
        return Definition(name: v(0).string, issuer: v(1).string, cost: v(2).double, weeks: v(3).int, renewalCost: v(4).double, note: v(5).string)
    }

    public static func isSkipped(_ id: String, country: Country) -> Bool {
        country.pack["documents"]["notNeeded"].array.contains { $0.string == id }
    }

    /// Which documents the company needs now. Original: `docNeeds`.
    public static func needed(_ co: Company, _ bd: Trade, _ w: World) -> [String] {
        let country = w.country(co)
        var need = bd.documents.filter { !($0 == "vat" && Vat.isExempt(co, w)) }
        for knob in bd.knobs {
            for o in Knobs.activeOptions(co, knob) { for d in o.requiredDocs where !need.contains(d) { need.append(d) } }
        }
        if co.form == .limited && !need.contains("accountant_agreement") { need.append("accountant_agreement") }
        return need.filter { !isSkipped($0, country: country) }
    }

    /// Fee for an application. Original: `docCost`.
    public static func cost(_ id: String, company co: Company, _ bd: Trade, _ w: World) -> Double {
        let country = w.country(co)
        guard let dd = definition(id, country: country, tables: w.catalog.tables) else { return 0 }
        let abroad = co.countryCode != w.state.homeCountryCode
        var c = dd.cost * country.bureaucracy * country.costIndex * (abroad ? 1.8 : 1)
        if let q = bd.documentQuantities[id] {
            c *= q.string == "veh" ? max(1, Double(co.value("veh").array.count)) : q.double
        }
        let local = country.pack["documents"]["fees"][id]
        if !local.isNull && bd.documentQuantities[id] == nil {
            c = local.double * w.rates.rate(country) * (abroad ? 1.8 : 1)
        }
        if id == "accountant_agreement" { c = 0 }
        if co.form == .soleTrader, country.pack["documents"]["freeForSoleTraders"].array.contains(where: { $0.string == id }) { c = 0 }
        let fx = w.rates.rate(country)
        return jsRound(Currency.nicePrice(c / fx) * fx)
    }

    public static func renewalCost(_ id: String, company co: Company, _ w: World) -> Double {
        let country = w.country(co)
        guard let dd = definition(id, country: country, tables: w.catalog.tables), dd.renewalCost > 0 else { return 0 }
        let abroad = co.countryCode != w.state.homeCountryCode
        let c = dd.renewalCost * country.bureaucracy * country.costIndex * (abroad ? 1.4 : 1)
        let fx = w.rates.rate(country)
        return jsRound(Currency.nicePrice(c / fx) * fx)
    }

    public enum ApplyResult: Equatable { case ok, alreadyHeld, notEnoughCash, pickAccountant }

    /// Apply for a document: pay the fee, wait the weeks. Original: `applyDoc`.
    public static func apply(_ id: String, companyID: Int, state s: inout GameState, data: GameData) -> ApplyResult {
        guard let i = s.companyIndex(companyID) else { return .alreadyHeld }
        let co = s.companies[i]
        let w = World(state: s, data: data)
        guard let bd = w.trade(co), let dd = definition(id, country: w.country(co), tables: data.catalog.tables) else { return .alreadyHeld }
        let existing = co.value("docs")[id]["st"].string
        if !existing.isEmpty && existing != "lapsed" { return .alreadyHeld }
        if id == "accountant_agreement" && co.value("acc").isNull { return .pickAccountant }
        let fee = cost(id, company: co, bd, w)
        if fee > 0 && co.cash < fee { return .notEnoughCash }
        let abroad = co.countryCode != s.homeCountryCode
        var weeks = Double(dd.weeks)
        if abroad { weeks = (weeks * w.country(co).bureaucracy * 1.4).rounded(.up) }
        if id == "vat" || id == "registration" || id == "vat_not_applicable" { weeks = max(1, weeks) }
        if co.value("law")["own"].bool && weeks > 3 { weeks = (weeks * 0.75).rounded(.up) }
        if fee > 0 { Payments.companyPays(&s, companyID: companyID, amount: fee, category: "oth", label: "Application: \(dd.name)") }
        var docs = s.companies[i].value("docs")
        docs[id] = .object(["st": .string(weeks <= 0 ? "ok" : "applied"), "done": .number(Double(s.week) + weeks), "w0": .number(Double(s.week))])
        s.companies[i].set("docs", docs)
        return .ok
    }

    /// Weekly: approvals arrive, renewals fall due. Original: `docsWeek`.
    public static func weekly(_ s: inout GameState, companyIndex i: Int, data: GameData) {
        let co = s.companies[i]
        let w = World(state: s, data: data)
        var docs = co.value("docs")
        var notes: [(String, String)] = []
        var payments: [(Double, String)] = []
        for (id, d) in docs.object.sorted(by: { $0.key < $1.key }) {
            guard let dd = definition(id, country: w.country(co), tables: data.catalog.tables) else { continue }
            if d["st"].string == "applied" && Double(s.week) >= d["done"].double {
                docs[id]["st"] = "ok"; docs[id]["ok"] = .number(Double(s.week))
                notes.append(("\(dd.name) approved for \(co.name).", "good"))
            } else if d["st"].string == "ok" && dd.renewalCost > 0 && Double(s.week) - d["ok"].double >= 52
                        && (Int(Double(s.week) - d["ok"].double) % 52 == 0 || d["due"].bool) {
                // A renewal that cannot be paid on the day gets four weeks of grace before the licence lapses.
                let fee = renewalCost(id, company: co, w)
                if fee <= 0 || co.cash >= fee {
                    if fee > 0 { payments.append((fee, "Renewal: \(dd.name)")) }
                    docs[id]["due"] = 0
                } else {
                    let due = d["due"].double + 1
                    docs[id]["due"] = .number(due)
                    if due > 4 {
                        docs[id]["st"] = "lapsed"; docs[id]["due"] = 0
                        notes.append(("\(dd.name) lapsed for \(co.name) - renewal not paid.", "bad"))
                    } else if due == 1 {
                        notes.append(("\(dd.name) renewal is due at \(co.name) but the company is short of cash. It lapses in four weeks if unpaid.", "bad"))
                    }
                }
            }
        }
        s.companies[i].set("docs", docs)
        for (fee, label) in payments { Payments.companyPays(&s, companyID: co.id, amount: fee, category: "oth", label: label) }
        for (t, tone) in notes { s.note(t, tone: tone, companyID: co.id) }
    }
}
