import XCTest
import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses
import Simulation
import Events
import SaveSystem

enum Policy: String, CaseIterable { case competent, reckless, passive }
enum Scenario: String, CaseIterable { case single, multi, chain, holding, startup, football, rework }

struct Job {
    var country: String, trade: String, seed: Int
    var policy: Policy = .competent
    var scenario: Scenario = .single
    var years: Int = PT.years
    var name: String { "\(scenario.rawValue)/\(country)/\(trade)/\(seed)/\(policy.rawValue)" }
    var repro: String {
        "LEDGER_PLAYTEST=1 LEDGER_PT_COUNTRY=\(country) LEDGER_PT_TRADE=\(trade) LEDGER_PT_SEED=\(seed) LEDGER_PT_POLICY=\(policy.rawValue) LEDGER_PT_SCENARIO=\(scenario.rawValue) swift test --filter PlaytestSweepTests/testRepro"
    }
}

struct RunResult { var hash = ""; var gameOver = false; var nw = 0.0; var note = ""; var weeks = 0 }

final class PlayBot {
    var e: GameEngine
    let job: Job
    let F = Findings.shared
    var cur: Currency
    var mainID = 0
    var baseline: [Int: [String: Int]] = [:]
    var setupSince: [Int: Int] = [:]
    var openedWeek: [Int: Int] = [:]
    var zeroRevWeeks: [Int: Int] = [:]
    var staffedWeek: [Int: Int] = [:]
    var zeroCapWeeks: [Int: Int] = [:]
    var rescues = 0
    var foreignSeen = Set<String>()
    var hireFails: [String: Int] = [:]
    var searchEmpty: [String: Int] = [:]
    var vacancyTries: [String: Int] = [:]
    var managerHired: [Int: Int] = [:]
    var recentBuy: [Int] = []
    var lastStructuralWeek = -99
    var lastNW = 0.0
    var weekMsgs = 0, weekBad = 0, weekWarn = 0
    var weekTitles: [String: Int] = [:]
    var weekOf = 0
    var absDay: Int { e.state.week * 7 + e.state.day }
    var answered = 0
    var noteLog: [String] = []
    var statusSeen: [Int: CompanyStatus] = [:]
    var everStock: Set<Int> = []
    var openedEver = false
    var weekOwnerNew = 0
    var saleRoute = "", saleStartWeek = 0, soldWeek = 0, meetings = 0

    init(_ job: Job) throws {
        self.job = job
        e = try GameEngine.newGame(countryCode: job.country, playerName: "Bot", seed: job.seed)
        cur = e.homeCurrency
    }

    var ctxLine: String { "\(job.name) wk\(e.state.week)" }
    func find(_ sev: Int, _ key: String, _ title: String, _ file: String, _ detail: String = "") {
        F.add(sev, key, title, repro: "\(job.repro) [\(job.name) week \(e.state.week) \(detail)]", file: file, detail: detail)
    }
    var liquid: Double { Payments.liquid(e.state) }
    func bought() { recentBuy.append(absDay) }
    func structural() { lastStructuralWeek = e.state.week }

    func estimate(_ trade: String) -> Double? {
        var rich = e.state; rich.cash += 1e12
        return CompanySetup.estimate(tradeID: trade, cityID: e.state.player.cityID, size: 1, state: rich, data: e.data)?.total
    }

    @discardableResult
    func openCompany(trade: String, fund: Double? = nil, topUp: Bool = true) -> Int {
        let city = e.state.player.cityID
        let need = estimate(trade)
        if let need, liquid < need * 1.1, topUp {
            find(3, "needs-topup:\(trade)", "Trade \(trade) cannot be started from the start-up loan alone (needs \(Int(need)) > liquid \(Int(liquid))): bot injected test capital", "PlayerActions.swift:startCompany / TradeAffordability")
            e.update { s, _, _ in Ledger.move(&s, .me, need * 1.5, why: "Test capital") }
        }
        let want = fund ?? max(0, liquid * 0.9)
        func start() -> Result<Int, CompanySetup.StartError> {
            if job.policy == .passive { return e.startCompany(tradeID: trade, cityID: city, fundWith: want) }
            switch e.startCompanyChoosingPremises(tradeID: trade, cityID: city, size: nil, name: nil, pick: nil, fundWith: want) {
            case .success(let out): return .success(out.companyID)
            case .failure(let err): return .failure(err)
            }
        }
        let r = start()
        switch r {
        case .success(let id):
            structural(); bought()
            statusSeen[id] = e.state.company(id)?.status
            setupSince[id] = e.state.week
            if job.policy != .passive { driveSetup(id, since: e.state.week) }
            return id
        case .failure(let err):
            find(2, "start-failed:\(trade):\(err)", "startCompany(\(trade)) failed with \(err) although cash was provided", "PlayerActions.swift:startCompany / CompanySetup.create", "liquid=\(Int(liquid))")
            return 0
        }
    }

    func pick(_ m: Message) -> Int {
        let opts = m.options
        guard !opts.isEmpty else { return 0 }
        if m.actionID.hasPrefix("pay29") { return 0 }
        switch job.policy {
        case .reckless:
            var r = HashedRandom("bot:\(job.seed):\(m.id)"); return Int(r.next() * Double(opts.count)) % opts.count
        default:
            let coCash = e.state.company(m.companyID)?.cash ?? liquid
            let decline = ["no", "decline", "not now", "ignore", "later", "refuse", "reject", "pass"]
            var best = 0, bestScore = -Double.infinity
            for (i, o) in opts.enumerated() {
                let cost = o["fx"]["cash"].double
                var score = -abs(cost) * 0.0001
                if cost < 0 && -cost > coCash * 0.5 { score -= 1e6 }
                let label = o["l"].string.lowercased()
                if i == 0 { score += 1 }
                if decline.contains(where: { label.hasPrefix($0) }) && opts.count > 1 { score -= 0.5 }
                if job.scenario == .rework, ["sale", "sell", "close", "dismiss", "replace"].contains(where: { label.contains($0) }) { score -= 100 }
                if score > bestScore { bestScore = score; best = i }
            }
            return best
        }
    }

    func answerAll() {
        for m in e.openDecisions {
            if m.options.isEmpty && (m.kind == "ask" || m.kind == "decision") {
                find(1, "no-options:\(m.actionID.isEmpty ? m.str("ev") : m.actionID)", "Open decision has no options and can never be answered: \"\(normTitle(m.title, names: names))\"", "Events/EventEngine.swift (message creation) / DecisionRouting.swift", "id=\(m.id)")
                continue
            }
            if job.policy == .passive { continue }
            guard e.state.inbox.first(where: { $0.id == m.id })?.status == "open" else { continue }
            let opt = pick(m)
            let ok = e.answer(messageID: m.id, option: opt)
            answered += 1
            F.countTitle("ANSWERED " + (m.actionID.isEmpty ? m.str("ev") : m.actionID))
            if !ok {
                find(1, "answer-rejected:\(m.actionID.isEmpty ? m.str("ev") : m.actionID)", "Answering decision returned false (nothing happened): \"\(normTitle(m.title, names: names))\" option \(opt)", "GameEngine.swift:answer / EventEngine.answer", "id=\(m.id) act=\(m.actionID) ev=\(m.str("ev")) cat=\(m.str("cat")) status=\(m.status) exp=\(m.expiresWeek ?? -1) week=\(e.state.week) co=\(m.companyID) opts=\(m.options.count)")
            } else if e.state.inbox.first(where: { $0.id == m.id })?.status == "open" {
                find(1, "answer-still-open:\(m.actionID)", "Answered decision is still open: \"\(normTitle(m.title, names: names))\"", "EventEngine.answer", "id=\(m.id)")
            } else { bought() }
        }
    }
    var names: [String] { e.state.companies.map { $0.name } }

    @discardableResult
    func hireWorker(_ id: Int, role: String) -> Bool {
        let cands = e.searchWorkers(companyID: id, role: role, mode: .ads)
        guard !cands.isEmpty else { searchEmpty[role, default: 0] += 1; find(2, "search-empty:\(role)", "Worker search for \(role) returned nobody", "PlayerActions.swift:searchWorkers / Hiring.search", "co=\(id)"); return false }
        let p = Hiring.bestValue(cands)
        let post = HirePost.worker(role: role)
        guard var offer = e.hearTheirAsk(post: post, companyID: id, personID: p.id) else { find(2, "ask-nil:\(role)", "hearTheirAsk returned nil for a shortlisted \(role)", "HiringNegotiation.swift:hearTheirAsk", "co=\(id)"); return false }
        for _ in 0..<4 {
            switch e.hireOffer(post: post, companyID: id, personID: p.id, monthlyWage: offer) {
            case .hired: bought(); structural(); return true
            case .countered(let a, _): offer = a
            case .termsRefused(let why), .blocked(let why):
                hireFails[role, default: 0] += 1; find(2, "hire-blocked:\(role)", "Hiring \(role) refused: \(why.prefix(60))", "HiringNegotiation.swift:hireOffer", "co=\(id)"); return false
            default: hireFails[role, default: 0] += 1; return false
            }
        }
        hireFails[role, default: 0] += 1
        find(2, "hire-never:\(role)", "Offer of their own ask for \(role) never accepted (countered 4 times)", "Hiring.answer / Negotiation", "co=\(id) ask=\(Int(offer))")
        return false
    }

    func staffCounts(_ co: Company) -> [String: Int] { Dictionary(co.staff.map { ($0.role, 1) }, uniquingKeysWith: +) }

    func tend() {
        guard job.policy != .passive else { return }
        let reckless = job.policy == .reckless
        for co in e.state.companies where co.status.isLive && co.type != "hold" && co.holdingID == 0 {
            let id = co.id
            if co.status == .setup {
                let since = setupSince[id] ?? e.state.week
                driveSetup(id, since: since)
                if e.state.week - since >= 20 {
                    find(1, "stuck-setup:\(co.type)", "Company sits in setup for 20+ weeks although the bot did every checklist step on the Setup screen (\(e.openingChecklist(companyID: id).filter { !$0.isDone }.map { $0.title }.joined(separator: " | ").prefix(100)))", "CompanySetup.swift / OpeningChecklist.swift", "co=\(id)")
                    setupSince[id] = e.state.week
                }
                continue
            }
            if co.status == .open {
                if openedWeek[id] == nil {
                    openedWeek[id] = e.state.week; openedEver = true
                    let lines = e.data.catalog[co.type]?.standardStaff ?? []
                    baseline[id] = Dictionary((reckless ? lines : Array(lines.prefix(1))).map { ($0.role, max(1, Int($0.count.rounded(.up)))) }, uniquingKeysWith: +)
                    if reckless, let ch = e.marketing.channels["google"], ch.budgetOptions.count > 1 { _ = e.setCampaign(companyID: id, channel: "google", weeklyBudget: ch.budgetOptions[1]) }
                    if reckless { for lv in [0.4, 3.0] { _ = e.setPriceLevel(companyID: id, level: lv) } }
                }
                let wages = max(co.lastWages, cur.scaledPrice(3000))
                let buffer = wages * (reckless ? 0.2 : 2)
                if co.cash < buffer {
                    let need = buffer * 2 - co.cash
                    if liquid - cur.scaledPrice(2000) > need { _ = e.putMoneyInto(companyID: id, amount: need) }
                    else if !reckless, e.loanOffer(kind: "biz", amount: need, companyID: id).maximum >= need { applyLoan(id, need) }
                    else if !reckless, co.cash < 0 { rescues += 1; structural(); e.update { s, _, _ in Ledger.move(&s, .me, need * 2, why: "Test rescue") }; _ = e.putMoneyInto(companyID: id, amount: need) }
                }
                if !reckless, e.state.week % 2 == 0 { buyNeededEquipment(id) }
                if !reckless, e.state.week % 13 == 0, let c = e.state.company(id), c.monthlyHistory.count >= 3, c.monthlyHistory.suffix(3).allSatisfy({ $0.profit > 0 }),
                   let ch = e.marketing.channels["google"], ch.budgetOptions.count > 1 {
                    let r = e.setCampaign(companyID: id, channel: "google", weeklyBudget: ch.budgetOptions[1])
                    if r != .done { find(3, "campaign-refused", "setCampaign refused for a profitable company: \(r)", "CompanyTabActions.setCampaign", "co=\(id)") }
                }
                if let base = baseline[id] {
                    let now = staffCounts(co)
                    for (role, n) in base { for _ in 0..<min(3, max(0, n - (now[role] ?? 0))) where hireFails[role, default: 0] < 12 { hireWorker(id, role: role) } }
                    if staffedWeek[id] == nil, base.allSatisfy({ staffCounts(e.state.company(id)!)[$0.key, default: 0] >= $0.value }) { staffedWeek[id] = e.state.week }
                    if reckless, e.state.week % 8 == 0, let role = e.hireableRoles(companyID: id).first { hireWorker(id, role: role) }
                }
                if e.state.week % 4 == 0 { fillVacancies(id) }
                if reckless && liquid > cur.scaledPrice(50_000) { _ = e.buyInvestment(.stock, symbol: e.quotes(.stock).first?.symbol ?? "", amount: liquid * 0.8) }
            }
        }
    }

    func applyLoan(_ companyID: Int, _ amount: Double) {
        let docs = LoanDocuments(fullName: e.state.player.name, incomeProof: .payslips, companyPapers: (e.state.company(companyID)?.monthlyHistory.count ?? 0) >= 3 ? .accounts : .registration)
        switch e.applyForLoan(kind: "biz", amount: amount, termMonths: 36, companyID: companyID, documents: docs, agreed: true) {
        case .approved: structural()
        case .refused(let why):
            if e.loanOffer(kind: "biz", amount: amount, companyID: companyID).maximum >= amount { find(3, "loan-refused-within-offer", "applyForLoan refused although loanOffer.maximum covers the amount: \(why.prefix(70))", "LoanApplication.swift:applyForLoan vs Banking.offer", "co=\(companyID)") }
        }
    }

    func driveSetup(_ id: Int, since: Int) {
        guard e.state.company(id)?.status == .setup else { return }
        var stuck: [String] = []
        for it in e.openingChecklist(companyID: id) where !it.isDone {
            if it.id.hasPrefix("doc:") {
                let d = String(it.id.dropFirst(4))
                if ["rejected", "lapsed", ""].contains(e.documentState(companyID: id, document: d).status) {
                    var r = e.applyForDocument(companyID: id, documentID: d)
                    if r == .notEnoughCash { _ = e.putMoneyInto(companyID: id, amount: e.documentFee(companyID: id, document: d) * 1.2); r = e.applyForDocument(companyID: id, documentID: d) }
                    if r == .ok { bought() }
                }
            } else if it.id == "prem" {
                let ls = e.premisesListings(companyID: id)
                let want = (e.data.catalog[e.state.company(id)?.type ?? ""]?.premisesM2 ?? 0) * (e.state.company(id)?.size ?? 1)
                let all = ls.compactMap { l in e.premisesTerms(companyID: id, listing: l).map { (l, $0) } }
                let fits = all.filter { $0.1.squareMetres >= want }
                let priced = (fits.isEmpty ? all.sorted { $0.1.squareMetres > $1.1.squareMetres } : fits.sorted { $0.1.monthlyRent < $1.1.monthlyRent })
                if let (l, terms) = priced.first {
                    var r = e.takePremises(companyID: id, listing: l)
                    if r == .notEnoughCash { _ = e.putMoneyInto(companyID: id, amount: (terms.deposit + terms.fitOut + terms.monthlyRent) * 1.3); r = e.takePremises(companyID: id, listing: l) }
                    if r == .ok { bought() } else { stuck.append("premises:\(r)") }
                } else { stuck.append("premises: no listings") }
            } else if it.id.hasPrefix("eq:") {
                let eid = String(it.id.dropFirst(3))
                let need = e.equipmentNeeds(companyID: id).first { $0.equipmentID == eid }
                var done = false
                for attempt in 0..<2 where !done {
                    if need?.isVehicle == true, let o = e.vehicleOffers(companyID: id, equipmentID: eid).min(by: { $0.priceFactor < $1.priceFactor }) {
                        done = e.buyVehicleItem(companyID: id, equipmentID: eid, offer: o, payment: .cash) == .ok
                    } else if let o = e.equipmentOffers(companyID: id, equipmentID: eid).min(by: { $0.priceFactor < $1.priceFactor }) {
                        done = e.buyEquipmentItem(companyID: id, equipmentID: eid, offer: o, quantity: 1, payment: .cash) == .ok
                    } else { stuck.append("eq \(eid): no offers"); break }
                    if !done && attempt == 0 { _ = e.putMoneyInto(companyID: id, amount: e.equipmentPrice(companyID: id, equipmentID: eid, factor: 1.3) * 1.2) }
                }
                if done { bought() } else if !stuck.contains(where: { $0.hasPrefix("eq \(eid)") }) { stuck.append("eq \(eid): not bought") }
            }
        }
        var r = e.openCompany(companyID: id)
        if case .needsStockCash(let a) = r { _ = e.putMoneyInto(companyID: id, amount: a * 1.2); r = e.openCompany(companyID: id) }
        if r == .ok { structural(); return }
        let weeksIn = e.state.week - since
        if !stuck.isEmpty { find(2, "setup-item-unfinishable", "Setup item cannot be completed through the normal screens: \(stuck.prefix(2).joined(separator: "; "))", "OpeningChecklist / MarketActions (AirStay/TechPro)", "co=\(id)") }
        if weeksIn >= 24 { _ = e.quickSetupWithinBudget(companyID: id); if e.openCompany(companyID: id) == .ok { find(3, "needed-quicksetup", "Company only opened after the quick-setup fallback (normal checklist route did not finish in 4 weeks)", "OpeningChecklist", "co=\(id)"); structural() } }
        noteLog.append("open \(id): \(r) undone=\(e.openingChecklist(companyID: id).filter { !$0.isDone }.map { $0.id }.joined(separator: ","))")
    }

    func buyNeededEquipment(_ id: Int) {
        var bought = 0
        guard let co0 = e.state.company(id), let bd0 = e.data.catalog[co0.type] else { return }
        let cr = CapacityModel.compute(co0, bd0, World(state: e.state, data: e.data))
        let limiting = Set(cr.parts.filter { $0.key.hasPrefix("eq:") && $0.have < $0.need }.map { String($0.key.dropFirst(3)) })
        let own = Set(bd0.equipment.map { $0.id })
        for n in e.equipmentNeeds(companyID: id) where n.need > n.have + n.leased && !n.isSoftware && !n.isVehicle && !own.contains(n.equipmentID) && foreignSeen.insert(co0.type + n.equipmentID).inserted { find(3, "foreign-equipment-need:\(co0.type):\(n.equipmentID)", "Equipment list shows \(n.name) (need \(Int(n.need))) for a \(co0.type), which is not on its equipment spec", "MarketActions.equipmentNeeds / EquipmentMarket.needs (PersonalEquipment)", "co=\(id)") }
        for n in e.equipmentNeeds(companyID: id) where limiting.contains(n.equipmentID) && n.need > n.have + n.leased && !n.isSoftware && !n.isVehicle && bought < 2 {
            if !n.required, let c0 = e.state.company(id), c0.status == .open, c0.value("lastW")["cap"].double <= 0, c0.value("lastW")["D"].double > 0, c0.openedWeek.map({ e.state.week - $0 >= 2 }) == true { find(1, "optional-equipment-gates-capacity:\(c0.type):\(n.equipmentID)", "\(n.name) is not required to open (checklist done, company opened) but without it capacity is 0: the \(c0.type) sells nothing", "OpeningChecklist.items vs Capacity.swift:core (limitsCapacity equipment)", "co=\(id)") }
            guard let o = e.equipmentOffers(companyID: id, equipmentID: n.equipmentID).min(by: { $0.priceFactor < $1.priceFactor }) else { continue }
            let price = e.equipmentPrice(companyID: id, equipmentID: n.equipmentID, factor: o.priceFactor)
            guard let co = e.state.company(id) else { return }
            if co.cash < price * 2 { if liquid > price * 3 { _ = e.putMoneyInto(companyID: id, amount: price * 2) } else { continue } }
            if e.buyEquipmentItem(companyID: id, equipmentID: n.equipmentID, offer: o, quantity: 1, payment: .cash) == .ok { bought += 1; self.bought() }
        }
    }

    func fillVacancies(_ companyID: Int) {
        let ov = e.teamOverview()
        for v in ov.vacancies where v.needed && v.companyID == companyID {
            let key = "\(v.id)"
            vacancyTries[key, default: 0] += 1
            guard let route = e.vacancyRoute(v) else { continue }
            guard let cands = e.searchVacancy(v), !cands.isEmpty else {
                if vacancyTries[key]! == 6 { find(2, "vacancy-no-candidates:\(v.post)", "Needed vacancy \"\(v.title)\" searched 6 times, nobody to hire (or search refused)", "VacancyHiring.swift:searchVacancy", "co=\(companyID)") }
                continue
            }
            let p = Hiring.bestValue(cands)
            guard var offer = e.hearTheirAsk(post: route.post, companyID: route.companyID, chainID: route.chainID, personID: p.id) else { continue }
            var hired = false
            for _ in 0..<4 {
                let r = e.hireOffer(post: route.post, companyID: route.companyID, chainID: route.chainID, city: route.city, personID: p.id, monthlyWage: offer * 1.05)
                if r == .hired { hired = true; break }
                if case .countered(let a, _) = r { offer = a } else { break }
            }
            if hired { bought(); structural(); if route.post == .manager { managerHired[companyID] = e.state.week } }
            else if vacancyTries[key]! >= 6 { find(2, "vacancy-unfillable:\(v.post)", "Needed vacancy \"\(v.title)\" cannot be filled after 6 tries (offers refused/countered)", "VacancyHiring.swift / HiringNegotiation.swift:hireOffer", "co=\(companyID)") }
        }
    }

    func checkDay(_ out: GameEngine.DayOutcome) {
        let s = e.state
        let g = Ledger.gaps(s)
        if !g.isEmpty { find(1, "ledger-gap", "Ledger.gaps not empty: \(g.map { "\($0.holder)=\(Int($0.difference))" }.joined(separator: ", ").prefix(120))", "Finance/Ledger.swift / the action that moved cash without booking", "") }
        if !s.cash.isFinite { find(1, "nan-personal", "Personal cash not finite", "Finance/Payments.swift", "") }
        for m in out.newMessages { checkMessage(m) }
        checkRouting(out)
        let open = e.openDecisions.count
        if open >= 8 { find(2, "decision-pile", "\(open) decisions open at once", "Events/EventEngine.swift (offer volume)", "") }
        if s.day == 0 { statusTransitions() }
    }

    func checkRouting(_ out: GameEngine.DayOutcome) {
        var seen = Set<String>()
        for m in out.newMessages {
            let nt = normTitle(m.title, names: names)
            if !seen.insert("\(m.companyID)|\(m.title)|\(m.body)").inserted { find(2, "dup-today:\(nt.prefix(40))", "Identical message (same company, title and text) twice in one day: \"\(nt)\"", "message source of that title", "") }
            let isDecision = (m.kind == "ask" || m.kind == "decision") && m.status == "open"
            if isDecision && m.isOwnerAddressed { weekOwnerNew += 1 }
            if isDecision && !m.isOwnerAddressed { find(3, "desk-decision:\(nt.prefix(40))", "Open decision addressed to a desk, so the owner never sees it as theirs: \"\(nt)\"", "DeskNotices / message source", "") }
            if !m.isOwnerAddressed && m.status == "done" && m.handledBy.isEmpty { find(3, "desk-unhandled:\(nt.prefix(40))", "Desk notice that shows nobody as handling it: \"\(nt)\"", "use addDeskNotice at the source", "") }
        }
    }

    func checkMessage(_ m: Message) {
        let nt = normTitle(m.title, names: names)
        F.countTitle(nt)
        weekMsgs += 1
        if m.tone == "bad" { weekBad += 1 }
        weekTitles[nt, default: 0] += 1
        if m.title.hasPrefix("No answer in time") || m.body.hasPrefix("No answer in time") {
            let sev = job.policy == .competent ? 2 : 3
            find(sev, "expired-unseen", "Decision expired unanswered (default taken) while the bot answers every day: \"\(m.title.prefix(60))\"", "EventEngine.swift:expire (offers that live < 1 day)", "")
        }
        if m.status == "open", let x = m.expiresWeek, x <= e.state.week, m.kind != "info" {
            find(2, "born-expired:\(m.actionID)", "Decision arrives already expired (exp week \(x) <= now): \"\(nt)\"", "EventEngine / decision creators", "")
        }
        let t = (m.title + " " + m.body).lowercased()
        let verbs = ["you bought", "you purchased", "you ordered", "you signed", "you hired", "you took out", "you started", "you opened", "you invested", "you sold", "you paid"]
        if let v = verbs.first(where: { t.contains($0) }), !(job.scenario == .rework && soldWeek > 0) {
            let recent = recentBuy.contains { absDay - $0 <= 7 }
            if !recent { find(2, "unsolicited:\(nt.prefix(40))", "Message says \"\(v)\" but the bot did nothing of the kind this week: \"\(nt)\"", "message creator named by title", "") }
        }
    }

    func statusTransitions() {
        for co in e.state.companies {
            let old = statusSeen[co.id]
            if old != co.status {
                if co.status == .bust, job.policy == .competent { find(2, "competent-bust:\(co.type)", "Company \(co.type) went bust under the competent bot", "CompanyWeek / balance of trade \(co.type)", "year \(e.state.week / 52 + 1)") }
                statusSeen[co.id] = co.status
            }
        }
    }

    func checkWeek() {
        let s = e.state
        let w = s.week
        if PT.env["LEDGER_PT_DEBUG"] != nil {
            for co in s.companies where co.type != "hold" { print("DBG w\(w) \(co.type) \(co.status.rawValue) cash=\(Int(co.cash)) rev=\(Int(co.lastWeekRevenue)) units=\(Int(co.lastWeekUnits)) staff=\(co.staff.count) inv=\(Int(co.inventory)) price=\(co.priceLevel) setup=\(co.status == .setup ? e.openingChecklist(companyID: co.id).filter { !$0.isDone }.map { $0.id }.joined(separator: ",") : "") notes=\(noteLog.suffix(1))") }
        }
        if weekMsgs >= 30 { find(2, "spam-total", "\(weekMsgs) new messages in a single week", "Events / Simulation weekly message sources (see titles file)", "") }
        if weekBad >= 8 { find(2, "spam-bad", "\(weekBad) warn/bad-tone messages in a single week (notice/popup load)", "see titles file for the sources", "") }
        for (t, n) in weekTitles where n >= 3 { find(2, "dup:\(t)", "Same message \"\(t)\" \(n)x in one week", "message source of that title", "") }
        if weekOwnerNew >= 6 { find(2, "owner-flood", "\(weekOwnerNew) new owner-addressed decisions in one week", "see titles file", "") }
        weekOwnerNew = 0
        weekMsgs = 0; weekBad = 0; weekTitles = [:]
        for co in s.companies where co.status.isLive {
            if w % 4 == 0, let p = badNumber(.object(co.raw)) { find(1, "nan-company:\(p.split(separator: ".").first ?? "")", "Non-finite number in company record at \(p)", "Businesses/* writer of that field", "co=\(co.id) \(co.type)") }
            if !co.cash.isFinite { find(1, "nan-cash", "Company cash not finite", "CompanyWeek", "co=\(co.id) \(co.type)") }
            if co.type != "hold", co.cash < -e.context.overdraftRoom(co, s) * 1.2 - 1 { find(3, "cash-below-room:\(co.type)", "Company cash \(Int(co.cash)) is below its overdraft room (money spent that the account could not cover)", "Payments.companyPays / payBills", "co=\(co.id)") }
            if s.cash < -s.overdraftLimit * 1.5 - 1 { find(2, "personal-negative", "Personal cash below the personal overdraft limit (\(Int(s.cash)) vs \(Int(-s.overdraftLimit)))", "Payments / personal spending", "") }
            if co.inventory < -0.01 { find(1, "neg-inventory:\(co.type)", "Negative inventory (\(Int(co.inventory)))", "Businesses/CompanyWeek (stock handling)", "co=\(co.id)") }
            for st in co.staff where st.monthlyWage < 0 { find(1, "neg-wage", "Negative wage on staff \(st.role)", "Employees/Payroll", "co=\(co.id)") }
            for (k, v) in [("reputation", co.reputation), ("quality", co.quality), ("awareness", co.awareness)] where v < -1 || v > 101 {
                find(2, "range:\(k)", "\(k) outside 0..100 (\(Int(v)))", "CompanyWeek", "co=\(co.id) \(co.type)")
            }
            if co.inventory > 0 { everStock.insert(co.id) }
            if co.status == .open, let ow = openedWeek[co.id] {
                let age = w - ow
                let settled = job.policy == .passive ? age >= 6 : (staffedWeek[co.id].map { w - $0 >= 6 } ?? false)
                if job.policy != .passive, staffedWeek[co.id] == nil, age == 12 { find(2, "never-staffed:\(co.type)", "Open company still lacks its standard staff 12 weeks after opening (hire attempts fail: \(hireFails.map { "\($0.key)x\($0.value)" }.joined(separator: ",")) emptysearch \(searchEmpty.map { "\($0.key)x\($0.value)" }.joined(separator: ",")))", "Hiring.search / hireOffer for the trade roles", "co=\(co.id)") }
                if settled, co.value("lastW")["cap"].double <= 0, co.value("lastW")["D"].double > 0 { zeroCapWeeks[co.id, default: 0] += 1; if zeroCapWeeks[co.id] == 6 { let cr = CapacityModel.compute(co, e.data.catalog[co.type]!, World(state: e.state, data: e.data)); let bn = cr.parts.filter { $0.capacity <= 0 }.map { $0.key }.joined(separator: ","); find(2, "zero-capacity:\(co.type):\(bn)", "Open staffed \(co.type) has demand but capacity 0 for 6 weeks; zero-capacity parts: \(bn) (may not be a required opening item)", "Capacity.swift:core (gate/limiting equipment) vs OpeningChecklist.items", "co=\(co.id)") } } else { zeroCapWeeks[co.id] = 0 }
                if settled && co.lastWeekRevenue <= 0 { zeroRevWeeks[co.id, default: 0] += 1 } else { zeroRevWeeks[co.id] = 0 }
                if zeroRevWeeks[co.id] == 8, job.policy != .passive || true { find(2, "zero-revenue:\(co.type)", "Open company earned exactly 0 revenue for 8 weeks in a row", "DailyTrade / Demand for trade \(co.type)", "co=\(co.id) age \(age)w") }
                if age >= 14, co.monthlyHistory.count >= 4, co.monthlyHistory.suffix(3).allSatisfy({ $0.profit == 0 && $0.revenue > 0 }) { find(3, "zero-profit:\(co.type)", "Trading company shows profit of exactly 0 for 3 months", "CompanyWeek book/monthlyHistory", "co=\(co.id)") }
                if everStock.contains(co.id), co.inventory <= 0, co.lastWeekUnits > 0, co.lastWeekRevenue > 0 { find(3, "sells-no-stock:\(co.type)", "Sells units (\(Int(co.lastWeekUnits))) in a week with zero stock on hand", "DailyTrade / stock handling for \(co.type)", "co=\(co.id)") }
            }
            if let ow = managerHired[co.id], co.managerID == nil, w - ow <= 6, w > ow {
                find(2, "manager-quit-at-once", "Manager hired in week \(ow) is gone within 6 weeks", "ManagerModel.hire / quit logic", "co=\(co.id) \(co.type)")
                managerHired[co.id] = nil
            }
        }
        for l in s.loans where l.balance < -0.5 { find(1, "neg-loan", "Loan balance negative", "Finance/Loans", "loan=\(l.id)") }
        let nw = e.netWorth.total
        if !nw.isFinite { find(1, "nan-nw", "Net worth not finite", "Finance/Valuation", "") }
        else {
            if w - lastStructuralWeek > 3, w > 2, abs(nw - lastNW) > max(0.6 * abs(lastNW), cur.scaledPrice(150_000)) {
                find(3, "nw-jump", "Net worth jumped \(Int(lastNW)) -> \(Int(nw)) in one week with no action by the bot", "Valuation.netWorth / company value model", "")
            }
            lastNW = nw
        }
        if s.isGameOver {
            let sev = job.policy == .competent ? 1 : 3
            find(sev, "gameover-\(job.policy.rawValue)", "Game over reached by \(job.policy.rawValue) bot: \(s.gameOver["reason"].string)", "GameOver / Failure.swift / bank checks", "")
        }
        if job.policy == .passive {
            for co in s.companies where co.status == .setup && w - (setupSince[co.id] ?? w) >= 12 { find(3, "passive-setup:\(co.type)", "Company left in setup is never nudged or auto-opened (12 weeks)", "CompanySetup / OpeningChecklist", "co=\(co.id)"); setupSince[co.id] = w }
        }
        recentBuy.removeAll { absDay - $0 > 14 }
    }

    func roundTrip() {
        let before = e.playtestHash
        let dir = NSTemporaryDirectory() + "pt-save-\(job.seed)-\(UInt32.random(in: 0...UInt32.max))"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        do {
            let store = try SaveStore(directory: URL(fileURLWithPath: dir))
            try store.save(e.state, summary: store.summary(of: e.state, trades: e.data.catalog))
            let loaded = try store.load()
            var b = GameEngine(state: loaded, data: e.data, events: e.events, marketing: e.marketing)
            if b.playtestHash != before { find(1, "save-roundtrip-state", "State differs after save+load", "SaveSystem/SaveStore + GameState Codable (a field not persisted)", "") }
            var a = e
            for _ in 0..<28 { a.nextDay(); b.nextDay() }
            if a.playtestHash != b.playtestHash { find(1, "save-roundtrip-diverge", "Game played on after save+load diverges from the original within 4 weeks", "state held outside GameState (caches, transient) or not saved", "") }
        } catch { find(1, "save-roundtrip-error", "Save/load threw: \(error)", "SaveSystem/SaveStore", "") }
    }

    func scenarioSetup() {
        switch job.scenario {
        case .single: mainID = openCompany(trade: job.trade)
        case .multi:
            mainID = openCompany(trade: job.trade)
            for t in ["tutor", "cleaning"] where t != job.trade && e.data.catalog[t] != nil {
                if let n = estimate(t) { e.update { s, _, _ in Ledger.move(&s, .me, n * 1.5, why: "Test capital") } }
                openCompany(trade: t, topUp: false)
            }
        case .chain:
            e.update { s, _, _ in Ledger.move(&s, .me, cur.scaledPrice(5_000_000), why: "Test capital") }
            mainID = openCompany(trade: job.trade)
        case .holding:
            e.update { s, _, _ in Ledger.move(&s, .me, cur.scaledPrice(3_000_000), why: "Test capital") }
            mainID = openCompany(trade: job.trade)
            let b = openCompany(trade: job.trade == "tutor" ? "cleaning" : "tutor", topUp: false)
            if mainID != 0, b != 0 {
                switch e.createHolding(name: nil, companies: [mainID, b]) {
                case .success: structural()
                case .failure(let f): find(2, "holding-create:\(f)", "createHolding failed: \(f)", "HoldingModel / SpecialActions.createHolding", "")
                }
            }
        case .startup:
            e.update { s, _, _ in Ledger.move(&s, .me, cur.scaledPrice(2_000_000), why: "Test capital") }
            mainID = openCompany(trade: job.trade)
        case .rework:
            e.update { s, _, _ in Ledger.move(&s, .me, cur.scaledPrice(3_000_000), why: "Test capital") }
            mainID = openCompany(trade: job.trade)
        case .football:
            e.update { s, _, _ in Ledger.move(&s, .me, cur.scaledPrice(80_000_000), why: "Test capital") }
            let code = e.leagueCountries().first?.code ?? job.country
            switch e.foundClub(countryCode: code, allowRetired: true) {
            case .ok: structural()
            case let why: find(2, "club-found", "foundClub failed: \(why)", "FootballModel.foundClub", "country \(code)")
            }
        }
    }

    func midScenario(week: Int) {
        guard job.policy != .passive else { return }
        switch job.scenario {
        case .chain where [14, 18, 24, 30].contains(week) && mainID != 0:
            guard e.state.company(mainID)?.status == .open else { return }
            if week == 14 { _ = e.applyForChainDocument(companyID: mainID, document: "trademark"); _ = e.applyForChainDocument(companyID: mainID, document: "ops_manual"); return }
            if week == 18 { let r = e.applyForChainDocument(companyID: mainID, document: "chain"); if case .notYet(let w) = r { find(2, "chain-doc-stuck", "Chain registration refused after trademark+manual were applied for 4 weeks earlier: \(w.prefix(80))", "Chains.applyDocument / Documents wait", "") }; return }
            if week == 24 { if e.chainOf(companyID: mainID) == nil { let r = e.applyForChainDocument(companyID: mainID, document: "chain"); if r != .ok && r != .alreadyHeld { find(2, "chain-doc-stuck2", "Chain registration still not possible at week 24: \(r)", "Chains.applyDocument", "") } }; return }
            if let cid = e.makeChain(companyID: mainID, name: "Bot Chain") {
                structural()
                let cities = e.homeCountry.cities.map { $0.id }
                var opened = 0
                for c in cities.prefix(3) {
                    switch e.openLocation(chainID: cid, cityID: c) {
                    case .success: opened += 1
                    case .failure(let err): find(3, "chain-store:\(err)", "openLocation failed: \(err)", "Chains.swift / ChainActions.swift", "city \(c)")
                    }
                }
                if opened == 0 { find(2, "chain-no-store", "Chain made but no store could be opened in any city", "ChainLocationActions.openLocation", "") }
            } else if week == 30 { find(2, "chain-make", "makeChain returned nil at week 30 for an open company after all chain papers were applied for", "Chains.make", "") }
        case .chain where week > 30 && week % 4 == 0:
            for v in e.teamOverview().vacancies where v.needed && (v.chainID != nil || v.companyID != nil) {
                if let cands = e.searchVacancy(v), !cands.isEmpty, let route = e.vacancyRoute(v) {
                    let p = Hiring.bestValue(cands)
                    if let ask = e.hearTheirAsk(post: route.post, companyID: route.companyID, chainID: route.chainID, personID: p.id) {
                        _ = e.hireOffer(post: route.post, companyID: route.companyID, chainID: route.chainID, city: route.city, personID: p.id, monthlyWage: ask * 1.1)
                    }
                }
            }
        case .rework where mainID != 0: reworkWeek(week)
        case .startup where week == 6:
            let r = e.foundStartup(name: nil, sector: "saas", product: "crm", model: "sub", who: "c2", seedMultiple: 1)
            if case .ok = r { structural() } else { find(3, "startup-found", "foundStartup(\(r)) did not succeed", "Startups / VentureActions", "") }
        default: break
        }
    }

    func reworkWeek(_ w: Int) {
        guard let co = e.state.company(mainID), co.status == .open else { return }
        let routes = ["private", "broker", "auction", "mbo", "stake"]
        if w == 12, co.managerID == nil, let c = e.searchManagers(companyID: mainID), let p = c.first {
            if e.hireManager(personID: p.id, companyID: mainID, monthlyWage: p.askingMonthlyWage * 1.3) == .ok { managerHired[mainID] = w; structural() }
        }
        if w >= 16 && w % 4 == 0 && w < 40 {
            for c in e.ownerCounterparts(companyID: mainID) {
                let topics = e.ownerTopics(companyID: mainID, personID: c.id).filter { $0.waitWeeks == 0 }
                guard let t = topics.first, let sc = e.ownerScene(companyID: mainID, personID: c.id, topic: t.id), !sc.choices.isEmpty else { continue }
                let ch = sc.choices[(w / 4 + job.seed) % sc.choices.count]
                if e.ownerChoose(companyID: mainID, personID: c.id, topic: t.id, choice: ch.id) == nil { find(1, "owner-meeting-nil:\(c.position)/\(t.id)", "ownerChoose returned nil for a scene the screen just showed", "OwnerMeetings.choose", "") } else { meetings += 1; structural() }
            }
        }
        if w == 32, job.seed % 2 == 0, co.managerID != nil {
            let r = e.proposeCEOChange(companyID: mainID)
            if r != .dismissed { find(2, "ceo-change-solo", "A sole owner's CEO replacement was not carried out: \(r)", "ManagerBoards.proposeCEOChange", "") }
            structural()
        }
        if w == 40 {
            saleRoute = routes[job.seed % routes.count]; saleStartWeek = w
            let v = CompanySale.estimatedValue(e.state, companyID: mainID, data: e.data)
            let ok: Bool
            switch saleRoute {
            case "auction": ok = e.startAuction(companyID: mainID, reserve: max(1, v * 0.3))
            case "stake": ok = e.startSale(companyID: mainID, route: "private", percent: 25)
            case "mbo": ok = co.managerID == nil ? true : e.startSale(companyID: mainID, route: "mbo")
            default: ok = e.startSale(companyID: mainID, route: saleRoute)
            }
            if !ok { find(2, "sale-start:\(saleRoute)", "Sale route \(saleRoute) refused for an open trading company: \(e.saleRoutes(companyID: mainID).first { $0.id == (saleRoute == "stake" ? "stake" : saleRoute) }?.why ?? "")", "SaleListings.routeProblem", "") }
            structural()
        }
    }

    func saleWeek() {
        guard job.scenario == .rework, saleStartWeek > 0, soldWeek == 0, let l = e.saleListing(companyID: mainID) else {
            if job.scenario == .rework, soldWeek > 0, e.state.week == soldWeek + 4 { checkAfterSale() }
            return
        }
        let w = e.state.week
        if saleRoute == "auction", l.round < 3, w - saleStartWeek < 6 { return }
        guard let best = l.offers.max(by: { $0.price < $1.price }) else {
            if w - saleStartWeek > 70 { find(3, "sale-no-offer:\(saleRoute)", "No offer in 70 weeks on route \(saleRoute)", "CompanySale.weekly", ""); soldWeek = -1 }
            return
        }
        let nw0 = e.netWorth.total
        let stakeSale = saleRoute == "stake"
        let got = saleRoute == "auction" ? e.hammerSale(companyID: mainID) : e.acceptBuyerOffer(companyID: mainID, offerID: best.id)
        structural(); bought()
        guard let got, got > 0 else { find(1, "sale-accept-failed:\(saleRoute)", "Accepting the best offer on route \(saleRoute) returned nothing", "CompanySale.accept", ""); return }
        soldWeek = w
        let st = e.state.company(mainID)?.status
        if stakeSale { if st != .open { find(1, "stake-sold-whole", "A stake sale changed the company's status to \(String(describing: st))", "CompanySale.sellPart", "") } }
        else if st != .sold { find(1, "sale-not-sold:\(saleRoute)", "Company status after the sale is \(String(describing: st))", "CompanySale.complete", "") }
        if e.saleListing(companyID: mainID) != nil { find(1, "listing-stays", "Listing stays after a completed sale on route \(saleRoute)", "CompanySale.accept/withdraw", "") }
        let nw1 = e.netWorth.total
        if abs(nw1 - nw0) > max(cur.scaledPrice(500_000), 0.6 * abs(nw0)) { find(3, "sale-nw:\(saleRoute)", "Net worth moved \(Int(nw0)) -> \(Int(nw1)) by a sale of \(Int(got))", "Valuation vs CompanySale price", "") }
    }

    func checkAfterSale() {
        let open = e.openDecisions.filter { $0.companyID == mainID }
        if !open.isEmpty, e.state.company(mainID)?.status == .sold { find(2, "sold-open-decisions", "Decisions about a sold company stay open: \"\(open[0].title.prefix(50))\"", "CompanySale.complete (closes open messages) / later producers", "") }
    }

    func run() -> RunResult {
        var r = RunResult()
        scenarioSetup()
        lastNW = e.netWorth.total
        let days = job.years * 364
        for d in 0..<days {
            if d % 7 == 0 || job.policy != .passive { answerAll() }
            let out = e.nextDay()
            checkDay(out)
            if out.completedWeek {
                let w = e.state.week
                checkWeek()
                saleWeek()
                tend()
                midScenario(week: w)
                if w == 26 || w == 90 { roundTrip() }
            }
            if e.state.isGameOver { r.gameOver = true; r.note = e.state.gameOver["reason"].string; break }
        }
        if !openedEver && job.scenario != .football && job.policy != .passive || (job.policy == .passive && !openedEver) {
            find(1, "never-opened:\(job.trade)", "Company of trade \(job.trade) never opened in \(job.years) years", "CompanySetup / OpeningChecklist", noteLog.suffix(2).joined(separator: ";"))
        }
        r.hash = e.playtestHash; r.nw = e.netWorth.total; r.weeks = e.state.week
        if rescues >= 4 { find(3, "needs-rescue:\(job.trade)", "Competent bot had to be rescued with outside cash \(rescues) times: \(job.trade) loses money from the start-up funds (balance)", "Balance of trade \(job.trade)", "rescues=\(rescues)") }
        let cos = e.state.companies.filter { $0.type != "hold" }
        F.runLine("\(job.name)\t\(r.gameOver ? "OVER" : "ok")\tnw=\(Int(r.nw / max(1, cur.rate)))\tcos=\(cos.map { "\($0.type):\($0.status.rawValue)" }.joined(separator: ","))\tanswered=\(answered)\t\(r.hash)")
        return r
    }
}
