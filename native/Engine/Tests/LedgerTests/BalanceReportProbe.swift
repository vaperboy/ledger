import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Multi-year balance driver. Skipped unless LEDGER_REPORT=1.
/// LEDGER_TRADES=a,b  LEDGER_SEEDS=11,12,13  LEDGER_YEARS=5  LEDGER_OUT=/path/file.csv (one line per run is appended).
final class BalanceReportProbe: XCTestCase {
    static let mw: Set<MarketEvent.Kind> = [.supplierPriceChange, .competitorLaunch, .priceResponse, .newCountry, .acquisitionOpportunity, .competitorLostShare]
    static let defaultTrades = ["carclean", "barber", "restaurant", "hotel", "factory", "carrental", "tutor", "bakery", "courier", "cons", "webdev", "grocery", "airline", "gym"]

    func testReport() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["LEDGER_REPORT"] != nil else { return }
        let trades = env["LEDGER_TRADES"]?.split(separator: ",").map(String.init) ?? Self.defaultTrades
        let seeds = env["LEDGER_SEEDS"]?.split(separator: ",").compactMap { Int($0) } ?? [11, 12, 13]
        let years = Int(env["LEDGER_YEARS"] ?? "") ?? 5
        for t in trades { for sd in seeds { for competent in [false, true] {
            let line = try Self.run(trade: t, seed: sd, years: years, competent: competent)
            print(line)
            if let p = env["LEDGER_OUT"], let d = (line + "\n").data(using: .utf8) {
                if let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write(d); h.closeFile() } else { FileManager.default.createFile(atPath: p, contents: d) }
            }
        } } }
    }

    static func run(trade: String, seed: Int, years: Int, competent: Bool) throws -> String {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        var id = 0, invested = 0.0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 20_000_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, data: data, context: ctx) else { return }
            id = i
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, size: 1, state: s, data: data)
            invested = (est?.total ?? 1_000_000) * 1.3
            Payments.injectCash(&s, companyID: id, amount: invested)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        guard id != 0 else { return "RPT \(trade) seed \(seed) \(competent ? "competent" : "baseline") DID_NOT_START" }
        if competent {
            for (k, n) in [("google", 1), ("meta", 1), ("seo", 1)] {
                if let ch = e.marketing.channels[k], ch.budgetOptions.count > n { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions[n]) }
            }
        }
        var nw: [Double] = [], profitY: [Double] = [], staffY: [Int] = [], wageShare: [Double] = []
        var hiringSpend = 0.0, prevTx: [JSONValue] = []
        var eventIDs = Set<Int>(), marketWide = 0, maxWeekMW = 0, weekMW: [Int: Int] = [:]
        var warWeeks = 0, openWeeks = 0, premAccepted = 0, itemsAdded = 0, managerWeek = -1
        var revBefore = 0.0, premWeek = -1, revAfter = 0.0
        var bust = false
        let totalDays = years * 52 * 7
        for day in 0..<totalDays {
            BalanceProbeTests.drained {
                e.nextDay()
                for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
                guard let co = e.state.company(id) else { return }
                if co.status.isLive, co.cash < -50_000 {
                    let top = -co.cash + 100_000
                    e.update { s, _, _ in Payments.injectCash(&s, companyID: id, amount: top) }
                    invested += top
                }
                // hiring spend: new transactions since yesterday
                let tx = co.transactions
                var k = tx.count
                for c in 0...tx.count { if Array(tx[c...]) == Array(prevTx.prefix(tx.count - c)) { k = c; break } }
                for x in tx.prefix(k) { let l = x["l"].string; if l.hasPrefix("Job ad") || l.hasPrefix("Agency") { hiringSpend += -x["a"].double } }
                prevTx = tx
                if day % 7 == 0 {
                    for ev in MarketEvents.events(e.state, limit: 60) where !eventIDs.contains(ev.id) {
                        eventIDs.insert(ev.id)
                        if Self.mw.contains(ev.kind) { marketWide += 1; weekMW[day / 7, default: 0] += 1 }
                    }
                    if co.status == .open {
                        openWeeks += 1
                        if MarketPressure.pressure(co, week: e.state.week, kind: .response) > 0.001 { warWeeks += 1 }
                    }
                    if competent, co.status == .open {
                        let w = day / 7
                        if co.managerID == nil, w % 4 == 0, w >= 4, managerWeek < 0 || w - managerWeek >= 26 {
                            e.update { s, data, _ in
                                guard let c = s.company(id), let bd = data.catalog[c.type] else { return }
                                let cand = ManagerModel.generateCandidate(company: c, type: bd.managerType, state: &s, data: data)
                                if (s.company(id)?.cash ?? 0) > cand.askingMonthlyWage * 8 {
                                    if ManagerModel.hire(&s, personID: cand.id, companyID: id, monthlyWage: cand.askingMonthlyWage * 1.2, data: data) == .ok { managerWeek = w }
                                }
                            }
                        }
                        if w == 8 || w == 26 {
                            let r = e.addSalesItem(companyID: id, name: w == 8 ? "Extra A" : "Extra B", isService: e.data.catalog[co.type].map { SalesItems.isService($0) } ?? true)
                            _ = r; itemsAdded += 1
                        }
                    }
                }
                if competent {
                    for m in e.openDecisions where m.actionID == "prop" && m.value("data")["t"].string == "prem" {
                        let rev13 = co.monthlyHistory.suffix(3).reduce(0) { $0 + $1.revenue } / 3
                        if e.answer(messageID: m.id, option: 0) { premAccepted += 1; if premWeek < 0 { premWeek = day / 7; revBefore = rev13 } }
                    }
                }
                if day > 0 && day % (52 * 7) == 0 {
                    nw.append(Valuation.companyValue(co, state: e.state, trades: e.data.catalog))
                    let h = co.monthlyHistory
                    let rev = h.suffix(12).reduce(0) { $0 + $1.revenue }
                    profitY.append(h.suffix(12).reduce(0) { $0 + $1.profit })
                    staffY.append(co.staff.count)
                    wageShare.append(rev > 0 ? co.staff.reduce(0) { $0 + $1.monthlyWage } * 12 / rev : 0)
                }
                if premWeek >= 0, day / 7 == premWeek + 26 { revAfter = co.monthlyHistory.suffix(3).reduce(0) { $0 + $1.revenue } / 3 }
            }
            if let co = e.state.company(id), !co.status.isLive { bust = true; break }
        }
        maxWeekMW = weekMW.values.max() ?? 0
        let co = e.state.company(id)
        let totRev = (co?.monthlyHistory ?? []).reduce(0) { $0 + $1.revenue }
        let value = co.map { Valuation.companyValue($0, state: e.state, trades: e.data.catalog) } ?? 0
        func f(_ a: [Double]) -> String { a.map { String(format: "%.0f", $0 / 1000) }.joined(separator: "/") }
        let roiY = profitY.map { String(format: "%.0f%%", $0 / max(1, invested) * 100) }.joined(separator: "/")
        let prem = premWeek >= 0 ? String(format: "w%d rev %.0f->%.0f", premWeek, revBefore / 1000, revAfter / 1000) : "-"
        return String(format: "RPT|%@|%d|%@|inv %.0f|nw %@|profit %@|roi %@|final %.0f|status %@|bust %d|staff %@|wageShare %@|hiring %.0f|hiringShare %.2f%%|events %d|mw %d|maxMWweek %d|warWeeks %d/%d|premAcc %d|prem %@|items %d|mgr %@",
                      trade, seed, competent ? "competent" : "baseline", invested / 1000, f(nw), f(profitY), roiY, value / 1000, co?.status.rawValue ?? "gone", bust ? 1 : 0,
                      staffY.map(String.init).joined(separator: "/"), wageShare.map { String(format: "%.0f%%", $0 * 100) }.joined(separator: "/"),
                      hiringSpend / 1000, totRev > 0 ? hiringSpend / totRev * 100 : 0, eventIDs.count, marketWide, maxWeekMW, warWeeks, openWeeks, premAccepted, prem, itemsAdded,
                      co?.managerID != nil ? "yes" : "no")
    }
}
