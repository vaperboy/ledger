import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Events
@testable import Simulation

/// A holding that borrows to buy, divisions, selling moved shares, board talks and a holding made from part of a company.
final class HoldingExtrasTests: XCTestCase {
    private func start() throws -> (GameEngine, hid: Int) {
        var e = try ChainsTests.engine("UK")
        guard case .success(let hid) = e.createHolding(name: "H", companies: []) else { throw XCTSkip("holding was not created") }
        return (e, hid)
    }
    private func company(_ e: inout GameEngine) -> Int {
        let cid = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in _ = Payments.injectCash(&s, companyID: cid, amount: 100_000_000) }
        return cid
    }
    private func cash(_ e: GameEngine, _ id: Int) -> Double { e.state.company(id)?.cash ?? 0 }
    private func pct(_ e: GameEngine, _ hid: Int, _ cid: Int) -> Double { HoldingStakes.sharePercent(of: e.state.company(cid)!, holdingID: hid) }
    private func value(_ e: GameEngine, _ cid: Int) -> Double { Valuation.companyValue(e.state.company(cid)!, state: e.state, trades: e.data.catalog) }
    /// Bring the holding's cash to `target` by putting money in (never takes it out).
    private func setCash(_ e: inout GameEngine, _ hid: Int, to target: Double) {
        let add = target - cash(e, hid)
        if add > 0 { e.update { s, _, _ in _ = Payments.injectCash(&s, companyID: hid, amount: add) } }
    }

    // MARK: Borrowing to buy

    func testBuyWithLoanBorrowsTheShortfall() throws {
        var (e, hid) = try start()
        let cid = company(&e)
        let price = try e.holdingStakeQuote(holdingID: hid, companyID: cid, percent: 25).get().price
        setCash(&e, hid, to: price * 0.7)
        XCTAssertLessThan(cash(e, hid), price)
        XCTAssertEqual(e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 25).failureValue, .notEnoughCash(needed: price))
        let terms = try e.holdingBuyLoanQuote(holdingID: hid, companyID: cid, percent: 25).get()
        if terms.creditBand == "E" { throw XCTSkip("no credit") }
        XCTAssertTrue(terms.allowed, terms.reason)
        XCTAssertEqual(terms.shortfall, price - cash(e, hid), accuracy: 1)
        XCTAssertEqual(terms.amount, terms.shortfall.rounded(.up))
        XCTAssertGreaterThan(terms.yearlyRate, e.state.economy.policyRate + HoldingStakes.holdingLoanMargin)
        XCTAssertGreaterThan(terms.monthlyPayment, 0)
        XCTAssertEqual(terms.debtAfter, terms.debtBefore + terms.amount, accuracy: 1e-6)
        let loans0 = e.state.loans.count
        let r = try e.holdingBuyStakeWithLoan(holdingID: hid, companyID: cid, percent: 25).get()
        XCTAssertEqual(r.borrowed, terms.amount)
        XCTAssertEqual(pct(e, hid, cid), 25, accuracy: 0.01)
        XCTAssertEqual(e.state.loans.count, loans0 + 1)
        let loan = try XCTUnwrap(e.state.loans.first { $0.id == r.loanID })
        XCTAssertEqual(loan.companyID, hid)
        XCTAssertEqual(loan.balance, terms.amount, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(cash(e, hid), 0)
        XCTAssertLessThan(cash(e, hid), 2, "the loan was sized to the shortfall")
        XCTAssertGreaterThanOrEqual(CompanyFigures.debts(try XCTUnwrap(e.state.company(hid)), loans: e.state.loans), terms.amount)
        XCTAssertTrue(e.loanRecords(companyID: hid).contains { $0.id == r.loanID })
        XCTAssertFalse(e.loanSchedule(loanID: r.loanID).isEmpty)
        XCTAssertGreaterThanOrEqual(e.holdingOverview(companyID: hid)?.debtInGroup ?? 0, terms.amount - 1, "the debt shows in the holding's finances")
    }

    func testBuyWithLoanWithEnoughCashBorrowsNothing() throws {
        var (e, hid) = try start()
        let cid = company(&e)
        let price = try e.holdingStakeQuote(holdingID: hid, companyID: cid, percent: 10).get().price
        setCash(&e, hid, to: price * 2)
        let r = try e.holdingBuyStakeWithLoan(holdingID: hid, companyID: cid, percent: 10).get()
        XCTAssertEqual(r.borrowed, 0)
        XCTAssertEqual(r.loanID, 0)
        XCTAssertTrue(e.state.loans.filter { $0.companyID == hid }.isEmpty)
    }

    func testLoanIsCappedByWhatTheHoldingOwnsAndRefusalChangesNothing() throws {
        var (e, hid) = try start()
        let cid = company(&e)
        let price = try e.holdingStakeQuote(holdingID: hid, companyID: cid, percent: 25).get().price
        setCash(&e, hid, to: price * 0.05)
        let terms = try e.holdingBuyLoanQuote(holdingID: hid, companyID: cid, percent: 25).get()
        if terms.creditBand == "E" { throw XCTSkip("no credit") }
        XCTAssertFalse(terms.allowed)
        XCTAssertLessThanOrEqual(terms.maximum, cash(e, hid) + 1)
        let before = e.state
        if case .failure(let f) = e.holdingBuyStakeWithLoan(holdingID: hid, companyID: cid, percent: 25) { XCTAssertFalse(f.reason.isEmpty) } else { XCTFail("the lender should refuse") }
        XCTAssertEqual(e.state.loans.count, before.loans.count)
        XCTAssertEqual(cash(e, hid), before.company(hid)?.cash ?? -1, accuracy: 1e-9)
        XCTAssertEqual(pct(e, hid, cid), 0, accuracy: 1e-9)
    }

    // MARK: Division

    func testDivisionKeepsEverythingAndNetWorth() throws {
        var (e, hid) = try start()
        let cid = company(&e)
        XCTAssertTrue(e.moveToHolding(companyID: cid, holdingID: hid))
        let t = e.holdingDivisionTerms(holdingID: hid, companyID: cid)
        XCTAssertTrue(t.allowed, t.reason)
        XCTAssertTrue(t.hostIsHolding)
        let nw0 = e.netWorth.total
        let co0 = try XCTUnwrap(e.state.company(cid))
        let staff0 = co0.staff.count, cash0 = co0.cash, items0 = e.salesItems(companyID: cid).map { $0.id }, type0 = co0.type
        _ = try e.holdingMakeDivision(holdingID: hid, companyID: cid).get()
        let co = try XCTUnwrap(e.state.company(cid))
        XCTAssertTrue(HoldingStakes.isDivision(co))
        XCTAssertEqual(HoldingStakes.divisionHostID(co), hid)
        XCTAssertEqual(co.type, type0)
        XCTAssertEqual(co.staff.count, staff0)
        XCTAssertEqual(co.cash, cash0, accuracy: 1e-9)
        XCTAssertEqual(e.salesItems(companyID: cid).map { $0.id }, items0)
        XCTAssertEqual(e.netWorth.total, nw0, accuracy: max(1, abs(nw0) * 1e-9))
        XCTAssertEqual(e.holdingDivisions(hostID: hid).map { $0.id }, [cid])
        XCTAssertFalse(e.holdingStakeOffers(holdingID: hid).contains { $0.companyID == cid }, "no longer a company to buy shares of")
        XCTAssertFalse(e.releaseFromHolding(companyID: cid), "a division cannot be taken out as a company")
        XCTAssertFalse(e.holdingMakeDivision(holdingID: hid, companyID: cid).isSuccess, "once")
    }

    func testDivisionOfAnotherCompanyOfTheHolding() throws {
        var (e, hid) = try start()
        let a = company(&e), b = company(&e)
        XCTAssertTrue(e.moveToHolding(companyID: a, holdingID: hid))
        XCTAssertTrue(e.moveToHolding(companyID: b, holdingID: hid))
        let t = e.holdingDivisionTerms(holdingID: hid, companyID: a, hostID: b)
        XCTAssertTrue(t.allowed, t.reason)
        XCTAssertFalse(t.hostIsHolding)
        let nw0 = e.netWorth.total
        _ = try e.holdingMakeDivision(holdingID: hid, companyID: a, hostID: b).get()
        XCTAssertEqual(HoldingStakes.divisionHostID(try XCTUnwrap(e.state.company(a))), b)
        XCTAssertEqual(e.netWorth.total, nw0, accuracy: max(1, abs(nw0) * 1e-9))
        XCTAssertFalse(e.releaseFromHolding(companyID: b), "the host keeps its division under the holding")
        // the host cannot itself become a division of its own division
        XCTAssertFalse(e.holdingDivisionTerms(holdingID: hid, companyID: b, hostID: a).allowed)
    }

    func testDivisionNeedsAWhollyOwnedCompany() throws {
        var (e, hid) = try start()
        let cid = company(&e)
        _ = try e.moveToHolding(companyID: cid, holdingID: hid, percent: 50).get()
        let t = e.holdingDivisionTerms(holdingID: hid, companyID: cid)
        XCTAssertFalse(t.allowed)
        XCTAssertFalse(t.reason.isEmpty)
        XCTAssertFalse(e.holdingMakeDivision(holdingID: hid, companyID: cid).isSuccess)
    }

    // MARK: Selling moved shares

    func testSellingSharesMovedUnderTheHolding() throws {
        var (e, hid) = try start()
        let cid = company(&e)
        XCTAssertTrue(e.moveToHolding(companyID: cid, holdingID: hid))
        let v = value(e, cid)
        let h0 = cash(e, hid)
        let q = try e.holdingSellStakeQuote(holdingID: hid, companyID: cid, percent: 10).get()
        XCTAssertEqual(q.movedPercent, 10, accuracy: 0.01)
        XCTAssertEqual(q.boughtPercent, 0, accuracy: 1e-9)
        XCTAssertEqual(q.price, v * 0.10, accuracy: max(10, v * 1e-4), "a controlling stake sells at fair value")
        let d = try e.holdingSellStake(holdingID: hid, companyID: cid, percent: 10).get()
        XCTAssertEqual(d.movedPercent, 10, accuracy: 0.01)
        XCTAssertEqual(cash(e, hid), h0 + q.price, accuracy: 1e-6)
        XCTAssertEqual(pct(e, hid, cid), 90, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(e.state.company(cid)).ownership, 90, accuracy: 0.01)
        let t = CapTable.table(try XCTUnwrap(e.state.company(cid)))
        XCTAssertEqual(t.you + t.holders.reduce(0) { $0 + $1.shares }, t.total, "shares still add up")
        // moved shares cannot be bought back as a purchase: they come back with release
        XCTAssertFalse(e.holdingSellStakeQuote(holdingID: hid, companyID: cid, percent: 5, to: .owner).isSuccess)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testSaleReportsTheSplitBetweenBoughtAndMovedShares() throws {
        var (e, hid) = try start()
        let cid = company(&e)
        e.update { s, _, _ in
            let i = s.companyIndex(cid)!
            CapTable.issue(&s, i, newShares: CapTable.sharesForPercent(30, total: CapTable.table(s.companies[i]).total), to: "Angel", paid: 1)
        }
        setCash(&e, hid, to: 2_000_000_000)
        XCTAssertTrue(e.moveToHolding(companyID: cid, holdingID: hid))   // your 70% under the holding
        _ = try e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 10, from: .others).get()
        XCTAssertEqual(pct(e, hid, cid), 80, accuracy: 0.01)
        let q = try e.holdingSellStakeQuote(holdingID: hid, companyID: cid, percent: 15).get()
        XCTAssertEqual(q.boughtPercent, 10, accuracy: 0.01, "the bought shares go first")
        XCTAssertEqual(q.movedPercent, 5, accuracy: 0.01)
        XCTAssertEqual(q.boughtPercent + q.movedPercent, q.percent, accuracy: 1e-9)
        let d = try e.holdingSellStake(holdingID: hid, companyID: cid, percent: 15).get()
        XCTAssertEqual(d.boughtPercent, 10, accuracy: 0.01)
        XCTAssertEqual(d.movedPercent, 5, accuracy: 0.01)
        XCTAssertEqual(pct(e, hid, cid), 65, accuracy: 0.01)
        XCTAssertFalse(try XCTUnwrap(e.state.company(cid)).value("holders").array.contains { $0["hid"].int == hid }, "the bought line is gone")
        XCTAssertEqual(try XCTUnwrap(e.state.company(cid)).holdingID, hid, "what is left of your shares is still under the holding")
        // more than the holding owns is refused
        XCTAssertFalse(e.holdingSellStakeQuote(holdingID: hid, companyID: cid, percent: 90).isSuccess)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    // MARK: Owner talks at a holding's board

    func testOwnerTalksAtABoardTheHoldingSitsOn() throws {
        var (e, hid) = try start()
        let a = company(&e), b = company(&e)
        setCash(&e, hid, to: 2_000_000_000)
        _ = try e.holdingBuyStake(holdingID: hid, companyID: a, percent: 60).get()   // control: a seat of right
        _ = try e.holdingBuyStake(holdingID: hid, companyID: b, percent: 10, from: .owner).get()   // passive: none
        XCTAssertTrue(e.holdingSeatedCompanies(holdingID: hid).contains { $0.id == a })
        XCTAssertFalse(e.holdingSeatedCompanies(holdingID: hid).contains { $0.id == b })
        let people = try e.holdingOwnerCounterparts(holdingID: hid, companyID: a).get()
        XCTAssertEqual(people.map { $0.id }, e.ownerCounterparts(companyID: a).map { $0.id }, "the same people as the owner's own round")
        XCTAssertFalse(e.holdingOwnerCounterparts(holdingID: hid, companyID: b).isSuccess, "no seat, no talks")
        XCTAssertFalse(e.holdingOwnerTopics(holdingID: hid, companyID: b, personID: 1).isSuccess)
        XCTAssertFalse(e.holdingOwnerScene(holdingID: hid, companyID: b, personID: 1, topic: "results").isSuccess)
        XCTAssertFalse(e.holdingOwnerChoose(holdingID: hid, companyID: b, personID: 1, topic: "results", choice: "x").isSuccess)
        if let p = people.first {
            let topics = try e.holdingOwnerTopics(holdingID: hid, companyID: a, personID: p.id).get()
            XCTAssertEqual(topics.map { $0.id }, e.ownerTopics(companyID: a, personID: p.id).map { $0.id })
            if let tp = topics.first, e.ownerScene(companyID: a, personID: p.id, topic: tp.id) != nil {
                let sc = try e.holdingOwnerScene(holdingID: hid, companyID: a, personID: p.id, topic: tp.id).get()
                if let c = sc.choices.first { _ = e.holdingOwnerChoose(holdingID: hid, companyID: a, personID: p.id, topic: tp.id, choice: c.id) }
            }
        }
    }

    // MARK: A holding made from part of a company

    func testCreateHoldingWithPartialStakes() throws {
        var e = try ChainsTests.engine("UK")
        let a = company(&e), b = company(&e)
        let hid = try e.createHolding(name: "Part", stakes: [HoldingModel.StakeInput(companyID: a, percent: 100), HoldingModel.StakeInput(companyID: b, percent: 40)]).get()
        XCTAssertEqual(try XCTUnwrap(e.state.company(a)).holdingID, hid, "the whole company moves")
        XCTAssertEqual(pct(e, hid, a), 100, accuracy: 0.01)
        XCTAssertEqual(pct(e, hid, b), 40, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(e.state.company(b)).ownership, 60, accuracy: 0.01, "you keep the rest")
        XCTAssertEqual(try XCTUnwrap(e.state.company(b)).holdingID, 0)
        XCTAssertEqual(e.holdingStakeTier(holdingID: hid, companyID: b), .influence)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testCreateHoldingSkipsAStakeThatCannotMoveAndSaysSo() throws {
        var e = try ChainsTests.engine("UK")
        let a = company(&e)
        let hid = try e.createHolding(name: "Skip", stakes: [HoldingModel.StakeInput(companyID: a, percent: 0.1), HoldingModel.StakeInput(companyID: 999_999, percent: 50)]).get()
        XCTAssertEqual(pct(e, hid, a), 0, accuracy: 1e-9)
    }
}

private extension Result {
    var isSuccess: Bool { if case .success = self { return true } else { return false } }
    var failureValue: Failure? { if case .failure(let f) = self { return f } else { return nil } }
}
