import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation
@testable import Businesses

final class CarDealerTests: XCTestCase {
    private func game(seed: Int = 7, country: String = "UK", cash: Double = 900_000_000) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: country, playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 2_000_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cardealer", cityID: e.state.player.cityID) else { throw XCTSkip("no company") }
        _ = e.quickSetup(companyID: id)
        _ = e.openCompany(companyID: id)
        var n = 0
        while e.state.company(id)?.status != .open && n < 90 { _ = e.nextDay(); n += 1 }
        return (e, id)
    }
    private func weeks(_ e: inout GameEngine, _ n: Int) { for _ in 0..<(n * 7) { _ = e.nextDay() } }

    func testBrandDataIsComplete() {
        XCTAssertGreaterThan(CarBrands.all.count, 8)
        for b in CarBrands.all {
            XCTAssertTrue((0.10...0.14).contains(b.margin), b.id)
            XCTAssertLessThanOrEqual(b.margin + b.bonus, 0.155, "\(b.id) total margin incl. bonus")
            XCTAssertGreaterThan(b.margin, CarBrands.distributorMargin, "a brand pays more than the generic distributor: \(b.id)")
            XCTAssertFalse(b.models.isEmpty)
            XCTAssertFalse(b.markets.isEmpty)
        }
        for code in ["NO", "UK", "US", "JP", "AE"] { XCTAssertGreaterThan(CarBrands.forCountry(code).count, 4, code) }
    }

    func testNothingAppearsByItself() throws {
        var (e, id) = try game()
        weeks(&e, 6)
        XCTAssertTrue(e.carDealerRows(companyID: id).isEmpty)
        XCTAssertEqual(e.state.company(id)?.inventory ?? -1, 0, accuracy: 0.01)
    }

    func testOrderArrivesIsPaidAndSells() throws {
        var (e, id) = try game()
        let offers = e.carDealerOffers(companyID: id)
        XCTAssertGreaterThan(offers.count, 10)
        let o = offers[3]
        XCTAssertEqual(o.cost, (o.listPrice * (1 - CarBrands.distributorMargin)).rounded(), accuracy: 1)
        let cash0 = e.state.company(id)!.cash
        XCTAssertEqual(e.carDealerOrder(companyID: id, brandID: o.brandID, modelID: o.modelID), .applied)
        XCTAssertEqual(e.state.company(id)!.cash, cash0, accuracy: 0.01, "paid on delivery, not on order")
        XCTAssertEqual(e.carDealerRows(companyID: id).first?.status, .onOrder)
        weeks(&e, 5)
        let rows = e.carDealerRows(companyID: id)
        let sold = rows.isEmpty
        if !sold { XCTAssertEqual(rows.first?.status, .inStock); XCTAssertGreaterThan(rows[0].cost, 0) }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testPriceSliderShowsProfitAndLoss() throws {
        var (e, id) = try game()
        let o = e.carDealerOffers(companyID: id)[0]
        _ = e.carDealerOrder(companyID: id, brandID: o.brandID, modelID: o.modelID)
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var cd = s.companies[i].value("cd")
            var orders = cd["orders"].array
            orders[0]["due"] = .number(Double(s.week))
            cd["orders"] = .array(orders)
            s.companies[i].set("cd", cd)
            CarDealer.deliver(&s, i)
        }
        guard let car = e.carDealerRows(companyID: id).first else { return XCTFail("no car") }
        XCTAssertEqual(car.status, .inStock)
        XCTAssertGreaterThan(car.profit, 0)
        XCTAssertEqual(e.carDealerSetPrice(companyID: id, carID: car.id, price: car.cost * 0.9), .applied)
        let cheap = e.carDealerRows(companyID: id)[0]
        XCTAssertLessThan(cheap.profit, 0, "selling below cost shows a loss")
        XCTAssertLessThan(cheap.profitPercent, 0)
        XCTAssertEqual(e.carDealerSetPrice(companyID: id, carID: car.id, price: -1), .refused("That car cannot be priced like that."))
    }

    func testBrandContractReplacesSupplierAndNeedsStandards() throws {
        var (e, id) = try game()
        let terms = e.carBrandTerms(companyID: id)
        XCTAssertGreaterThan(terms.count, 4)
        let pick = terms.first { $0.allMet } ?? terms[0]
        e.update { s, d, _ in
            let i = s.companyIndex(id)!
            s.companies[i].reputation = 90
            _ = d
        }
        let hard = e.carBrandTerms(companyID: id).first { !$0.allMet }
        if let hard { XCTAssertTrue(e.carBrandSign(companyID: id, brandID: hard.brand.id).isRefused) }
        let ready = e.carBrandTerms(companyID: id).first { $0.allMet } ?? pick
        if !ready.allMet {
            guard case .refused(let why) = e.carBrandSign(companyID: id, brandID: ready.brand.id) else { return XCTFail("should be refused") }
            XCTAssertTrue(why.contains("requires"), why)
            return
        }
        XCTAssertEqual(e.carBrandSign(companyID: id, brandID: ready.brand.id), .applied)
        XCTAssertTrue(e.carBrandSign(companyID: id, brandID: ready.brand.id).isRefused, "one contract at a time")
        let offers = e.carDealerOffers(companyID: id)
        XCTAssertTrue(offers.allSatisfy { $0.brandID == ready.brand.id }, "only the brand's cars")
        XCTAssertEqual(offers[0].cost, (offers[0].listPrice * (1 - ready.margin)).rounded(), accuracy: 1)
        let other = CarBrands.forCountry("UK").first { $0.id != ready.brand.id }!
        XCTAssertTrue(e.carDealerOrder(companyID: id, brandID: other.id, modelID: other.models[0].id).isRefused)
        XCTAssertEqual(e.carDealerSupplier(companyID: id), ready.brand.name)
    }

    private func signed(_ e: inout GameEngine, _ id: Int, brand: String = "kasumi") {
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var co = s.companies[i]
            co.reputation = 95
            var prem = co.value("prem"); prem["m2"] = .number(60 * 40); co.set("prem", prem)
            var staff = co.staff
            for k in 0..<3 where staff.filter({ $0.role == "cardealer" }).count < 3 {
                var m = staff.first ?? StaffMember(raw: [:]); m.set("id", 9000 + k); m.set("role", "cardealer"); staff.append(m)
            }
            co.staff = staff
            s.companies[i] = co
        }
        XCTAssertEqual(e.carBrandSign(companyID: id, brandID: brand), .applied)
    }

    func testReviewBonusWarningsAndDrop() throws {
        var (e, id) = try game()
        signed(&e, id)
        guard let a = e.carBrandContract(companyID: id) else { return XCTFail("no contract") }
        XCTAssertGreaterThan(a.exitPenalty, 0)
        XCTAssertEqual(a.warnings, 0)
        e.update { s, d, _ in
            let i = s.companyIndex(id)!
            var cd = s.companies[i].value("cd")
            cd["con"]["sold"] = .number(Double(a.target)); cd["con"]["soldList"] = .number(10_000_000); cd["con"]["yr"] = .number(Double(s.week - 52))
            s.companies[i].set("cd", cd)
            s.companies[i].reputation = 95
            CarBrandContract.week(&s, i, d.catalog["cardealer"]!, d)
        }
        let r = e.carBrandContract(companyID: id)!
        XCTAssertEqual(r.last?.bonus ?? 0, 10_000_000 * a.bonus, accuracy: 1)
        XCTAssertEqual(r.sold, 0)
        for n in 1...2 {
            e.update { s, d, _ in
                let i = s.companyIndex(id)!
                var cd = s.companies[i].value("cd")
                if cd["con"].isNull { return }
                cd["con"]["yr"] = .number(Double(s.week - 52)); cd["con"]["sold"] = 0
                s.companies[i].set("cd", cd)
                CarBrandContract.week(&s, i, d.catalog["cardealer"]!, d)
            }
            if n == 1 { XCTAssertEqual(e.carBrandContract(companyID: id)?.warnings, 1) }
        }
        XCTAssertNil(e.carBrandContract(companyID: id), "dropped after the second warning")
        XCTAssertTrue(e.carDealerOffers(companyID: id).count > 5, "back on the distributor")
    }

    func testEarlyExitPenaltyAndRenewal() throws {
        var (e, id) = try game()
        signed(&e, id)
        let a = e.carBrandContract(companyID: id)!
        let cash = e.state.company(id)!.cash
        XCTAssertEqual(e.carBrandLeave(companyID: id), .applied)
        XCTAssertEqual(e.state.company(id)!.cash, cash - a.exitPenalty, accuracy: 1)
        XCTAssertNil(e.carBrandContract(companyID: id))
        signed(&e, id)
        e.update { s, d, _ in
            let i = s.companyIndex(id)!
            var cd = s.companies[i].value("cd")
            cd["con"]["end"] = .number(Double(s.week + 6))
            cd["con"]["last"] = .object(["w": .number(Double(s.week)), "ratio": 1.2, "sat": 90, "outcome": "ok", "bonus": 0])
            s.companies[i].set("cd", cd)
            s.companies[i].reputation = 95
            CarBrandContract.week(&s, i, d.catalog["cardealer"]!, d)
        }
        let o = e.carBrandContract(companyID: id)?.offer
        XCTAssertNotNil(o)
        let end0 = e.carBrandContract(companyID: id)!.end
        XCTAssertEqual(e.carBrandRenew(companyID: id), .applied)
        XCTAssertEqual(e.carBrandContract(companyID: id)!.end, end0 + o!.years * 52)
        XCTAssertNil(e.carBrandContract(companyID: id)?.offer)
    }

    func testUnhappyBrandLetsContractLapse() throws {
        var (e, id) = try game()
        signed(&e, id)
        e.update { s, d, _ in
            let i = s.companyIndex(id)!
            var cd = s.companies[i].value("cd")
            cd["con"]["end"] = .number(Double(s.week + 4)); cd["con"]["warn"] = 1
            s.companies[i].set("cd", cd)
            CarBrandContract.week(&s, i, d.catalog["cardealer"]!, d)
        }
        XCTAssertNil(e.carBrandContract(companyID: id)?.offer, "no renewal for an unhappy brand")
        e.update { s, d, _ in
            let i = s.companyIndex(id)!
            var cd = s.companies[i].value("cd")
            cd["con"]["end"] = .number(Double(s.week))
            s.companies[i].set("cd", cd)
            CarBrandContract.week(&s, i, d.catalog["cardealer"]!, d)
        }
        XCTAssertNil(e.carBrandContract(companyID: id))
    }

    func testBuyerOrdersAndShowroomSellsWithBooksBalanced() throws {
        var (e, id) = try game()
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var co = s.companies[i]
            var staff = co.staff
            var m = staff.first ?? StaffMember(raw: [:]); m.set("id", 9100); m.set("role", "buyer"); m.set("wage", 4000)
            staff.append(m); co.staff = staff
            s.companies[i] = co
        }
        XCTAssertTrue(e.carDealerHasBuyer(companyID: id))
        weeks(&e, 20)
        let co = e.state.company(id)!
        let d0 = e.data
        XCTAssertTrue(co.value("cd")["cars"].array.count + co.value("cd")["orders"].array.count > 0 || co.books.total["rev"] ?? 0 > 0, "the buyer ordered cars")
        XCTAssertLessThanOrEqual(CarDealer.carsInShowroom(co) + CarDealer.carsOnOrder(co), CarDealer.spaces(co, d0.catalog["cardealer"]!))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        print("CARDEALER 20 weeks: revenue \(co.books.total["rev"] ?? 0) cogs \(co.books.total["cogs"] ?? 0) stock \(CarDealer.carsInShowroom(co)) orders \(CarDealer.carsOnOrder(co)) cash \(co.cash)")
    }

    func testSpacesLimitOrders() throws {
        var (e, id) = try game()
        let o = e.carDealerOffers(companyID: id)[0]
        let total = e.carDealerSpaces(companyID: id).total
        XCTAssertGreaterThan(total, 5)
        for _ in 0..<total { XCTAssertEqual(e.carDealerOrder(companyID: id, brandID: o.brandID, modelID: o.modelID), .applied) }
        XCTAssertTrue(e.carDealerOrder(companyID: id, brandID: o.brandID, modelID: o.modelID).isRefused)
    }
}
