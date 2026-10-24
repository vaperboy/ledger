import Foundation
import GameCore
import Countries
import Finance

/// Franchising from both sides.
///
/// You as the franchisor (`co.fr`): a proven chain launches a franchise system, people apply, you talk terms, units pay a
/// fee and royalties, struggle, renew, leave or are ended. You as the franchisee (`co.franchise`): you pay royalties and a
/// marketing fund, the brand holds you to a quality standard, and the contract ends after its term.
/// Originals: engine/world/deals.js (`frReq`, `frSetup`, `frApplicants`, `frAcceptCore`), features/world/franchise_lifecycle.js
/// (`frWeek`, `franchiseeWeek`, `endUnit`, `leaveBrand`), features/company/franchise_talks.js, engine/world/abroad.js (`frMaster`, `masterWeek`).
public enum Franchising {
    // MARK: Helpers

    static func pay(_ s: inout GameState, _ id: Int, _ amount: Double, _ category: String?, _ label: String? = nil) {
        Payments.companyPays(&s, companyID: id, amount: amount, category: category, label: label)
    }
    static func receive(_ s: inout GameState, _ id: Int, _ amount: Double, _ category: String?, _ label: String? = nil) {
        Payments.companyReceives(&s, companyID: id, amount: amount, category: category, label: label)
    }
    static func money(_ s: GameState, _ fc: FinanceContext, _ co: Company, _ v: Double) -> String { fc.currency(co.countryCode, s).short(v) }
    static func season(_ bd: Trade, week: Int, data: GameData) -> Double {
        (data.catalog.tables.seasons[bd.seasonKey] ?? Array(repeating: 1, count: 12))[GameCalendar.month(week: week)]
    }
    static func round(_ v: Double) -> Double { jsRound(v) }

    /// What it costs a franchisee to open one unit. Original: `unitSetupCost`.
    public static func unitSetupCost(_ co: Company, _ bd: Trade, data: GameData) -> Double {
        let t = data.catalog.tables
        var eq = 0.0
        for e in bd.equipment where e.standardCount > 0 {
            if let m = e.vehicleModels?.first { eq += (t.vehicles[m]?.price ?? 0) * max(1, (e.standardCount * 0.7).rounded()) }
            else { eq += e.cost * max(1, (e.standardCount * 0.7).rounded()) }
        }
        var pm = 0.0
        if let kind = bd.premisesKind, bd.premisesM2 > 0 { pm = bd.premisesM2 * 0.7 * (t.fitOut[kind] ?? 0) }
        return ((eq + pm + bd.openingCost) / 1000).rounded() * 1000
    }

    // MARK: Requirements

    public struct Requirement: Equatable, Sendable, Identifiable {
        public var id: String { title }
        public var title: String
        public var ok: Bool
        public var detail: String
    }

    /// Franchising is for a chain that has proven itself. Original: `frReq` (the checklist on the chain page).
    public static func requirements(_ s: GameState, _ co: Company) -> [Requirement] {
        let ch = Chains.chain(s, of: co)
        let L = ch.map { Chains.stores(s, $0) } ?? []
        let open1y = L.filter { $0.status == .open && s.week - ($0.openedWeek ?? s.week) >= 52 }.count
        let age = ch.map { s.week - $0["w0"].int } ?? 0
        let prof = L.reduce(0.0) { $0 + $1.monthlyHistory.suffix(12).reduce(0) { $0 + $1.profit } }
        let rep = L.isEmpty ? 0 : L.reduce(0.0) { $0 + $1.reputation } / Double(L.count)
        let boss = ch.map { Chains.hasChainBoss(s, $0, stores: L) } ?? false
        func months(_ w: Int) -> Int { Int((Double(max(0, w)) / 4.33).rounded(.up)) }
        return [
            Requirement(title: "A registered chain", ok: ch != nil, detail: ch?["name"].string ?? "Register the first store as a chain first"),
            Requirement(title: "Three stores open for a year", ok: open1y >= 3, detail: "\(open1y) of 3"),
            Requirement(title: "Three years as a chain", ok: age >= 156, detail: age >= 156 ? "Yes" : "\(months(156 - age)) months to go"),
            Requirement(title: "The chain made money last year", ok: prof > 0, detail: prof > 0 ? "Yes" : "Not yet"),
            Requirement(title: "Customers like the chain", ok: rep >= 60, detail: L.isEmpty ? "-" : "reputation \(Int(rep))"),
            Requirement(title: "Someone to look after franchisees", ok: boss, detail: boss ? "Your chain team does" : "Hire a chain manager, or have a manager in every store"),
        ]
    }

    public enum LaunchResult: Equatable, Sendable { case ok, already, notYet(String), needDocuments, notFranchisable }

    /// Start franchising a concept. The franchise documents must be approved first. Original: `frSetup`.
    public static func launch(_ s: inout GameState, companyID: Int, fee: Double, royalty: Double, support: Int) -> LaunchResult {
        guard let i = s.companyIndex(companyID) else { return .notYet("") }
        let co = s.companies[i]
        guard FranchiseBrands.isFranchisable(co.type) else { return .notFranchisable }
        if co.value("fr")["on"].bool { return .already }
        if let miss = requirements(s, co).first(where: { !$0.ok }) { return .notYet("Not yet: \(miss.title.lowercased()) (\(miss.detail.lowercased())).") }
        if co.value("docs")["fran"]["st"].string != "ok" { return .needDocuments }
        s.companies[i].set("fr", .object(["on": 1, "fee": .number(fee), "roy": .number(royalty), "supp": .number(Double(support)), "share": 0.45, "brand": 15, "mkt": 0.02,
                                          "units": .array([]), "app": .array([]), "w0": .number(Double(s.week))]))
        return .ok
    }

    // MARK: Applicants

    static func applicantsWeek(_ s: inout GameState, _ i: Int, data: GameData) {
        var f = s.companies[i].value("fr")
        guard f["on"].bool, f["units"].array.count + f["app"].array.count < 14 else { return }
        let hs = StaffPerks.hosted(s, "fr")   // prospects you hosted come twice as often, keener and with more money
        guard s.week % (hs > 0 ? 3 : 6) == 0, s.random.chance(0.55 + f["brand"].double / 200 + 0.2 * hs) else { return }
        let co = s.companies[i]
        guard let country = data.countries[co.countryCode] else { return }
        let city = s.random.pick(country.cities)
        let cur = Currency(country: country, rates: ExchangeRates(drift: s.exchangeRates.values))
        let cap = cur.scaledPrice(Double(s.random.int(120, 900)) * 1000 * (1 + 0.3 * hs))
        let skill = Double(s.random.int(30, 85))
        let exp = max(0, ((skill - 30) / 3.5 + s.random.range(-2, 3)).rounded())
        let name = s.random.pick(country.firstNames) + " " + s.random.pick(country.lastNames)
        let pers = hs > 0 && s.random.chance(0.5) ? "eager" : s.random.pick(["eager", "careful", "tough"])
        let age = s.random.int(26, 58)
        let id = s.makeID()
        var apps = f["app"].array
        apps.append(.object(["id": .number(Double(id)), "name": .string(name), "city": .string(city.id), "capital": .number(cap), "skill": .number(skill), "exp": .number(exp),
                             "pers": .string(pers), "age": .number(Double(age)), "w": .number(Double(s.week)), "pat": .number(patience[pers] ?? 3)]))
        f["app"] = .array(apps)
        s.companies[i].set("fr", f)
    }

    static let patience: [String: Double] = ["eager": 4, "careful": 3, "tough": 2]
    /// How many offers an applicant sits through, by character.
    public static func patienceDots(for personality: String) -> Int { Int(patience[personality] ?? 3) }

    public enum AcceptResult: Equatable, Sendable { case ok, gone, poor, cash }

    /// Sign an applicant: the unit opens. Without agreed terms the franchise's standard terms apply. Original: `frAcceptCore` + `frAccept.after`.
    public static func accept(_ s: inout GameState, companyID: Int, applicantID: Int, data: GameData) -> AcceptResult {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type] else { return .gone }
        var f = s.companies[i].value("fr")
        guard f["on"].bool, let k = f["app"].array.firstIndex(where: { $0["id"].int == applicantID }) else { return .gone }
        let a = f["app"].array[k]
        let co = s.companies[i]
        let setup = unitSetupCost(co, bd, data: data)
        let t = a["terms"]
        let supp = f["supp"].int
        let cover = t.isNull ? [0.0, 0.5, 1][min(2, supp)] : t["grant"].double
        let loan = t.isNull ? 0 : (setup * t["loan"].double).rounded()
        if t.isNull && a["capital"].double < setup * (1 - cover) * 0.5 && supp == 0 { return .poor }
        if co.cash < setup * cover + loan { return .cash }
        if cover > 0 { pay(&s, co.id, setup * cover, "oth", "Franchise support: \(a["name"].string)") }
        if loan > 0 {
            Ledger.moveRaw(&s, .company(co.id), -loan)
            s.companies[i].addTransaction(week: s.week, amount: -loan, label: "Loan to franchisee \(a["name"].string)")
        }
        let feeFactor = t.isNull ? 1 : t["feeF"].double
        receive(&s, co.id, f["fee"].double * feeFactor, "rev", "Franchise fee")
        let term = t.isNull ? (f["term"].isNull ? 10 : f["term"].double) : t["term"].double
        var u: [String: JSONValue] = ["id": a["id"], "name": a["name"], "city": a["city"], "w0": .number(Double(s.week)), "skill": a["skill"], "rev": 0, "prof": 0, "neg": 0,
                                      "setup": .number(setup), "end": .number(Double(s.week) + term * 52), "owed": 0, "late": 0, "term": .number(term)]
        u["q"] = .number(clamp(a["skill"].double + Double(s.random.int(-10, 10)), 20, 95))
        u["loc"] = .number(s.random.gauss() * 0.045)
        if !t.isNull {
            u["roy"] = t["roy"]; u["supp"] = .number(cover >= 1 ? 2 : cover > 0 ? 1 : 0); u["share"] = t["share"]; u["feeF"] = t["feeF"]
            if loan > 0 {
                let rate = t["rate"].double
                u["loan"] = .object(["bal": .number(loan), "rate": .number(rate), "pay": .number((Loans.annuity(principal: loan, yearlyRate: rate, months: 60) * 12 / 52).rounded())])
            }
        }
        var units = f["units"].array; units.append(.object(u)); f["units"] = .array(units)
        var apps = f["app"].array; apps.remove(at: k); f["app"] = .array(apps)
        f["brand"] = .number(min(100, f["brand"].double + 1))
        s.companies[i].set("fr", f)
        return .ok
    }

    // MARK: The talk with an applicant

    public struct TalkTerms: Equatable, Sendable {
        /// 1 full entry fee, 0.5 half, 0 waived
        public var feeFactor = 1.0
        public var royalty = 0.06
        /// "none", "l25" (lend a quarter of the set-up), "l50", "c50" (cover half for a share of the profit)
        public var help = "none"
        public var profitShare = 0.45
        public var years = 10
        public init() {}
        public init(standardFor f: JSONValue) {
            royalty = f["roy"].double
            help = ["none", "c50", "c50"][min(2, f["supp"].int)]
            profitShare = f["share"].isNull ? 0.45 : f["share"].double
            years = f["term"].isNull ? 10 : f["term"].int
        }
        public var grant: Double { help == "c50" ? 0.5 : 0 }
        public var loan: Double { help == "l25" ? 0.25 : help == "l50" ? 0.5 : 0 }
    }

    public struct TalkSums: Equatable, Sendable {
        public var setup = 0.0, revenue = 0.0, profit = 0.0, theirs = 0.0, own = 0.0, need = 0.0, youPutIn = 0.0, yours = 0.0, rate = 0.0
    }

    public struct Applicant: Equatable, Identifiable, Sendable {
        public var id: Int
        public var name: String
        public var cityID: String
        public var capital: Double
        public var skill: Double
        public var experience: Int
        public var personality: String
        public var age: Int
        public var patience: Int
        init(_ j: JSONValue) {
            id = j["id"].int; name = j["name"].string; cityID = j["city"].string; capital = j["capital"].double; skill = j["skill"].double
            experience = j["exp"].int; personality = j["pers"].isNull ? "careful" : j["pers"].string; age = j["age"].int
            patience = j["pat"].isNull ? Int(Franchising.patience[j["pers"].string] ?? 3) : j["pat"].int
        }
        public var personalityText: String { ["eager": "Keen to get going", "careful": "Careful with money", "tough": "A hard bargainer"][personality] ?? "" }
    }

    public static func applicants(_ co: Company) -> [Applicant] { co.value("fr")["app"].array.map { Applicant($0) } }

    /// The concept's own margin, kept within reason for the trade. Original: `conceptMargin`.
    static func conceptMargin(_ co: Company, _ bd: Trade) -> Double {
        let f = co.value("fr")
        var own = f["cmE"].isNull ? nil : f["cmE"].double
        if own == nil {
            let H = co.monthlyHistory.suffix(6)
            let rev = H.reduce(0.0) { $0 + $1.revenue }, pr = H.reduce(0.0) { $0 + $1.profit }
            own = rev > 0 ? pr / rev : bd.margin
        }
        return clamp(own ?? bd.margin, bd.margin - 0.04, bd.margin + 0.12)
    }

    /// Years a franchisee accepts to earn back what they put in. Original: `payback` (PB_FAM, PB_PERS).
    static func payback(_ bd: Trade, _ a: Applicant, setup: Double, scaledSix: Double) -> Double {
        let fam: [String: Double] = ["svc": 3, "retail": 4.5, "venue": 5, "prod": 6, "logi": 4.5, "project": 4]
        var base = fam[bd.family] ?? 4.5
        if bd.family == "venue" && setup > scaledSix { base = 7 }
        let pers: [String: Double] = ["eager": 1.35, "careful": 1.0, "tough": 0.85]
        return (base * (pers[a.personality] ?? 1) * 10).rounded() / 10
    }

    static func talkRate(_ s: GameState) -> Double { ((s.economy.policyRate + 0.03) * 1000).rounded() / 1000 }

    /// What the unit would earn in a normal year, and who gets what. Original: `sums` in franchise_talks.js.
    public static func talkSums(_ s: GameState, company co: Company, applicant a: Applicant, terms t: TalkTerms, data: GameData) -> TalkSums {
        guard let bd = data.catalog[co.type] else { return TalkSums() }
        let f = co.value("fr")
        let city = data.countries.city(a.cityID, preferring: co.countryCode)?.city
        let setup = unitSetupCost(co, bd, data: data)
        let brand = f["brand"].double
        let rev = bd.normalDemand * bd.ticket * (city?.demand ?? 1) * (0.35 + brand / 100 * 0.6) * (0.6 + a.skill / 160) * season(bd, week: s.week, data: data) * 0.85 * 52
        let m = conceptMargin(co, bd) + (brand / 100 - 0.35) * 0.06 + (a.skill - 55) * 0.0012 + (t.grant > 0 ? 0.01 : 0) - 0.01
        let prof = rev * (m - t.royalty - f["mkt"].double)
        let rate = talkRate(s)
        let loan = setup * t.loan
        let loanYear = loan > 0 ? Loans.annuity(principal: loan, yearlyRate: rate, months: 60) * 12 : 0
        let share = t.grant > 0 ? t.profitShare : 0
        let theirs = prof * (1 - share) - loanYear
        let own = setup * (1 - t.grant - t.loan) + f["fee"].double * t.feeFactor
        let yours = rev * t.royalty + prof * share + loanYear
        return TalkSums(setup: setup, revenue: rev, profit: prof, theirs: theirs, own: own, need: own + setup * 0.1, youPutIn: setup * (t.grant + t.loan), yours: yours, rate: rate)
    }

    public struct TalkAnswer: Equatable, Sendable {
        public var ok: Bool
        public var text: String
        /// A kind of help that would close the gap, if one would
        public var hint: String?
    }

    /// Their answer to an offer. Original: `answer` in franchise_talks.js.
    public static func talkAnswer(_ s: GameState, company co: Company, applicant a: Applicant, terms t: TalkTerms, data: GameData, context fc: FinanceContext) -> TalkAnswer {
        guard let bd = data.catalog[co.type] else { return TalkAnswer(ok: false, text: "", hint: nil) }
        let sm = talkSums(s, company: co, applicant: a, terms: t, data: data)
        let f = co.value("fr")
        let cur = fc.currency(co.countryCode, s)
        if a.capital < sm.need {
            let more = (sm.need - a.capital) / max(1, sm.setup) + t.loan + t.grant
            let hint = more <= 0.25 ? "l25" : more <= 0.5 ? "l50" : "none"
            let say = ["l25": "If you lent me a quarter of the setup, I could do it.", "l50": "If you lent me half of the setup, or covered half of it, I could do it.",
                       "none": "Even with help I do not have enough of my own to open a unit. Perhaps when I have saved more."][hint]!
            let tail = hint == "none" ? say : (t.help == hint ? "Could you waive the fee as well?" : say)
            return TalkAnswer(ok: false, text: "I have \(cur.short(a.capital)) of my own. On these terms I would need about \(cur.short(max(0, sm.need))), with something left for the first months. \(tail)",
                              hint: (t.help == hint || hint == "none") ? nil : hint)
        }
        if sm.theirs <= 0 { return TalkAnswer(ok: false, text: "I ran the numbers. With these costs I would lose money every year. The royalty and the share would have to come down.", hint: nil) }
        let years = sm.own / sm.theirs
        let lim = payback(bd, a, setup: sm.setup, scaledSix: cur.scaledPrice(6e6))
        if a.personality == "tough" && t.royalty > f["roy"].double && t.feeFactor > 0 {
            return TalkAnswer(ok: false, text: "A higher royalty than your other franchisees pay? Not with me. Standard terms, or less.", hint: nil)
        }
        if years > lim {
            let ask = t.royalty > 0.04 ? "a royalty one point lower" : t.feeFactor > 0 ? "half the entry fee" : "more help with the setup"
            return TalkAnswer(ok: false, text: "It would take me \(String(format: "%.1f", years)) years to earn back what I put in. I need it closer to \(lim). With \(ask) I am in.", hint: nil)
        }
        return TalkAnswer(ok: true, text: a.personality == "eager" ? "Yes! When can we start?" : a.personality == "careful" ? "That works for me. I would like it in writing, and then we can begin." : "Fine. That is a deal.", hint: nil)
    }

    public struct OfferResult: Equatable, Sendable {
        public var answer: TalkAnswer
        public var signed: Bool
        /// The applicant gave up
        public var walkedAway: Bool
        public var note: String?
    }

    /// The player sends an offer. If they say yes and the cash is there, the contract is signed. Otherwise patience goes down.
    /// Original: `ACT.frt56go`.
    public static func makeOffer(_ s: inout GameState, companyID: Int, applicantID: Int, terms t: TalkTerms, data: GameData, context fc: FinanceContext) -> OfferResult? {
        guard let i = s.companyIndex(companyID) else { return nil }
        let co = s.companies[i]
        guard let a = applicants(co).first(where: { $0.id == applicantID }) else { return nil }
        let ans = talkAnswer(s, company: co, applicant: a, terms: t, data: data, context: fc)
        if ans.ok {
            let sm = talkSums(s, company: co, applicant: a, terms: t, data: data)
            if co.cash < sm.youPutIn {
                return OfferResult(answer: ans, signed: false, walkedAway: false, note: "\(co.name) does not have the cash for its part (\(money(s, fc, co, sm.youPutIn))).")
            }
            var f = s.companies[i].value("fr")
            var apps = f["app"].array
            guard let k = apps.firstIndex(where: { $0["id"].int == applicantID }) else { return nil }
            apps[k]["terms"] = .object(["feeF": .number(t.feeFactor), "roy": .number(t.royalty), "grant": .number(t.grant), "loan": .number(t.loan),
                                        "share": .number(t.grant > 0 ? t.profitShare : 0), "term": .number(Double(t.years)), "rate": .number(sm.rate)])
            f["app"] = .array(apps)
            s.companies[i].set("fr", f)
            let r = accept(&s, companyID: companyID, applicantID: applicantID, data: data)
            if r == .ok { return OfferResult(answer: ans, signed: true, walkedAway: false, note: "Contract signed. \(a.name) opens a unit.") }
            var f2 = s.companies[i].value("fr")
            var apps2 = f2["app"].array
            if let k2 = apps2.firstIndex(where: { $0["id"].int == applicantID }) { apps2[k2]["terms"] = .null; f2["app"] = .array(apps2); s.companies[i].set("fr", f2) }
            return OfferResult(answer: ans, signed: false, walkedAway: false, note: r == .cash ? "Not enough cash in \(co.name)." : "It could not be signed.")
        }
        var f = s.companies[i].value("fr")
        var apps = f["app"].array
        guard let k = apps.firstIndex(where: { $0["id"].int == applicantID }) else { return nil }
        let left = (apps[k]["pat"].isNull ? Double(a.patience) : apps[k]["pat"].double) - 1
        apps[k]["pat"] = .number(left)
        var gone = false
        if left <= 0 { apps.remove(at: k); gone = true }
        f["app"] = .array(apps)
        s.companies[i].set("fr", f)
        return OfferResult(answer: ans, signed: false, walkedAway: gone, note: gone ? "\(a.name) has found another opportunity." : nil)
    }

    // MARK: Ending units

    /// Original: `endUnit`. how: "term" (you ended it), "left" (did not renew), "bust".
    static func endUnit(_ s: inout GameState, _ i: Int, _ f: inout JSONValue, unitID: Int, how: String, context fc: FinanceContext) {
        var units = f["units"].array
        guard let k = units.firstIndex(where: { $0["id"].int == unitID }) else { return }
        var u = units.remove(at: k)
        f["units"] = .array(units)
        let id = s.companies[i].id
        let co = s.companies[i]
        if u["loan"]["bal"].double > 0 {
            let b = u["loan"]["bal"].double.rounded()
            if how == "bust" {
                Payments.book(&s, companyID: id, category: "loss", amount: b)
                s.note("\(u["name"].string) went bankrupt owing \(money(s, fc, co, b)) on your loan. It is written off.", tone: "bad", companyID: id)
            } else { receive(&s, id, b, nil, "Franchise loan repaid: \(u["name"].string)") }
            u["loan"] = .null
        }
        let owed = u["owed"].double
        let q = u["q"].double
        if how == "term" {
            pay(&s, id, fc.currency(co.countryCode, s).scaledPrice(15000), "oth", "Franchise termination: lawyer")
            let rec = owed > 0 ? (owed * s.random.range(0.25, 0.55)).rounded() : 0
            if rec > 0 { receive(&s, id, rec, "rev", "Arrears recovered from \(u["name"].string)") }
            f["brand"] = .number(clamp(f["brand"].double + (q < 45 ? 0.5 : -1), 0, 100))
            s.note("Franchise contract with \(u["name"].string) terminated. \(owed > 0 ? "Recovered \(money(s, fc, s.companies[i], rec)) of \(money(s, fc, s.companies[i], owed)) owed." : "")", companyID: id)
        } else if how == "left" {
            f["brand"] = .number(max(0, f["brand"].double - 1))
            s.note("\(u["name"].string) did not renew and left the \(co.name) brand.", companyID: id)
        } else {
            f["brand"] = .number(max(0, f["brand"].double - 2))
            s.note("The franchise unit run by \(u["name"].string) in \(u["city"].string) went bankrupt. \(owed > 0 ? money(s, fc, s.companies[i], owed) + " in royalties is lost." : "")", tone: "bad", companyID: id)
        }
        f["ended"] = .number(f["ended"].double + 1)
        if owed > 0 { f["lostOwed"] = .number(f["lostOwed"].double + owed * (how == "term" ? 0.6 : 1)) }
    }

    /// Terminate one unit's contract. Original: `ACT.fr24term`.
    public static func terminate(_ s: inout GameState, companyID: Int, unitID: Int, context fc: FinanceContext) -> Bool {
        guard let i = s.companyIndex(companyID) else { return false }
        var f = s.companies[i].value("fr")
        guard f["units"].array.contains(where: { $0["id"].int == unitID }) else { return false }
        endUnit(&s, i, &f, unitID: unitID, how: "term", context: fc)
        s.companies[i].set("fr", f)
        return true
    }

    // MARK: Master franchise abroad

    public static func masterCap(_ c: Country) -> Double { clamp((c.populationMillions.squareRoot() * 2).rounded(), 4, 30) }

    public enum MasterResult: Equatable, Sendable { case ok, noFranchise, bad, already, banned(String), cash }

    /// Sell a whole country to a local partner for a big fee and half the royalties. Original: `frMaster`.
    public static func sellMaster(_ s: inout GameState, companyID: Int, country code: String, data: GameData) -> MasterResult {
        guard let i = s.companyIndex(companyID) else { return .bad }
        let co = s.companies[i]
        var f = co.value("fr")
        guard f["on"].bool else { return .noFranchise }
        guard let C = data.countries[code], code != co.countryCode else { return .bad }
        var masters = f["masters"].array
        if masters.contains(where: { $0["c"].string == code }) { return .already }
        if let why = CompanySetup.banReason(co.type, country: C) { return .banned(why) }
        let cur = Currency(country: C, rates: ExchangeRates(drift: s.exchangeRates.values))
        let franCost = Documents.definition("fran", country: C, tables: data.catalog.tables)?.cost ?? 25000
        let legal = cur.scaledPrice(franCost * C.bureaucracy)
        if co.cash < legal { return .cash }
        let fee = f["fee"].double * 3
        pay(&s, co.id, legal, "oth", "Master franchise legal work: \(C.name)")
        receive(&s, co.id, fee, "rev", "Master franchise fee: \(C.name)")
        masters.append(.object(["c": .string(code), "w0": .number(Double(s.week)), "ready": .number(Double(s.week) + (6 * C.bureaucracy * 1.3).rounded(.up)), "n": 0, "cap": .number(masterCap(C)), "rev": 0]))
        f["masters"] = .array(masters)
        s.companies[i].set("fr", f)
        return .ok
    }

    static func masterWeek(_ s: inout GameState, _ i: Int, _ f: inout JSONValue, _ bd: Trade, data: GameData) -> Double {
        var masters = f["masters"].array
        if masters.isEmpty { return 0 }
        var tot = 0.0
        for k in masters.indices {
            var m = masters[k]
            if Double(s.week) < m["ready"].double { continue }
            guard let c = data.countries[m["c"].string] else { continue }
            if s.week % 8 == 0 && m["n"].double < m["cap"].double && s.random.chance(0.35 + f["brand"].double / 200) { m["n"] = .number(m["n"].double + 1) }
            if m["n"].double > 0 && s.random.chance(0.0015 * m["n"].double) { m["n"] = .number(m["n"].double - 1) }
            let rev = m["n"].double * bd.normalDemand * bd.ticket * c.marketStrength * c.priceLevel * (0.35 + f["brand"].double / 100 * 0.6) * (1 + (s.economy.demand - 1) * 0.8) * 0.7
            m["rev"] = .number(rev)
            tot += rev * f["roy"].double * 0.5
            masters[k] = m
        }
        f["masters"] = .array(masters)
        if tot > 0 { receive(&s, s.companies[i].id, tot, "rev", "Master franchise royalties") }
        return tot
    }

    // MARK: The franchisor's week

    static func askAboutUnit(_ s: inout GameState, _ i: Int, unit u: JSONValue, kind: String, context fc: FinanceContext, data: GameData) {
        let co = s.companies[i]
        let f = co.value("fr")
        let due = u["rev"].double * (u["roy"].isNull ? f["roy"].double : u["roy"].double)
        _ = due
        let city = data.countries.city(u["city"].string, preferring: co.countryCode)?.city.name ?? ""
        let body = kind == "owed"
            ? "\(u["name"].string) (\(city)) is \(Int(u["late"].double)) weeks behind and owes \(money(s, fc, co, u["owed"].double)) in royalties. The unit is losing money."
            : "\(u["name"].string) (\(city)) failed a brand inspection. Poor units drag down the whole brand."
        s.addMessage(kind: "ask", from: "\(co.name) franchise", title: kind == "owed" ? "Franchisee behind on royalties" : "Franchisee below standard", body: body, companyID: co.id, tone: "bad", status: "open",
                     options: [.option(kind == "owed" ? "Give them time" : "Warn them", kind == "owed" ? "Arrears stay on the books; they repay when they can." : "They get three months to fix it."),
                               .option("Terminate the contract", "The unit loses your brand. You chase " + (kind == "owed" ? "the arrears through a lawyer." : "nothing, but the brand is protected."))],
                     action: "fr24", data: .object(["u": u["id"], "kind": .string(kind)]), expiresWeek: s.week + 3)
    }

    static func franchisorWeek(_ s: inout GameState, _ i: Int, data: GameData, context fc: FinanceContext) {
        guard let bd = data.catalog[s.companies[i].type] else { return }
        applicantsWeek(&s, i, data: data)
        var f = s.companies[i].value("fr")
        let co = s.companies[i]
        let cm = conceptMargin(co, bd)
        var roy = 0.0, sup = 0.0, renew = 0.0, back = 0.0, intr = 0.0
        let termYears = f["term"].isNull ? 10.0 : f["term"].double
        let infl = 1 + (s.economy.demand - 1) * 0.8
        for u0 in f["units"].array {
            var u = u0
            let uid = u["id"].int
            let city = data.countries.city(u["city"].string, preferring: co.countryCode)?.city
            let age = Double(s.week) - u["w0"].double
            let ramp = min(1, 0.35 + age / 40)
            let brand = f["brand"].double
            let rev = bd.normalDemand * bd.ticket * (city?.demand ?? 1) * (0.35 + brand / 100 * 0.6) * (0.6 + u["skill"].double / 160) * season(bd, week: s.week, data: data) * ramp * infl * (0.9 + 0.2 * s.random.next()) * 0.85
            let uRoy = u["roy"].isNull ? f["roy"].double : u["roy"].double
            let uSupp = u["supp"].isNull ? f["supp"].int : u["supp"].int
            let uShare = u["share"].isNull ? f["share"].double : u["share"].double
            let m0 = cm + (brand / 100 - 0.35) * 0.06 + (u["skill"].double - 55) * 0.0012 + (uSupp > 0 ? 0.01 : 0) - 0.01 - (1 - ramp) * 0.06 + u["loc"].double + s.random.gauss() * 0.01
            let due = rev * uRoy, fund = rev * f["mkt"].double
            let prof = rev * m0 - due - fund
            u["rev"] = .number(rev); u["prof"] = .number(prof)
            f["fund"] = .number(f["fund"].double + fund)
            var paid = due
            var late = u["late"].double, owed = u["owed"].double
            if prof < 0 {
                late += 1
                if late > 3 { paid = due * clamp(0.95 - late * 0.05, 0.15, 0.9) }
            } else {
                late = max(0, late - 1)
                if owed > 0 { let x = min(owed, prof * 0.5); paid += x; owed -= x }
            }
            owed += max(0, due - min(paid, due))
            roy += paid
            if uSupp == 2 || (u["share"].double > 0 && uSupp > 0) { if prof > 0 { roy += prof * uShare } else { sup += -prof * uShare } }
            if u["loan"]["bal"].double > 0 {
                var L = u["loan"]
                let interest = L["bal"].double * L["rate"].double / 52
                L["bal"] = .number(L["bal"].double + interest)
                let p = (prof > 0 || late <= 3) ? min(L["bal"].double, L["pay"].double) : 0
                L["bal"] = .number(L["bal"].double - p)
                back += p; intr += min(p, interest)
                u["loan"] = L["bal"].double < 1 ? .null : L
            }
            u["late"] = .number(late); u["owed"] = .number(owed)
            u["neg"] = .number(prof < 0 ? u["neg"].double + 1 : max(0, u["neg"].double - 1))
            u["q"] = .number(clamp(u["q"].double + (u["skill"].double - u["q"].double) * 0.02 + (prof < 0 ? -0.15 : 0.05), 10, 98))
            var asked = u["asked"].double, qasked = u["qasked"].double
            if owed > due * 8 && late >= 8 && !(u["grace"].double > Double(s.week)) && asked == 0 {
                asked = Double(s.week); u["asked"] = .number(asked); askAboutUnit(&s, i, unit: u, kind: "owed", context: fc, data: data)
            }
            if u["q"].double < 40 && !(u["qwarn"].double > Double(s.week) - 13) && qasked == 0 {
                qasked = Double(s.week); u["qasked"] = .number(qasked); askAboutUnit(&s, i, unit: u, kind: "qual", context: fc, data: data)
            }
            if asked != 0 && Double(s.week) - asked > 13 { u["asked"] = 0 }
            if qasked != 0 && Double(s.week) - qasked > 13 { u["qasked"] = 0 }
            // store the unit back before it may be removed
            if let k = f["units"].array.firstIndex(where: { $0["id"].int == uid }) { var arr = f["units"].array; arr[k] = u; f["units"] = .array(arr) }
            if (u["neg"].double > 30 && uSupp < 2) || u["neg"].double > 52 { endUnit(&s, i, &f, unitID: uid, how: "bust", context: fc); continue }
            if Double(s.week) >= u["end"].double {
                if prof > 0 && u["q"].double >= 45 && s.random.chance(0.85) {
                    var arr = f["units"].array
                    if let k = arr.firstIndex(where: { $0["id"].int == uid }) { arr[k]["end"] = .number(Double(s.week) + termYears * 52); f["units"] = .array(arr) }
                    renew += (f["fee"].double * 0.3).rounded()
                    s.note("\(u["name"].string) renewed the \(co.name) franchise for another \(Int(termYears)) years.", tone: "good", companyID: co.id)
                } else { endUnit(&s, i, &f, unitID: uid, how: "left", context: fc) }
            }
        }
        let id = co.id
        if roy > 0 { receive(&s, id, roy, "rev") }
        if back > 0 { receive(&s, id, back - intr, nil, "Franchise loans repaid"); receive(&s, id, intr, "rev", "Interest on franchise loans") }
        if renew > 0 { receive(&s, id, renew, "rev", "Franchise renewal fees") }
        if sup > 0 { pay(&s, id, sup, "oth", "Covering franchise-unit losses") }
        let used = f["fund"].double * 0.9
        if used > 0 {
            s.companies[i].awareness = min(100, s.companies[i].awareness + used.squareRoot() * 0.002)
            f["fund"] = 0
        }
        let units = f["units"].array
        let qAvg = units.isEmpty ? 60 : units.reduce(0.0) { $0 + $1["q"].double } / Double(units.count)
        f["brand"] = .number(clamp(f["brand"].double + Double(units.count) * 0.05 + (s.companies[i].quality - 60) * 0.0015 + (qAvg - 55) * 0.002 * min(1, Double(units.count) / 3) - f["brand"].double * 0.003, 0, 100))
        let mw = masterWeek(&s, i, &f, bd, data: data)
        f["income"] = .number(roy + renew + mw)
        // the store's own trading margin, without franchise money (so paying for set-ups does not make the concept look worse)
        let lw = s.companies[i].value("lastW")
        let r = lw["rev"].double
        if r > 0 && s.companies[i].status == .open {
            let e = lw["cogs"].double + fc.weeklyCost(s.companies[i], s) - lw["cogs"].double * 0.5
            let m = clamp((r - e) / r, -1, 1)
            f["cmE"] = .number(f["cmE"].isNull ? m : f["cmE"].double + (m - f["cmE"].double) * 0.06)
        }
        s.companies[i].set("fr", f)
    }

    // MARK: The franchisee's week

    public static func brandMinimumQuality(_ f: JSONValue) -> Double { (min(f["std"].isNull ? 60 : f["std"].double, 72) - 27).rounded() }

    static func franchiseeWeek(_ s: inout GameState, _ i: Int, rev: Double, context fc: FinanceContext) {
        var f = s.companies[i].value("franchise")
        guard f["fran"].bool else { return }
        let co = s.companies[i]
        if f["term"].double > 0 && !f["w0"].isNull && f["end"].isNull { f["end"] = .number(f["w0"].double + f["term"].double * 52) }
        let due = rev * (f["roy"].double + f["mkt"].double)
        let can = max(0, min(due + f["owed"].double, co.cash))
        if can > 0 { pay(&s, co.id, can, "oth") }
        f["owed"] = .number(max(0, f["owed"].double + due - can))
        f["lateW"] = .number(f["owed"].double > 0.5 ? f["lateW"].double + 1 : 0)
        f["brand"] = .number(clamp(f["brand"].double + (co.quality - 55) * 0.004, 10, 90))
        if !f["brandId"].isNull { s.companies[i].awareness = max(s.companies[i].awareness, 15 + f["brand"].double * 0.45) }
        let minQ = brandMinimumQuality(f)
        let lw = s.companies[i].value("lastW")
        if co.status == .open && lw["units"].double > 0 && Double(s.week) - f["w0"].double >= 26 {
            f["lowQ"] = .number(co.quality < minQ ? f["lowQ"].double + 1 : max(0, f["lowQ"].double - 1))
        }
        if f["lowQ"].double == 8 {
            s.note("The franchisor warns \(co.name): quality is well below the brand standard. Fix it within two months or the contract can be terminated.", tone: "bad", companyID: co.id)
            s.companies[i].reputation -= 2
        }
        s.companies[i].set("franchise", f)
        if f["lowQ"].double >= 17 && f["asked"].double == 0 { askAsFranchisee(&s, i, kind: "qual", context: fc) }
        else if f["lateW"].double >= 8 && f["owed"].double > due * 6 && f["asked"].double == 0 { askAsFranchisee(&s, i, kind: "owed", context: fc) }
        else if !f["end"].isNull && Double(s.week) >= f["end"].double && f["asked"].double == 0 { askAsFranchisee(&s, i, kind: "end", context: fc) }
    }

    static func askAsFranchisee(_ s: inout GameState, _ i: Int, kind: String, context fc: FinanceContext) {
        var f = s.companies[i].value("franchise")
        let co = s.companies[i]
        let bn = f["brandName"].isNull ? "The franchisor" : f["brandName"].string
        f["asked"] = .number(Double(s.week))
        s.companies[i].set("franchise", f)
        let renewFee = (f["fee"].double * 0.3).rounded()
        let years = f["term"].isNull ? 10 : f["term"].int
        var title = "", body = ""
        var opts: [JSONValue] = []
        switch kind {
        case "owed":
            title = "\(bn) demands unpaid royalties"
            body = "\(co.name) owes \(money(s, fc, co, f["owed"].double)) in royalties and marketing fees. Pay now or the franchise contract ends."
            opts = [.option("Pay \(money(s, fc, co, f["owed"].double))", "From company cash."), .option("Let the contract end", "You lose the brand. The debt stays as a bill to pay.")]
        case "qual":
            title = "\(bn) terminates for poor quality"
            body = "Quality at \(co.name) has been far below the brand standard for months. Invest in a refit and training, or the contract ends."
            opts = [.option("Refit and retrain · \(money(s, fc, co, refitCost(s, co, fc)))", "Quality improves; the warning is withdrawn."), .option("Let the contract end", "You run on as an independent.")]
        default:
            title = "Your \(bn) contract has ended"
            body = "The \(years)-year franchise agreement for \(co.name) is up. Renew on the same terms, or go independent (new signs, fewer people know the name)."
            opts = [.option("Renew · \(money(s, fc, co, renewFee))", "Another \(years) years on the same royalty."), .option("Go independent", "No more royalties. Awareness drops.")]
        }
        s.addMessage(kind: "ask", from: bn, title: title, body: body, companyID: co.id, tone: kind == "end" ? "n" : "bad", status: "open", options: opts,
                     action: "fb24", data: .object(["kind": .string(kind)]), expiresWeek: s.week + 3)
    }

    static func refitCost(_ s: GameState, _ co: Company, _ fc: FinanceContext) -> Double { fc.currency(co.countryCode, s).scaledPrice(30000) * max(1, co.size) }

    /// Leave the brand: by choice, at contract end, or terminated by the franchisor. Original: `leaveBrand`.
    static func leaveBrand(_ s: inout GameState, _ i: Int, why: String, context fc: FinanceContext) {
        let f = s.companies[i].value("franchise")
        guard !f.isNull else { return }
        let co = s.companies[i]
        if f["owed"].double > 0.5 { s.companies[i].addPayable("other", f["owed"].double) }
        pay(&s, co.id, fc.currency(co.countryCode, s).scaledPrice(8000) * max(1, co.size), "oth", "New signs and rebranding")
        s.companies[i].awareness = max(5, s.companies[i].awareness * 0.55)
        s.companies[i].set("franchise", .null)
        var docs = s.companies[i].value("docs"); docs["fran_op"] = .null
        s.companies[i].set("docs", .object(docs.object.filter { !$0.value.isNull }))
        s.note("\(co.name)\(why == "term" ? " lost its franchise contract." : " is now independent.")\(f["owed"].double > 0.5 ? " \(money(s, fc, s.companies[i], f["owed"].double)) in unpaid royalties is still owed." : "")",
               tone: why == "term" ? "bad" : "n", companyID: co.id)
    }

    /// What it costs to leave early. Original: `R24.buyout`.
    public static func buyout(_ co: Company, week: Int) -> Double {
        let f = co.value("franchise")
        guard !f.isNull, !f["end"].isNull else { return 0 }
        let yrs = max(0, (f["end"].double - Double(week)) / 52)
        let weeks = Double(max(1, week % 52 == 0 ? 52 : week % 52))
        let yRoy = ((co.books.year["rev"] ?? 0) / weeks * 52) * (f["roy"].double + f["mkt"].double)
        let base = max(f["fee"].double * 0.25 * min(1, yrs / 3), min(f["fee"].double * 1.5, yRoy * yrs * 0.5))
        return (base / 1000).rounded() * 1000 + f["owed"].double.rounded()
    }

    /// Buy out the rest of the contract and go independent. Original: `ACT.fb24leave`.
    public static func leaveFranchise(_ s: inout GameState, companyID: Int, context fc: FinanceContext) -> Bool {
        guard let i = s.companyIndex(companyID), !s.companies[i].value("franchise").isNull else { return false }
        let fee = buyout(s.companies[i], week: s.week)
        if fee > 0 { pay(&s, companyID, fee, "oth", "Franchise contract buyout") }
        var f = s.companies[i].value("franchise"); f["owed"] = 0; s.companies[i].set("franchise", f)
        leaveBrand(&s, i, why: "exit", context: fc)
        return true
    }

    // MARK: Answers to the messages

    public static func handlesAnswer(_ action: String) -> Bool { action == "fr24" || action == "fb24" }

    /// The player's answer to a franchisee/franchisor question. Original: `ACTS.fr24`, `ACTS.fb24`.
    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, context fc: FinanceContext) {
        guard let i = s.companyIndex(m.companyID) else { return }
        let d = m.value("data")
        if m.actionID == "fr24" {
            var f = s.companies[i].value("fr")
            guard let k = f["units"].array.firstIndex(where: { $0["id"].int == d["u"].int }) else { return }
            if idx == 1 { endUnit(&s, i, &f, unitID: d["u"].int, how: "term", context: fc) }
            else {
                var arr = f["units"].array
                if d["kind"].string == "qual" { arr[k]["qwarn"] = .number(Double(s.week)) } else { arr[k]["grace"] = .number(Double(s.week + 12)) }
                f["units"] = .array(arr)
            }
            s.companies[i].set("fr", f)
            return
        }
        var f = s.companies[i].value("franchise")
        guard !f.isNull else { return }
        f["asked"] = 0
        s.companies[i].set("franchise", f)
        switch d["kind"].string {
        case "owed":
            if idx == 0 {
                let x = min(f["owed"].double, max(0, s.companies[i].cash))
                pay(&s, m.companyID, x, "oth", "Royalty arrears")
                f["owed"] = .number(f["owed"].double - x); f["lateW"] = 0
                s.companies[i].set("franchise", f)
                if f["owed"].double > 0.5 { leaveBrand(&s, i, why: "term", context: fc) }
            } else { leaveBrand(&s, i, why: "term", context: fc) }
        case "qual":
            if idx == 0 {
                pay(&s, m.companyID, refitCost(s, s.companies[i], fc), "oth", "Refit and training (franchise standard)")
                s.companies[i].quality = min(100, s.companies[i].quality + 15)
                f["lowQ"] = 0
                s.companies[i].set("franchise", f)
            } else { leaveBrand(&s, i, why: "term", context: fc) }
        default:
            if idx == 0 {
                pay(&s, m.companyID, (f["fee"].double * 0.3).rounded(), "oth", "Franchise renewal fee")
                f["end"] = .number(Double(s.week) + (f["term"].isNull ? 10 : f["term"].double) * 52)
                s.companies[i].set("franchise", f)
            } else { leaveBrand(&s, i, why: "end", context: fc) }
        }
    }

    // MARK: The week

    /// Everything franchising does once a week. Original: `fbWeek`, `frWeek`, `franchiseeWeek` and the answers to unanswered questions.
    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        FranchiseBrands.weekly(&s, data: data)
        for i in s.companies.indices {
            let co = s.companies[i]
            if co.status == .bust && co.value("fr")["on"].bool {
                let n = co.value("fr")["units"].array.count
                var f = co.value("fr"); f["units"] = .array([]); f["on"] = 0; f["masters"] = .array([]); f["app"] = .array([])
                s.companies[i].set("fr", f)
                if n > 0 { s.note("\(n) franchise units of \(co.name) rebrand and go their own way.") }
                continue
            }
            guard co.status == .open || co.status == .closed else { continue }
            if co.value("fr")["on"].bool { franchisorWeek(&s, i, data: data, context: fc) }
            if co.value("franchise")["fran"].bool, !s.companies[i].value("lastW").isNull { franchiseeWeek(&s, i, rev: s.companies[i].lastWeekRevenue, context: fc) }
        }
        // Questions nobody answered: royalty and quality questions give time / a warning; the franchisor ends the contract, an expired one is not renewed.
        for k in s.inbox.indices {
            let m = s.inbox[k]
            guard handlesAnswer(m.actionID), m.status == "done", m.flag("auto"), !m.flag("done24") else { continue }
            s.inbox[k].set("done24", 1)
            answer(&s, message: m, option: m.actionID == "fr24" ? 0 : 1, context: fc)
        }
    }
}
