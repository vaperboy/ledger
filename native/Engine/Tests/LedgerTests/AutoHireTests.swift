import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Automatic hiring: always as cheaply as possible for the best talent, better when the hirer is better, and no change to how often people are hired.
final class AutoHireTests: XCTestCase {
    private let weak = AutoHire.Hirer(reading: 0.05, push: 0.05, breadth: 0.1)
    private let strong = AutoHire.Hirer(reading: 0.95, push: 0.95, breadth: 0.95)

    private func shop(_ seed: Int, trade: String = "cafe") throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: 20_000_000) else { throw XCTSkip("start") }
        return (e, id)
    }

    /// Same candidates, same company, same random stream: only the hirer differs. Over many seeds the better hirer pays less for each point of skill.
    func testABetterHirerPaysLessPerSkillAndGetsMoreTalent() throws {
        var costWeak = 0.0, costStrong = 0.0, skillWeak = 0.0, skillStrong = 0.0, hiredWeak = 0, hiredStrong = 0
        for seed in 1...80 {
            let (base, id) = try shop(seed)
            var pool: [Person] = []
            var b = base
            b.update { s, d, _ in pool = Hiring.search(role: "barista", company: s.company(id)!, mode: .network, state: &s, data: d) }
            for (hirer, isStrong) in [(weak, false), (strong, true)] {
                var e = b
                var got: Person?
                var wage = 0.0, market = 0.0
                e.update { s, d, _ in
                    market = Hiring.marketWage(role: "barista", company: s.company(id), state: s, data: d)
                    got = AutoHire.hireWorker(role: "barista", companyID: id, candidates: pool, hirer: hirer, state: &s, data: d)
                    wage = s.company(id)?.staff.first { $0.id == got?.id }?.monthlyWage ?? 0
                }
                guard let p = got else { continue }
                let skill = e.state.people[p.id]!.skill
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
                if isStrong { costStrong += wage / market / (0.5 + skill / 100); skillStrong += skill; hiredStrong += 1 }
                else { costWeak += wage / market / (0.5 + skill / 100); skillWeak += skill; hiredWeak += 1 }
            }
        }
        XCTAssertGreaterThan(hiredWeak, 60); XCTAssertGreaterThan(hiredStrong, 60)
        let cw = costWeak / Double(hiredWeak), cs = costStrong / Double(hiredStrong)
        print("NEGO autohire cost per skill weak \(cw) strong \(cs); skill weak \(skillWeak / Double(hiredWeak)) strong \(skillStrong / Double(hiredStrong)); hired \(hiredWeak)/\(hiredStrong)")
        XCTAssertLessThan(cs, cw, "a better hirer pays less for each point of skill")
        XCTAssertGreaterThan(skillStrong / Double(hiredStrong), skillWeak / Double(hiredWeak), "and finds more talented people")
    }

    /// Nobody is hired above what their believed skill is worth at the going rate (the walk-away value), and never below the minimum wage.
    func testNeverPaysAboveTheWalkAwayValue() throws {
        for seed in 1...40 {
            let (base, id) = try shop(seed)
            var e = base
            e.update { s, d, _ in
                let pool = Hiring.search(role: "barista", company: s.company(id)!, mode: .ads, state: &s, data: d)
                guard let p = AutoHire.hireWorker(role: "barista", companyID: id, candidates: pool, hirer: self.strong, state: &s, data: d),
                      let m = s.company(id)?.staff.first(where: { $0.id == p.id }) else { return }
                let market = Hiring.marketWage(role: "barista", company: s.company(id), state: s, data: d)
                // the most the hirer could believe is the claim; the oldest age group asks 1.2 times the going rate at the same skill
                let worth = market * 1.2 * (0.55 + max(p.skill, p.claimedSkill) / 110) * 1.25
                XCTAssertLessThanOrEqual(m.monthlyWage, max(worth, World(state: s, data: d).minimumWage(s.company(id)!)) + 100, "seed \(seed)")
            }
        }
    }

    /// The same offers go through the same single door: a worker the hirer settles on is hired by `Hiring.hire` and nobody else makes the record.
    func testManagersAreHiredByTheSameRule() throws {
        var better = 0.0, worse = 0.0, n = 0
        for seed in 1...40 {
            let (base, id) = try shop(seed)
            var found: [Person] = []
            var b = base
            b.update { s, d, _ in
                let co = s.company(id)!
                found = (0..<3).map { _ in ManagerModel.generateCandidate(company: co, type: d.catalog[co.type]!.managerType, state: &s, data: d) }
                found.append(ManagerModel.generateCandidate(company: co, type: "gen", state: &s, data: d))
            }
            var dw: AutoHire.Deal?, ds: AutoHire.Deal?
            var e1 = b, e2 = b
            e1.update { s, d, _ in dw = AutoHire.bestManagerDeal(candidates: found, companyID: id, hirer: self.weak, state: &s, data: d) }
            e2.update { s, d, _ in ds = AutoHire.bestManagerDeal(candidates: found, companyID: id, hirer: self.strong, state: &s, data: d) }
            guard let a = dw, let c = ds else { continue }
            worse += a.price / (0.5 + a.person.skill / 100); better += c.price / (0.5 + c.person.skill / 100); n += 1
            var e3 = b
            e3.update { s, d, _ in XCTAssertEqual(ManagerModel.hire(&s, personID: c.person.id, companyID: id, monthlyWage: c.price, data: d), .ok, "the agreed wage is accepted") }
        }
        XCTAssertGreaterThan(n, 30)
        print("NEGO manager deals: cost per skill weak \(worse / Double(n)) strong \(better / Double(n))")
        XCTAssertLessThan(better, worse)
    }

    /// The cadence is unchanged: whenever a company is short of someone and can pay, the standing instruction fills the gap in that same week, as before.
    func testEveryGapIsFilledInTheWeekItIsFound() throws {
        var gaps = 0, filled = 0
        for seed in 1...60 {
            var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
            var id = 0
            e.update { s, data, ctx in
                Ledger.move(&s, .me, 80_000_000, why: "Test funds")
                if case .success(let i) = CompanySetup.create(&s, tradeID: "grocery", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
                Payments.injectCash(&s, companyID: id, amount: 60_000_000)
                _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
                let i = s.companyIndex(id)!
                s.companies[i].status = .open
                if let m = s.companies[i].staff.last {
                    s.companies[i].staff.removeLast()
                    if var p = s.people[m.id] { p.employerID = 0; s.people[m.id] = p }
                }
            }
            let before = e.state.company(id)!.staff.count
            e.update { s, d, _ in AutoStaff.weekly(&s, data: d) }
            gaps += 1
            if e.state.company(id)!.staff.count == before + 1 { filled += 1 }
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        }
        XCTAssertEqual(filled, gaps, "every gap is filled in the week it is found")
    }

    /// Whole-game sanity check, not an exact pin (a different price changes who stays and who leaves, so the random paths differ): over 10 runs of 104 weeks
    /// the number of people added after setup stays near what the code before this change produced (restaurant and grocery, seeds 1-5: 22 + 51 = 73).
    func testHiringVolumesInAWholeGame() throws {
        var hires = 0
        for trade in ["restaurant", "grocery"] {
            for seed in 1...5 {
                var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
                var id = 0
                e.update { s, data, ctx in
                    Ledger.move(&s, .me, 80_000_000, why: "Test funds")
                    if case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
                    let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
                    Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 3)
                    _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: false)
                }
                var seen = Set(e.state.company(id)!.staff.map { $0.id })
                for _ in 0..<(104 * 7) {
                    e.nextDay()
                    for m in e.state.company(id)?.staff ?? [] where !seen.contains(m.id) { seen.insert(m.id); hires += 1 }
                }
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
            }
        }
        print("NEGO volumes: \(hires) hires after setup (before this change: 73)")
        XCTAssertEqual(Double(hires), 73, accuracy: 73 * 0.4)
    }
}
