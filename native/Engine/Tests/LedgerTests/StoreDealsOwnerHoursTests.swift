import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Simulation

final class StoreDealsOwnerHoursTests: XCTestCase {
    private func game(seed: Int = 7) throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        return e
    }

    private func cafe(_ e: inout GameEngine) throws -> Int {
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else { throw XCTSkip("no cafe") }
        return id
    }

    func testBlackFridayIsTheWeekOfTheFridayAfterTheFourthThursday() {
        XCTAssertTrue(StoreDeals.isBlackFridayWeek(7), "week of 23 Nov 2026 holds Friday 27 Nov")
        XCTAssertFalse(StoreDeals.isBlackFridayWeek(6))
        XCTAssertFalse(StoreDeals.isBlackFridayWeek(8))
        XCTAssertEqual((0..<104).filter { StoreDeals.isBlackFridayWeek($0) }.count, 2, "one a year")
    }

    func testSalesFollowRealLifeShape() {
        let keys = (0..<300).map { "item\($0)|v\($0 % 7)" }
        let bf = keys.map { StoreDeals.deal(week: 7, seed: 5, key: $0) }
        XCTAssertGreaterThanOrEqual(bf.filter { $0.kind == .blackFriday && $0.percentOff >= 25 }.count, 255, "nearly everything is heavily discounted")
        var small = 0, big = 0, none = 0, total = 0
        for week in 10..<60 where !StoreDeals.isBlackFridayWeek(week) && !StoreDeals.isClearanceWeek(week) {
            for k in keys.prefix(60) {
                let d = StoreDeals.deal(week: week, seed: 5, key: k)
                total += 1
                switch d.kind {
                case .small: small += 1; XCTAssertTrue(d.percentOff >= 4 && d.percentOff <= 10)
                case .big: big += 1; XCTAssertGreaterThanOrEqual(d.percentOff, 25)
                case .none: none += 1
                default: break
                }
            }
        }
        XCTAssertGreaterThan(small, total / 8, "small discounts are regular")
        XCTAssertGreaterThan(big, 0, "big ones do happen")
        XCTAssertLessThan(big, small / 3, "but far less often")
        XCTAssertGreaterThan(none, total / 2, "most things are at list price")
        XCTAssertEqual(StoreDeals.deal(week: 12, seed: 5, key: "a"), StoreDeals.deal(week: 12, seed: 5, key: "a"), "same week, same item: same deal")
    }

    func testPriceShownIsPricePaidAndBlackFridayIsCheaperAndLocksIn() throws {
        var e = try game()
        let id = try cafe(&e)
        let item = try XCTUnwrap(e.equipmentNeeds(companyID: id).first { !$0.isVehicle && !$0.isSoftware && $0.kind != "svc" })
        let offer = try XCTUnwrap(e.equipmentOffers(companyID: id, equipmentID: item.equipmentID).first { $0.cls == 1 })
        let line = StoreOrders.Line(kind: .new, equipmentID: item.equipmentID, quantity: 1, offerIndex: offer.index, payment: .cash)
        e.update { s, _, _ in s.week = 3 }
        let shown0 = e.equipmentPrice(companyID: id, equipmentID: item.equipmentID, factor: offer.priceFactor, vendorID: offer.vendorID)
        let q0 = try XCTUnwrap(e.storeQuote(companyID: id, lines: [line], delivery: .standard))
        XCTAssertEqual(q0.goods, shown0, accuracy: 0.5, "the quote is the shown price")
        e.update { s, _, _ in s.week = 7 }
        let shown = e.equipmentPrice(companyID: id, equipmentID: item.equipmentID, factor: offer.priceFactor, vendorID: offer.vendorID)
        let q = try XCTUnwrap(e.storeQuote(companyID: id, lines: [line], delivery: .standard))
        XCTAssertEqual(q.goods, shown, accuracy: 0.5)
        let deal = e.equipmentDeal(equipmentID: item.equipmentID, vendorID: offer.vendorID)
        if deal.kind == .blackFriday { XCTAssertLessThan(shown, shown0 * 0.95) }
        let cash0 = try XCTUnwrap(e.state.company(id)?.cash)
        guard case .placed = e.placeStoreOrder(companyID: id, lines: [line], delivery: .standard, receiptCompanyID: id) else { return XCTFail("not placed") }
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)?.cash), cash0 - q.chargeNow, accuracy: 1)
        let n0 = e.state.company(id)?.value("eq")[item.equipmentID]["n"].double ?? 0
        for _ in 0..<(q.days + 1) { _ = e.nextDay() }
        XCTAssertGreaterThan(e.state.company(id)?.value("eq")[item.equipmentID]["n"].double ?? 0, n0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testEveryItemIsOnTheShelfWithItsSale() throws {
        var e = try game()
        let id = try cafe(&e)
        e.update { s, _, _ in s.week = 7 }
        let needs = e.equipmentNeeds(companyID: id)
        XCTAssertFalse(needs.isEmpty)
        for n in needs {
            XCTAssertGreaterThanOrEqual(n.listPrice + 1, n.fromPrice, n.name)
            if n.dealPercent > 0 { XCTAssertLessThan(n.fromPrice, n.listPrice) }
        }
        XCTAssertGreaterThan(needs.filter { $0.dealPercent >= 25 }.count, needs.count / 2, "Black Friday")
    }

    func testListingsHaveOwnAddressesAndVariedPicturesThatStayWhenRented() throws {
        var e = try game()
        let id = try cafe(&e)
        let offers = e.placeOffers()
        XCTAssertGreaterThanOrEqual(offers.count, 5)
        XCTAssertEqual(Set(offers.map { $0.title }).count, offers.count, "every listing has its own name")
        XCTAssertTrue(offers.allSatisfy { !$0.title.isEmpty && $0.title != $0.listing.name && !$0.title.hasPrefix("Office") })
        XCTAssertGreaterThan(Set(offers.map { $0.photoSlot }).count, 1, "not the same picture for all")
        XCTAssertEqual(offers.map { $0.title }, e.placeOffers().map { $0.title }, "stable")
        XCTAssertEqual(offers.map { $0.photoSlot }, e.placeOffers().map { $0.photoSlot })
        let de = try GameEngine.newGame(countryCode: "DE", playerName: "T", seed: 7)
        var d2 = de
        d2.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        let id2 = try cafe(&d2)
        XCTAssertTrue(d2.placeOffers().contains { $0.title.contains("stra") || $0.title.contains("weg") || $0.title.contains("allee") || $0.title.contains("platz") || $0.title.hasPrefix("Unit") }, "German street style")
        _ = id2
        let pick = try XCTUnwrap(offers.first { $0.category == e.placeOffers()[0].category })
        let cand = e.placeCandidates(for: pick).first { $0.canRent }
        if let c = cand {
            XCTAssertEqual(e.takePlace(companyID: c.companyID, offer: pick, buy: false, receiptCompanyID: c.companyID).result, .ok)
            let r = try XCTUnwrap(e.rentedPlaces().first { $0.companyID == c.companyID })
            XCTAssertEqual(r.title, pick.title)
            XCTAssertEqual(r.photoSlot, pick.photoSlot, "the picture is locked to the listing")
        }
        _ = id
    }

    func testHoursFollowDemandAndStayWithinTheCap() throws {
        var e = try game()
        let a = try cafe(&e), b = try cafe(&e), c = try cafe(&e)
        e.update { s, d, _ in
            for i in s.companies.indices { s.companies[i].status = .open }
            OwnerHours.adjustWeek(&s, data: d)
        }
        let hours = [a, b, c].map { e.state.company($0)?.ownerHours ?? -1 }
        XCTAssertTrue(hours.allSatisfy { $0 >= 0 && $0 <= 80 })
        XCTAssertLessThanOrEqual(hours.reduce(0, +), 80, "never more than 80 across the companies")
        XCTAssertGreaterThanOrEqual(hours[0], OwnerHours.floor)
    }

    func testStepOutAndInKeepsTheKeyOnlyWhenSet() throws {
        var e = try game()
        let id = try cafe(&e)
        XCTAssertNil(e.state.company(id)?.raw["ownOut"], "no key until the player steps out")
        _ = e.setWorksHere(companyID: id, works: false)
        XCTAssertEqual(e.state.company(id)?.ownerHours, 0)
        e.update { s, d, _ in
            if let i = s.companyIndex(id) { s.companies[i].status = .open }
            OwnerHours.adjustWeek(&s, data: d)
        }
        XCTAssertEqual(e.state.company(id)?.ownerHours, 0, "stays out")
        XCTAssertFalse(OwnerHours.works(try XCTUnwrap(e.state.company(id))))
        _ = e.setWorksHere(companyID: id, works: true)
        XCTAssertNil(e.state.company(id)?.raw["ownOut"])
        XCTAssertGreaterThanOrEqual(e.state.company(id)?.ownerHours ?? 0, OwnerHours.floor)
        XCTAssertTrue(OwnerHours.works(try XCTUnwrap(e.state.company(id))))
    }

    func testBurnoutStartsFromSixtyFiveHours() throws {
        var e = try game()
        let id = try cafe(&e)
        e.update { s, _, _ in
            if let i = s.companyIndex(id) { s.companies[i].ownerHours = 65 }
            s.rest["fat"] = .number(10)
            Luxury.ownerWeek(&s)
        }
        XCTAssertLessThanOrEqual(e.state.rest["fat"]?.double ?? 99, 10, "65 hours do not build tiredness")
        e.update { s, _, _ in
            if let i = s.companyIndex(id) { s.companies[i].ownerHours = 75 }
            s.rest["fat"] = .number(10)
            Luxury.ownerWeek(&s)
        }
        XCTAssertGreaterThan(e.state.rest["fat"]?.double ?? 0, 10, "75 hours do")
        e.update { s, _, _ in
            if let i = s.companyIndex(id) { s.companies[i].ownerHours = 75 }
            s.rest["fat"] = .number(99)
            s.rest["burnUntil"] = nil
            Luxury.ownerWeek(&s)
        }
        XCTAssertNotNil(e.state.rest["burnUntil"], "worn out: burned out")
    }
}
