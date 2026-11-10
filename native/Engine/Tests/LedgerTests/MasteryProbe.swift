import XCTest
import Finance
import GameCore
import Businesses
import Countries
@testable import Simulation

final class MasteryProbe: XCTestCase {
    static let channelIDs = ["google", "meta", "seo", "flyer", "local", "tiktok", "b2b", "ref", "bill"]

    func play(_ code: String, _ trade: String, _ policy: String, years: Int, seed: Int = 7) throws -> String {
        var e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: seed, story: .fresh, tradeID: trade, companyName: "T")
        let id = e.state.companies[0].id
        let cur = e.homeCurrency
        let idx = cur.scaledPrice(1_000_000) / 1_000_000
        let nw0 = Valuation.netWorth(e.state, trades: e.data.catalog).total
        let bd = e.data.catalog[trade]!
        let env = ProcessInfo.processInfo.environment
        let competentLevel = Int(env["LEDGER_ADLEVEL"] ?? "1") ?? 1
        let maxStores = policy == "expert" ? 6 : policy == "competent" ? 2 : 1
        var out: [String] = []
        var broke = false
        var lastStoreDay = -999
        var ids = [id]
        let homePop = e.homeCountry.city(e.state.player.cityID)?.population ?? 300
        let cities = e.homeCountry.cities.filter { $0.id != e.state.player.cityID }.sorted { abs(log($0.population / homePop)) < abs(log($1.population / homePop)) }.map { $0.id }
        var hires = 0

        func bestCampaign(_ co: Company) -> (String, Double, Double)? {
            var best: (String, Double, Double)? = nil
            for k in Self.channelIDs {
                guard let ch = e.marketing.channels[k], ch.offered(in: e.homeCountry) != nil else { continue }
                for b in ch.budgets(in: cur) where b > 0 {
                    guard let est = Marketing.estimate(co, channel: k, weeklyBudget: b, state: e.state, data: e.data, tables: e.marketing) else { continue }
                    if est.netPerWeek > (best?.2 ?? 0), let pb = est.paybackWeeks, pb <= 78 { best = (k, b, est.netPerWeek) }
                }
            }
            return best
        }
        func fitChannel() -> String {
            let t = e.marketing
            func score(_ k: String) -> Double {
                guard let c = t.channels[k] else { return 0 }
                let fit = (1 - bd.audience) * c.localShare + bd.audience * c.businessShare
                let aff = (t.affinityByFamily[bd.family]?[k] ?? 1) * (t.affinityByTrade[trade]?[k] ?? 1)
                return c.efficiency * (0.45 + fit) * aff / (c.scale / 3000 + 1)
            }
            return Self.channelIDs.filter { e.marketing.channels[$0] != nil && $0 != "bill" && $0 != "tiktok" }.max { score($0) < score($1) } ?? "google"
        }
        func setAds(_ cid: Int) {
            guard let co = e.state.company(cid), co.status == .open else { return }
            if policy == "competent" {
                if co.value("mkt").object.isEmpty, let ch = e.marketing.channels[fitChannel()], ch.budgets(in: cur).count > competentLevel {
                    _ = e.setCampaign(companyID: cid, channel: fitChannel(), weeklyBudget: ch.budgets(in: cur)[competentLevel])
                }
            } else if policy == "expert" {
                let choice = bestCampaign(co)
                for k in co.value("mkt").object.keys where k != choice?.0 { _ = e.setCampaign(companyID: cid, channel: k, weeklyBudget: 0) }
                if let c = choice { _ = e.setCampaign(companyID: cid, channel: c.0, weeklyBudget: c.1) }
            }
        }
        func tendPrice(_ cid: Int, step: Double) {
            guard let co = e.state.company(cid), co.status == .open else { return }
            let lw = co.value("lastW")
            let util = lw["util"].double
            var p = co.priceLevel
            let h = co.monthlyHistory.suffix(3).map { $0.profit }
            let falling = h.count == 3 && h[2] < h[1] && h[1] < h[0]
            if falling && p > 0 { p -= step } else if util > 0.95 && p < 1.25 && !falling { p += step } else if util < 0.7 && p > -1 { p -= step } else { return }
            _ = e.setPriceLevel(companyID: cid, level: p)
        }
        func tendStaff(_ cid: Int) {
            guard let co = e.state.company(cid), co.status == .open, hires < 30, let role = bd.standardStaff.first?.role, e.data.catalog.tables.roles[role] != nil else { return }
            let lw = co.value("lastW")
            let empty = co.staff.isEmpty && (bd.standardStaff.first?.count ?? 0) >= 1
            guard empty || (env["LEDGER_HIRE"] != nil && lw["D"].double > lw["cap"].double * 1.05), co.cash > cur.scaledPrice(5_000) else { return }
            let found = e.searchWorkers(companyID: cid, role: role, mode: .network)
            if let c = found.max(by: { $0.skill / max(1, $0.askingMonthlyWage) < $1.skill / max(1, $1.askingMonthlyWage) }) {
                if e.hire(personID: c.id, companyID: cid, monthlyWage: c.askingMonthlyWage) == .ok { hires += 1 }
            }
        }

        let off = (env["LEDGER_OFF"] ?? "").split(separator: ",").map(String.init)
        if policy != "idle", !off.contains("ads") { setAds(id) }
        for d in 1...(364 * years) {
            e.nextDay()
            for m in e.openDecisions where !m.options.isEmpty {
                let opt = m.actionID.lowercased().contains("sale") || m.title.lowercased().contains("offer for") || m.title.lowercased().contains("wants to buy") ? m.options.count - 1 : policy != "idle" && m.title.contains("campaign is working") ? 1 : policy != "idle" && ((m.actionID == "emg37" && !m.title.contains("Cash is running")) || m.actionID == "prop") ? m.options.count - 1 : 0
                if env["LEDGER_DEBUG"] != nil { print("DECISION \(policy) d\(d)", m.title, m.actionID, m.options.map { $0["l"].string }.joined(separator: " / ")) }
                _ = e.answer(messageID: m.id, option: opt)
            }
            if e.state.isGameOver { broke = true; break }
            if policy != "idle", d % 3 == 0 {
                let fc = FinanceContext(countries: e.data.countries, trades: e.data.catalog)
                for c in ids.compactMap({ e.state.company($0) }) where c.status == .open {
                    let buffer = max(fc.weeklyCost(c, e.state) * 6, (c.monthlyHistory.last?.revenue ?? 0) * 0.5)
                    guard c.cash < buffer else { continue }
                    let top = buffer * 2 - c.cash
                    let give = min(top, Payments.liquid(e.state) - cur.scaledPrice(2_000)); if give > 0 { _ = e.putMoneyInto(companyID: c.id, amount: give) }
                }
            }
            if policy != "idle" {
                let live = ids.filter { e.state.company($0)?.status == .open }
                if d % 28 == 0 && d > 60 && !off.contains("price") { for c in live { tendPrice(c, step: policy == "expert" ? 0.25 : 0.5) } }
                if policy == "competent" && d % 91 != 0 {  }
                if d % 91 == 0 && d > 60 && !off.contains("ads") { for c in live { setAds(c) } }
                if env["LEDGER_HIRE"] != nil, d % 14 == 0 && d > 20 { for c in live { tendStaff(c) } }
                if d % 28 == 0, !off.contains("exp"), ids.count < maxStores, d - lastStoreDay > (policy == "expert" ? 112 : 180) {
                    let cos = live.compactMap { e.state.company($0) }
                    let ok = !cos.isEmpty && cos.allSatisfy { $0.monthlyHistory.count >= 6 && $0.monthlyHistory.suffix(6).reduce(0) { $0 + $1.profit } > 0 }
                    let yearRev = (cos.first?.monthlyHistory.suffix(12).reduce(0) { $0 + $1.revenue } ?? 0) / idx
                    if ok, yearRev > 2_500_000, let rd = Expansion.readiness(e.state, data: e.data, companyID: id, cityID: cities[min(ids.count - 1, cities.count - 1)]) {
                        for c in cos { let md = e.maximumDividend(companyID: c.id); if md > 0, c.cash > cur.scaledPrice(30_000) { let amt = min(md, c.cash - cur.scaledPrice(30_000)); _ = e.payDividend(companyID: c.id, amount: amt) } }
                        if env["LEDGER_DEBUG"] != nil { print("EXPAND d\(d) need=\(Int(rd.cashNeeded / idx / 1000))k liquid=\(Int(Payments.liquid(e.state) / idx / 1000))k co=\(cos.map { Int($0.cash / idx / 1000) }) md=\(cos.map { Int(e.maximumDividend(companyID: $0.id) / idx / 1000) })") }
                        if policy == "expert", Payments.liquid(e.state) < rd.cashNeeded {
                            let short = (rd.cashNeeded - Payments.liquid(e.state)) * 1.05
                            if e.loanOffer(kind: "biz", amount: short, companyID: nil).maximum >= short { _ = e.takeLoan(kind: "biz", amount: short, termMonths: 60, companyID: nil) }
                        }
                        if Payments.liquid(e.state) >= rd.cashNeeded {
                            if case .success(let nid) = e.startCompany(tradeID: trade, cityID: cities[min(ids.count - 1, cities.count - 1)], name: "T\(d)", fundWith: rd.startCost + rd.rampReserve) {
                                ids.append(nid); lastStoreDay = d
                                setAds(nid)
                                if let m = e.searchManagers(companyID: nid)?.first { _ = e.hireManager(personID: m.id, companyID: nid, monthlyWage: m.askingMonthlyWage * 1.3) }
                            }
                        }
                    }
                }
            }
            if d % 28 == 0, env["LEDGER_DEBUG2"] != nil, let c = e.state.company(id) {
                let m = c.monthlyHistory.last
                print("MON d\(d) cash=\(Int(c.cash / idx / 1000))k me=\(Int(Payments.liquid(e.state) / idx / 1000))k rev=\(Int((m?.revenue ?? 0) / idx / 1000))k prof=\(Int((m?.profit ?? 0) / idx / 1000))k aware=\(Int(c.awareness)) util=\(String(format: "%.2f", c.value("lastW")["util"].double)) price=\(c.priceLevel) staff=\(c.staff.count) mkt=\(c.value("mkt").object.map { "\($0.key):\(Int($0.value["b"].double / idx))" }) st=\(c.status.rawValue) nw=\(Int(Valuation.netWorth(e.state, trades: e.data.catalog).total / idx / 1000))k")
            }
            if d % 364 == 0, env["LEDGER_DEBUG"] != nil {
                for cid in ids {
                    guard let c = e.state.company(cid) else { continue }
                    let lw = c.value("lastW")
                    let yr = c.monthlyHistory.suffix(12)
                    let mk = c.value("mkt").object.map { "\($0.key):\(Int($0.value["b"].double))" }.joined(separator: ",")
                    print("DIAG \(code) \(trade) \(policy) y\(d / 364) co\(cid) aware=\(Int(c.awareness)) rep=\(Int(c.reputation)) util=\(String(format: "%.2f", lw["util"].double)) D=\(Int(lw["D"].double)) cap=\(Int(lw["cap"].double)) rev12=\(Int(yr.reduce(0) { $0 + $1.revenue } / idx / 1000))k prof12=\(Int(yr.reduce(0) { $0 + $1.profit } / idx / 1000))k cash=\(Int(c.cash / idx / 1000))k price=\(c.priceLevel) staff=\(c.staff.count) mkt=[\(mk)] st=\(c.status.rawValue)")
                }
            }
            if d % 364 == 0 && (d / 364 <= 3 || d / 364 == 5) { out.append(String(Int((Valuation.netWorth(e.state, trades: e.data.catalog).total - nw0) / idx / 1000))) }
        }
        let live = e.state.companies.filter { $0.status.isLive }.count
        let statuses = e.state.companies.map { $0.status.rawValue }.joined(separator: ",")
        return out.joined(separator: "|") + (broke ? " BROKE wk \(e.state.week)" : "") + " owned=\(Gates.companiesOwned(e.state)) live=\(live) [\(statuses)]"
    }

    func testMastery() throws {
        let env = ProcessInfo.processInfo.environment
        guard let spec = env["LEDGER_MASTERY"] else { throw XCTSkip("set LEDGER_MASTERY") }
        let policies = (env["LEDGER_POLICIES"] ?? "idle,competent,expert").split(separator: ",").map(String.init)
        let years = Int(env["LEDGER_MYEARS"] ?? "5") ?? 5
        let seed = Int(env["LEDGER_SEED"] ?? "7") ?? 7
        for pair in spec.split(separator: ",") {
            let p = pair.split(separator: ":").map(String.init)
            for pol in policies { print("MASTERY", p[0], p[1], pol, try play(p[0], p[1], pol, years: years, seed: seed)) }
        }
    }
}
