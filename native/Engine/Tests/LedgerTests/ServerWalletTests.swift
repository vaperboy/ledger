import XCTest
import GameCore
@testable import Simulation

final class TrustedClockTests: XCTestCase {
    override func tearDown() { TrustedClock.reset() }

    func testUnsyncedClockIsThePhoneButNeverBeforeTheLastServerTime() {
        TrustedClock.reset()
        let phone = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertEqual(TrustedClock.now(local: phone, uptime: 5), phone)
        TrustedClock.remember(lastServerTime: 2_000_086_400)
        XCTAssertEqual(TrustedClock.now(local: phone, uptime: 5).timeIntervalSince1970, 2_000_086_400)
        XCTAssertFalse(TrustedClock.isSynced)
    }

    func testSyncedClockFollowsServerTimeAndUptimeNotThePhoneDate() {
        TrustedClock.reset()
        TrustedClock.sync(serverTime: 1_800_000_000, uptime: 100)
        let movedBack = Date(timeIntervalSince1970: 1_000_000_000)
        let movedAhead = Date(timeIntervalSince1970: 2_500_000_000)
        XCTAssertEqual(TrustedClock.now(local: movedBack, uptime: 160).timeIntervalSince1970, 1_800_000_060)
        XCTAssertEqual(TrustedClock.now(local: movedAhead, uptime: 160).timeIntervalSince1970, 1_800_000_060)
        XCTAssertEqual(TrustedClock.today(local: movedAhead, uptime: 160), TrustedClock.today(local: movedBack, uptime: 160))
        XCTAssertTrue(TrustedClock.isSynced)
    }

    func testPassDayCannotBeFarmedByChangingTheDateOnceSynced() {
        TrustedClock.reset()
        TrustedClock.sync(serverTime: 1_800_000_000, uptime: 0)
        let day: Int = SeasonCatalog.today()
        XCTAssertEqual(day, TrustedClock.today(local: Date(timeIntervalSince1970: 0), uptime: ProcessInfo.processInfo.systemUptime))
        var pass = SeasonPass(today: day)
        let first: Int = pass.award(.weekReport, today: SeasonCatalog.today(), count: 10)
        let second: Int = pass.award(.weekReport, today: SeasonCatalog.today(), count: 10)
        XCTAssertEqual(first + second, SeasonPass.dailyXPCap)
    }

    func testBadServerTimesAreIgnored() {
        TrustedClock.reset()
        TrustedClock.sync(serverTime: .nan)
        TrustedClock.sync(serverTime: -5)
        XCTAssertFalse(TrustedClock.isSynced)
    }
}

final class MoneyPackLimitTests: XCTestCase {
    func testWeeklyCapIsTwoMountainPacks() {
        let mountain: MoneyPack? = MoneyPacks.pack("mountain")
        XCTAssertNotNil(mountain)
        XCTAssertEqual(MoneyPacks.weeklyGoldCap, 2 * (mountain?.gold ?? 0))
        XCTAssertEqual(MoneyPacks.weeklyGoldCap, 1060)
    }

    func testRoomShrinksWithUseAndTheFreePackAlwaysFits() throws {
        let mountain: MoneyPack = try XCTUnwrap(MoneyPacks.pack("mountain"))
        XCTAssertTrue(MoneyPacks.fitsThisWeek(mountain, used: 0))
        XCTAssertTrue(MoneyPacks.fitsThisWeek(mountain, used: 530))
        XCTAssertFalse(MoneyPacks.fitsThisWeek(mountain, used: 531))
        XCTAssertEqual(MoneyPacks.weeklyRoom(used: 2000), 0)
        XCTAssertEqual(MoneyPacks.weeklyRoom(used: -4), MoneyPacks.weeklyGoldCap)
        XCTAssertTrue(MoneyPacks.fitsThisWeek(MoneyPacks.free, used: 99_999))
    }

    func testAServerConfirmedPackPaysTheGameOnceThroughTheLedger() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7, story: .fresh, tradeID: "cafe", companyName: "Test")
        let before: Double = e.state.cash
        let paid: Double? = e.claimMoneyPack("mountain", claimID: "server-request-1")
        XCTAssertEqual(paid, MoneyPacks.gameMoney(try XCTUnwrap(MoneyPacks.pack("mountain"))))
        XCTAssertNil(e.claimMoneyPack("mountain", claimID: "server-request-1"))
        XCTAssertEqual(e.state.cash, before + (paid ?? 0), accuracy: 0.01)
    }

    func testABoxResultCanBeBuiltFromAServerRoll() {
        let r = BoxResult(rarity: .epic, content: .artifact(ArtifactItem(defID: "abacus", serial: 3)), guaranteed: true)
        XCTAssertEqual(BoxHaul([r]).artifacts.count, 1)
        XCTAssertTrue(r.guaranteed)
    }
}

/// The server rolls boxes and prices goods from its own catalogue; it must hold the same odds and prices as the app.
final class ServerCatalogTests: XCTestCase {
    private func catalog() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let dir: URL = root.appendingPathComponent("supabase/migrations")
        let names: [String] = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".sql") }.sorted()
        for name in names.reversed() {
            let text: String = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            if text.contains("-- store catalog begin") { return text }
        }
        throw XCTSkip("no store catalogue in the migrations")
    }

    /// Rows of one generated insert, as unquoted strings.
    private func rows(_ table: String, in sql: String) -> [[String]] {
        var out: [[String]] = []
        var inside = false
        for raw in sql.components(separatedBy: "\n") {
            let line: String = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("insert into private.\(table) (") { inside = true; continue }
            guard inside else { continue }
            guard line.hasPrefix("(") else { break }
            var body = line
            body.removeFirst()
            if body.hasSuffix(");") { body.removeLast(2); inside = false } else if body.hasSuffix("),") { body.removeLast(2) }
            out.append(body.components(separatedBy: ", ").map { (v: String) -> String in v.trimmingCharacters(in: CharacterSet(charactersIn: "'")) })
            if !inside { break }
        }
        return out
    }

    private func prize(_ p: BoxPrizeClass) -> (String, Int) {
        switch p {
        case .cosmetic: return ("cosmetic", 0)
        case .artifact: return ("artifact", 0)
        case .gold(let g): return ("gold", g)
        case .money(let m): return ("money", m)
        case .profileCard: return ("profileCard", 0)
        case .companyCard: return ("companyCard", 0)
        }
    }

    func testBoxOddsAndPricesMatchTheServer() throws {
        let sql: String = try catalog()
        let kinds: [[String]] = rows("store_box_kinds", in: sql)
        XCTAssertEqual(kinds.count, BoxKind.allCases.count)
        for k in BoxKind.allCases {
            let row: [String]? = kinds.first { $0.first == k.rawValue }
            XCTAssertEqual(row?[1], String(k.price), "price of \(k)")
            let server: [[String]] = rows("store_box_rows", in: sql).filter { $0.first == k.rawValue }
            let app: [BoxRow] = BoxOdds.rows(k)
            XCTAssertEqual(server.count, app.count, "rows of \(k); run supabase/tools/store_catalog.py into a new migration")
            for (i, r) in app.enumerated() where i < server.count {
                let (name, amount) = prize(r.prize)
                XCTAssertEqual(server[i], [k.rawValue, String(i + 1), r.rarity.rawValue, name, String(amount), String(r.weight)], "\(k) row \(i + 1)")
            }
        }
        let bundles: [[String]] = rows("store_box_bundles", in: sql)
        for b in GoldStore.boxBundles {
            XCTAssertTrue(bundles.contains([b.id, b.kind.rawValue, String(b.count), String(b.price)]), b.id)
        }
    }

    func testGoldPacksMoneyPacksAndLevelGoldMatchTheServer() throws {
        let sql: String = try catalog()
        let products: [[String]] = rows("store_gold_products", in: sql)
        for p in GoldStore.packs {
            XCTAssertEqual(products.first { $0.first == "com.ledger." + p.id }?[2], String(p.gold), p.id)
        }
        XCTAssertEqual(products.first { $0.first == PurchaseCatalog.seasonBundleID }?[2], String(GoldStore.seasonBundle.gold))
        XCTAssertEqual(products.first { $0.first == LedgerProduct.pro.rawValue }?[2], String(GoldPrices.proBundleGold))
        XCTAssertEqual(products.first { $0.first == LedgerProduct.founder.rawValue }?[2], String(GoldPrices.founderBundleGold))
        let packs: [[String]] = rows("store_money_packs", in: sql)
        for p in MoneyPacks.packs + [MoneyPacks.free] {
            XCTAssertEqual(packs.first { $0.first == p.id }, [p.id, String(p.gold), String(p.bonusPercent), p.isFree ? "true" : "false"], p.id)
        }
        let levels: [[String]] = rows("store_level_rewards", in: sql)
        XCTAssertEqual(levels.count, LevelRewards.all.count)
        for r in LevelRewards.all { XCTAssertTrue(levels.contains([String(r.level), String(r.gold)]), "level \(r.level)") }
        XCTAssertTrue(sql.contains("\"moneyPackWeeklyGold\": \(MoneyPacks.weeklyGoldCap)"))
        XCTAssertTrue(sql.contains("\"freeMoneyPerDay\": \(MoneyPacks.freePerDay)"))
    }

    func testEveryBoxItemIsKnownToTheServer() throws {
        let sql: String = try catalog()
        let items: [[String]] = rows("store_items", in: sql)
        for d in ArtifactCatalog.defs { XCTAssertTrue(items.contains { $0[0] == d.id && $0[1] == "artifact" && $0[2] == d.rarity.rawValue }, d.id) }
        for c in CardCatalog.everything {
            XCTAssertTrue(items.contains { $0[0] == c.id && $0[1] == (c.kind == .company ? "companyCard" : "profileCard") && $0[2] == c.rarity.rawValue }, c.id)
        }
        let cosmetics: Set<String> = Set(rows("store_cosmetics", in: sql).map { $0[0] })
        for c in GoldCosmetics.everything where c.source == .box || c.source == .store { XCTAssertTrue(cosmetics.contains(c.id), c.id) }
    }
}
