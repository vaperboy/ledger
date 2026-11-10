import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

final class PhoneAppsTests: XCTestCase {
    private func game(seed: Int = 7) throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        return e
    }

    private func cafe(_ e: inout GameEngine, funds: Double = 60_000_000) throws -> Int {
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else { throw XCTSkip("no cafe") }
        return id
    }

    private func machineLine(_ e: GameEngine, _ id: Int, cls: Int = 1) throws -> (line: StoreOrders.Line, equipmentID: String) {
        let item = try XCTUnwrap(e.equipmentNeeds(companyID: id).first { !$0.isVehicle && !$0.isSoftware && $0.kind != "svc" })
        let offer = try XCTUnwrap(e.equipmentOffers(companyID: id, equipmentID: item.equipmentID).first { $0.cls == cls })
        return (StoreOrders.Line(kind: .new, equipmentID: item.equipmentID, quantity: 1, offerIndex: offer.index, payment: .cash), item.equipmentID)
    }

    func testOrderIsPaidAtCheckoutAndArrivesOnTheDeliveryDay() throws {
        var e = try game()
        let id = try cafe(&e)
        let (line, eq) = try machineLine(e, id)
        let quote = try XCTUnwrap(e.storeQuote(companyID: id, lines: [line], delivery: .standard))
        XCTAssertGreaterThan(quote.days, 0, "a machine is not delivered the same day")
        XCTAssertTrue(quote.needsShipping)
        XCTAssertGreaterThan(quote.shipping, 0)
        XCTAssertEqual(quote.chargeNow, quote.goods + quote.shipping, accuracy: 0.5)
        let cash0 = try XCTUnwrap(e.state.company(id)?.cash)
        let n0 = e.state.company(id)?.value("eq")[eq]["n"].double ?? 0
        guard case .placed(let number, _, let total) = e.placeStoreOrder(companyID: id, lines: [line], delivery: .standard, receiptCompanyID: id) else { return XCTFail("not placed") }
        XCTAssertTrue(number.hasPrefix("TS-"))
        XCTAssertEqual(total, quote.chargeNow, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)?.cash), cash0 - quote.chargeNow, accuracy: 1, "paid at checkout, nothing more at delivery")
        XCTAssertEqual(e.state.company(id)?.value("eq")[eq]["n"].double ?? 0, n0, "not delivered yet")
        XCTAssertEqual(e.storeOrders(companyID: id).first?.delivered, false)
        var delivered = false
        for day in 1...(quote.days + 1) {
            _ = e.nextDay()
            let n = e.state.company(id)?.value("eq")[eq]["n"].double ?? 0
            if n > n0 { delivered = true; XCTAssertEqual(day, quote.days, "arrives on the delivery date, not before"); break }
        }
        XCTAssertTrue(delivered, "the item arrived on its delivery day")
        XCTAssertEqual(e.storeOrders(companyID: id).first?.delivered, true)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testExpressIsQuickerAndDearerAndOwnDeliveryNeedsYourOwnCarrier() throws {
        var e = try game(seed: 11)
        let id = try cafe(&e)
        let (line, _) = try machineLine(e, id)
        let std = try XCTUnwrap(e.storeQuote(companyID: id, lines: [line], delivery: .standard))
        let exp = try XCTUnwrap(e.storeQuote(companyID: id, lines: [line], delivery: .express))
        XCTAssertLessThanOrEqual(exp.days, std.days)
        XCTAssertGreaterThan(exp.shipping, std.shipping)
        XCTAssertNil(e.storeQuote(companyID: id, lines: [line], delivery: .own), "no delivery company of your own yet")
        XCTAssertNil(e.storeShipping().ownCompanyID)
        guard case .success(let carrier) = e.startCompany(tradeID: "courier", cityID: e.state.player.cityID) else { throw XCTSkip("no courier") }
        e.update { s, _, _ in if let i = s.companyIndex(carrier) { s.companies[i].status = .open } }
        let own = try XCTUnwrap(e.storeQuote(companyID: id, lines: [line], delivery: .own))
        XCTAssertGreaterThan(own.shipping, 0, "your own company charges a delivery fee")
        XCTAssertLessThan(own.shipping, std.shipping)
        XCTAssertLessThanOrEqual(own.days, std.days)
        XCTAssertTrue(own.carrier.hasPrefix("Own delivery"))
        XCTAssertEqual(e.storeShipping().ownCompanyID, carrier)
    }

    func testDigitalGoodsArriveAtOnceAndTheReceiptIsFiledWithTheChosenCompany() throws {
        var e = try game(seed: 9)
        let books = try cafe(&e)
        var found: (id: Int, equipmentID: String, offer: EquipmentMarket.Offer)?
        for trade in e.data.catalog.all.prefix(40) where found == nil {
            guard case .success(let tid) = e.startCompany(tradeID: trade.id, cityID: e.state.player.cityID) else { continue }
            if let soft = e.equipmentNeeds(companyID: tid).first(where: { $0.isSoftware && !$0.subscription }),
               let offer = e.equipmentOffers(companyID: tid, equipmentID: soft.equipmentID).first { found = (tid, soft.equipmentID, offer) }
        }
        guard let f = found else { throw XCTSkip("no trade sells a one-off licence") }
        let id = f.id
        e.update { s, _, _ in if let i = s.companyIndex(id) { Ledger.set(&s, to: s.cash + (50_000_000)) } }
        let line = StoreOrders.Line(kind: .new, equipmentID: f.equipmentID, quantity: 1, offerIndex: f.offer.index, payment: .cash)
        let soft = (equipmentID: f.equipmentID, x: 0)
        let quote = try XCTUnwrap(e.storeQuote(companyID: id, lines: [line], delivery: .standard))
        XCTAssertEqual(quote.days, 0)
        XCTAssertEqual(quote.shipping, 0)
        XCTAssertFalse(quote.needsShipping)
        XCTAssertEqual(quote.carrier, "Digital delivery")
        guard case .placed(let number, _, _) = e.placeStoreOrder(companyID: id, lines: [line], delivery: .standard, receiptCompanyID: books) else { return XCTFail("not placed") }
        XCTAssertGreaterThan(e.state.company(id)?.value("eq")[soft.equipmentID]["n"].double ?? 0, 0, "licence delivered at once")
        XCTAssertEqual(e.storeOrders(companyID: id).first?.delivered, true)
        XCTAssertTrue(e.receipts(companyID: books).contains { $0.number == number && $0.kind == "order" })
        XCTAssertFalse(e.receipts(companyID: id).contains { $0.number == number })
        let docs = try XCTUnwrap(e.companyDocuments(companyID: books))
        XCTAssertTrue(docs.contains { $0.kind == "receipt" && $0.id == "rcpt-" + number })
    }

    func testTooLittleCashRefusesTheOrderAndChangesNothing() throws {
        var e = try game(seed: 5)
        let id = try cafe(&e, funds: 2_000_000)
        let (line, eq) = try machineLine(e, id, cls: 2)
        e.update { s, _, _ in if let i = s.companyIndex(id) { Ledger.set(&s, to: 10) } }
        let n0 = e.state.company(id)?.value("eq")[eq]["n"].double ?? 0
        let r = e.placeStoreOrder(companyID: id, lines: [line], delivery: .standard, receiptCompanyID: id)
        guard case .notEnoughCash(let missing) = r else { return XCTFail("expected a refusal, got \(r)") }
        XCTAssertGreaterThan(missing, 0)
        XCTAssertEqual(e.state.company(id)?.cash, 10)
        XCTAssertTrue(e.storeOrders(companyID: id).isEmpty)
        XCTAssertEqual(e.state.company(id)?.value("eq")[eq]["n"].double ?? 0, n0)
    }

    func testNewKeysExistOnlyOnceUsedAndSavesRoundTrip() throws {
        var e = try game()
        let id = try cafe(&e)
        for key in ["ord", "rcpt", "polNo"] { XCTAssertNil(e.state.company(id)?.raw[key], "\(key) is absent until something is recorded") }
        let (line, _) = try machineLine(e, id)
        _ = e.placeStoreOrder(companyID: id, lines: [line], delivery: .standard, receiptCompanyID: id)
        XCTAssertNotNil(e.state.company(id)?.raw["ord"])
        XCTAssertNotNil(e.state.company(id)?.raw["rcpt"])
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(back.company(id)?.value("ord"), e.state.company(id)?.value("ord"))
    }

    func testBankDetailsAreRealAndStable() throws {
        var e = try game()
        let id = try cafe(&e)
        let a = try XCTUnwrap(e.bankPaymentDetails(companyID: id))
        let b = try XCTUnwrap(e.bankPaymentDetails(companyID: id))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.holder, e.state.company(id)?.name)
        XCTAssertEqual(a.accountNumber.count, 9, "two groups of four digits")
        XCTAssertNil(e.bankPaymentDetails(companyID: 999_999))
    }

    func testPlaceFeedHasListingsAndCandidatesAreSameKindAndCity() throws {
        var e = try game()
        let id = try cafe(&e)
        let offers = e.placeOffers()
        XCTAssertFalse(offers.isEmpty)
        let offer = try XCTUnwrap(offers.first { $0.originCompanyID == id })
        XCTAssertEqual(offer.cityID, e.state.company(id)?.cityID)
        XCTAssertFalse(offer.buildingType.isEmpty)
        let c = e.placeCandidates(for: offer)
        XCTAssertTrue(c.contains { $0.companyID == id })
        XCTAssertTrue(c.allSatisfy { $0.monthlyRent > 0 && $0.upfrontRent > 0 })
    }

    func testRentingFilesTheReceiptAndTheActiveRentCanBeReassigned() throws {
        var e = try game(seed: 13)
        let first = try cafe(&e)
        let second = try cafe(&e)
        let offer = try XCTUnwrap(e.placeOffers().first { $0.originCompanyID == first })
        let cash0 = try XCTUnwrap(e.state.company(first)?.cash)
        let out = e.takePlace(companyID: first, offer: offer, buy: false, receiptCompanyID: second)
        XCTAssertEqual(out.result, .ok)
        XCTAssertTrue(out.reference.hasPrefix("AS-"))
        XCTAssertLessThan(try XCTUnwrap(e.state.company(first)?.cash), cash0)
        XCTAssertTrue(e.receipts(companyID: second).contains { $0.number == out.reference && $0.kind == "lease" })
        let active = try XCTUnwrap(e.rentedPlaces().first { $0.companyID == first })
        XCTAssertFalse(active.owned)
        XCTAssertGreaterThan(active.monthlyRent, 0)

        let targets = e.placeTargets(from: first)
        XCTAssertEqual(targets.map { $0.companyID }, [second], "the other company of the same kind in the same city can take it")
        XCTAssertEqual(targets.first?.monthlyRent ?? 0, active.monthlyRent, accuracy: 0.01)
        XCTAssertTrue(e.placeTargets(from: second).isEmpty || e.placeTargets(from: second).allSatisfy { $0.companyID != second })
        let deposit = e.state.company(first)?.value("prem")["dep"].double ?? 0
        let secondCash = try XCTUnwrap(e.state.company(second)?.cash)
        let secondPrem = try XCTUnwrap(e.state.company(second)?.value("prem"))
        let secondBack: Double = (secondPrem["m2"].double > 0 && !secondPrem["owned"].bool) ? secondPrem["dep"].double : 0
        let firstCash = try XCTUnwrap(e.state.company(first)?.cash)
        let move = e.reassignPlace(from: first, to: second)
        XCTAssertEqual(move, .ok)
        XCTAssertEqual(try XCTUnwrap(e.state.company(first)?.cash), firstCash + deposit, accuracy: 1, "the deposit comes back")
        XCTAssertEqual(try XCTUnwrap(e.state.company(second)?.cash), secondCash + secondBack - deposit, accuracy: 1, "the new tenant pays the deposit, its old one comes back")
        let movedRent: Double = try XCTUnwrap(e.state.company(second)?.value("prem")["rent"].double)
        XCTAssertEqual(movedRent, active.monthlyRent * 12 / active.squareMetres, accuracy: 0.01)
        XCTAssertEqual(e.state.company(first)?.value("prem")["m2"].double, 0)
        XCTAssertNil(e.rentedPlaces().first { $0.companyID == first && !$0.atHome && $0.squareMetres > 0 })
        XCTAssertEqual(e.reassignPlace(from: first, to: second), .notRented)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testBuyingAndNonCandidatesAreRefused() throws {
        var e = try game(seed: 3)
        let id = try cafe(&e)
        let offer = try XCTUnwrap(e.placeOffers().first { $0.originCompanyID == id })
        XCTAssertEqual(e.takePlace(companyID: 424_242, offer: offer, buy: false, receiptCompanyID: id).result, .bad)
        XCTAssertEqual(e.takePlace(companyID: id, offer: offer, buy: false, receiptCompanyID: 424_242).result, .bad)
        XCTAssertEqual(PlaceMarket.category(kind: "office", squareMetres: 30), .offices)
        XCTAssertEqual(PlaceMarket.category(kind: "shop", squareMetres: 80), .shops)
        XCTAssertEqual(PlaceMarket.category(kind: "shop", squareMetres: 900), .retail)
        XCTAssertEqual(PlaceMarket.category(kind: "warehouse", squareMetres: 100), .retail)
    }

    func testPolicyGetsANumberWhenSwitchedOnAndReceiptsGoToTheChosenCompany() throws {
        var e = try game(seed: 21)
        let id = try cafe(&e)
        e.prepareAdvisers(companyID: id)
        let insurer = try XCTUnwrap(e.adviserChoices(companyID: id, kind: .insurer).first)
        XCTAssertEqual(e.chooseAdviser(companyID: id, kind: .insurer, providerID: insurer.id), .done)
        guard let policy = e.coverageOverview(companyID: id)?.policies.first(where: { !$0.isOn }) else { throw XCTSkip("every policy is already on") }
        XCTAssertNil(e.policyRecord(companyID: id, product: policy.id))
        let out = e.buyInsurance(companyID: id, product: policy.id, receiptCompanyID: id)
        XCTAssertEqual(out.result, .done)
        XCTAssertTrue(out.number.hasPrefix("AT-"))
        XCTAssertGreaterThan(out.yearlyCost, 0)
        XCTAssertEqual(e.policyRecord(companyID: id, product: policy.id)?.number, out.number, "the number is a stored record")
        XCTAssertTrue(e.receipts(companyID: id).contains { $0.number == out.number && $0.kind == "policy" })
        XCTAssertEqual(e.buyInsurance(companyID: id, product: policy.id, receiptCompanyID: id).result, .unknown)
        XCTAssertEqual(e.toggleInsurancePolicy(companyID: id, product: policy.id), .done)
        XCTAssertNil(e.policyRecord(companyID: id, product: policy.id))
        let other = try cafe(&e)
        XCTAssertEqual(e.buyInsurance(companyID: other, product: policy.id, receiptCompanyID: other).result, .done)
        XCTAssertEqual(e.state.company(other)?.value("insr")["name"].string, "Atlas Insurance")
    }
}
