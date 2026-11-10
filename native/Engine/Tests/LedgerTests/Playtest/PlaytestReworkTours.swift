import XCTest
import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses
import SaveSystem
@testable import Events
@testable import Simulation

final class PlaytestReworkTours: XCTestCase {
    var tour = ""
    var cur: Currency!
    var maxOwnerNew = 0
    var stress = false

    override func setUpWithError() throws { try XCTSkipUnless(PT.enabled, "set LEDGER_PLAYTEST=1") }
    override func tearDown() { Findings.shared.flush(tag: PT.tag + "-rework") }

    func find(_ sev: Int, _ what: String, _ detail: String = "", line: UInt = #line) {
        Findings.shared.add(sev, "rework:\(tour):\(what)", "TOUR \(tour): \(what)", repro: "LEDGER_PLAYTEST=1 swift test --filter PlaytestReworkTours/test\(tour)", file: "see PlaytestReworkTours.swift line \(line)", detail: detail)
    }
    func ex(_ cond: @autoclosure () -> Bool, _ msg: String, sev: Int = 2, line: UInt = #line) {
        if !cond() { find(sev, msg, line: line); XCTFail("\(tour): \(msg)", line: line) }
    }

    func fixture(_ trade: String = "cafe", manager: Bool = false, accountant: Bool = false, weeks: Int = 10, seed: Int = 5) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tour", seed: seed)
        cur = e.homeCurrency
        e.update { s, _, _ in Ledger.move(&s, .me, cur.scaledPrice(60_000_000), why: "Test capital") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, fundWith: cur.scaledPrice(12_000_000), quickSetup: true) else {
            throw XCTSkip("cannot start \(trade)")
        }
        for _ in 0..<(40 * 7) {
            if e.state.company(id)?.status == .open { break }
            if e.state.day == 0 || e.state.day == 6 {
                _ = e.quickSetupWithinBudget(companyID: id)
                for it in e.openingChecklist(companyID: id) where !it.isDone {
                    if ["rejected", "lapsed", ""].contains(e.documentState(companyID: id, document: it.id).status) { _ = e.applyForDocument(companyID: id, documentID: it.id) }
                }
                _ = e.openCompany(companyID: id)
            }
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            e.nextDay()
        }
        if accountant { e.update { s, d, _ in CompanySetup.chooseAccountant(&s, companyID: id, accountantID: nil, data: d) } }
        else { e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].raw["acc"] = .null; s.companies[i].staff.removeAll { $0.role == "acct" } } } }
        if manager { hireManager(&e, id) }
        run(&e, weeks: weeks)
        return (e, id)
    }

    @discardableResult
    func hireManager(_ e: inout GameEngine, _ id: Int) -> Int? {
        guard let c = e.searchManagers(companyID: id), let p = c.first else { find(2, "manager search empty"); return nil }
        let r = e.hireManager(personID: p.id, companyID: id, monthlyWage: p.askingMonthlyWage * 1.3)
        if r != .ok { find(2, "hireManager at 1.3x ask refused: \(r)"); return nil }
        return p.id
    }

    @discardableResult
    func hireHead(_ e: inout GameEngine, _ id: Int, _ key: String) -> Int? {
        guard let c = e.searchTeam(companyID: id, key: key), let p = c.first else { find(3, "team search \(key) empty"); return nil }
        let r = e.hireTeam(companyID: id, key: key, personID: p.id, monthlyWage: p.askingMonthlyWage * 1.3)
        if r != .ok { find(3, "hireTeam \(key) refused: \(r)"); return nil }
        return p.id
    }

    func coOwn(_ e: inout GameEngine, _ id: Int, owner pct: Double) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            let out = 100 - pct
            let total = CapTable.table(s.companies[i]).total
            _ = CapTable.issue(&s, i, newShares: CapTable.sharesForPercent(out * 0.55, total: total), to: "Ann Partner", paid: 1, extra: ["k27": "growth", "sat": 60])
            _ = CapTable.issue(&s, i, newShares: CapTable.sharesForPercent(out * 0.45, total: CapTable.table(s.companies[i]).total), to: "Bo Capital", paid: 1, extra: ["k27": "div", "sat": 60])
        }
    }

    func history(_ e: inout GameEngine, _ id: Int, profit: Double) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].monthlyHistory = (0..<6).map { MonthRecord(monthIndex: $0, revenue: 40_000, profit: profit, cash: 10_000) }
        }
    }

    @discardableResult
    func run(_ e: inout GameEngine, weeks: Int, answer: Bool = true, extraDaily: ((GameEngine) -> Void)? = nil) -> [Message] {
        var all: [Message] = []
        var ownerNew = 0
        for _ in 0..<(weeks * 7) {
            if answer { for m in e.openDecisions where !m.options.isEmpty { e.answer(messageID: m.id, option: safeOption(m)) } }
            let out = e.nextDay()
            all += out.newMessages
            check(e, out, &ownerNew)
            extraDaily?(e)
            if out.completedWeek {
                if ownerNew > maxOwnerNew { maxOwnerNew = ownerNew }
                if ownerNew >= 6 { find(2, "owner flooded: \(ownerNew) new owner-addressed decisions in one week", "week \(e.state.week)") }
                ownerNew = 0
            }
            if e.state.isGameOver { break }
        }
        return all
    }

    func safeOption(_ m: Message) -> Int {
        let bad = ["sale", "sell", "close", "dismiss", "fire", "replace", "let go", "shut"]
        return m.options.indices.first { i in let l = m.options[i]["l"].string.lowercased(); return !bad.contains { l.contains($0) } } ?? 0
    }

    func check(_ e: GameEngine, _ out: GameEngine.DayOutcome, _ ownerNew: inout Int) {
        let s = e.state
        let g = Ledger.gaps(s)
        if !g.isEmpty { find(1, "ledger gap: \(g.map { "\($0.holder)=\(Int($0.difference))" }.joined(separator: ",").prefix(80))", "week \(s.week)") }
        if s.cash < -s.overdraftLimit - 1 { find(2, "personal cash below the personal overdraft limit (\(Int(s.cash)))", "week \(s.week)") }
        for co in s.companies where co.status.isLive && co.type != "hold" && co.cash < -e.context.overdraftRoom(co, s) * 1.2 - 1 && !stress { find(2, "company cash below its overdraft room (\(co.type))", "week \(s.week) \(Int(co.cash))") }
        var seen = Set<String>()
        for m in out.newMessages {
            let key = "\(m.companyID)|\(m.title)|\(m.body)"
            if !seen.insert(key).inserted { find(2, "duplicate message today: \(normTitle(m.title, names: s.companies.map { $0.name }))") }
            let isDecision = (m.kind == "ask" || m.kind == "decision") && m.status == "open"
            if isDecision && m.isOwnerAddressed { ownerNew += 1 }
            if isDecision && !m.isOwnerAddressed { find(3, "open decision addressed to a desk, not the owner: \(normTitle(m.title, names: s.companies.map { $0.name }))") }
            if !m.isOwnerAddressed && m.handledBy.isEmpty && m.status == "done" { find(3, "desk notice with nobody shown as handling it: \(normTitle(m.title, names: s.companies.map { $0.name }))") }
            if m.sev > 4 || m.sev < 0 { find(2, "severity out of range \(m.sev)") }
        }
        var open = Set<String>()
        for m in s.inbox where m.status == "open" {
            let key = "\(m.companyID)|\(m.title)"
            if !open.insert(key).inserted && !m.title.isEmpty { find(2, "two identical open decisions: \(normTitle(m.title, names: s.companies.map { $0.name }))") }
        }
    }

    func saves(_ e: GameEngine, _ what: String) {
        let before = e.playtestHash
        let dir = NSTemporaryDirectory() + "pt-rw-\(UInt32.random(in: 0...UInt32.max))"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        do {
            let store = try SaveStore(directory: URL(fileURLWithPath: dir))
            try store.save(e.state, summary: store.summary(of: e.state, trades: e.data.catalog))
            var b = GameEngine(state: try store.load(), data: e.data, events: e.events, marketing: e.marketing)
            if b.playtestHash != before { find(1, "save round trip differs: \(what)") }
            var a = e
            for _ in 0..<28 { a.nextDay(); b.nextDay() }
            if a.playtestHash != b.playtestHash { find(1, "save round trip diverges after 4 weeks: \(what)") }
        } catch { find(1, "save round trip threw \(error): \(what)") }
    }

    func testOwnerMeetings() throws {
        tour = "OwnerMeetings"
        var (e, id) = try fixture(manager: true, accountant: true, weeks: 12)
        for k in ["fin", "sales", "hr", "ops"] { hireHead(&e, id, k) }
        run(&e, weeks: 2)
        let who = e.ownerCounterparts(companyID: id)
        let positions = Set(who.map { $0.position })
        ex(positions.contains("ceo"), "a hired manager shows as the CEO counterpart")
        for k in ["fin", "sales", "hr", "ops"] where !positions.contains(k) { find(2, "hired \(k) head is not a meeting counterpart") }
        for c in who where c.position != "ceo" { ex(e.ownerTopics(companyID: id, personID: c.id).isEmpty, "\(c.position) holds no talk of their own") }
        guard let ceo = who.first(where: { $0.position == "ceo" }), let sc = e.ownerScene(companyID: id, personID: ceo.id, topic: "review") else { return find(1, "the CEO has no review scene") }
        ex(!sc.lines.isEmpty, "the review has lines")
        for l in sc.lines where l.isEmpty || l.contains("{") || l.contains("NaN") || l.contains("inf ") || l.contains("nil") || l.contains("Optional") { find(2, "review has unclean text", l) }
        ex(sc.choices.allSatisfy { !$0.preview.isEmpty && !$0.label.isEmpty }, "review choices show a preview")
        var choicesRun = 0
        for ch in sc.choices {
            var f = e
            guard let o = f.ownerChoose(companyID: id, personID: ceo.id, topic: "review", choice: ch.id) else { find(1, "review choice \(ch.id) returns nil"); continue }
            choicesRun += 1
            ex(!o.text.isEmpty && ["good", "bad", "n"].contains(o.tone), "outcome text and tone for \(ch.id) (tone \(o.tone))")
            ex(Ledger.gaps(f.state).isEmpty, "ledger after \(ch.id)", sev: 1)
            run(&f, weeks: 3)
            ex(f.state.company(id) != nil, "company still exists after \(ch.id)", sev: 1)
        }
        ex(choicesRun == sc.choices.count && choicesRun >= 7, "every choice of the review plays (\(choicesRun))", sev: 3)
        if let ch = sc.choices.first {
            _ = e.ownerChoose(companyID: id, personID: ceo.id, topic: "review", choice: ch.id)
            let h = e.playtestHash
            let again = e.ownerChoose(companyID: id, personID: ceo.id, topic: "review", choice: ch.id)
            ex(again != nil && again!.text.contains("this quarter") && e.playtestHash == h, "a repeated pick inside the quarter changes nothing")
        }
        run(&e, weeks: OwnerMeetings.cooldownWeeks + 1)
        ex(e.ownerTopics(companyID: id, personID: ceo.id).allSatisfy { $0.waitWeeks == 0 }, "the review opens again after \(OwnerMeetings.cooldownWeeks) weeks")
        ex(e.ownerChoose(companyID: id, personID: 999_999, topic: "review", choice: "dir:lean") == nil, "a person who is not at the company cannot be met")
        saves(e, "after meetings")
    }

    func testSoleOwnerAdvisoryRound() throws {
        tour = "AdvisoryRound"
        var (e, id) = try fixture(manager: true, accountant: true, weeks: 12)
        for k in ["fin", "sales", "hr", "ops"] { hireHead(&e, id, k) }
        run(&e, weeks: 1)
        ex(e.boardIsAdvisory(companyID: id), "a sole owner's board is advisory")
        let round = e.boardRound(companyID: id)
        let who = e.ownerCounterparts(companyID: id)
        ex(round.count == who.count, "every position speaks in the round (\(round.count) of \(who.count))")
        ex(round.allSatisfy { !$0.text.isEmpty }, "round lines are not empty")
        for kind in ["sell", "close", "loan", "ceo"] {
            let v = e.advisoryVote(kind: kind, companyID: id, amount: cur.scaledPrice(100_000))
            ex(!v.active && v.passes, "sole owner decides alone on \(kind) (active=\(v.active) passes=\(v.passes))")
            ex(!v.advice.isEmpty, "advice is given on \(kind)")
            ex(v.board.isEmpty, "no binding board lines for a sole owner on \(kind)")
            let titles = Set(v.advice.map { $0.title })
            ex(titles.count >= 3, "advice on \(kind) comes from several positions (\(titles.count))", sev: 3)
        }
        ex(e.ceoVote(companyID: id).owners.count == 1, "only the owner is in the owners column for a sole-owner company")
    }

    func testCeoVoteSoleOwner() throws {
        tour = "CeoVoteSolo"
        var (e, id) = try fixture(manager: true, accountant: true, weeks: 10)
        let mgr = e.state.company(id)?.managerID
        ex(mgr != nil, "company has a manager to replace")
        let cash0 = e.state.cash + (e.state.company(id)?.cash ?? 0)
        let r = e.proposeCEOChange(companyID: id)
        ex(r == .dismissed, "a sole owner replaces the CEO alone (\(r))")
        ex(e.state.company(id)?.managerID == nil, "manager is gone after dismissal")
        ex(!e.ownerCounterparts(companyID: id).contains { $0.id == mgr }, "dismissed CEO is no longer a counterpart")
        ex(e.state.cash + (e.state.company(id)?.cash ?? 0) <= cash0 + 1, "dismissal does not create money")
        let r2 = e.proposeCEOChange(companyID: id)
        if case .refused = r2 {} else { ex(false, "a second proposal with nobody to replace is refused (\(r2))") }
        let told = run(&e, weeks: 8)
        ex(!told.contains { $0.title.contains("manager has left") }, "after the owner replaces the CEO on purpose there is no \"manager has left\" emergency")
        hireManager(&e, id)
        run(&e, weeks: 4)
        ex(e.proposeCEOChange(companyID: id) == .dismissed, "the next CEO can be replaced too")
        saves(e, "after dismissals")
    }

    func testCeoVoteMajorityOwner() throws {
        tour = "CeoVoteMajority"
        var (e, id) = try fixture(manager: true, accountant: true, weeks: 10)
        coOwn(&e, id, owner: 60)
        history(&e, id, profit: 5_000)
        let own = e.state.company(id)?.ownership ?? 0
        ex(own > 50, "owner keeps a majority after issuing shares (\(Int(own))%)")
        let v = e.ceoVote(companyID: id)
        ex(v.active, "a co-owned company has a binding board")
        ex(v.decidingOwner != nil, "a majority owner is named as the deciding owner")
        ex(v.passes, "the majority owner's yes passes")
        let r = e.proposeCEOChange(companyID: id)
        ex(r == .dismissed, "the majority owner dismisses against co-owners who say no (\(r))")
        ex(e.state.company(id)?.managerID == nil, "manager gone")
        run(&e, weeks: 6)
    }

    func testCeoVoteMinorityFailedAndBlock() throws {
        tour = "CeoVoteMinority"
        var (e, id) = try fixture(manager: true, accountant: true, weeks: 10)
        coOwn(&e, id, owner: 25)
        history(&e, id, profit: 6_000)
        let own = e.state.company(id)?.ownership ?? 100
        ex(own < 50, "owner is a minority (\(Int(own))%)")
        var failedAt: Int?
        for _ in 0..<12 {
            let v = e.ceoVote(companyID: id)
            if !v.passes {
                var f = e
                let m0 = f.state.company(id).map { $0.value("mood").isNull ? 60 : $0.value("mood").double } ?? 60
                let r = f.proposeCEOChange(companyID: id)
                guard case .voteFailed(let pct) = r else { ex(false, "predicted failing vote returns voteFailed (got \(r))"); break }
                ex(pct < 50, "voteFailed reports a minority yes share (\(pct))")
                ex(f.state.company(id)?.managerID != nil, "the CEO stays after a failed vote")
                let m1 = f.state.company(id).map { $0.value("mood").isNull ? 60 : $0.value("mood").double } ?? 60
                ex(m1 < m0, "a failed vote costs the CEO's mood")
                failedAt = f.state.week
                for w in 0..<8 {
                    let r2 = f.proposeCEOChange(companyID: id)
                    if case .blocked(let wk) = r2 { ex(wk == 8 - w, "block shows \(8 - w) weeks left (got \(wk))") }
                    else { ex(false, "proposal \(w) weeks after a failed vote is blocked (got \(r2))") }
                    run(&f, weeks: 1)
                }
                let r3 = f.proposeCEOChange(companyID: id)
                if case .blocked = r3 { ex(false, "the block ends after eight weeks (still \(r3))") }
                ex(Ledger.gaps(f.state).isEmpty, "ledger after failed vote", sev: 1)
                saves(f, "after a failed vote")
                break
            }
            run(&e, weeks: 1)
        }
        ex(failedAt != nil, "co-owners with a profitable company vote the replacement down within 12 weeks", sev: 3)
        history(&e, id, profit: -6_000)
        var passed = false
        for _ in 0..<8 { if e.ceoVote(companyID: id).passes { let r = e.proposeCEOChange(companyID: id); passed = (r == .dismissed); break }; run(&e, weeks: 1) }
        ex(passed, "co-owners agree to replace the CEO of a company that loses money", sev: 3)
    }

    func waitForOffer(_ e: inout GameEngine, _ id: Int, weeks: Int = 40) -> CompanySale.Offer? {
        for _ in 0..<weeks {
            if let o = e.saleListing(companyID: id)?.offers.first { return o }
            run(&e, weeks: 1)
            if e.saleListing(companyID: id) == nil { return nil }
        }
        return e.saleListing(companyID: id)?.offers.first
    }

    func netBook(_ e: GameEngine, _ id: Int) -> Double { e.state.cash }

    func soldClean(_ e: GameEngine, _ id: Int, _ what: String) {
        ex(e.state.company(id)?.status == .sold, "\(what): company is marked sold (\(e.state.company(id)?.status.rawValue ?? "nil"))")
        ex(e.saleListing(companyID: id) == nil, "\(what): listing is gone after the sale")
        ex(Ledger.gaps(e.state).isEmpty, "\(what): ledger consistent after the sale", sev: 1)
    }

    func testSaleRoutesList() throws {
        tour = "SaleRoutesList"
        let (e, id) = try fixture(manager: true, accountant: true, weeks: 14)
        let routes = e.saleRoutes(companyID: id)
        let ids = Set(routes.map { $0.id })
        for want in ["private", "broker", "auction", "mbo", "merger", "group", "stake", "ipo", "franchise"] { ex(ids.contains(want), "route \(want) is listed") }
        for r in routes { ex(r.available || !r.why.isEmpty, "shut route \(r.id) always says why") ; ex(!r.available || r.why.isEmpty, "open route \(r.id) has no refusal text") }
        let ipo = routes.first { $0.id == "ipo" }
        ex(ipo?.available == false && (ipo?.why.lowercased().contains("holding") ?? false), "IPO refusal for a plain company names the holding rule (\(ipo?.why ?? "-"))")
        let tiers = e.stakeTiers(companyID: id)
        ex(tiers.map { $0.pct } == [10, 25, 34, 49], "stake tiers are 10/25/34/49")
        for t in tiers { ex(abs(t.buyerPoints + t.youKeep - (e.state.company(id)?.ownership ?? 100)) < 0.01, "tier \(t.pct): buyer points + what you keep = your ownership") }
        for t in tiers {
            var f = e
            let started = f.startSale(companyID: id, route: "private", percent: t.pct)
            ex(started == t.allowed, "tier \(t.pct): allowed flag (\(t.allowed)) agrees with startSale (\(started))")
        }
    }

    func testSaleHandshakeAndBroker() throws {
        tour = "SaleHandshakeBroker"
        for route in ["private", "broker"] {
            var (e, id) = try fixture(manager: true, accountant: true, weeks: 16, seed: seedOffset(route))
            guard e.startSale(companyID: id, route: route) else { find(2, "\(route): startSale refused for an open trading company"); continue }
            ex(e.saleListing(companyID: id)?.route == route, "\(route): listing carries its route")
            ex(!e.startSale(companyID: id, route: route), "\(route): a second listing of the same company is refused")
            guard let off = waitForOffer(&e, id) else { find(2, "\(route): no offer in 40 weeks"); continue }
            ex(off.price > 0 && off.expiresWeek > e.state.week - 1, "\(route): offer has a price and a future expiry")
            var f = e
            f.askBuyer(companyID: id, offerID: off.id, question: "staff")
            f.askBuyer(companyID: id, offerID: off.id, question: "payment")
            let low = f.counterBuyer(companyID: id, offerID: off.id, price: off.price * 0.9)
            ex(low != CompanySale.TalkResult.refused, "\(route): a counter below the offer is not refused (\(low))", sev: 3)
            let nw0 = netBook(e, id)
            let got = e.acceptBuyerOffer(companyID: id, offerID: off.id)
            ex(got != nil && got! > 0, "\(route): accept pays out (\(String(describing: got)))")
            soldClean(e, id, route)
            ex(netBook(e, id) > nw0, "\(route): the owner has more personal money after the sale")
            run(&e, weeks: 10)
            let open = e.openDecisions.filter { $0.companyID == id }
            ex(open.isEmpty, "\(route): nothing stays open for a sold company (\(open.map { $0.title }.prefix(2)))")
            saves(e, "after \(route) sale")
        }
        var (e, id) = try fixture(manager: true, accountant: true, weeks: 16)
        _ = e.startSale(companyID: id, route: "private")
        if let off = waitForOffer(&e, id) {
            e.declineSaleOffer(companyID: id, offerID: off.id)
            ex(!(e.saleListing(companyID: id)?.offers.contains { $0.id == off.id } ?? false), "declined offer is removed")
            ex(e.acceptBuyerOffer(companyID: id, offerID: off.id) == nil, "a declined offer cannot be accepted")
        }
        run(&e, weeks: 8)
        for o in e.saleListing(companyID: id)?.offers ?? [] { ex(o.expiresWeek > e.state.week, "no offer outlives its expiry (\(o.expiresWeek) vs \(e.state.week))") }
        if let l = e.saleListing(companyID: id) { ex(l.offers.count <= 4, "at most four offers at once (\(l.offers.count))") }
    }

    func seedOffset(_ s: String) -> Int { s == "broker" ? 9 : 5 }

    func testSaleAuction() throws {
        tour = "SaleAuction"
        var (e, id) = try fixture(manager: true, accountant: true, weeks: 16)
        let v = CompanySale.estimatedValue(e.state, companyID: id, data: e.data)
        ex(!e.startAuction(companyID: id, reserve: 0), "reserve 0 is refused")
        guard e.startAuction(companyID: id, reserve: v * 0.3) else { return find(2, "startAuction refused for an open company") }
        var l = e.saleListing(companyID: id)!
        ex(l.round == 1 && l.offers.count >= 3, "round 1 brings at least three named bids (\(l.offers.count))")
        ex(Set(l.offers.map { $0.buyer }).count == l.offers.count, "bidders have distinct names")
        ex(l.offers.allSatisfy { $0.price >= l.reserve }, "bids start at the reserve or higher")
        do { var f = e; let n0 = netBook(f, id); let got = f.hammerSale(companyID: id); ex(got != nil && got! > 0 && netBook(f, id) > n0, "hammer in round 1 sells"); soldClean(f, id, "hammer r1") }
        var best: [Double] = [l.offers.map { $0.price }.max() ?? 0]
        var counts = [l.offers.count]
        for _ in 0..<2 {
            run(&e, weeks: 1)
            guard let nl = e.saleListing(companyID: id) else { break }
            l = nl
            best.append(l.offers.map { $0.price }.max() ?? 0); counts.append(l.offers.count)
        }
        ex(counts.last! <= counts.first!, "bidders drop out, they do not multiply (\(counts))")
        ex(l.round <= 3, "no more than three rounds (\(l.round))")
        let n0 = netBook(e, id)
        let got = e.hammerSale(companyID: id)
        ex(got != nil && netBook(e, id) > n0, "hammer after waiting sells (got \(String(describing: got)))")
        soldClean(e, id, "hammer after wait")
        let fee = (got ?? 0)
        ex(fee > 0, "auction proceeds positive")
        run(&e, weeks: 6)
        saves(e, "after auction")
        var (g, gid) = try fixture(manager: true, accountant: true, weeks: 16, seed: 8)
        let gv = CompanySale.estimatedValue(g.state, companyID: gid, data: g.data)
        _ = g.startAuction(companyID: gid, reserve: gv * 0.3)
        run(&g, weeks: 12)
        ex(g.saleListing(companyID: gid) == nil, "an unattended auction does not stay listed after 12 weeks")
        var (h, hid) = try fixture(manager: true, accountant: true, weeks: 16, seed: 9)
        _ = h.startAuction(companyID: hid, reserve: gv * 50)
        let hh = h.playtestHash
        ex(h.hammerSale(companyID: hid) == nil && h.playtestHash == hh, "hammer with no bids over the reserve does nothing")
        var (k, kid) = try fixture(manager: true, accountant: true, weeks: 16, seed: 10)
        let own0 = k.state.company(kid)?.ownership ?? 100
        if k.startAuction(companyID: kid, reserve: gv * 0.05, percent: 25) {
            let got = k.hammerSale(companyID: kid)
            ex(got != nil, "a 25% stake auction can be hammered")
            ex((k.state.company(kid)?.ownership ?? own0) < own0 && k.state.company(kid)?.status == .open, "a stake auction lowers ownership and keeps the company")
            ex(Ledger.gaps(k.state).isEmpty, "ledger after a stake auction", sev: 1)
        } else { find(3, "startAuction for a 25% stake refused") }
    }

    func testSaleBuyout() throws {
        tour = "SaleBuyout"
        var (e0, id0) = try fixture(manager: false, accountant: true, weeks: 14)
        ex(!e0.startSale(companyID: id0, route: "mbo"), "a management buyout without a manager is refused")
        ex(e0.saleRoutes(companyID: id0).first { $0.id == "mbo" }?.why.isEmpty == false, "the buyout route says why it is shut without a manager")
        var (e, id) = try fixture(manager: true, accountant: true, weeks: 14)
        guard e.startSale(companyID: id, route: "mbo") else { return find(2, "mbo startSale refused with a manager") }
        guard let off = waitForOffer(&e, id, weeks: 60) else { return find(2, "no buyout offer from the manager in 60 weeks") }
        ex(off.kind == "mbo" && off.buyer.contains("manager"), "the only bidder is the manager (\(off.buyer))")
        let nw0 = netBook(e, id)
        let got = e.acceptBuyerOffer(companyID: id, offerID: off.id)
        ex(got != nil, "buyout accepted")
        soldClean(e, id, "mbo")
        let paidNow = netBook(e, id) - nw0
        let owed = (e.state.rest["deferred"]?.array ?? []).reduce(0.0) { $0 + $1["amt"].double }
        ex(owed > 0, "a third is deferred over two years (owed \(Int(owed)))")
        ex(paidNow > 0, "some of the price arrives at once")
        let nw1 = netBook(e, id)
        run(&e, weeks: 110)
        ex(netBook(e, id) > nw1, "the deferred money is paid in the following two years")
        ex((e.state.rest["deferred"]?.array ?? []).isEmpty, "no deferred payment is left after two years")
        saves(e, "after buyout")
    }

    func testSaleMerger() throws {
        tour = "SaleMerger"
        var (e, id) = try fixture(manager: true, accountant: true, weeks: 20)
        let cands = e.mergeCandidates(companyID: id)
        guard let c = cands.first else { return find(3, "no merge candidate after 30 weeks in a city market") }
        let own0 = e.state.company(id)?.ownership ?? 100
        let res = e.mergeWithRival(companyID: id, rivalID: c.id, percent: 30)
        ex(res == .merged, "a 30% merge is certain (\(res))")
        ex((e.state.company(id)?.ownership ?? 100) < own0, "the merge dilutes the owner")
        ex(!e.mergeCandidates(companyID: id).contains { $0.id == c.id }, "a merged rival is no longer a candidate")
        ex(e.mergeWithRival(companyID: id, rivalID: c.id, percent: 30) != .merged, "the same rival cannot merge twice")
        run(&e, weeks: 10)
        saves(e, "after merger")
        var (f, fid) = try fixture(manager: true, accountant: true, weeks: 20, seed: 11)
        if let c2 = f.mergeCandidates(companyID: fid).first {
            var tries = 0
            while tries < 10, f.mergeWithRival(companyID: fid, rivalID: c2.id, percent: 15) == .declined { tries += 1; run(&f, weeks: 1) }
            ex(tries < 10, "a 15% merge offer is accepted within ten weekly tries (\(tries))", sev: 3)
        }
    }

    func testSaleStakes() throws {
        tour = "SaleStakes"
        for pct in [10, 25, 34, 49] {
            var (e, id) = try fixture(manager: true, accountant: true, weeks: 16, seed: 20 + pct)
            let tier = e.stakeTiers(companyID: id).first { $0.pct == pct }!
            guard e.startSale(companyID: id, route: "private", percent: pct) else { find(2, "stake \(pct)% startSale refused although tier allowed=\(tier.allowed)"); continue }
            ex(e.saleListing(companyID: id)?.pct == pct, "stake \(pct)%: listing carries the percent")
            guard let off = waitForOffer(&e, id, weeks: 60) else { find(3, "stake \(pct)%: no offer in 60 weeks"); continue }
            let own0 = e.state.company(id)?.ownership ?? 100
            let nw0 = netBook(e, id)
            let got = e.acceptBuyerOffer(companyID: id, offerID: off.id)
            ex(got != nil, "stake \(pct)%: accepted")
            let own1 = e.state.company(id)?.ownership ?? 100
            let drop: Double = own0 - own1
            ex(abs(drop - tier.buyerPoints) < 0.6, "stake \(pct)%: ownership falls by the tier's buyer points (\(own0)->\(own1), expected -\(tier.buyerPoints))")
            ex(e.state.company(id)?.status == .open, "stake \(pct)%: the company stays open and yours")
            ex(netBook(e, id) > nw0, "stake \(pct)%: cash comes to the owner")
            ex(Ledger.gaps(e.state).isEmpty, "stake \(pct)%: ledger after sale", sev: 1)
            ex(e.saleListing(companyID: id) == nil, "stake \(pct)%: listing is closed")
            run(&e, weeks: 6)
            ex(!e.boardIsAdvisory(companyID: id), "stake \(pct)%: with a co-owner the board is no longer advisory")
            let t2 = e.stakeTiers(companyID: id)
            ex(t2.allSatisfy { $0.youKeep >= 0 }, "stake \(pct)%: nothing negative is kept after a second look")
            saves(e, "after \(pct)% stake")
        }
    }

    func testSaleGroupAndMaster() throws {
        tour = "SaleGroupMaster"
        var (e, id) = try fixture(manager: true, accountant: true, weeks: 40)
        let buyers = e.groupBuyers(companyID: id)
        if let b = buyers.first {
            ex(b.price > 0, "group quote positive")
            var f = e
            let n0 = netBook(f, id)
            let got = f.sellToGroup(companyID: id, groupID: b.id)
            ex(got != nil && netBook(f, id) > n0, "selling to a group pays the owner (\(String(describing: got)))")
            soldClean(f, id, "group")
            ex(f.sellToGroup(companyID: id, groupID: b.id) == nil, "a sold company cannot be sold again")
            run(&f, weeks: 8)
            saves(f, "after group sale")
        } else { find(3, "no rival group is active in the UK after 50 weeks (route shut: \(e.saleRoutes(companyID: id).first { $0.id == "group" }?.why ?? ""))") }
        do {
            var l = e
            if l.startSale(companyID: id, route: "private"), let b = buyers.first {
                let open = l.saleRoutes(companyID: id).first { $0.id == "group" }?.available ?? false
                let r = l.sellToGroup(companyID: id, groupID: b.id)
                if open && r == nil { find(3, "group route shows as available while the company is listed, then sellToGroup silently returns nil") }
            }
        }
        ex(e.sellMasterFranchise(companyID: id, country: "DE") == .noFranchise, "master franchise refused before the franchise exists")
        ex(e.saleRoutes(companyID: id).first { $0.id == "franchise" }?.available == false, "franchise route is shut before the franchise exists")
        run(&e, weeks: 16)
        let lr = e.launchFranchise(companyID: id, entryFee: cur.scaledPrice(20_000), royalty: 0.06, support: 1)
        if !e.isFranchisor(companyID: id) {
            _ = lr
            e.update { s, _, _ in
                guard let i = s.companyIndex(id) else { return }
                s.companies[i].set("fr", .object(["on": 1, "fee": .number(cur.scaledPrice(20_000)), "roy": 0.06, "supp": 1, "brand": 15, "units": .array([]), "app": .array([]), "masters": .array([])]))
            }
        }
        ex(e.saleRoutes(companyID: id).first { $0.id == "franchise" }?.available == true, "franchise route opens once the franchise runs")
        let countries = e.masterFranchiseCountries(companyID: id)
        ex(!countries.isEmpty, "there are countries to sell a master franchise in")
        if let c = countries.first {
            let cash0 = e.state.company(id)?.cash ?? 0
            e.update { s, _, _ in if let i = s.companyIndex(id) { Ledger.moveRaw(&s, .company(id), cur.scaledPrice(5_000_000)); _ = i } }
            let cash1 = e.state.company(id)?.cash ?? 0
            let r = e.sellMasterFranchise(companyID: id, country: c.code)
            ex(r == .ok, "master franchise for \(c.code) sells (\(r))")
            if r == .ok {
                ex((e.state.company(id)?.cash ?? 0) > cash1 - cur.scaledPrice(2_000_000), "the master fee arrives in the company")
                ex(e.sellMasterFranchise(companyID: id, country: c.code) == .already, "the same country cannot be sold twice")
            }
            _ = cash0
            run(&e, weeks: 30)
        }
        saves(e, "after master franchise")
    }

    func testSaleIpoRefusal() throws {
        tour = "SaleIpo"
        var (e, id) = try fixture(manager: true, accountant: true, weeks: 14)
        var other = 0
        if let b = try? fixture("tutor", weeks: 2, seed: 6) { other = b.1; _ = other }
        e.update { s, _, _ in Ledger.move(&s, .me, cur.scaledPrice(5_000_000), why: "Test capital") }
        let b = e.startCompany(tradeID: "tutor", cityID: e.state.player.cityID, fundWith: cur.scaledPrice(2_000_000), quickSetup: true)
        guard case .success(let bid) = b else { return find(3, "second company for a holding did not start") }
        run(&e, weeks: 2)
        switch e.createHolding(name: nil, companies: [id, bid]) {
        case .success(let hid):
            let r = e.saleRoutes(companyID: hid).first { $0.id == "ipo" }
            ex(r != nil, "a holding lists the ipo route")
            if let r, !r.available { ex(r.why.lowercased().contains("worth too little") || r.why.lowercased().contains("listed"), "holding IPO refusal names the value or listing (\(r.why))") }
            ex(e.saleRoutes(companyID: hid).first { $0.id == "private" }?.available == false, "a holding itself cannot be sold on the handshake route")
        case .failure(let f): find(3, "createHolding failed: \(f)")
        }
        run(&e, weeks: 6)
    }

    func payrollShort(_ e: inout GameEngine, _ id: Int, fraction: Double) -> [Message] {
        var seen: [Message] = []
        stress = true; defer { stress = false }
        for _ in 0..<(6 * 7) {
            let room = e.context.overdraftRoom(e.state.company(id)!, e.state)
            e.update { s, _, _ in
                guard let i = s.companyIndex(id) else { return }
                let due = max(s.companies[i].payables["wages"] ?? 0, 1)
                let target = -room + due * fraction
                if s.companies[i].cash > target { Ledger.moveRaw(&s, .company(id), target - s.companies[i].cash) }
            }
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") && m.actionID != "pay29s" { e.answer(messageID: m.id, option: 0) }
            let out = e.nextDay()
            var o = 0; check(e, out, &o)
            seen += out.newMessages.filter { $0.actionID == "pay29s" }
        }
        return seen
    }

    func testPayrollShortRouting() throws {
        tour = "PayrollShort"
        for (acct, mgr) in [(true, false), (false, true), (true, true), (false, false)] {
            var (e, id) = try fixture(manager: mgr, accountant: acct, weeks: 12, seed: 5 + (acct ? 1 : 0) + (mgr ? 2 : 0))
            let msgs = payrollShort(&e, id, fraction: 0.7)
            let tag = "acct=\(acct) mgr=\(mgr)"
            guard !msgs.isEmpty else { find(3, "no payroll-short notice when the account held 70% of wages (\(tag))"); continue }
            let weekly = Dictionary(grouping: msgs, by: { $0.week })
            for (w, l) in weekly { ex(l.count <= 1, "at most one payroll-short notice per week (\(l.count) in week \(w), \(tag))") }
            for m in msgs {
                if acct || mgr {
                    if m.isOwnerAddressed { find(2, "payroll short at 70% reached the owner although a desk exists (\(tag))", "week \(m.week) status \(m.status)") }
                    else { ex(m.status == "done" && !m.handledBy.isEmpty && m.audience == "finance", "desk notice is done, handled by someone and addressed to finance (\(tag): \(m.status)/\(m.handledBy)/\(m.audience))") }
                } else {
                    ex(m.isOwnerAddressed && m.status == "open" && m.severity >= 3, "with nobody responsible the owner gets it as an open decision (\(tag): \(m.audience)/\(m.status)/sev\(m.severity))")
                    if m.status == "open" { ex(e.answer(messageID: m.id, option: 0), "the owner can acknowledge the notice") }
                }
            }
            saves(e, "payroll short \(tag)")
        }
        var (e, id) = try fixture(manager: false, accountant: true, weeks: 12, seed: 14)
        let msgs = payrollShort(&e, id, fraction: 0.03)
        if msgs.isEmpty { find(3, "no payroll-short notice at 3% of wages with an accountant") }
        else { ex(msgs.contains { $0.isOwnerAddressed && $0.severity >= 3 }, "a serious shortfall (3% of wages) reaches the owner although an accountant exists") }
        var (m, a) = try fixture(manager: false, accountant: true, weeks: 12, seed: 15)
        m.update { s, _, _ in Ledger.move(&s, .me, cur.scaledPrice(20_000_000), why: "Test capital") }
        guard case .success(let b) = m.startCompany(tradeID: "cafe", cityID: m.state.player.cityID, fundWith: cur.scaledPrice(6_000_000), quickSetup: true) else { return }
        run(&m, weeks: 8)
        m.update { s, d, _ in
            for id in [a, b] { CompanySetup.chooseAccountant(&s, companyID: id, accountantID: nil, data: d) }
        }
        m.update { s, d, c in
            for id in [a, b] { Payday.reportShort(&s, s.company(id)!, due: 5000, short: 1000, serious: false, data: d, context: c) }
        }
        let wkNow: Int = m.state.week
        let shared: [Message] = m.state.inbox.filter { (x: Message) -> Bool in x.actionID == "pay29s" && x.week == wkNow }
        ex(shared.count == 1, "two short companies in one week share one notice")
    }

    func testUnlocksFollowThePlayer() throws {
        tour = "Unlocks"
        var (e, a) = try fixture(manager: true, accountant: true, weeks: 12)
        let early = e.unlockState(companyID: a)
        ex(early.contains { $0.id == "chain" && !$0.unlocked }, "chain is locked for a 12-week-old company")
        run(&e, weeks: 60)
        let later = e.unlockState(companyID: a)
        let earnedChain = later.first { $0.id == "chain" }?.unlocked ?? false
        if !earnedChain { find(3, "chain unlock not earned after 72 weeks of trading (reason: \(later.first { $0.id == "chain" }?.reason ?? ""))") }
        e.update { s, _, _ in Ledger.move(&s, .me, cur.scaledPrice(20_000_000), why: "Test capital") }
        guard case .success(let b) = e.startCompany(tradeID: "tutor", cityID: e.state.player.cityID, fundWith: cur.scaledPrice(3_000_000), quickSetup: true) else { return find(3, "second company did not start") }
        let sb = e.unlockState(companyID: b)
        for id in ["chain", "franchise", "abroad", "research"] {
            let mine = later.first { $0.id == id }?.unlocked ?? false
            if mine { ex(sb.first { $0.id == id }?.unlocked == true, "\(id) follows the player to a new company") }
        }
        for id in ["board", "dividends"] where later.first(where: { $0.id == id })?.unlocked == true {
            ex(sb.first { $0.id == id }?.unlocked == true, "\(id) follows the player to a new company")
        }
        e.markUnlockShown(id: "chain", companyID: a)
        for _ in 0..<12 { run(&e, weeks: 1) }
        let pend = e.pendingUnlocks().filter { $0.companyID == b }
        for p in pend where ["chain", "franchise", "abroad", "research"].contains(p.id) { find(2, "player-level unlock \(p.id) is announced again for the second company") }
        for p in e.pendingUnlocks() { e.markUnlockShown(id: p.id, companyID: p.companyID) }
        ex(e.pendingUnlocks().isEmpty, "marking every unlock shown clears the list")
        if e.startSale(companyID: a, route: "private"), let off = waitForOffer(&e, a, weeks: 40) {
            _ = e.acceptBuyerOffer(companyID: a, offerID: off.id)
            for id in ["chain", "franchise", "abroad", "research"] {
                let mine = later.first { $0.id == id }?.unlocked ?? false
                if mine { ex(e.unlockState(companyID: b).first { $0.id == id }?.unlocked == true, "\(id) stays open after the company that earned it is sold") }
            }
        }
        run(&e, weeks: 4)
        saves(e, "after unlocks")
    }

    func testLongPlayFlood() throws {
        tour = "LongPlay"
        for (acct, mgr) in [(false, false), (true, false), (false, true)] {
            var (e, id) = try fixture(manager: mgr, accountant: acct, weeks: 8, seed: 31 + (acct ? 1 : 0) + (mgr ? 2 : 0))
            maxOwnerNew = 0
            var perWeek: [Int] = []
            var week = 0, wk = 0
            for _ in 0..<(104 * 7) {
                for m in e.openDecisions where !m.options.isEmpty { e.answer(messageID: m.id, option: safeOption(m)) }
                let out = e.nextDay()
                var o = 0; check(e, out, &o); wk += o
                if out.completedWeek { perWeek.append(wk); wk = 0; week += 1 }
                if e.state.isGameOver { break }
            }
            let big = perWeek.filter { $0 >= 4 }.count
            ex(big <= 2, "owner gets 4+ new decisions in a week at most twice in two years (acct=\(acct) mgr=\(mgr): \(big), max \(perWeek.max() ?? 0))", sev: 3)
            _ = id
        }
    }
}

extension PlaytestReworkTours {
    func testScratchRework() throws {
        try XCTSkipUnless(PT.env["LEDGER_PT_SCRATCH"] == "1")
        let mode = PT.env["LEDGER_PT_SCRATCH_MODE"] ?? "neg"
        let bot = try PlayBot(Job(country: PT.env["LEDGER_PT_COUNTRY"] ?? "DE", trade: PT.env["LEDGER_PT_TRADE"] ?? "cafe", seed: Int(PT.env["LEDGER_PT_SEED"] ?? "1") ?? 1, policy: .competent, scenario: Scenario(rawValue: PT.env["LEDGER_PT_SCENARIO"] ?? "rework") ?? .rework, years: 1))
        bot.scenarioSetup()
        var shown = 0
        var prevCash = 0.0
        var floodWeek: [String] = []
        for d in 0..<((Int(PT.env["LEDGER_PT_WEEKS"] ?? "45") ?? 45) * 7) {
            if mode == "nw", bot.e.state.week >= 55, bot.e.state.week <= 56 { for m in bot.e.openDecisions { print("S OPEN", bot.e.state.week, bot.e.state.day, m.actionID, m.title.prefix(60), m.options.map { "\($0["l"].string)|cash \(Int($0["fx"]["cash"].double))" }, "pick", bot.pick(m)) } }
            bot.answerAll()
            let before = bot.e.state.cash
            let o = bot.e.nextDay()
            if mode == "neg", bot.e.state.cash < -1, shown < 6 {
                shown += 1
                print("S NEG wk", bot.e.state.week, "day", bot.e.state.day, "cash", Int(before), "->", Int(bot.e.state.cash))
                for l in bot.e.state.statement.suffix(6) { print("S   line", l.week, l.day, Int(l.amount), l.label) }
                for m in o.newMessages.prefix(4) { print("S   msg", m.title) }
            }
            if mode == "flood2" { for m in o.newMessages where (m.kind == "ask" || m.kind == "decision") && m.status == "open" && m.isOwnerAddressed { floodWeek.append("\(m.actionID)|\(m.title.prefix(50))") } }
            if mode == "flood2", o.completedWeek { if floodWeek.count >= 6 { print("S FLOODWEEK", bot.e.state.week, floodWeek.count, floodWeek) }; floodWeek = [] }
            if mode == "flood", bot.e.state.week >= 31 && bot.e.state.week <= 34 { for m in o.newMessages where (m.kind == "ask" || m.kind == "decision") && m.status == "open" && m.isOwnerAddressed { print("S FLOOD wk", bot.e.state.week, m.actionID, m.title.prefix(70)) } }
            if mode == "room", shown < 4, let c = bot.e.state.company(bot.mainID), c.cash < -bot.e.context.overdraftRoom(c, bot.e.state) - 1 {
                shown += 1
                print("S ROOM wk", bot.e.state.week, bot.e.state.day, "cash", Int(c.cash), "room", Int(bot.e.context.overdraftRoom(c, bot.e.state)), "before", Int(prevCash))
                for t in c.transactions.suffix(5) { print("S   TX", t["w"].int, Int(t["a"].double), t["l"].string) }
                for m in o.newMessages { print("S   MSG", m.title.prefix(60)) }
            }
            if let c = bot.e.state.company(bot.mainID) { prevCash = c.cash }
            if mode == "nw", bot.e.state.week >= Int(PT.env["LEDGER_PT_FROM"] ?? "55")!, bot.e.state.week <= Int(PT.env["LEDGER_PT_FROM"] ?? "55")! + 2 { let c = bot.e.state.company(bot.mainID); print("S DAY", bot.e.state.week, bot.e.state.day, "co", Int(c?.cash ?? 0), "pers", Int(bot.e.state.cash), "msgs", o.newMessages.map { $0.title.prefix(40) }, "stmt", bot.e.state.statement.suffix(2).map { "\(Int($0.amount)) \($0.label)" }) }
            if mode == "nw", o.completedWeek { let c = bot.e.state.company(bot.mainID); print("S NW wk", bot.e.state.week, "nw", Int(bot.e.netWorth.total), "pers", Int(bot.e.state.cash), "co", c?.status.rawValue ?? "-", Int(c?.cash ?? 0), "route", bot.saleRoute, "sold", bot.soldWeek, "loans", Int(bot.e.state.loans.reduce(0) { $0 + $1.balance })); if bot.e.state.week >= 55 && bot.e.state.week <= 57 { for m in o.newMessages { print("S   MSG", m.title, m.status) }; if let c { for t in c.transactions.suffix(12) { print("S   TX", t["w"].int, Int(t["a"].double), t["l"].string) } } } }
            if o.completedWeek { bot.tend(); bot.midScenario(week: bot.e.state.week); bot.saleWeek() }
        }
    }
}
