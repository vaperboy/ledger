import Foundation
import GameCore
import Countries
import Finance

public enum PremisesProposals {
    public static let kind = "prem"
    public static let streakWeeks = 6
    public static let askCooldownWeeks = 13, declineCooldownWeeks = 52
    public static let minUnmetShare = 0.10
    public static let maxPaybackWeeks = 104.0
    public static let marginKept = 0.70
    public static let maxUpliftShare = 0.60

    public struct Plan: Equatable, Sendable {
        public var companyID: Int
        public var listingIndex: Int
        public var placeName: String
        public var landlord: String
        public var fromSquareMetres: Double
        public var toSquareMetres: Double
        public var fromPlaces: Int?
        public var toPlaces: Int?
        public var unmetUnitsPerWeek: Double
        public var extraUnitsPerWeek: Double
        public var extraCapacityPercent: Double
        public var monthlyRentBefore: Double
        public var monthlyRentAfter: Double
        public var rentChangeMonthly: Double
        public var oneOffCost: Double
        public var movingCost: Double
        public var projectedWeeklyProfitUplift: Double
        public var projectedYearlyProfitUplift: Double
        public var paybackWeeks: Double?
        var listing: CompanySetup.Listing
    }

    public static func unmetDemand(_ s: GameState, companyID: Int, data: GameData) -> Double? {
        guard let co = s.company(companyID), co.status == .open, let bd = data.catalog[co.type] else { return nil }
        let lw = co.value("lastW")
        guard !lw.isNull, lw["cap"].double > 0, lw["D"].double > lw["cap"].double * (1 + minUnmetShare) else { return nil }
        let w = World(state: s, data: data)
        let spaceLimits = CapacityModel.compute(co, bd, w).bottleneck?.kind == .space
        let info = Workplaces.info(co, data: data)
        let placesFull = info.capacity != nil && (info.free ?? 1) <= 0
        guard spaceLimits || placesFull else { return nil }
        return lw["D"].double - lw["cap"].double
    }

    static func monthlyRent(_ co: Company) -> Double {
        let p = co.value("prem")
        return p["owned"].bool ? 0 : p["rent"].double * p["m2"].double / 12
    }

    public static func plan(_ s: GameState, companyID: Int, data: GameData) -> Plan? {
        guard let unmet = unmetDemand(s, companyID: companyID, data: data), let co = s.company(companyID), let bd = data.catalog[co.type], !co.value("prem")["owned"].bool else { return nil }
        let w = World(state: s, data: data)
        let cur = w.currency(co)
        let lw = co.value("lastW")
        let units = lw["units"].double, cap = lw["cap"].double
        guard units > 0 else { return nil }
        let margin = max(0, (lw["rev"].double - lw["cogs"].double) / units) * marginKept
        let fromM2 = co.value("prem")["m2"].double
        let info = Workplaces.info(co, data: data)
        let kind = PremisesExtras.isHomeTrade(bd) ? PremisesExtras.placeKind(bd) : (co.value("prem")["kind"].isNull ? (bd.premisesKind ?? "none") : co.value("prem")["kind"].string)
        let base = CapacityModel.compute(co, bd, w).capacity
        let rentBefore = monthlyRent(co)
        let refund = co.value("prem")["dep"].double > 0 ? co.value("prem")["dep"].double : 0
        var best: Plan?
        for l in CompanySetup.listings(for: co, bd, w) where l.squareMetres > fromM2 * 1.15 {
            guard let t = CompanySetup.premisesTerms(co, l, data: data, world: w) else { continue }
            var c2 = co
            var prem = c2.value("prem"); prem["m2"] = .number(l.squareMetres); c2.set("prem", prem)
            let spaceGain = fromM2 > 0 ? max(0, CapacityModel.compute(c2, bd, w).capacity - base) : 0
            let toPlaces = Workplaces.places(kind: kind, squareMetres: l.squareMetres)
            var placeGain = 0.0
            if let from = info.capacity, let to = toPlaces, to > from, (info.free ?? 1) <= 0 { placeGain = cap * Double(to - from) / Double(max(1, info.used)) }
            if max(spaceGain, placeGain) > cap * maxUpliftShare { continue }
            let gain = min(unmet, max(spaceGain, placeGain))
            guard gain > 0 else { continue }
            let moving = cur.scaledPrice(1500) + cur.scaledPrice(12) * fromM2
            let oneOff = t.deposit - refund + t.fitOut + moving
            let weekly = gain * margin - (t.monthlyRent - rentBefore) * 12 / 52
            guard weekly > 0 else { continue }
            let plan = Plan(companyID: companyID, listingIndex: l.index, placeName: l.name, landlord: l.landlord, fromSquareMetres: fromM2, toSquareMetres: l.squareMetres,
                            fromPlaces: info.capacity, toPlaces: toPlaces, unmetUnitsPerWeek: unmet, extraUnitsPerWeek: gain, extraCapacityPercent: cap > 0 ? gain / cap * 100 : 0,
                            monthlyRentBefore: rentBefore, monthlyRentAfter: t.monthlyRent, rentChangeMonthly: t.monthlyRent - rentBefore, oneOffCost: oneOff, movingCost: moving,
                            projectedWeeklyProfitUplift: weekly, projectedYearlyProfitUplift: weekly * 52, paybackWeeks: oneOff > 0 ? oneOff / weekly : 0, listing: l)
            if (plan.paybackWeeks ?? 0) > maxPaybackWeeks { continue }
            func value(_ p: Plan) -> Double { p.projectedWeeklyProfitUplift * 104 - p.oneOffCost }
            if best == nil || value(plan) > value(best!) { best = plan }
        }
        return best
    }

    static func managerWeek(_ s: inout GameState, _ ci: Int, _ n: Person, data: GameData) {
        let co = s.companies[ci]
        var fl = co.value("flags")
        let limited = unmetDemand(s, companyID: co.id, data: data) != nil
        fl["premStreak"] = .number(limited ? fl["premStreak"].double + 1 : 0)
        s.companies[ci].set("flags", fl)
        guard limited, fl["premStreak"].double >= Double(streakWeeks), ManagerModel.dutyKept(co, "prem"), ManagerModel.dutyAllows(n, "space") else { return }
        if s.inbox.contains(where: { $0.companyID == co.id && $0.status == "open" && $0.actionID == "prop" && $0.value("data")["t"].string == kind }) { return }
        if !fl["premAsk"].isNull, Double(s.week) - fl["premAsk"].double < Double(askCooldownWeeks) { return }
        if !fl["premNo"].isNull, Double(s.week) - fl["premNo"].double < Double(declineCooldownWeeks) { return }
        guard let p = plan(s, companyID: co.id, data: data) else { return }
        fl["premAsk"] = .number(Double(s.week))
        s.companies[ci].set("flags", fl)
        let cur = World(state: s, data: data).currency(co)
        let places = (p.fromPlaces != nil && p.toPlaces != nil) ? " It seats \(p.toPlaces!) people instead of \(p.fromPlaces!)." : ""
        let rent = p.rentChangeMonthly >= 0 ? "rent up \(cur.display(p.rentChangeMonthly)) a month" : "rent down \(cur.display(-p.rentChangeMonthly)) a month"
        let body = "We are turning away about \(Int(saturating: p.unmetUnitsPerWeek.rounded())) sales a week because the place is full. \(p.placeName) (\(p.landlord)) is \(Int(p.toSquareMetres)) m2 instead of \(Int(p.fromSquareMetres)) m2:" +
            " about \(Int(saturating: p.extraCapacityPercent.rounded()))% more capacity,\(places) \(rent). It should add about \(cur.display(p.projectedWeeklyProfitUplift * 52 / 12)) profit a month once we are in, and the move costs about \(cur.display(p.oneOffCost)) (deposit, fit-out and moving)."
        let l = p.listing
        s.addMessage(kind: "ask", from: n.name, title: "Move \(co.name) to bigger premises?", body: body, companyID: co.id, tone: "n", status: "open",
                     options: [.option("Approve the move", "About \(cur.display(p.oneOffCost)) once; \(rent)."), .option("Not now", "I will not ask again for a year.")],
                     action: "prop",
                     data: .object(["t": .string(kind), "kind": .string(kind), "co": .number(Double(co.id)), "amt": .number(p.oneOffCost), "li": .number(Double(l.index)), "ln": .string(l.name),
                                    "lm": .number(l.squareMetres), "lr": .number(l.rentFactor), "ll": .number(l.location), "ld": .string(l.landlord),
                                    "unmet": .number(p.unmetUnitsPerWeek), "extra": .number(p.extraUnitsPerWeek), "up": .number(p.projectedWeeklyProfitUplift)]),
                     expiresWeek: s.week + 4)
    }

    static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData) {
        guard s.companyIndex(m.companyID) != nil else { return }
        if idx == 0 { _ = accept(&s, message: m, data: data) } else { decline(&s, companyID: m.companyID) }
    }

    public static func decline(_ s: inout GameState, companyID: Int) {
        guard let ci = s.companyIndex(companyID) else { return }
        var fl = s.companies[ci].value("flags"); fl["premNo"] = .number(Double(s.week)); s.companies[ci].set("flags", fl)
    }

    public static func cooldownWeeks(_ s: GameState, companyID: Int) -> Int {
        guard let co = s.company(companyID) else { return 0 }
        let fl = co.value("flags")
        let a = fl["premAsk"].isNull ? 0 : max(0, askCooldownWeeks - (s.week - fl["premAsk"].int))
        let d = fl["premNo"].isNull ? 0 : max(0, declineCooldownWeeks - (s.week - fl["premNo"].int))
        return max(a, d)
    }

    @discardableResult
    static func accept(_ s: inout GameState, message m: Message, data: GameData) -> Bool {
        let d = m.value("data")
        let l = CompanySetup.Listing(index: d["li"].int, name: d["ln"].string, squareMetres: d["lm"].double, rentFactor: d["lr"].double, location: d["ll"].double, landlord: d["ld"].string)
        return move(&s, companyID: m.companyID, listing: l, data: data)
    }

    @discardableResult
    public static func accept(_ s: inout GameState, companyID: Int, data: GameData) -> Bool {
        guard let p = plan(s, companyID: companyID, data: data) else { return false }
        return move(&s, companyID: companyID, listing: p.listing, data: data)
    }

    static func move(_ s: inout GameState, companyID: Int, listing l: CompanySetup.Listing, data: GameData) -> Bool {
        guard let ci = s.companyIndex(companyID) else { return false }
        let w = World(state: s, data: data)
        let co = s.companies[ci]
        guard let t = CompanySetup.premisesTerms(co, l, data: data, world: w) else { return false }
        let cur = w.currency(co)
        let moving = cur.scaledPrice(1500) + cur.scaledPrice(12) * co.value("prem")["m2"].double
        let refund = co.value("prem")["dep"].double > 0 && !co.value("prem")["owned"].bool ? co.value("prem")["dep"].double : 0
        let need = max(0, t.deposit + t.fitOut + moving - refund)
        if Payments.liquid(s) < need {
            s.note("\(co.name) could not move: \(cur.display(need)) is needed and you do not have it.", tone: "bad", companyID: companyID)
            return false
        }
        let fromM2 = co.value("prem")["m2"].double
        guard CompanySetup.setPremises(&s, companyID: companyID, listing: l, data: data) == .ok else { return false }
        Payments.companyPays(&s, companyID: companyID, amount: moving, category: "oth", label: "Moving to \(l.name)")
        guard let k = s.companyIndex(companyID) else { return false }
        var fl = s.companies[k].value("flags")
        fl["premStreak"] = 0
        fl["premMove"] = .object(["w": .number(Double(s.week)), "from": .number(fromM2), "to": .number(l.squareMetres), "unmet": .number(co.value("lastW")["D"].double - co.value("lastW")["cap"].double)])
        s.companies[k].set("flags", fl)
        s.note("\(co.name) moved to \(l.name) (\(Int(l.squareMetres)) m2, \(l.landlord)); the lease starts now.", tone: "good", companyID: companyID)
        return true
    }
}
