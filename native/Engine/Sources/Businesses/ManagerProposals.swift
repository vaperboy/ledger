import Foundation
import GameCore
import Countries
import Employees
import Finance

/// What a manager brings you: proposals to buy equipment, vehicles and premises, the proposals of a meeting, the profit bonus, the duties
/// of a promoted manager, an assistant's monthly suggestion and basic insurance, and the rule that a manager never runs a team from home.
/// Originals: engine/management/managers.js (`decideProposal`, `execProposal`), features/people/manager_search_and_meetings.js (`mprops`, `mtgo2`,
/// `ACTS.mprop`), engine/core/week.js (the profit bonus), features/people/worker_roles_and_promotions.js (the duties step),
/// features/people/owner_hours_clients_assistants.js (`asstWeek`), features/people/managers_who_manage.js (section 7), features/people/manager_duties.js.
extension ManagerModel {
    // MARK: Buying what is the bottleneck

    /// What the manager would buy for the part that limits capacity. Original: the `over` branch of `decideProposal`.
    static func bottleneckProposal(_ s: GameState, _ co: Company, _ bd: Trade, data: GameData) -> Proposal? {
        let w = World(state: s, data: data)
        guard let bot = CapacityModel.compute(co, bd, w).bottleneck else { return nil }
        let key = bot.key.split(separator: ":").last.map(String.init) ?? ""
        switch bot.kind {
        case .staff:
            guard data.catalog.tables.roles[key] != nil else { return nil }
            return Proposal(kind: "hire", role: key, cost: marketWage(s, co, role: key, data: data) * 12)
        case .equip:
            guard let e = bd.equipment.first(where: { $0.id == key }) else { return nil }
            if let vm = e.vehicleModels?.first, let v = data.catalog.tables.vehicles[vm] { return Proposal(kind: "veh", cost: EquipmentMarket.vehiclePrice(v, factor: 1, w) * 0.5, id: key) }
            return Proposal(kind: "eq", cost: EquipmentMarket.price(e, company: co, w), id: key)
        case .space:
            guard dutyKept(co, "prem"), let kind = co.value("prem")["kind"].isNull ? nil : co.value("prem")["kind"].string, let P = data.catalog.tables.premises[kind], let city = w.city(co) else { return nil }
            return Proposal(kind: "space", cost: P.rentPerM2Year * city.rent * co.value("prem")["m2"].double * 0.25 / 12 * w.inflationIndex)
        case .gate: return nil
        }
    }

    /// A duty the manager looks after unless you keep it (`duty56[k] = 0`): `sec` IT security, `ins` insurance, `prem` asking to expand the premises.
    public static func dutyKept(_ co: Company, _ k: String) -> Bool { co.value("duty56")[k].isNull || co.value("duty56")[k].double != 0 }
    public static func setManagerDuty(_ s: inout GameState, companyID: Int, duty: String, manager: Bool) {
        guard let i = s.companyIndex(companyID) else { return }
        var d = s.companies[i].value("duty56"); if d.isNull { d = .object([:]) }
        d[duty] = .number(manager ? 1 : 0)
        s.companies[i].set("duty56", d)
    }

    /// A manager promoted for only some duties leaves the other decisions to you. Original: the `makeProposal` step of worker_roles_and_promotions.js.
    static func dutyAllows(_ n: Person, _ kind: String) -> Bool {
        let k = n.value("k11")
        guard k["post"].string.hasPrefix("mgr@") else { return true }
        let need = kind == "hire" ? "hire" : ["eq", "veh", "space"].contains(kind) ? "buy" : nil
        guard let nd = need else { return true }
        return k["duties"].array.contains { $0.string == nd }
    }

    /// Carry out a purchase the manager asked for. Original: `execProposal` for `eq`, `veh`, `space`.
    static func buyForProposal(_ s: inout GameState, _ ci: Int, _ dp: Proposal, _ n: Person, data: GameData) {
        let co = s.companies[ci]
        let w = World(state: s, data: data)
        switch dp.kind {
        case "eq":
            guard let o = EquipmentMarket.offers(s, companyID: co.id, equipmentID: dp.id, data: data).min(by: { $0.priceFactor < $1.priceFactor }) else { return }
            let r = EquipmentMarket.buyNew(&s, companyID: co.id, equipmentID: dp.id, offer: o, quantity: 1, payment: .cash, data: data)
            if r == .ok { s.note("\(n.name) bought equipment for \(co.name).", tone: "n", companyID: co.id) }
            else if r == .notEnoughCash, s.week - co.value("flags")["cashAsk"].int > 8 || co.value("flags")["cashAsk"].isNull {
                var f = s.companies[ci].value("flags"); f["cashAsk"] = .number(Double(s.week)); s.companies[ci].set("flags", f)
                s.addMessage(kind: "info", from: n.name, title: "Could not buy equipment", body: "I could not buy the equipment for \(co.name): not enough cash. Put money in or tell me to wait.", companyID: co.id, tone: "bad", status: "done")
            }
        case "veh":
            guard let o = EquipmentMarket.vehicleOffers(s, companyID: co.id, equipmentID: dp.id, data: data).min(by: { $0.priceFactor < $1.priceFactor }) else { return }
            if EquipmentMarket.buyNewVehicle(&s, companyID: co.id, equipmentID: dp.id, offer: o, payment: .finance, data: data) == .ok { s.note("\(n.name) financed a vehicle for \(co.name).", tone: "n", companyID: co.id) }
        case "space":
            var prem = co.value("prem")
            guard let kind = prem["kind"].isNull ? nil : prem["kind"].string, let P = data.catalog.tables.premises[kind], let city = w.city(co) else { return }
            let add = jsRound(prem["m2"].double * 0.25)
            prem["m2"] = .number(prem["m2"].double + add)
            if prem["owned"].bool {
                let dv = add * P.pricePerM2 * city.rent
                Payments.companyPays(&s, companyID: co.id, amount: dv, category: nil, label: "Extension of the premises")
                prem["val"] = .number(prem["val"].double + dv)
            } else { Payments.companyPays(&s, companyID: co.id, amount: dp.cost * 0.5, category: "oth", label: "Fit-out of the extra space") }
            if let k = s.companyIndex(co.id) { s.companies[k].set("prem", prem) }
            s.note("\(n.name) expanded the premises of \(co.name) by \(Int(add)) m2.", tone: "n", companyID: co.id)
        default: break
        }
    }

    // MARK: Meeting: the manager brings two or three proposals

    public struct ManagerProposal: Equatable, Sendable {
        public var kind: String          // hire, price_up, price_down, mkt_more, quality, cut, eq, save
        public var title: String
        public var why: String
        public var role: String
        public var id: String
        public var addedCost: Double
        public var addedRevenue: Double
        public var once: Double
    }

    /// The proposals a manager would bring to a meeting, with costs and expected revenue, best first. Original: `mprops`.
    public static func managerProposals(_ s: inout GameState, companyID: Int, data: GameData) -> [ManagerProposal] {
        guard let ci = s.companyIndex(companyID), let bd = data.catalog[s.companies[ci].type] else { return [] }
        let co = s.companies[ci]
        let w = World(state: s, data: data)
        let q = quality(co, bd, people: s.people)
        let lw = co.value("lastW")
        let units = lw["units"].double, rev = lw["rev"].double, util = lw["util"].double
        let D = lw["D"].double, cap = lw["cap"].double
        let tk = units > 0 ? rev / units : bd.ticket
        let cur = w.currency(co)
        var out: [ManagerProposal] = []
        var role: String?
        for st in CompanySetup.standardStaff(bd, size: co.size) where role == nil {
            if co.staff.filter({ $0.role == st.role && $0.noticeWeeks <= 0 }).count < st.count, data.catalog.tables.roles[st.role] != nil { role = st.role }
        }
        if role == nil && util > 0.85, let f = bd.standardStaff.first?.role, data.catalog.tables.roles[f] != nil { role = f }
        if let r = role, util > 0.75 || D > cap {
            let per = cap > 0 ? cap / Double(max(1, co.staff.count)) : D
            var extra = min(per, max(0, D - cap * 0.9)); if extra == 0 { extra = per * 0.3 }
            let wage = marketWage(s, co, role: r, data: data)
            if extra * tk > 0 {
                out.append(ManagerProposal(kind: "hire", title: "Hire one more \((data.catalog.tables.roles[r]?.name ?? r).lowercased())",
                                           why: "Utilisation is \(Int(jsRound(util * 100)))%\(D > cap ? " and we turn customers away" : ""). I would like to hire one more. Salary around \(cur.short(wage)) a month.",
                                           role: r, id: "", addedCost: wage * 12 * 1.14 / 52, addedRevenue: extra * tk * 0.9, once: 0))
            }
        }
        let L = co.priceLevel
        let pm: [Double] = [0.7, 0.8, 0.9, 1, 1.15, 1.4, 1.9]
        func pmAt(_ l: Double) -> Double { pm[min(6, max(0, Int(l.rounded()) + 3))] }
        if util > 0.85 && L < 3 { out.append(ManagerProposal(kind: "price_up", title: "Raise prices one step", why: "We are nearly fully booked, so a higher price costs us few customers.", role: "", id: "", addedCost: 0, addedRevenue: rev * (pmAt(L + 1) / pmAt(L) * 0.9 - 1), once: 0)) }
        if util < 0.6 && L > -3 && units > 0 { out.append(ManagerProposal(kind: "price_down", title: "Lower prices one step", why: "We have free capacity. A lower price fills it.", role: "", id: "", addedCost: 0, addedRevenue: rev * (pmAt(L - 1) / pmAt(L) * 1.22 - 1), once: 0)) }
        if co.awareness < 70, FranchiseStandards.campaignRefusal(co, channel: bd.audience > 0.5 ? "google" : "meta") == nil {
            let ch = bd.audience > 0.5 ? "google" : "meta"
            let cur0 = co.value("mkt")[ch]["b"].double
            let steps: [Double] = marketingSteps(ch, cur)
            if let nx = steps.first(where: { $0 > cur0 }) {
                out.append(ManagerProposal(kind: "mkt_more", title: "Spend more on \(ch == "google" ? "Google" : "Meta")", why: "We are not known enough locally. More people need to hear about us.", role: "", id: "",
                                           addedCost: nx - cur0, addedRevenue: (nx - cur0) * (1.1 + (70 - co.awareness) / 60) * (util < 0.9 ? 1 : 0.4), once: 0))
            }
        }
        if let eqc = co.value("eqc").isNull ? nil : co.value("eqc").double, eqc < 0.7, co.maintenance < 2 {
            out.append(ManagerProposal(kind: "quality", title: "Step up maintenance", why: "Equipment is at \(Int(jsRound(eqc * 100)))% and breakdowns cost us jobs.", role: "", id: "", addedCost: max(cur.scaledPrice(200), rev * 0.02), addedRevenue: rev * 0.05, once: 0))
        }
        if util < 0.5 && co.staff.count > 1, let weak = co.staff.min(by: { (s.people[$0.id]?.skill ?? 0) < (s.people[$1.id]?.skill ?? 0) }) {
            out.append(ManagerProposal(kind: "cut", title: "Let one person go", why: "We have more people than work right now.", role: "", id: "", addedCost: -weak.monthlyWage * 1.14 * 12 / 52, addedRevenue: -rev * 0.04, once: 0))
        }
        if util > 0.9, let p = bottleneckProposal(s, co, bd, data: data), p.kind == "eq", let e = bd.equipment.first(where: { $0.id == p.id }) {
            out.append(ManagerProposal(kind: "eq", title: "Buy \(e.name)", why: "It is our bottleneck right now.", role: "", id: p.id, addedCost: 0, addedRevenue: tk * max(1, D - cap) * 0.8, once: p.cost))
        }
        if co.maintenance > 0 && rev > 0 && out.count < 3 { out.append(ManagerProposal(kind: "save", title: "Trim upkeep", why: "A little less maintenance saves money with small risk.", role: "", id: "", addedCost: -max(cur.scaledPrice(100), rev * 0.015), addedRevenue: -rev * 0.01, once: 0)) }
        var scored: [(ManagerProposal, Double)] = out.map { x in (x, x.addedRevenue - x.addedCost - x.once / 26 + s.random.gauss() * abs(x.addedRevenue - x.addedCost + 1) * 0.6 * (1 - q)) }
        scored.sort { $0.1 > $1.1 }
        return scored.prefix(3).map { $0.0 }
    }
    static func marketingSteps(_ ch: String, _ cur: Currency) -> [Double] {
        (ch == "google" ? [500, 1500, 3000, 7000, 15000] : [300, 1000, 2500, 5000, 10000]).map { cur.scaledPrice($0) }
    }

    /// Call a meeting with one manager: they put proposals on the table as messages you answer. Original: `ACT.mtgo2`.
    @discardableResult
    public static func meetForProposals(_ s: inout GameState, companyID: Int, data: GameData) -> Int? {
        guard let ci = s.companyIndex(companyID), let mid = s.companies[ci].managerID, let n = s.people[mid] else { return nil }
        let co0 = s.companies[ci]
        if !co0.value("meetW").isNull && Double(s.week) - co0.num("meetW") < 3 { return nil }
        let props = managerProposals(&s, companyID: companyID, data: data)
        s.companies[ci].set("meetW", s.week)
        s.companies[ci].set("mood", min(100, mood(co0) + 3))
        let cur = World(state: s, data: data).currency(co0)
        if props.isEmpty {
            s.addMessage(kind: "info", from: n.name, title: "Meeting: \(co0.name)", body: "Things run well. I do not see anything worth changing right now.", companyID: companyID, tone: "n", status: "done")
        }
        let first = firstName(n.name)
        for x in props {
            s.addMessage(kind: "ask", from: n.name, title: x.title, body: x.why + "\nAdded cost " + (x.once > 0 ? "\(cur.short(x.once)) once" : "\(cur.short(x.addedCost))/wk") + ", added revenue about \(cur.short(x.addedRevenue))/wk.",
                         companyID: companyID, tone: "n", status: "open",
                         options: [.option(x.kind == "hire" ? "Approve, I pick" : "Approve"), .option("Let \(first) decide"), .option("Not now")], action: "mprop",
                         data: .object(["t": .string(x.kind), "role": .string(x.role), "id": .string(x.id), "cost": .number(x.once > 0 ? x.once : x.addedCost * 52), "cw": .number(x.addedCost), "rw": .number(x.addedRevenue), "title": .string(x.title)]),
                         expiresWeek: s.week + 2)
        }
        return props.count
    }

    /// Answer a meeting proposal: 0 approve (hires wait for you to pick), 1 let the manager decide, 2 not now. Original: `ACTS.mprop`, `doProp`.
    static func answerProposal(_ s: inout GameState, message m: Message, option idx: Int, data: GameData, marketing: MarketingTables) {
        guard idx != 2, let ci = s.companyIndex(m.companyID), let mid = s.companies[ci].managerID, let n = s.people[mid], let bd = data.catalog[s.companies[ci].type] else { return }
        let d = m.value("data")
        let q = quality(s.companies[ci], bd, people: s.people)
        if idx == 1 && !(d["rw"].double - d["cw"].double > 0 && s.random.chance(0.55 + q * 0.4)) {
            s.note("\(n.name) decided against: \(d["title"].string).", tone: "n", companyID: m.companyID); return
        }
        let kind = d["t"].string
        let dp = Proposal(kind: kind, role: d["role"].string, cost: d["cost"].double, id: d["id"].string)
        if kind == "hire" && idx == 0 { s.note("\(n.name) waits for you to pick the new \(data.catalog.tables.roles[dp.role]?.name.lowercased() ?? "person") at \(s.companies[ci].name).", tone: "n", companyID: m.companyID); return }
        if ["hire", "eq", "cut"].contains(kind) {
            if kind == "hire" {
                let need = hireShort(s, s.companies[ci], cost: dp.cost, data: data)
                if need > 0 { guard Payments.liquid(s) >= need else { s.note("Not enough money to hire at \(s.companies[ci].name): needs \(need) first.", tone: "bad", companyID: m.companyID); return }
                    Payments.injectCash(&s, companyID: m.companyID, amount: need) }
            }
            exec(&s, ci, dp, n, q, data: data); return
        }
        let keys = ["price_up": "price_up", "price_down": "price_down", "mkt_more": "mkt_more", "quality": "quality", "save": "save"]
        if let k = keys[kind], let said = ask(&s, companyID: m.companyID, key: k, data: data, marketing: marketing) { s.note("\(n.name): \(said)", tone: "n", companyID: m.companyID) }
    }

    // MARK: Profit bonus and a manager's year

    /// The share of a month's profit a manager is paid on top of the salary is booked in `MonthEnd.closeMonth` (original: `monthEndCoCore`).
    public static func setManagerProfitBonus(_ s: inout GameState, companyID: Int, share: Double) {
        guard let i = s.companyIndex(companyID), s.companies[i].managerID != nil else { return }
        s.companies[i].managerProfitBonus = clamp(share, 0, 0.3)
    }

    // MARK: Assistants: monthly suggestion and basic insurance

    /// Every fourth week the assistant advises on something; with the paperwork duty they also take out basic insurance. Original: `asstWeek` (end).
    static func assistantExtras(_ s: inout GameState, companyIndex ci: Int, data: GameData) {
        let co = s.companies[ci]
        var a = co.value("asst")
        guard a["npc"].int != 0, let n = s.people[a["npc"].int], co.status == .open else { return }
        if a["duties"].array.contains(where: { $0.string == "paper" }), !co.value("insr").isNull, co.value("ins").object.values.allSatisfy({ !$0.bool }) {
            var ins = co.value("ins"); ins["liab"] = 1
            let hasPlace = co.value("prem")["m2"].double > 0
            if hasPlace { ins["prop"] = 1 }
            s.companies[ci].set("ins", ins)
            s.note("\(n.name) took out basic liability\(hasPlace ? " and property" : "") insurance for \(co.name).", tone: "n", companyID: co.id)
        }
        let last = a["sug"].isNull ? a["w0"].int : a["sug"].int
        if s.week - last >= 4 {
            a["sug"] = .number(Double(s.week)); s.companies[ci].set("asst", a)
            let props = managerProposals(&s, companyID: co.id, data: data)
            if !props.isEmpty {
                let x = props[Int(HashedRandom.first("asug:\(co.id):\(s.week)") * Double(min(3, props.count))) % props.count]
                s.addMessage(kind: "info", from: n.name, title: "Suggestion for \(co.name): \(x.title)", body: x.why + " I can only advise. You decide.", companyID: co.id, tone: "n", status: "done")
            }
        }
    }

    // MARK: A manager never runs a team from your home

    static let homeTrades: Set<String> = ["plumber", "electrician", "construction", "mktg", "webdev", "acctfirm", "law", "cleaning", "estate", "engcons", "event", "drivsk", "staffing"]
    /// A manager with staff rents a small place if the company works from home. Original: managers_who_manage.js section 7.
    static func managerRentsPlace(_ s: inout GameState, companyIndex ci: Int, data: GameData) {
        let co = s.companies[ci]
        guard co.status == .open, let mid = co.managerID, let n = s.people[mid], homeTrades.contains(co.type), !(co.value("prem")["m2"].double > 0), !co.staff.isEmpty else { return }
        let w = World(state: s, data: data)
        guard let city = w.city(co), let P = data.catalog.tables.premises["office"] else { return }
        let m2 = 25.0
        let rent = w.currency(co).tidy(P.rentPerM2Year * city.rent * w.inflationIndex)
        let deposit = rent * m2 / 12 * 3
        guard co.cash >= deposit else { return }
        Payments.companyPays(&s, companyID: co.id, amount: deposit, category: nil, label: "Lease deposit (3 months)")
        s.companies[ci].set("prem", .object(["kind": "office", "m2": .number(m2), "rent": .number(rent), "owned": false, "val": 0, "loan": 0, "dep": .number(deposit), "loc": 1, "lname": "Small office", "landlord": "Local landlord"]))
        s.note("\(n.name) rented a small office of \(Int(m2)) m² for \(co.name): staff need somewhere to work.", tone: "n", companyID: co.id)
    }
}
