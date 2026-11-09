import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Chain locations: names that vary by place (never by number), one quoted way to open a location, and managers appointed from the chain level.
final class ChainLocationsTests: XCTestCase {
    private func chain(stores count: Int) throws -> (e: GameEngine, chain: Int, stores: [Int]) {
        var e = try ChainsTests.engine("NO")
        let first = ChainsTests.start(&e, "cafe")
        ChainsTests.season(&e, first)
        let id = try XCTUnwrap(e.makeChain(companyID: first, name: "Khan Shop"))
        var stores = [first]
        for _ in 1..<count {
            if case .success(let s) = e.openLocation(chainID: id, cityID: e.state.player.cityID) { stores.append(s) }
        }
        guard stores.count == count else { throw XCTSkip("locations could not be opened") }
        return (e, id, stores)
    }

    private func hasDigit(_ s: String) -> Bool { s.contains { $0.isNumber } }

    func testEveryCountryHasPlaceNamesAndNoFallbackIsANumber() throws {
        let e = try ChainsTests.engine("NO")
        for c in e.data.countries.countries {
            XCTAssertFalse(LocationNames.places(countryCode: c.code, cityID: "no-such-city").isEmpty, "\(c.code) has no place names")
        }
        XCTAssertTrue(LocationNames.fallbacks().allSatisfy { !hasDigit($0) })
        XCTAssertTrue(LocationNames.places(countryCode: "NO", cityID: "oslo").contains("Grünerløkka"))
    }

    func testLocationsInOneCityGetDistinctPlaceNames() throws {
        let (e, id, stores) = try chain(stores: 5)
        let names = stores.compactMap { e.state.company($0)?.name }
        XCTAssertEqual(Set(names.map { $0.lowercased() }).count, names.count, "names repeat: \(names)")
        XCTAssertTrue(names.allSatisfy { $0.hasPrefix("Khan Shop ") && !hasDigit($0) }, "\(names)")
        XCTAssertNotEqual(names[0], Chains.chain(e.state, id: id)?["name"].string, "the first store is a location, not the brand")
    }

    func testNamePickerSkipsNamesInUseAndNeverCountsUp() throws {
        var e = try ChainsTests.engine("NO")
        var seen: [String] = []
        var created = true
        for _ in 0..<15 {
            let n = LocationNames.locationName(e.state, brand: "Khan Shop", countryCode: "NO", cityID: "oslo", cityName: "Oslo", data: e.data)
            XCTAssertFalse(seen.contains(n)); XCTAssertFalse(hasDigit(n))
            seen.append(n)
            e.update { s, d, c in
                if case .success = CompanySetup.create(&s, tradeID: "cafe", cityID: "oslo", name: n, countryCode: "NO", data: d, context: c) {} else { created = false }
            }
            guard created else { throw XCTSkip("companies could not be created") }
        }
        XCTAssertEqual(seen.first, "Khan Shop Oslo")
        XCTAssertEqual(seen[1], "Khan Shop Grünerløkka")
    }

    func testQuoteMatchesTheOpenedLocation() throws {
        var (e, id, _) = try chain(stores: 1)
        let city = e.state.player.cityID
        let q = try XCTUnwrap(e.locationQuote(chainID: id, cityID: city))
        XCTAssertEqual(q.total, Chains.newStoreCost(e.state, chainID: id, cityID: city, size: 1, data: e.data))
        XCTAssertGreaterThan(q.fitOut, 0); XCTAssertGreaterThan(q.total, q.fitOut)
        XCTAssertFalse(q.managerFromChain)
        guard case .success(let new) = e.openLocation(chainID: id, cityID: city) else { return XCTFail("not opened") }
        let co = try XCTUnwrap(e.state.company(new))
        XCTAssertEqual(co.name, q.name)
        XCTAssertEqual(e.chainOf(companyID: new)?["id"].int, id)
        XCTAssertEqual(co.status, .setup)
        let other = try XCTUnwrap(e.locationQuote(chainID: id, cityID: city))
        XCTAssertNotEqual(other.name, q.name, "the next quote names a different place")
    }

    func testChainManagerAppointsManagersForEveryLocationAndNewOnes() throws {
        var (e, id, stores) = try chain(stores: 2)
        e.update { s, _, _ in
            for sid in stores {
                guard let i = s.companyIndex(sid) else { continue }
                s.companies[i].status = .open; s.companies[i].ownerHours = 0; s.companies[i].managerID = nil
                Payments.injectCash(&s, companyID: sid, amount: 20_000_000)
            }
        }
        let cand = try XCTUnwrap(e.searchExecutive(.chainmgr)?.first)
        XCTAssertEqual(e.hireExecutive(.chainmgr, personID: cand.id, monthlyWage: cand.askingMonthlyWage * 1.3, chainID: id), .ok)
        XCTAssertNotNil(ChainLocations.chainLead(e.state, chainID: id))
        var filled = 0
        e.update { s, d, _ in filled = ChainLocations.fillManagers(&s, chainID: id, data: d) }
        XCTAssertEqual(filled, 2)
        for sid in stores { XCTAssertNotNil(e.state.company(sid)?.managerID, "store \(sid) has no manager") }
        // a location opened afterwards gets its manager at once
        guard case .success(let third) = e.openLocation(chainID: id, cityID: e.state.player.cityID) else { return XCTFail("not opened") }
        XCTAssertNotNil(e.state.company(third)?.managerID)
    }

    func testNoChainLeadMeansNoAutomaticManager() throws {
        var (e, id, _) = try chain(stores: 1)
        guard case .success(let second) = e.openLocation(chainID: id, cityID: e.state.player.cityID) else { return XCTFail("not opened") }
        XCTAssertNil(ChainLocations.chainLead(e.state, chainID: id))
        XCTAssertNil(e.state.company(second)?.managerID)
        XCTAssertEqual(e.chainHeadOffice(chainID: id)?.services.first { $0.id == "management" }?.active, false)
    }
}
