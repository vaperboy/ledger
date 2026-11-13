import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

final class SupplyMapTests: XCTestCase {
    private func open(_ trade: String, seed: Int = 11) throws -> (GameEngine, Int) {
        var e = try ChainsTests.engine("NO", seed: seed)
        let id = ChainsTests.start(&e, trade)
        ChainsTests.season(&e, id)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            _ = Payments.injectCash(&s, companyID: id, amount: 2_000_000)
        }
        ChainsTests.play(&e, days: 5 * 7)
        return (e, id)
    }

    func testEveryReaderUsesTheOneMap() throws {
        let cat = try TradeCatalog.bundled()
        XCTAssertEqual(SupplyMap.groups, ["Stock", "Upkeep", "Transport", "Services"])
        let shown = SupplyMap.allLines.filter { !$0.automatic }
        XCTAssertGreaterThanOrEqual(shown.count, 20); XCTAssertLessThanOrEqual(shown.count, 28)
        for l in shown {
            XCTAssertTrue(SupplyMap.groups.contains(l.group), l.id)
            XCTAssertFalse(l.suppliers.isEmpty, "\(l.id) has a supplying trade")
            for t in l.suppliers { XCTAssertTrue(cat.order.contains(t), "\(l.id) is supplied by \(t), which players can start") }
        }
        var fromMap: [String: Set<String>] = [:]
        for p in SupplyMap.supplyPairs { fromMap[p.trade, default: []].insert(p.line) }
        XCTAssertEqual(SupplyMarketCatalogue.supplies.mapValues { Set($0) }, fromMap, "what players may list is the map")
        for k in IntercompanySupply.kinds {
            let spec = try XCTUnwrap(SupplyMap.line(k.id), k.id)
            XCTAssertEqual(k.suppliers, spec.suppliers, k.id)
            for (buyer, share) in k.buyers { XCTAssertEqual(SupplyMap.need(buyer, line: k.id)?.salesShare, share, "\(buyer) \(k.id)") }
        }
        for (trade, bd) in cat.trades {
            for n in SupplyMap.needs(trade) {
                for s in SupplyMap.suppliers(line: n.line, buyer: trade) {
                    XCTAssertTrue(SupplyNeeds.uses(buyerTrade: trade, buyerFamily: bd.family, line: n.line, supplierTrade: s), "\(trade) \(n.line) \(s)")
                }
            }
        }
        XCTAssertNil(SupplyMap.line("pack")); XCTAssertNil(SupplyMap.line("goods")); XCTAssertNil(SupplyMap.line("mat"))
    }

    func testTheServerSeedIsGeneratedFromTheMap() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("supabase/migrations/0031_supply_players.sql")
        guard let sql = try? String(contentsOf: url, encoding: .utf8) else { throw XCTSkip("migrations not available") }
        let start = try XCTUnwrap(sql.range(of: "insert into public.supply_trade_lines (trade_id, line_id) values"))
        let end = try XCTUnwrap(sql.range(of: ";", range: start.upperBound..<sql.endIndex))
        let block = String(sql[start.upperBound..<end.lowerBound])
        let re = try NSRegularExpression(pattern: #"\('([a-z0-9]+)','([a-z0-9]+)'\)"#)
        var pairs = Set<String>()
        for m in re.matches(in: block, range: NSRange(block.startIndex..., in: block)) {
            pairs.insert(String(block[Range(m.range(at: 1), in: block)!]) + "|" + String(block[Range(m.range(at: 2), in: block)!]))
        }
        XCTAssertEqual(pairs, Set(SupplyMap.supplyPairs.map { $0.trade + "|" + $0.line }), "regenerate the supply_trade_lines rows from supply_map.json")
    }

    func testTheMarkSaysWhetherASupplierCanCoverTheNeed() {
        XCTAssertEqual(SupplyFit.of(free: 130, need: 100), .fine)
        XCTAssertEqual(SupplyFit.of(free: 120, need: 100), .fine)
        XCTAssertEqual(SupplyFit.of(free: 110, need: 100), .mayFallShort)
        XCTAssertEqual(SupplyFit.of(free: 100, need: 100), .mayFallShort)
        XCTAssertEqual(SupplyFit.of(free: 99, need: 100), .cannot)
        XCTAssertEqual(SupplyFit.of(free: 500, need: 100, open: false), .cannot)
        XCTAssertEqual(SupplyFit.of(free: 0, need: 0), .cannot)
        XCTAssertNil(SupplyFit.fine.mark)
        XCTAssertEqual(SupplyFit.mayFallShort.mark, "May not supply enough")
        XCTAssertEqual(SupplyFit.cannot.mark, "Cannot supply")
    }

    func testSupplierCompaniesLookLikePlayersAndTheStandardOneKeepsTodaysBalance() throws {
        let book = try CountryBook.bundled()
        let list = SupplyPlayers.list(seed: 5, countryCode: "NO", line: "upkeep", trades: ["handy", "electrician", "plumber"], count: 4, countries: book)
        XCTAssertEqual(list.count, 4)
        XCTAssertEqual(list.map { $0.tradeID }, ["handy", "electrician", "plumber", "handy"])
        let std = list[0]
        XCTAssertTrue(std.isStandard)
        XCTAssertEqual(std.tier, 1); XCTAssertEqual(std.quality, 0)
        XCTAssertGreaterThanOrEqual(std.reliability, 0.97)
        let code = try NSRegularExpression(pattern: #"^[A-Z2-9]{3}-[A-Z2-9]{4}$"#)
        for s in list {
            XCTAssertFalse(s.name.isEmpty); XCTAssertFalse(s.owner.isEmpty); XCTAssertFalse(s.city.isEmpty); XCTAssertFalse(s.logoID.isEmpty)
            XCTAssertEqual(code.numberOfMatches(in: s.ownerCode, range: NSRange(s.ownerCode.startIndex..., in: s.ownerCode)), 1, s.ownerCode)
            XCTAssertTrue(SupplyPlayers.isSupplierID(s.id))
            XCTAssertEqual(SupplyPlayers.supplier(seed: 5, id: s.id, countries: book), s, "an id always brings back the same company")
            XCTAssertNotNil(LogoCatalogue.logo(s.logoID))
        }
        XCTAssertEqual(Set(list.map { $0.id }).count, list.count)
        XCTAssertEqual(list, SupplyPlayers.list(seed: 5, countryCode: "NO", line: "upkeep", trades: ["handy", "electrician", "plumber"], count: 4, countries: book))
        XCTAssertFalse(SupplyPlayers.isSupplierID("V-NO-3"))
    }

    func testNoLineIsEverLeftWithoutTwoSuppliers() throws {
        let opened = try open("cafe")
        var e = opened.0
        let id = opened.1
        e.setRealSuppliers(count: 500)
        XCTAssertEqual(e.removeFakePlayers(), 1)
        let co = try XCTUnwrap(e.state.company(id))
        for n in SupplyMap.needs(co.type) where !(SupplyMap.line(n.line)?.automatic ?? true) {
            XCTAssertGreaterThanOrEqual(Suppliers.lineSuppliers(e.state, company: co, line: n.line, data: e.data).count, Suppliers.minimumSuppliers, n.line)
        }
        for r in e.supplyLines(companyID: id).flatMap({ $0.rows }) {
            XCTAssertNotNil(r.now, "\(r.id) has a supplier in use")
            XCTAssertFalse(["Market", "Standard supplier", "Outside suppliers", "No fixed supplier"].contains(r.current), r.current)
            for o in r.offers where !o.isOwn { XCTAssertFalse(o.owner.isEmpty, "\(r.id) \(o.name) has an owner like any player company") }
        }
    }

    func testOwnCompaniesCanSupplyAnyLineTheyMake() throws {
        var e = try ChainsTests.engine("NO", seed: 31)
        let cafe = ChainsTests.start(&e, "cafe")
        let wholesaler = ChainsTests.start(&e, "wholesale")
        ChainsTests.play(&e, days: 10 * 7)
        let rows = e.supplyLines(companyID: cafe).flatMap { $0.rows }
        let food = try XCTUnwrap(rows.first { $0.id == "food" })
        let own = try XCTUnwrap(food.offers.first { $0.isOwn }, "the player's own wholesaler is offered for the café's stock")
        XCTAssertEqual(own.tradeID, "wholesale")
        XCTAssertEqual(e.chooseSupply(companyID: cafe, change: own.change), .ok)
        XCTAssertNotNil(e.supplyLink(buyer: cafe, kind: "food"), "it runs on the own-company supply links")
        ChainsTests.play(&e, days: 4 * 7)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        let back = try XCTUnwrap(e.supplyLines(companyID: cafe).flatMap { $0.rows }.first { $0.id == "food" }?.offers.first { !$0.isOwn })
        XCTAssertEqual(e.chooseSupply(companyID: cafe, change: back.change), .ok)
        XCTAssertNil(e.supplyLink(buyer: cafe, kind: "food"), "picking another supplier ends the own supply")
        _ = wholesaler
    }

    func testTheNeedIsComputedAndListingsAreMarked() throws {
        let (e, id) = try open("grocery")
        let need = e.playerSupplyNeed(companyID: id, lineID: "food")
        XCTAssertGreaterThanOrEqual(need, 1)
        XCTAssertEqual(e.supplyLines(companyID: id).flatMap { $0.rows }.first { $0.id == "food" }?.need, need)
        func listing(cap: Int, committed: Int) -> SupplyListing {
            SupplyListing(id: "L\(cap)", ownerID: "o\(cap)", ownerName: "Ann Holt", profileCode: "ABC-DEFG", companyName: "Holt Wholesale", tradeID: "wholesale",
                          tradeName: "Wholesaler", city: "Oslo", region: "Oslo", lineID: "food", lineName: "Food and drink", priceTier: 1, qualityTier: 1,
                          capacityPerWeek: cap, leadDays: 2, minOrder: 1, termsDays: 14, linkKey: "k\(cap)",
                          record: DeliveryRecord(weeksTrading: 20, ordersTotal: 40, ordersOnTime: 39, unitsPromised: 800, unitsDelivered: 790, cleanWeeks: 12, lifetimeUnits: 790),
                          committedUnits: committed, country: "NO")
        }
        let today = e.state.week * 7 + e.state.day
        XCTAssertEqual(e.playerSupplyFit(companyID: id, listing: listing(cap: need * 10, committed: 0), today: today), .fine)
        XCTAssertEqual(e.playerSupplyFit(companyID: id, listing: listing(cap: need * 10, committed: need * 10 - need), today: today), .mayFallShort)
        XCTAssertEqual(e.playerSupplyFit(companyID: id, listing: listing(cap: need * 10, committed: need * 10), today: today), .cannot)
    }

    func testOldSavesMoveFromVendorsAndMarketToPlayerSuppliers() throws {
        var e = try ChainsTests.engine("UK", seed: 9)
        let cafe = ChainsTests.start(&e, "cafe")
        ChainsTests.play(&e, days: 14)
        var s = e.state
        let i = try XCTUnwrap(s.companyIndex(cafe))
        s.companies[i].set("sc", .object(["laundry": "V-UK-2", "pack": "V-UK-1", "supplies": "P:x"]))
        s.companies[i].set("src", .object(["v": "V-UK-3", "c": 1]))
        s.companies[i].set("fixv", .string("V-UK-4"))
        s.companies[i].set("scw", .object(["pack": .array([1, 1])]))
        var vr: [String: JSONValue] = [:]
        for n in 0..<8 { vr["V-UK-\(n)"] = .object(["r": 50, "w": .number(Double(s.week)), "meet": -99]) }
        s.rest["vr"] = .object(vr)
        s.rest["agree"] = .object(["goods": "V-UK-3"])
        s.rest["psup"] = .object(["c": .array([.object(["id": "C1", "b": .number(Double(cafe)), "ln": "goods", "li": "L1", "ow": "o", "nm": "Ann", "u": 20, "d0": 0]),
                                                .object(["id": "C2", "b": .number(Double(cafe)), "ln": "pack", "li": "L2", "ow": "o", "nm": "Bo", "u": 20, "d0": 0])])])
        s.rest["supmap"] = nil
        XCTAssertTrue(SupplyMigration.needed(s))
        let (data, events, marketing) = try GameEngine.loadResources()
        let moved = GameEngine(state: s, data: data, events: events, marketing: marketing)
        let co = try XCTUnwrap(moved.state.company(cafe))
        let sc = co.value("sc").object
        XCTAssertNil(sc["pack"]); XCTAssertNil(sc["supplies"])
        for (line, v) in sc {
            XCTAssertNotNil(SupplyMap.need("cafe", line: line), line)
            XCTAssertTrue(SupplyPlayers.isSupplierID(v.string), "\(line) → \(v.string)")
        }
        let src = co.value("src")["v"].string
        XCTAssertTrue(src == "auto" || SupplyPlayers.isSupplierID(src), src)
        if src != "auto" { XCTAssertEqual(Suppliers.relationship(moved.state, src), 50, "the relationship carries over") }
        let fix = co.value("fixv").string
        XCTAssertTrue(fix == "auto" || SupplyPlayers.isSupplierID(fix), fix)
        XCTAssertFalse((moved.state.rest["agree"] ?? .null)["goods"].string.hasPrefix("V-"), "board agreements no longer name a made-up vendor")
        XCTAssertTrue(co.value("scw").isNull)
        let contracts = PlayerSupply.contracts(moved.state)
        XCTAssertEqual(contracts.map { $0.base.lineID }, ["food"], "the stock contract moves to the stock line, the packaging one ends")
        XCTAssertNotNil(Suppliers.goodsVendor(moved.state, company: co, data: data))
        XCTAssertFalse(SupplyMigration.needed(moved.state))
        var again = moved.state
        XCTAssertEqual(SupplyMigration.run(&again, countries: data.countries, nouns: data.catalog.tables.raw["FAM_NOUN"]), 0, "runs once")
        XCTAssertEqual(again, moved.state)
    }

    func testTheNewSupplierTradesAreOrdinaryStartableBusinesses() throws {
        let cat = try TradeCatalog.bundled()
        for t in ["wholesale", "fuelstation", "laundry", "security"] {
            let bd = try XCTUnwrap(cat[t], t)
            XCTAssertTrue(cat.order.contains(t), t)
            XCTAssertTrue(SpecialFamilies.isStartable(bd), t)
            for s in bd.standardStaff { XCTAssertNotNil(cat.tables.roles[s.role], "\(t) role \(s.role)") }
            for q in bd.equipment where q.vehicleModels == nil { XCTAssertFalse(cat.tables.raw["EQ_KINDS"][t][q.id].isNull, "\(t) equipment kind \(q.id)") }
            XCTAssertGreaterThan(bd.normalDemand, 0, t)
            XCTAssertLessThanOrEqual(bd.margin, 0.06, "\(t) is an ordinary business, not a get-rich path")
            XCTAssertFalse(SupplyMap.linesSupplied(by: t).isEmpty, "\(t) supplies other companies")
            XCTAssertFalse(SupplyMap.needs(t).isEmpty, "\(t) buys too")
        }
        XCTAssertTrue(SupplyMap.uses(buyerTrade: "cafe", line: "food", supplierTrade: "wholesale"))
        XCTAssertTrue(SupplyMap.uses(buyerTrade: "barber", line: "care", supplierTrade: "wholesale"))
        XCTAssertTrue(SupplyMap.uses(buyerTrade: "boutique", line: "wares", supplierTrade: "wholesale"))
        XCTAssertTrue(SupplyMap.uses(buyerTrade: "taxi", line: "fuel", supplierTrade: "fuelstation"))
        XCTAssertTrue(SupplyMap.uses(buyerTrade: "airline", line: "fuel", supplierTrade: "oilgas"))
        XCTAssertTrue(SupplyMap.uses(buyerTrade: "hotel", line: "laundry", supplierTrade: "laundry"))
        XCTAssertTrue(SupplyMap.uses(buyerTrade: "nightclub", line: "guards", supplierTrade: "security"))
        XCTAssertFalse(SupplyMap.uses(buyerTrade: "law", line: "guards", supplierTrade: "security"), "only companies that need guards buy them")
        XCTAssertFalse(SupplyMap.uses(buyerTrade: "cleaning", line: "care", supplierTrade: "cleaning"), "cleaners supply cleaning, not materials")
        XCTAssertTrue(SupplyMap.linesSupplied(by: "cleaning") == ["clean"])
        for t in ["wholesale", "fuelstation", "laundry"] {
            var e = try ChainsTests.engine("NO", seed: 21)
            let id = ChainsTests.start(&e, t)
            XCTAssertNotEqual(id, 0, t)
            ChainsTests.play(&e, days: 13 * 7)
            XCTAssertTrue(e.state.company(id)?.status.isLive ?? false, t)
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(t): \(Ledger.gaps(e.state))")
            XCTAssertFalse(e.supplyLines(companyID: id).isEmpty, t)
        }
    }
}
