import XCTest
import GameCore
import Finance
import Businesses
import Simulation

/// LEDGER_PTRACE=<trade>: what a project company does, quarter by quarter (for balancing).
final class ProjectTraceTests: XCTestCase {
    func testTrace() throws {
        guard let trade = ProcessInfo.processInfo.environment["LEDGER_PTRACE"] else { return }
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: Int(ProcessInfo.processInfo.environment["LEDGER_SEED"] ?? "11") ?? 11)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 2_000_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
            id = i
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.3 + (trade == "realdev" ? 40_000_000 : 0))
            print("PT setup", CompanySetup.quickSetup(&s, companyID: id, data: data))
        }
        if trade != "realdev" {
            for (k, n) in [("google", 1), ("meta", 1), ("seo", 1)] {
                if let ch = e.marketing.channels[k], ch.budgetOptions.count > n { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions[n]) }
            }
        }
        for w in 0..<156 {
            if let co = e.state.company(id), co.status.isLive, co.cash < -50_000 { e.update { s, _, _ in Payments.injectCash(&s, companyID: id, amount: -co.cash + 100_000) } }
            for _ in 0..<7 {
                e.nextDay()
                for m in e.openDecisions { e.answer(messageID: m.id, option: 0) }
            }
            if trade == "realdev", let co = e.state.company(id), co.status == .open, w % 10 == 0 { let r1 = e.startDevelopment(companyID: id, size: 1, financed: true); if w < 60 { print("PT start", r1) }; if r1 == .loanRefused { print("PT start unfinanced", e.startDevelopment(companyID: id, size: 1, financed: false)) } }
            guard let co = e.state.company(id) else { print("PT gone"); break }
            if w == 100, let bd = e.data.catalog[co.type] {
                let wd = World(state: e.state, data: e.data)
                let d = DemandModel.compute(co, bd, wd), c = CapacityModel.compute(co, bd, wd)
                print("PT demand", d.customers, d.parts.map { "\($0.name)=\(String(format: "%.3f", $0.value))" }, "normal", bd.normalDemand, bd.normalCapacity)
                print("PT cap", c.capacity, c.parts.map { "\($0.key)=\(String(format: "%.3f", $0.capacity))" }, "staff", co.staff.map { $0.role })
            }
            if w % 12 == 0 {
                let fm = co.value("fm"), lw = co.value("lastW")
                let b = co.books
                print("PT w\(w) \(co.status.rawValue) cash=\(Int(co.cash/1000))k staff=\(co.staff.count) D=\(String(format: "%.1f", lw["D"].double)) cap=\(String(format: "%.1f", lw["cap"].double)) util=\(String(format: "%.2f", lw["util"].double)) rev=\(Int(lw["rev"].double/1000))k cogs=\(Int(lw["cogs"].double/1000))k jobs=\(fm["jobs"].array.count) backH=\(fm["backlogH"].int) hw=\(Int(fm["hw41"].double)) hvl=\(Int(fm["hvl41"].double)) lost=\(fm["lost41"].array.map { $0.int }) done=\(fm["done"].int) rep=\(Int(co.reputation)) aw=\(Int(co.awareness)) proj=\(fm["proj"].array.map { $0["st"].string + ":" + String($0["sold"].int) }) yr=\(b.year.sorted { $0.key < $1.key }.map { "\($0.key)=\(Int($0.value/1000))" })")
            }
        }
    }
}
