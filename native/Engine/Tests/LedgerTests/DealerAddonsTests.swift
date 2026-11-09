import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Dealer add-ons: warranty with a real reserve, car loans through the bank, insurance at the sale. Setup, booking, take rates and the ledger.
final class DealerAddonsTests: XCTestCase {
    private func game(trade: String = "usedcar", seed: Int = 7) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, fundWith: 400_000_000) else { throw XCTSkip("no company") }
        _ = e.quickSetup(companyID: id)
        _ = e.openCompany(companyID: id)
        // The opening checklist belongs to the trade's own rules (staff, premises); these tests only need a trading company.
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        return (e, id)
    }
    private func balanced(_ e: GameEngine, _ what: String) { XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(what): \(Ledger.gaps(e.state))") }
    private func week(_ e: inout GameEngine, _ id: Int, by n: Int = 1) {
        for _ in 0..<n { e.update { s, d, _ in s.week += 1; if let i = s.companyIndex(id) { DealerAddons.weekly(&s, companyIndex: i, data: d) } } }
    }
    /// All three add-ons set up, approved and switched on.
    private func ready(_ e: inout GameEngine, _ id: Int, _ addons: [DealerAddon] = DealerAddon.allCases) {
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].openedWeek = s.week - 30; s.companies[i].reputation = 70 } }
        for a in addons { XCTAssertEqual(e.startDealerAddonSetup(companyID: id, addon: a), .applied) }
        week(&e, id, by: 8)
        for a in addons {
            XCTAssertEqual(e.dealerAddonSetup(companyID: id, addon: a)?.phase, .approved)
            XCTAssertEqual(e.setDealerAddonEnabled(companyID: id, addon: a, on: true), .applied)
        }
    }
    private func sell(_ e: inout GameEngine, _ id: Int, _ sale: DealerSale) -> DealerAddonResult {
        var r = DealerAddonResult()
        e.update { s, d, _ in r = DealerAddons.apply(&s, companyID: id, sale: sale, data: d) }
        return r
    }
    private func cash(_ e: GameEngine, _ id: Int) -> Double { e.state.company(id)?.cash ?? 0 }
    private func sale(_ e: GameEngine, _ id: Int, _ k: Int, factor: Double = 1) -> DealerSale {
        let co = e.state.company(id)!
        let t = DealerAddons.typicalSale(company: co, state: e.state, data: e.data)
        return DealerSale(key: "t\(k)", price: t.price * factor, car: t.car)
    }

    // MARK: Setup

    func testSetupCostsReviewTimeAndApproval() throws {
        var (e, id) = try game()
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].openedWeek = s.week - 30; s.companies[i].reputation = 70 } }
        let st = try XCTUnwrap(e.dealerAddonSetup(companyID: id, addon: .loan))
        XCTAssertEqual(st.phase, .notStarted)
        XCTAssertTrue(st.canStart)
        XCTAssertEqual(st.requirements.count, 3)
        XCTAssertTrue(st.requirements.contains { $0.isLicence })
        XCTAssertEqual(st.reviewWeeks, 6)
        let before = cash(e, id)
        XCTAssertEqual(e.startDealerAddonSetup(companyID: id, addon: .loan), .applied)
        XCTAssertEqual(before - cash(e, id), st.totalCost, accuracy: 3)
        XCTAssertEqual(e.dealerAddonSetup(companyID: id, addon: .loan)?.phase, .inReview(weeksLeft: 6))
        XCTAssertTrue(e.startDealerAddonSetup(companyID: id, addon: .loan).isRefused)
        XCTAssertTrue(e.setDealerAddonEnabled(companyID: id, addon: .loan, on: true).isRefused, "cannot switch on before approval")
        week(&e, id, by: 5)
        XCTAssertEqual(e.dealerAddonSetup(companyID: id, addon: .loan)?.phase, .inReview(weeksLeft: 1))
        week(&e, id, by: 1)
        XCTAssertEqual(e.dealerAddonSetup(companyID: id, addon: .loan)?.phase, .approved)
        balanced(e, "setup")
    }

    func testReviewCanFailAndFeesAreNotRefunded() throws {
        var (e, id) = try game()
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].openedWeek = s.week - 30; s.companies[i].reputation = 70 } }
        XCTAssertEqual(e.startDealerAddonSetup(companyID: id, addon: .insurance), .applied)
        let after = cash(e, id)
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].reputation = 5 } }
        week(&e, id, by: 5)
        guard case .rejected? = e.dealerAddonSetup(companyID: id, addon: .insurance)?.phase else { return XCTFail("expected a rejection") }
        XCTAssertEqual(cash(e, id), after, accuracy: 1)
        XCTAssertFalse(e.dealerAddonSetup(companyID: id, addon: .insurance)?.canStart ?? true, "reputation still too low to apply again")
        balanced(e, "rejection")
    }

    func testNotACarDealerGetsNothing() throws {
        let (e, id) = try game(trade: "cafe")
        XCTAssertNil(e.dealerAddonSettings(companyID: id))
        XCTAssertTrue(e.dealerAddonPreview(companyID: id).isEmpty)
        XCTAssertNil(e.dealerAddonSetup(companyID: id, addon: .warranty))
    }

    func testNothingIsWrittenUntilUsed() throws {
        var (e, id) = try game()
        XCTAssertTrue(e.state.company(id)!.value("dap").isNull)
        let r = e.update { s, d, _ in DealerAddons.apply(&s, companyID: id, sale: DealerSale(key: "x", price: 14000, car: DealerCar(title: "Car", ageYears: 5, wear: 0.4)), data: d) }
        _ = r
        e.update { s, d, _ in if let i = s.companyIndex(id) { DealerAddons.weekly(&s, companyIndex: i, data: d) } }
        XCTAssertTrue(e.state.company(id)!.value("dap").isNull, "a company that never set anything up keeps its old save shape")
    }

    // MARK: Warranty

    func testWarrantyReserveIsARealLiabilityAndClaimsDrawFromIt() throws {
        var (e, id) = try game()
        ready(&e, id, [.warranty])
        e.setDealerWarranty(companyID: id, includedMonths: 12, extraMonths: 12, extraRate: 0.03)
        var extra = 0.0, reserve = 0.0, sold = 0
        for k in 0..<120 {
            let c0 = cash(e, id)
            var r = DealerAddonResult()
            r = sell(&e, id, sale(e, id, k))
            XCTAssertEqual(cash(e, id) - c0, r.income, accuracy: 1, "only the extension price reaches the cash")
            extra += r.warrantyPrice; reserve += r.warrantyReserve
            if r.warrantyMonths > 0 { sold += 1 }
        }
        XCTAssertEqual(sold, 120, "a year is included in every sale")
        XCTAssertGreaterThan(extra, 0)
        var co = e.state.company(id)!
        XCTAssertEqual(DealerAddons.reserve(co), reserve, accuracy: 1)
        XCTAssertEqual(DealerAddons.warranties(co).reduce(0) { $0 + $1.reserveLeft }, DealerAddons.reserve(co), accuracy: 1)
        XCTAssertEqual(co.payables[DealerAddons.reserveKey] ?? 0, reserve, accuracy: 1)
        let booked = co.books.total["oth"] ?? 0
        XCTAssertGreaterThan(booked, reserve - 1, "the reserve is an expense in the accounts")
        balanced(e, "after sales")
        // Run the warranties out: claims are paid, what is unused is released, the liability ends.
        week(&e, id, by: 120)
        co = e.state.company(id)!
        let t = DealerAddons.totals(co)
        XCTAssertGreaterThan(t.claimCount, 5)
        XCTAssertEqual(DealerAddons.reserve(co), 0, accuracy: 1)
        XCTAssertTrue(DealerAddons.warranties(co).isEmpty)
        XCTAssertGreaterThan(t.claimsPaid, reserve * 0.4, "claims follow the expected cost: \(t.claimsPaid) against reserve \(reserve)")
        XCTAssertLessThan(t.claimsPaid, reserve * 1.8)
        balanced(e, "after expiry")
    }

    func testWarrantyTakeRateFollowsPriceAndAge() throws {
        var (e, id) = try game()
        ready(&e, id, [.warranty])
        func take(rate: Double, age: Double) -> Double {
            e.setDealerWarranty(companyID: id, extraMonths: 12, extraRate: rate)
            let co = e.state.company(id)!
            let t = DealerAddons.typicalSale(company: co, state: e.state, data: e.data)
            return DealerAddons.offers(forSale: t.price, car: DealerCar(title: "c", ageYears: age, wear: min(1, age / 12)), company: co, state: e.state, data: e.data).first { $0.addon == .warranty }!.takeRate
        }
        XCTAssertGreaterThan(take(rate: 0.05, age: 6), take(rate: 0.12, age: 6))
        XCTAssertGreaterThan(take(rate: 0.07, age: 9), take(rate: 0.07, age: 1), "older cars worry buyers more")
        XCTAssertGreaterThan(take(rate: 0.0, age: 3), 0.9, "a free extension is taken")
    }

    func testIncludedWarrantyCostsReserveButSellsNothing() throws {
        var (e, id) = try game()
        ready(&e, id, [.warranty])
        e.setDealerWarranty(companyID: id, includedMonths: 6, extraMonths: 0)
        var r = DealerAddonResult()
        r = sell(&e, id, sale(e, id, 1))
        XCTAssertEqual(r.warrantyMonths, 6)
        XCTAssertEqual(r.warrantyPrice, 0)
        XCTAssertGreaterThan(r.warrantyReserve, 0)
        let off = DealerAddons.offers(forSale: 14000, car: DealerCar(title: "c", ageYears: 6, wear: 0.4), company: e.state.company(id)!, state: e.state, data: e.data).first { $0.addon == .warranty }!
        XCTAssertGreaterThan(off.demandBoost, 0)
        XCTAssertLessThan(off.expectedNet, 0, "an included warranty is a cost of the sale")
        balanced(e, "included")
    }

    // MARK: Loans

    func testLoanCommissionComesFromTheBankAndTheLoanIsNotTheDealers() throws {
        var (e, id) = try game()
        ready(&e, id, [.loan])
        let loansBefore = e.state.loans.count
        var financed = 0.0, comm = 0.0, n = 0
        for k in 0..<300 {
            var r = DealerAddonResult()
            let c0 = cash(e, id)
            r = sell(&e, id, sale(e, id, k))
            XCTAssertEqual(cash(e, id) - c0, r.income, accuracy: 1)
            if r.financedAmount > 0 {
                n += 1; financed += r.financedAmount; comm += r.financeCommission
                XCTAssertEqual(r.financeCommission / r.financedAmount, 0.02, accuracy: 0.0005)
            }
        }
        XCTAssertGreaterThan(n, 20)
        XCTAssertEqual(comm / financed, 0.02, accuracy: 0.0005, "commission is 2 percent of the financed amount")
        XCTAssertEqual(e.state.loans.count, loansBefore, "the customer's loan is the bank's: nothing on the dealer's books")
        XCTAssertEqual(DealerAddons.totals(e.state.company(id)!).financedSales, n)
        balanced(e, "loans")
    }

    func testDeclinedApplicationsLoseSalesMoreOnExpensiveCars() throws {
        var (e, id) = try game()
        ready(&e, id, [.loan])
        func lost(_ factor: Double) -> Int {
            var lost = 0
            for k in 0..<400 {
                var r = DealerAddonResult()
                r = sell(&e, id, sale(e, id, 1000 * Int(factor * 10) + k, factor: factor))
                if !r.saleCompleted { lost += 1; XCTAssertTrue(r.financeDeclined); XCTAssertEqual(r.income, 0) }
            }
            return lost
        }
        let cheap = lost(0.5), dear = lost(4)
        XCTAssertGreaterThan(dear, cheap)
        XCTAssertGreaterThan(dear, 10)
        balanced(e, "declines")
    }

    func testHigherLoanCommissionIsClampedToTheSchedule() throws {
        var (e, id) = try game()
        e.setDealerCommission(companyID: id, addon: .loan, rate: 0.09)
        XCTAssertEqual(e.dealerAddonSettings(companyID: id)?.loanCommission ?? 0, 0.03, accuracy: 1e-9)
        e.setDealerCommission(companyID: id, addon: .loan, rate: 0.0)
        XCTAssertEqual(e.dealerAddonSettings(companyID: id)?.loanCommission ?? 0, 0.01, accuracy: 1e-9)
    }

    // MARK: Insurance

    func testInsuranceTakeRateComesFromThePriceAdvantage() throws {
        var (e, id) = try game()
        ready(&e, id, [.insurance])
        func offer(_ c: Double) -> DealerAddonOffer {
            e.setDealerCommission(companyID: id, addon: .insurance, rate: c)
            return e.dealerAddonPreview(companyID: id).first { $0.addon == .insurance }!
        }
        let low = offer(0.10), mid = offer(0.15), high = offer(0.20)
        XCTAssertGreaterThan(low.takeRate, mid.takeRate)
        XCTAssertGreaterThan(mid.takeRate, high.takeRate)
        XCTAssertGreaterThan(mid.takeRate, 0.7, "cheaper than buying it separately: most customers take it")
        XCTAssertGreaterThan(low.customerSaving, high.customerSaving)
        XCTAssertGreaterThan(high.customerSaving, 0)
        // The dealer's income per sale: take rate times commission on the first-year premium.
        XCTAssertEqual(mid.expectedIncome, mid.takeRate * mid.customerPrice * 0.15, accuracy: mid.customerPrice * 0.001)
    }

    func testInsuranceCommissionIsOneTimeAndThePolicyIsARealRecord() throws {
        var (e, id) = try game()
        ready(&e, id, [.insurance])
        var comm = 0.0
        let c0 = cash(e, id)
        for k in 0..<100 {
            var r = DealerAddonResult()
            r = sell(&e, id, sale(e, id, k))
            comm += r.insuranceCommission
            if let no = r.policyNumber { XCTAssertTrue(no.hasPrefix("DI-")) }
        }
        let pols = DealerAddons.policies(e.state.company(id)!)
        XCTAssertGreaterThan(pols.count, 60)
        XCTAssertEqual(Set(pols.map { $0.number }).count, pols.count, "policy numbers are unique")
        XCTAssertEqual(pols.reduce(0) { $0 + $1.commission }, comm, accuracy: 1)
        for p in pols { XCTAssertEqual(p.commission / p.premium, 0.15, accuracy: 0.01); XCTAssertGreaterThan(p.yearlySaving, 0); XCTAssertEqual(p.untilWeek - p.week, 52) }
        XCTAssertEqual(cash(e, id) - c0, comm, accuracy: 1, "the commission is the only cash: the customer pays the insurer")
        // A year later nothing more is paid: it was a one-time commission.
        let before = cash(e, id)
        week(&e, id, by: 60)
        XCTAssertEqual(cash(e, id), before, accuracy: 1)
        balanced(e, "insurance")
    }

    // MARK: Whole

    func testAllThreeTogetherOnNewCarDealerKeepTheLedgerBalanced() throws {
        var (e, id) = try game(trade: "cardealer")
        ready(&e, id)
        e.setDealerWarranty(companyID: id, includedMonths: 12, extraMonths: 24, extraRate: 0.02)
        let off = e.dealerAddonPreview(companyID: id)
        XCTAssertEqual(off.count, 3)
        XCTAssertTrue(off.allSatisfy { $0.active && $0.setUp })
        var income = 0.0
        let c0 = cash(e, id)
        for k in 0..<200 {
            var r = DealerAddonResult()
            r = sell(&e, id, sale(e, id, k))
            income += r.income
        }
        XCTAssertEqual(cash(e, id) - c0, income, accuracy: 2)
        week(&e, id, by: 200)
        balanced(e, "three add-ons")
        XCTAssertEqual(DealerAddons.reserve(e.state.company(id)!), 0, accuracy: 1)
    }
}
