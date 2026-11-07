import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation
import Investments

/// Throwaway balancing harness (not committed). LEDGER_CAREER=1; LEDGER_COUNTRIES=CH,UK,MX,JP; LEDGER_CAREERS=baker,...; LEDGER_SEEDS=1,2,3; LEDGER_YEARS=10
func Dk(_ x: Double) -> String { x.isFinite ? String(Int(x / 1000)) : "NaN" }

final class CareerSimHarness: XCTestCase {
    struct Result {
        var career = "", country = "", seed = 0
        var samples: [(day: Int, nwUnits: Double)] = []
        var idx = 1.0, rate = 1.0
        var cashY1 = 0.0, coCashY1 = 0.0, personalY1 = 0.0
        var bankrupt = false, bustCount = 0, gameOver = false
        var firstProfitMonth: Int? = nil, firstYearProfitable: Bool = false
        var steppingStone = false, openedTargetDay: Int? = nil
        var companies: [(trade: String, invested: Double, months: [MonthRecord], status: String)] = []
        var distressDays = 0
        var finalNW = 0.0
        var note = ""
    }

    static func run(career: String, country: String, seed: Int, years: Int) throws -> Result {
        var e = try GameEngine.newGame(countryCode: country, playerName: "T", seed: seed)
        var r = Result(); r.career = career; r.country = country; r.seed = seed
        let cur = e.homeCurrency
        r.idx = cur.scaledPrice(1_000_000) / 1_000_000; r.rate = cur.rate
        let city = e.state.player.cityID
        var invested: [Int: Double] = [:]
        var target = ""   // trade the career wants
        switch career {
        case "baker": target = "bakery"
        case "landlord": target = "resrent"
        case "heavy": target = "hardware"
        case "service": target = "cleaning"
        case "consult": target = "cons"
        default: target = ""
        }
        var mainID = 0
        func est(_ t: String) -> Double {
            var rich = e.state; rich.cash += 1e12   // the estimate refuses when the share capital is not in the account
            return CompanySetup.estimate(tradeID: t, cityID: city, form: .limited, size: 1, state: rich, data: e.data)?.total ?? .infinity
        }
        func liquid() -> Double { Payments.liquid(e.state) }
        var reserve: Double { max(cur.scaledPrice(20_000), 0.02 * e.netWorth.total) }

        /// Start a company: funded from cash, topped up with a business loan if short (only when the bank would grant it). Returns id or 0.
        func open(_ trade: String, allowLoan: Bool, fundX: Double = 1.2) -> Int {
            let need = est(trade) * fundX
            guard need.isFinite else { return 0 }
            let have = max(0, liquid() - reserve)
            var shortfall = max(0, need - have)
            if shortfall > 0 {
                guard allowLoan else { return 0 }
                shortfall *= 1.05
                if e.loanOffer(kind: "biz", amount: shortfall, companyID: nil).maximum < shortfall { return 0 }
            }
            var id = 0
            e.update { s, data, ctx in
                if case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: city, form: .limited, data: data, context: ctx) { id = i }
                else if case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: city, form: .soleTrader, data: data, context: ctx) { id = i }
            }
            if id == 0 { return 0 }
            if shortfall > 0 {
                if e.takeLoan(kind: "biz", amount: shortfall, termMonths: 60, companyID: id) != .ok {
                    e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies.remove(at: i) } }
                    return 0
                }
            }
            let put = min(need, liquid() - reserve * 0.5)
            e.update { s, data, _ in
                Payments.injectCash(&s, companyID: id, amount: max(0, put))
                _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
            }
            invested[id, default: 0] += need
            let lvl = Int(ProcessInfo.processInfo.environment["LEDGER_MKTLEVEL"] ?? "1") ?? 1
            if lvl >= 0 {
                for k in ["google", "meta", "seo"] {
                    if let ch = e.marketing.channels[k], ch.budgetOptions.count > lvl { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions[lvl]) }
                }
            }
            return id
        }

        // ---- Scenario: "honest" = start loan only; "funded" = the same gift of capital for every career (isolates the trade economics)
        let funded = ProcessInfo.processInfo.environment["LEDGER_SCENARIO"] == "funded"
        if funded {
            let capital = max(est("hardware"), est("resrent"), est("bakery")) * 1.35
            e.update { s, _, _ in Ledger.move(&s, .me, capital, why: "Test capital") }
        }
        // ---- Opening move: the target if cash/bank allow, else the cheapest sensible starter (tutor)
        var stone = 0
        mainID = target.isEmpty ? 0 : open(target, allowLoan: true)
        if mainID == 0 && !target.isEmpty || target.isEmpty {
            r.steppingStone = true
            if !(funded && target.isEmpty) { stone = open("tutor", allowLoan: false, fundX: 1.05); mainID = stone }
        }
        var targetIDs: [Int] = (!target.isEmpty && !r.steppingStone && mainID != 0) ? [mainID] : []
        if !targetIDs.isEmpty { r.openedTargetDay = 0 }
        if funded && target.isEmpty { r.steppingStone = false }
        if mainID == 0 && !(funded && target.isEmpty) { r.note = "could not open" }

        var idxValue: Double { e.quotes(.fund).first { $0.symbol == "idx" }?.value ?? 0 }
        /// Make `amount` liquid by selling part of the index fund.
        func raise(_ amount: Double) {
            let short = amount - liquid()
            guard short > 0 else { return }
            let v = idxValue
            if v > 0 { e.sellInvestment(.fund, symbol: "idx", fraction: min(1, short * 1.003 / v)) }
        }
        /// Keep a cash cushion plus the tax bill coming: sell the index fund first, then shares.
        func cover() {
            let pend = e.netWorth.pendingTax
            let target = reserve * 2 + pend * 1.25
            let short = target - e.state.cash
            guard short > 0 else { return }
            if e.state.savings > 0 { _ = e.moveToSavings(-min(e.state.savings, short)) }
            let v = idxValue
            if v > 0 { e.sellInvestment(.fund, symbol: "idx", fraction: min(1, short * 1.003 / v)) }
            if e.state.cash < target {
                let held = e.quotes(.stock).filter { $0.quantity > 0 }
                let tot = held.reduce(0) { $0 + $1.value }
                if tot > 0 { for q in held { e.sellInvestment(.stock, symbol: q.symbol, fraction: min(1, (target - e.state.cash) * 1.01 / tot)) } }
            }
        }
        var lastMonthlyAction = -100
        let days = years * 364
        for day in 0..<days {
            e.nextDay()
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            if e.state.isGameOver { r.gameOver = true; r.bankrupt = true; r.note = "over:\(e.state.gameOver["reason"].string)@d\(day) nw=\(Int(e.netWorth.total/1000))k cash=\(Int(e.state.cash/1000))k"; break }
            if day % 28 == 27 { r.samples.append((day, e.netWorth.total))
                if ProcessInfo.processInfo.environment["LEDGER_DEBUG"] != nil {
                    let nw = e.netWorth
                    var line = "DBG \(career) d\(day) cash=\(Dk(e.state.cash))k sav=\(Dk(e.state.savings))k idx=\(Dk(idxValue))k funds=\(Dk(nw.funds))k stocks=\(Dk(nw.stocks))k debt=\(Dk(nw.debt))k tax=\(Dk(nw.pendingTax))k nw=\(Dk(nw.total))k |"
                    for c in e.state.companies where c.type != "hold" { line += " \(c.type):\(c.status.rawValue) cash=\(Dk(c.cash))k mo=\(c.monthlyHistory.last.map { "\(Dk($0.revenue))/\(Dk($0.profit))" } ?? "-") props=\(c.properties.count)" }
                    print(line)
                }
            }
            if day == 363 {
                r.cashY1 = liquid()
                r.personalY1 = e.state.cash + e.state.savings
                r.coCashY1 = e.state.companies.filter { $0.status.isLive }.reduce(0) { $0 + $1.cash }
            }
            guard day % 7 == 6 else { continue }
            cover()
            // weekly: keep companies alive from personal cash
            for co in e.state.companies where co.status.isLive && co.holdingID == 0 {
                if co.cash < -cur.scaledPrice(10_000) {
                    r.distressDays += 7
                    let top = -co.cash + cur.scaledPrice(20_000)
                    raise(top + reserve)
                    if liquid() - reserve > top { _ = e.putMoneyInto(companyID: co.id, amount: top); invested[co.id, default: 0] += top }
                }
            }
            guard day - lastMonthlyAction >= 28 else { continue }
            lastMonthlyAction = day
            let businessCareer = !["investor", "trader"].contains(career)
            // 1. sweep surplus out of operating companies (landlords keep rent for the next purchase)
            for co in e.state.companies where co.status == .open && co.type != "hold" && (career != "landlord" || co.type == "tutor") {
                let md = e.maximumDividend(companyID: co.id)
                let buffer = co.type == "tutor" ? cur.scaledPrice(30_000) : (invested[co.id] ?? 0) * 0.5
                let free = co.cash - buffer
                if md > 0 && free > 0 { _ = e.payDividend(companyID: co.id, amount: min(md, free)) }
            }
            // 2. expansion / upgrade
            if businessCareer && !target.isEmpty && career != "landlord" {
                let live = e.state.companies.filter { $0.status == .open && $0.type == target }.count
                let need = est(target) * 1.25
                let allProfitable = e.state.companies.filter { $0.status == .open && $0.type == target }.allSatisfy { $0.monthlyHistory.count >= 12 && $0.monthlyHistory.suffix(12).reduce(0) { $0 + $1.profit } > 0 }
                if targetIDs.isEmpty || (live < 6 && allProfitable) {
                    var canLoan = targetIDs.isEmpty
                    if liquid() + idxValue - reserve > need { raise(need + reserve) }
                    let id = open(target, allowLoan: canLoan)
                    canLoan = false
                    if id != 0 { targetIDs.append(id); if r.openedTargetDay == nil { r.openedTargetDay = day } }
                }
            }
            if career == "landlord" {
                if targetIDs.isEmpty, r.steppingStone {
                    raise(est(target) * 1.25 + reserve)
                    let id = open(target, allowLoan: true)
                    if id != 0 { targetIDs.append(id); r.openedTargetDay = day }
                }
                if let id = targetIDs.first, let co = e.state.company(id), co.status == .open {
                    let ls = e.propertyListings(companyID: id).sorted { $0.grossYield > $1.grossYield }
                    for l in ls.prefix(3) {
                        let down = l.price * 0.4 * 1.03 + reserve * 3
                        let c0 = e.state.company(id)!.cash
                        if c0 < down { raise(down - c0 + reserve) ; let put = min(down - c0, liquid() - reserve); if put > 0 { _ = e.putMoneyInto(companyID: id, amount: put); invested[id, default: 0] += put } }
                        if e.state.company(id)!.cash >= down { _ = e.buyProperty(companyID: id, listingIndex: l.index, loanToValue: 0.6); break }
                    }
                }
            }
            // 3. investors/traders: momentum or index; everybody else parks spare money in the index fund
            if career == "trader" {
                let qs = e.quotes(.stock).filter { !$0.isDelisted && $0.history.count >= 14 }
                let ranked = qs.sorted { ($0.price / $0.history[$0.history.count - 14]) > ($1.price / $1.history[$1.history.count - 14]) }
                let top = Set(ranked.prefix(3).map { $0.symbol })
                for q in qs where q.quantity > 0 && !top.contains(q.symbol) { e.sellInvestment(.stock, symbol: q.symbol, fraction: 1) }
                let spare = liquid() - reserve * 2 - e.netWorth.pendingTax * 1.25
                if spare > cur.scaledPrice(1500) { for sym in top.sorted() { _ = e.buyInvestment(.stock, symbol: sym, amount: spare * 0.99 / 3) } }
            } else {
                let keep = reserve * 2 + (career == "landlord" ? est(target) * 0.3 : 0)
                let spare = liquid() - keep - e.netWorth.pendingTax * 1.25
                if spare > cur.scaledPrice(2000) { let br = e.buyInvestment(.fund, symbol: "idx", amount: spare * 0.995); if ProcessInfo.processInfo.environment["LEDGER_DEBUG"] != nil { print("BUY idx \(Int(spare/1000))k -> \(br)") } }
            }
        }
        r.finalNW = e.netWorth.total
        for co in e.state.companies where co.type != "hold" {
            r.companies.append((co.type, invested[co.id] ?? 0, co.monthlyHistory, co.status.rawValue))
            if co.status == .bust { r.bustCount += 1 }
        }
        if r.bustCount > 0 { r.bankrupt = true }
        // first profitable month of the first company
        if let first = e.state.companies.first(where: { $0.type != "hold" }) {
            let h = first.monthlyHistory
            r.firstProfitMonth = h.firstIndex { $0.profit > 0 }.map { $0 + 1 }
            r.firstYearProfitable = h.prefix(12).reduce(0) { $0 + $1.profit } > 0
        }
        return r
    }

    /// Every startable trade in several countries, standard set-up + modest ad plan, funded 1.3x the estimate, topped up when short. Prints SWP rows.
    static func sweepOne(trade: String, country: String, seed: Int, years: Int) -> String? {
        guard var e = try? GameEngine.newGame(countryCode: country, playerName: "T", seed: seed) else { return nil }
        var id = 0, invested = 0.0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 1e12, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
            id = i
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            invested = (est?.total ?? 1_000_000) * 1.3
            Payments.injectCash(&s, companyID: id, amount: invested)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        guard id != 0 else { return nil }
        for (k, n) in [("google", 1), ("meta", 1), ("seo", 1)] {
            if let ch = e.marketing.channels[k], ch.budgetOptions.count > n { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions[n]) }
        }
        let rate = e.homeCurrency.rate
        for _ in 0..<(years * 364) {
            e.nextDay()
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            if let co = e.state.company(id), co.status.isLive, co.cash < -50_000 {
                let top = -co.cash + 100_000
                e.update { s, _, _ in Payments.injectCash(&s, companyID: id, amount: top) }
                invested += top
            }
            if e.state.isGameOver { break }
        }
        guard let co = e.state.company(id) else { return nil }
        let h = co.monthlyHistory
        var f = ["SWP", trade, country, "\(seed)", co.status.rawValue, String(format: "%.0f", invested / rate)]
        for y in 0..<years {
            let sl = Array(h.dropFirst(y * 12).prefix(12))
            f.append(sl.count == 12 ? String(format: "%.0f/%.0f", sl.reduce(0) { $0 + $1.revenue } / rate, sl.reduce(0) { $0 + $1.profit } / rate) : "-")
        }
        return f.joined(separator: "\t")
    }

    func testSweep() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["LEDGER_SWEEP"] != nil else { return }
        let countries = (env["LEDGER_COUNTRIES"] ?? "CH,UK,MX,JP").split(separator: ",").map(String.init)
        let seeds = (env["LEDGER_SEEDS"] ?? "1,2").split(separator: ",").compactMap { Int($0) }
        let years = Int(env["LEDGER_YEARS"] ?? "3") ?? 3
        let probe = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1)
        var trades = probe.data.catalog.all.filter { SpecialFamilies.isStartable($0) }.map { $0.id }.sorted()
        if let only = env["LEDGER_TRADES"]?.split(separator: ",").map(String.init) { trades = trades.filter { only.contains($0) } }
        var jobs: [(String, String, Int)] = []
        for t in trades { for c in countries { for sd in seeds { jobs.append((t, c, sd)) } } }
        var rows = [String?](repeating: nil, count: jobs.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: jobs.count) { n in
            let r = Self.sweepOne(trade: jobs[n].0, country: jobs[n].1, seed: jobs[n].2, years: years)
            lock.lock(); rows[n] = r; lock.unlock()
        }
        for r in rows.compactMap({ $0 }) { print(r) }
    }

    func testMarket() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_MARKET"] != nil else { return }
        for seed in 1...8 {
            var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
            e.update { s, _, _ in Ledger.move(&s, .me, 5_000_000, why: "x") }
            var line = "MKT seed \(seed) idx/yr:"
            for d in 0..<(10 * 364) {
                e.nextDay()
                if d % 364 == 363 { line += String(format: " %.0f", e.quotes(.fund).first { $0.symbol == "idx" }!.price) }
                if e.state.isGameOver { break }
            }
            let inf = e.state.economy.num("infl")
            print(line, "infl=\(inf) rate=\(e.state.economy.policyRate)")
        }
    }

    func testAffordable() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_AFF"] != nil else { return }
        for cc in ["CH", "UK", "MX", "JP"] {
            let e = try GameEngine.newGame(countryCode: cc, playerName: "T", seed: 1)
            for t in ["tutor", "carclean", "cons", "handy", "photo", "foodtruck", "barber"] {
                for form in [LegalForm.soleTrader, .limited] {
                    if let r = CompanySetup.estimate(tradeID: t, cityID: e.state.player.cityID, form: form, size: 1, state: e.state, data: e.data) {
                        print("BRK \(cc) \(t) \(form) cash=\(Int(e.state.cash/1000)) total=\(Int(r.total/1000)) docs=\(Int(r.documents/1000)) eq=\(Int(r.equipment/1000)) veh=\(Int(r.vehicles/1000)) prem=\(Int(r.premises/1000)) stock=\(Int(r.stock/1000)) pay=\(Int(r.firstPayroll/1000)) buf=\(Int(r.buffer/1000)) reg=\(Int(r.registration/1000)) cap=\(Int(r.shareCapital/1000))")
                    }
                }
            }
        }
        for cc in ["CH", "UK", "MX", "JP"] {
            let e = try GameEngine.newGame(countryCode: cc, playerName: "T", seed: 1)
            var line = "AFF \(cc) cash=\(Int(e.state.cash/1000))k city=\(e.state.player.cityID):"
            for t in e.data.catalog.all.filter({ SpecialFamilies.isStartable($0) }) {
                for form in [LegalForm.soleTrader, .limited] {
                    let sz = max(t.minSize, 0.01)
                    if let est = CompanySetup.estimate(tradeID: t.id, cityID: e.state.player.cityID, form: form, size: sz, state: e.state, data: e.data), est.total <= e.state.cash * 1.0 {
                        line += " \(t.id)\(form == .limited ? "L" : "S")@\(sz)=\(Int(est.total/1000))k"
                    }
                }
            }
            print(line)
            var e2 = e
            var id = 0
            e2.update { s, data, ctx in if case .success(let i) = CompanySetup.create(&s, tradeID: "cons", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i } }
            for k in ["biz", "personal", "consumer"] {
                let o = e2.loanOffer(kind: k, amount: 1_000_000, companyID: k == "biz" ? id : nil)
                print("AFF \(cc) loan \(k): max=\(Int(o.maximum/1000))k margin=\(o.margin) \(o.creditBand)")
            }
        }
    }

    func testCareers() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["LEDGER_CAREER"] != nil else { return }
        let countries = (env["LEDGER_COUNTRIES"] ?? "CH,UK,MX,JP").split(separator: ",").map(String.init)
        let careers = (env["LEDGER_CAREERS"] ?? "baker,landlord,investor,trader,heavy,service").split(separator: ",").map(String.init)
        let seeds = (env["LEDGER_SEEDS"] ?? "1,2,3").split(separator: ",").compactMap { Int($0) }
        let years = Int(env["LEDGER_YEARS"] ?? "10") ?? 10
        var jobs: [(String, String, Int)] = []
        for c in careers { for k in countries { for s in seeds { jobs.append((c, k, s)) } } }
        var results = [Result?](repeating: nil, count: jobs.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: jobs.count) { n in
            let j = jobs[n]
            let t0 = Date()
            if let r = try? Self.run(career: j.0, country: j.1, seed: j.2, years: years) {
                lock.lock(); results[n] = r; lock.unlock()
                FileHandle.standardError.write("DONE \(j) in \(Int(Date().timeIntervalSince(t0)))s\n".data(using: .utf8)!)
            } else { FileHandle.standardError.write("FAIL \(j)\n".data(using: .utf8)!) }
        }
        // Emit TSV rows
        func ttm(_ r: Result, _ thr: Double, ref: Bool) -> String {
            let div = ref ? r.idx : 1
            for s in r.samples where s.nwUnits / r.rate / div >= thr || (ref && s.nwUnits / div >= thr) {
                if ref ? (s.nwUnits / r.rate / r.idx / (1 / r.rate) >= thr) : true { }
            }
            // local currency = units / rate; reference-scaled = units / idx (units are the reference currency)
            for s in r.samples {
                let v = ref ? s.nwUnits / r.idx : s.nwUnits / r.rate
                if v >= thr { return String(format: "%.2f", Double(s.day + 1) / 364) }
            }
            return "-"
        }
        for r in results.compactMap({ $0 }) {
            let nwAt = { (y: Int) -> Double in r.samples.indices.contains(y * 13 - 1) ? r.samples[y * 13 - 1].nwUnits : .nan }
            var f: [String] = ["SIM", r.career, r.country, "\(r.seed)", r.bankrupt ? "BUST" : "ok", r.steppingStone ? "stone" : "direct",
                               r.openedTargetDay.map { String($0) } ?? "-"]
            for t in [1e6, 1e7, 1e8] { f.append(ttm(r, t, ref: false)) }
            for t in [1e6, 1e7, 1e8] { f.append(ttm(r, t, ref: true)) }
            for y in [1, 3, 5, 10] { f.append(String(format: "%.0f", nwAt(y) / r.rate)) }
            f.append(String(format: "%.0f", r.cashY1 / r.rate)); f.append(String(format: "%.0f", r.coCashY1 / r.rate))
            f.append(r.firstProfitMonth.map { String($0) } ?? "-"); f.append(r.firstYearProfitable ? "1" : "0")
            f.append(String(r.distressDays)); f.append(String(r.bustCount)); f.append(r.note)
            print(f.joined(separator: "\t"))
            // company rows: trade, year k profit, revenue, invested
            for c in r.companies {
                var g = ["COMP", r.career, r.country, "\(r.seed)", c.trade, c.status, String(format: "%.0f", c.invested / r.rate), "\(c.months.count)"]
                for y in 0..<4 {
                    let sl = Array(c.months.dropFirst(y * 12).prefix(12))
                    g.append(sl.count == 12 ? String(format: "%.0f/%.0f", sl.reduce(0) { $0 + $1.revenue } / r.rate, sl.reduce(0) { $0 + $1.profit } / r.rate) : "-")
                }
                print(g.joined(separator: "\t"))
            }
        }
    }
}
