import Foundation
import GameCore
import Countries
import Employees
import Finance

/// A chain runs itself: when someone sits above a store manager, requests go to them first. They judge on the numbers, move money between sister
/// stores as group loans, replace a missing store manager, answer a store manager's request to leave the chain price, and grow the chain (new stores,
/// new cities). Stores wait three weeks before they open. Original: features/company/chain_hierarchy.js (CHN56), features/company/chain_price_requests.js
/// (CPX56), features/company/org_chart.js (ORG56 `approve`, `openStore`, the weekly growth step), features/company/chain_registration_and_boards.js (`open13`).
extension ManagerModel {
    // MARK: Judging a request

    static func sisters(_ s: GameState, _ co: Company) -> [Company] {
        guard let ch = Chains.chain(s, of: co) else { return [] }
        return Chains.stores(s, ch).filter { $0.id != co.id && $0.status == .open }
    }
    static func spareCash(_ s: GameState, _ c: Company, data: GameData) -> Double {
        max(0, c.cash - weekCost(s, c, data: data) * 8 - World(state: s, data: data).currency(c).scaledPrice(20000))
    }

    /// Move money from the sister store that can spare the most, as a group loan the store pays back when it can. Original: `sisterCash`.
    static func sisterCash(_ s: inout GameState, to co: Company, need: Double, data: GameData) -> Company? {
        let cur = World(state: s, data: data).currency(co)
        guard let from = sisters(s, co).max(by: { spareCash(s, $0, data: data) < spareCash(s, $1, data: data) }), spareCash(s, from, data: data) >= need else { return nil }
        let amt = cur.roundedStep(need, about: 1000)
        Payments.companyPays(&s, companyID: from.id, amount: amt, category: nil, label: "Group loan to \(co.name)")
        Payments.companyReceives(&s, companyID: co.id, amount: amt, category: nil, label: "Group loan from \(from.name)")
        if let i = s.companyIndex(co.id) {
            var gl = s.companies[i].value("gl56").array
            gl.append(.object(["from": .number(Double(from.id)), "amt": .number(amt), "w": .number(Double(s.week))]))
            s.companies[i].set("gl56", .array(gl))
        }
        return from
    }

    /// Group loans inside a chain are paid back once the store has a cushion of its own. Original: step 'group loans inside a chain are paid back'.
    static func groupLoansRepay(_ s: inout GameState, data: GameData) {
        for i in s.companies.indices where s.companies[i].status == .open && !s.companies[i].value("gl56").array.isEmpty {
            var gl = s.companies[i].value("gl56").array
            var l = gl[0]
            let co = s.companies[i]
            guard let from = s.company(l["from"].int), from.status.isLive else { gl.removeFirst(); s.companies[i].set("gl56", .array(gl)); continue }
            let room = co.cash - weekCost(s, co, data: data) * 10
            if room <= 0 { continue }
            let x = min(l["amt"].double, (room * 0.5).rounded(.down))
            if x < 1000 { continue }
            Payments.companyPays(&s, companyID: co.id, amount: x, category: nil, label: "Group loan repaid to \(from.name)")
            Payments.companyReceives(&s, companyID: from.id, amount: x, category: nil, label: "Group loan repaid by \(co.name)")
            l["amt"] = .number(l["amt"].double - x)
            if l["amt"].double < 1000 { gl.removeFirst() } else { gl[0] = l }
            if let k = s.companyIndex(co.id) { s.companies[k].set("gl56", .array(gl)) }
        }
    }
    /// What a company owes its sister stores.
    public static func groupLoanBalance(_ s: GameState, companyID: Int) -> Double { s.company(companyID)?.value("gl56").array.reduce(0) { $0 + $1["amt"].double } ?? 0 }

    /// A store without a manager gets one from the boss. Original: `fillManager`.
    @discardableResult
    static func fillManager(_ s: inout GameState, companyID: Int, by: String, why: String, data: GameData) -> Person? {
        guard let ci = s.companyIndex(companyID), s.companies[ci].managerID == nil, s.companies[ci].status == .open || s.companies[ci].status == .setup, let bd = data.catalog[s.companies[ci].type] else { return nil }
        let n = generateCandidate(company: s.companies[ci], type: bd.managerType, state: &s, data: data)
        guard hire(&s, personID: n.id, companyID: companyID, monthlyWage: jsRound(n.askingMonthlyWage * 1.05), data: data) == .ok else { return nil }
        s.note((by.isEmpty ? "\(n.name) was appointed" : "\(by) appointed \(n.name)") + " as manager of \(s.companies[ci].name)" + (why.isEmpty ? "" : " after \(why)") + ".", tone: "n", companyID: companyID)
        return n
    }

    /// How a request looks to the boss: 1 yes, -1 no, 0 a close call. Original: `merit`.
    static func merit(_ s: GameState, _ co: Company, _ dp: Proposal) -> Int {
        let w = co.value("lastW")
        let over = w["cap"].double > 0 ? w["D"].double / w["cap"].double : 0, u = w["util"].double
        let h = co.monthlyHistory.suffix(3)
        let prof = h.isEmpty ? 0 : h.reduce(0) { $0 + $1.profit } / 3
        switch dp.kind {
        case "hire", "eq", "veh", "space": return over >= 1.2 && u >= 0.9 ? 1 : (over < 0.95 || u < 0.75 ? -1 : 0)
        case "cut": return u < 0.5 && prof < 0 ? 1 : (u > 0.7 ? -1 : 0)
        case "ad": return co.awareness < 20 && co.cash > 0 ? 1 : 0
        default: return 0
        }
    }
    static let proposalWhy: [String: String] = ["hire": "customers are being turned away and people are the limit", "eq": "the equipment is full and customers wait", "veh": "every vehicle is busy",
                                                "space": "the place is too small for the customers it gets", "cut": "the team has too little to do", "ad": "too few people know the store"]
    static let proposalNo: [String: String] = ["hire": "there is not enough work for one more", "eq": "what we have is not full yet", "veh": "the vehicles are not all busy",
                                               "space": "there is room in the place we have", "cut": "the team is busy enough", "ad": "the money is better kept for now"]

    /// The boss above the manager judges a request first. True when they dealt with it; false when it comes to you (with their view in `view`).
    /// Original: `CHN56.decide`.
    static func hierarchyDecide(_ s: inout GameState, _ ci: Int, _ dp: Proposal, _ n: Person, affordable: Bool, view: inout String, data: GameData) -> Bool {
        let co = s.companies[ci]
        let L = decisionChain(s, co, data: data).filter { $0.kind != "mgr" }
        guard let boss = L.first else { return false }
        let cur = World(state: s, data: data).currency(co)
        let who = "\(boss.name) (\(titleFor(co, kind: boss.kind, data: data, state: s)))"
        let cost = dp.kind == "hire" ? dp.cost / 12 : dp.cost
        let inBudget = boss.level >= 2 || (boss.level >= 1 && cost <= boss.buy)
        var afford = affordable
        let title = dp.kind == "hire" ? "hire a \(data.catalog.tables.roles[dp.role]?.name.lowercased() ?? "person") at \(co.name)" : dp.kind == "eq" ? "buy equipment for \(co.name)"
            : dp.kind == "veh" ? "add a vehicle at \(co.name)" : dp.kind == "space" ? "expand the premises of \(co.name)" : dp.kind == "cut" ? "reduce staffing at \(co.name)" : dp.kind == "ad" ? "start advertising at \(co.name)" : "cash at \(co.name)"
        if dp.kind == "cash" || (dp.kind == "hire" && !affordable) {
            let need = dp.kind == "cash" ? max(cur.scaledPrice(50000), weekCost(s, co, data: data) * 6 - co.cash) : hireShort(s, co, cost: dp.cost, data: data)
            if need > 0, let from = sisterCash(&s, to: co, need: need, data: data) {
                s.note("\(who) moved \(cur.short(need)) from \(from.name) to \(co.name) as a group loan\(dp.kind == "hire" ? ", so the hire can go ahead." : ".")", tone: "n", companyID: co.id)
                if dp.kind == "cash" { return true }
                afford = true
            } else if dp.kind == "cash" { return false }
        }
        let m = merit(s, co, dp)
        let cap = { (t: String) in t.prefix(1).uppercased() + t.dropFirst() }
        if m < 0 { s.note("\(who) said no to \(n.name): \(title). \(cap(proposalNo[dp.kind] ?? "not now")).", tone: "n", companyID: co.id); return true }
        if inBudget && afford {
            exec(&s, ci, dp, n, quality(s.companies[ci], data.catalog[co.type]!, people: s.people), data: data)
            s.note("\(who) approved: \(title). \(cap(m > 0 ? proposalWhy[dp.kind] ?? "" : "a close call, but the store can afford it and it should grow")).", tone: "n", companyID: co.id)
            return true
        }
        if inBudget && !afford { s.note("\(who) put off \(title) until \(co.name) has the cash.", tone: "n", companyID: co.id); return true }
        if m <= 0 { s.note("\(who) said no to \(title): above their budget and not clearly worth it.", tone: "n", companyID: co.id); return true }
        view = "\(boss.name) recommends it: \(proposalWhy[dp.kind] ?? "")\(inBudget ? "" : ", but it is above the budget you gave them")."
        return false
    }

    /// Trouble at a store: the boss above it deals with it. True when they did. Original: `CHN56.handle`.
    static func handleBelow(_ s: inout GameState, companyID: Int, kind: String, why: String, pick: Int, data: GameData) -> Bool {
        guard let co = s.company(companyID) else { return false }
        let L = decisionChain(s, co, data: data).filter { $0.kind != "mgr" }
        guard let boss = L.first(where: { $0.level >= 1 }) ?? L.first else { return false }
        let who = "\(boss.name) (\(titleFor(co, kind: boss.kind, data: data, state: s)))"
        let cur = World(state: s, data: data).currency(co)
        if kind == "mgr" { return fillManager(&s, companyID: companyID, by: who, why: "the last manager left", data: data) != nil }
        if kind == "cash" {
            if let from = sisterCash(&s, to: co, need: max(cur.scaledPrice(30000), weekCost(s, co, data: data) * 6), data: data) {
                s.note("\(who) moved money from \(from.name) to \(co.name): its cash was running out.", tone: "n", companyID: companyID)
            } else { doEmergency(&s, companyID: companyID, code: "mkt0", data: data); s.note("\(who) stopped marketing at \(co.name) to save cash.", tone: "n", companyID: companyID) }
            return true
        }
        if kind == "loss" { return false }
        guard let opts = ["drop": ["price-", "mkt+"], "stock": ["stock", "asst"], "rating": ["course", "raise"]][kind] else { return false }
        let code = opts[min(opts.count - 1, max(0, pick))]
        doEmergency(&s, companyID: companyID, code: code, data: data)
        let what = ["price-": "cut prices one step", "mkt+": "raised marketing by half", "stock": "ordered more stock from now on", "asst": "gave the ordering to the assistant", "course": "sent the staff on a course", "raise": "raised pay 5%"][code] ?? code
        s.note("\(who) \(what) at \(co.name): \(why.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))).", tone: "n", companyID: companyID)
        return true
    }

    // MARK: A store manager asks to leave the chain price

    static func stepWord(_ v: Double) -> String { v == 0 ? "the chain price" : "\(Int(abs(v))) step\(abs(v) > 1 ? "s" : "") \(v > 0 ? "above" : "below") the chain price" }

    /// What the last four weeks say: (+1 too busy, -1 too quiet, 0 back to normal) with a reason, or nil. Original: `CPX56.want`.
    static func priceWish(_ co: Company) -> (value: Double, dir: String, why: String)? {
        let H = co.value("wh56").array.suffix(4)
        guard H.count == 4 else { return nil }
        let d = H.reduce(0) { $0 + $1["d"].double } / 4, u = H.reduce(0) { $0 + $1["u"].double } / 4
        let off = co.value("off")["price"].double
        if d > 1.25 && u >= 0.95 && off < 2 { return (off + 1, "up", "far more customers than we can serve (about \(Int(jsRound(d * 100)))% of what we can do), and the store is full") }
        if d < 0.6 && u < 0.55 && off > -2 { return (off - 1, "down", "the store is only about \(Int(jsRound(u * 100)))% busy") }
        if off != 0 && d >= 0.8 && d <= 1.1 { return (0, "back", "customers and capacity are back in balance") }
        return nil
    }

    /// Weekly: remember how busy each store is, and let a store manager ask. Original: step 'chain store managers ask to leave the chain price'.
    static func priceRequestsWeekly(_ s: inout GameState, data: GameData) {
        for i in s.companies.indices where s.companies[i].status == .open {
            let lw = s.companies[i].value("lastW")
            var wh = s.companies[i].value("wh56").array
            wh.append(.object(["u": .number(lw["util"].double), "d": .number(lw["cap"].double > 0 ? min(9, lw["D"].double / lw["cap"].double) : 9)]))
            s.companies[i].set("wh56", .array(Array(wh.suffix(12))))
            let co = s.companies[i]
            guard let mid = co.managerID, let m = s.people[mid], let ch = Chains.chain(s, of: co) else { continue }
            if s.week - (co.value("cpx56")["w"].isNull ? -99 : co.value("cpx56")["w"].int) < 8 { continue }
            if s.inbox.contains(where: { $0.actionID == "cpx56" && $0.companyID == co.id && $0.status == "open" }) { continue }
            guard let r = priceWish(co) else { continue }
            s.companies[i].set("cpx56", .object(["w": .number(Double(s.week))]))
            let L = decisionChain(s, co, data: data).dropFirst()
            let ask = "Price at \(co.name): \(stepWord(r.value))?"
            if let boss = L.first(where: { $0.level >= 1 }) {
                let bp = s.people[boss.personID]
                let q = bp.map { ($0.value("stats")["ops"].isNull ? 0.6 : ($0.value("stats")["ops"].double + $0.value("stats")["fin"].double) / 200) } ?? 0.6
                let yes = r.dir == "back" || s.random.chance(0.55 + 0.4 * q)
                if yes { Chains.setStoreRule(&s, companyID: co.id, rule: .priceSteps(r.value)) }
                s.note("\(boss.name) (\(titleFor(co, kind: boss.kind, data: data, state: s))) \(yes ? "agreed" : "said no"): \(m.name) asked to move \(co.name) to \(stepWord(r.value)), because \(r.why).", tone: yes ? "n" : "bad", companyID: co.id)
                continue
            }
            if r.dir == "back" { Chains.setStoreRule(&s, companyID: co.id, rule: .priceSteps(0)); s.note("\(m.name) moved \(co.name) back to the chain price: \(r.why).", tone: "n", companyID: co.id); continue }
            s.addMessage(kind: "ask", from: m.name, title: ask, body: "We follow \(ch["name"].string)'s price. Over the last four weeks \(r.why). I would like to go \(r.dir == "up" ? "one step higher, so fewer people queue and each sale earns more" : "one step lower, to win back customers"). Every store in the chain keeps its own price only with your permission.",
                         companyID: co.id, tone: "n", status: "open", options: [.option("Allow it", stepWord(r.value)), .option("Keep the chain price", "The store stays with the others.")], action: "cpx56",
                         data: .object(["co": .number(Double(co.id)), "v": .number(r.value)]), expiresWeek: s.week + 3)
        }
    }

    // MARK: Every level grows the chain in its own way

    /// Ask the first boss above `from` with the authority and budget; if none, ask you. Original: `ORG56 approve`.
    static func approveUp(_ s: inout GameState, _ co: Company, from: String, cost: Double, title: String, why: String, action: [String: JSONValue], data: GameData, context fc: FinanceContext) {
        let L = decisionChain(s, co, data: data)
        let i = L.firstIndex { $0.kind == from } ?? 0
        let up = Array(L.dropFirst(i + 1))
        if let b = up.first(where: { $0.level >= 2 || ($0.level >= 1 && cost <= $0.buy) }) {
            runOrganisation(&s, .object(action), data: data, context: fc)
            s.note("\(b.name) (\(titleFor(co, kind: b.kind, data: data, state: s))) approved: \(title). \(why)", tone: "n", companyID: co.id)
            return
        }
        let key = (action["a"]?.string ?? "") + ":" + String(action["ch"]?.int ?? action["co"]?.int ?? 0)
        if s.inbox.contains(where: { $0.actionID == "org56" && $0.status == "open" && $0.value("data")["key"].string == key }) { return }
        var d = action; d["key"] = .string(key)
        let cur = World(state: s, data: data).currency(co)
        s.addMessage(kind: "ask", from: (up.last ?? L.last)?.name ?? co.name, title: title, body: why + " It is above what anyone below the board can approve, so it is yours to decide.", companyID: co.id, tone: "n", status: "open",
                     options: [.option("Approve", cost > 0 ? cur.short(cost) : ""), .option("Not now")], action: "org56", data: .object(d), expiresWeek: s.week + 3)
    }

    /// Carry out what a level decided: a new store, or a course for a team. Original: `ORG56.run`.
    static func runOrganisation(_ s: inout GameState, _ d: JSONValue, data: GameData, context fc: FinanceContext) {
        if d["a"].string == "store" { _ = openFundedStore(&s, chainID: d["ch"].int, cityID: d["city"].string, data: data, context: fc) }
        else if d["a"].string == "course", let i = s.companyIndex(d["co"].int), s.companies[i].cash > d["cost"].double {
            Payments.companyPays(&s, companyID: d["co"].int, amount: d["cost"].double, category: "oth", label: "Staff training")
            s.companies[i].quality = min(100, s.companies[i].quality + 4); s.companies[i].set("org56c", s.week)
        }
    }

    /// A chain opens a store paid from its stores' spare cash. Original: `ORG56 openStore`.
    @discardableResult
    static func openFundedStore(_ s: inout GameState, chainID: Int, cityID: String, data: GameData, context fc: FinanceContext) -> Int? {
        guard let ch = Chains.chain(s, id: chainID), let cost = Chains.newStoreCost(s, chainID: chainID, cityID: cityID, size: 1, data: data) else { return nil }
        var need = cost
        var parts: [Int: Double] = [:]
        for st in Chains.stores(s, ch).sorted(by: { spareCash(s, $0, data: data) > spareCash(s, $1, data: data) }) where need > 0 {
            let x = min(spareCash(s, st, data: data), need)
            if x > 1000 { parts[st.id] = x; need -= x }
        }
        if need > 1000 { return nil }
        if case .success(let id) = Chains.openStore(&s, chainID: chainID, cityID: cityID, size: 1, data: data, context: fc, fundedBy: parts) {
            s.note("\(s.company(id)?.name ?? "A new store") opens in about three weeks.", tone: "good", companyID: id)
            return id
        }
        return nil
    }

    /// Once a month: assistants book training, the chain manager opens stores where they are full, the CEO takes the chain to a new city.
    /// Original: the weekly step 'every level of the organisation grows the business in its own way' (`week % 4 === 1`).
    static func organisationWeekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        guard s.week % 4 == 1 else { return }
        for co in s.companies where co.status == .open && co.value("asst")["npc"].int != 0 && s.people[co.value("asst")["npc"].int] != nil && co.quality < 60 && Double(s.week) - (co.value("org56c").isNull ? -99 : co.num("org56c")) >= 26 {
            let cur = World(state: s, data: data).currency(co)
            let cost = cur.roundedStep(cur.scaledPrice(450) * Double(max(1, co.staff.count)), about: 100)
            if co.cash < cost * 3 { continue }
            if let i = s.companyIndex(co.id) { s.companies[i].set("org56c", s.week) }
            if co.managerID != nil, co.value("auth")["lvl"].double >= 1, cost <= co.value("auth")["buy"].double {
                runOrganisation(&s, .object(["a": "course", "co": .number(Double(co.id)), "cost": .number(cost)]), data: data, context: fc)
                s.note("\(s.people[co.value("asst")["npc"].int]?.name ?? "The assistant") (assistant) booked a course for the team at \(co.name), approved by \(s.people[co.managerID!]?.name ?? "the manager"): service had slipped.", tone: "n", companyID: co.id)
            }
        }
        for ch in Chains.list(s) {
            let L = Chains.stores(s, ch).filter { $0.status == .open }
            guard let any = L.first else { continue }
            let id = ch["id"].int
            let regs = regionals(s)
            let cm = regs.first { $0["scope"].string == "chain:\(id)" }
            let prof = L.allSatisfy { $0.monthlyHistory.suffix(3).count == 3 && $0.monthlyHistory.suffix(3).reduce(0) { $0 + $1.profit } > 0 }
            let full = L.map { ($0, $0.value("lastW")["cap"].double > 0 ? $0.value("lastW")["D"].double / $0.value("lastW")["cap"].double : 0) }.sorted { $0.1 > $1.1 }
            var chm = Chains.chain(s, id: id)!
            var org = chm["org56"]; if org.isNull { org = .object([:]) }
            let spareTotal = L.reduce(0) { $0 + spareCash(s, $1, data: data) }
            if cm != nil, person(s, cm!) != nil, prof, let top = full.first, top.1 >= 1.15, Double(s.week) - (org["st"].isNull ? -99 : org["st"].double) >= 26 {
                let city = top.0.cityID
                if let cost = Chains.newStoreCost(s, chainID: id, cityID: city, size: 1, data: data), spareTotal >= cost {
                    org["st"] = .number(Double(s.week)); chm["org56"] = org; Chains.save(&s, chm)
                    approveUp(&s, any, from: "chainmgr", cost: cost, title: "Open another store in \(cityName(s, city, data))", why: "\(person(s, cm!)?.name ?? "The chain manager") (chain manager): \(top.0.name) turns customers away, and the chain can pay for it from its own cash.",
                              action: ["a": "store", "ch": .number(Double(id)), "city": .string(city)], data: data, context: fc)
                }
            }
            chm = Chains.chain(s, id: id)!; org = chm["org56"]; if org.isNull { org = .object([:]) }
            if person(s, chm["ceo56"]) != nil, prof, L.count >= 3, Double(s.week) - (org["mk"].isNull ? -99 : org["mk"].double) >= 52 {
                let have = Set(L.map { $0.cityID })
                if let country = data.countries[any.countryCode], let c = country.cities.filter({ !have.contains($0.id) }).max(by: { $0.population < $1.population }),
                   let cost = Chains.newStoreCost(s, chainID: id, cityID: c.id, size: 1, data: data), spareTotal >= cost {
                    org["mk"] = .number(Double(s.week)); chm["org56"] = org; Chains.save(&s, chm)
                    approveUp(&s, any, from: "ceo56", cost: cost, title: "Take \(ch["name"].string) to \(c.name)", why: "\(person(s, chm["ceo56"])?.name ?? "The CEO") (CEO): every store makes money, and \(c.name) has none of ours yet.",
                              action: ["a": "store", "ch": .number(Double(id)), "city": .string(c.id)], data: data, context: fc)
                }
            }
            if cm != nil, person(s, cm!) != nil {
                for c in Chains.stores(s, Chains.chain(s, id: id)!) where c.managerID == nil && (c.status == .open || c.status == .setup) {
                    fillManager(&s, companyID: c.id, by: "\(person(s, cm!)?.name ?? "The chain manager") (chain manager)", why: "the store had no manager", data: data)
                }
            }
        }
    }
    static func cityName(_ s: GameState, _ id: String, _ data: GameData) -> String { data.countries[s.homeCountryCode]?.city(id)?.name ?? id }

    // MARK: A new store waits three weeks

    /// A store due to open opens when it can; otherwise it tries again every week. Original: the `open13` step.
    static func openingWait(_ s: inout GameState, data: GameData) {
        for i in s.companies.indices where !s.companies[i].value("open13").isNull && s.companies[i].status == .setup && s.week >= s.companies[i].value("open13").int {
            let r = OpeningChecklist.open(&s, companyIndex: i, data: data)
            let co = s.companies[i]
            if co.status == .open { s.companies[i].set("open13", .null); s.note("\(co.name) opened its doors today.", tone: "good", companyID: co.id); continue }
            s.companies[i].set("open13", s.week + 1)
            if co.value("wait13").isNull {
                s.companies[i].set("wait13", 1)
                var why = ""
                if r == .missing { why = ": things on its opening checklist are missing" } else if case .needsStockCash(let x) = r { why = ": it needs \(World(state: s, data: data).currency(co).short(x)) for its first stock" }
                s.note("\(co.name) could not open yet\(why). It tries again every week.", tone: "bad", companyID: co.id)
            }
        }
    }

    // MARK: Everything above the stores, once a week

    /// Called from `Chains.weekly`. Teams, boards, chain levels, requests and the monthly items.
    static func groupWeekly(_ s: inout GameState, data: GameData, context fc: FinanceContext, marketing: MarketingTables) {
        for i in s.companies.indices where s.companies[i].status.isLive {
            guard let bd = data.catalog[s.companies[i].type] else { continue }
            teamWeek(&s, i, bd, data: data)
            managerRentsPlace(&s, companyIndex: i, data: data)
        }
        groupLoansRepay(&s, data: data)
        priceRequestsWeekly(&s, data: data)
        organisationWeekly(&s, data: data, context: fc)
        openingWait(&s, data: data)
        boardsWeekly(&s, data: data)
        executivesWeekly(&s, data: data)
        if GameCalendar.isMonthEnd(week: s.week) {
            profitBonus(&s, data: data)
            groupMonthly(&s, data: data)
            Headquarters.monthly(&s, data: data)
        }
    }
}
