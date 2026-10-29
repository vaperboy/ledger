import XCTest
import GameCore
import Businesses
import SaveSystem

final class SaveStoreTests: XCTestCase {
    func tempStore() throws -> (SaveStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-test-\(UUID().uuidString)")
        return (try SaveStore(directory: dir), dir)
    }
    func legacyState() throws -> (GameState, String) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "save_cafe_week15", withExtension: "json", subdirectory: "Golden"))
        let text = try String(contentsOf: url)
        return (try LegacyImporter.importText(text), text)
    }

    func testImportsLegacyPlainAndPackedSaves() throws {
        let (s, text) = try legacyState()
        XCTAssertEqual(s.week, 15)
        XCTAssertTrue(s.dayMode)
        let g = try Golden.load("lz_pack")
        let packed = try LegacyImporter.importText(g["lz1"].string)
        XCTAssertEqual(packed.homeCountryCode, "DE")
        let packed64 = try LegacyImporter.importText(g["lz64"].string)
        XCTAssertEqual(packed64.homeCountryCode, "DE")
        XCTAssertThrowsError(try LegacyImporter.importText("not a save"))
        XCTAssertThrowsError(try LegacyImporter.importText("{\"a\":1}")) { XCTAssertEqual($0 as? SaveError, .notAGameSave) }
        XCTAssertFalse(text.isEmpty)
    }

    func testSaveLoadRoundTripKeepsEverything() throws {
        let (store, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (s, _) = try legacyState()
        let cat = try TradeCatalog.bundled()
        try store.save(s, summary: store.summary(of: s, trades: cat))
        let back = try store.load()
        XCTAssertEqual(back, s)
        XCTAssertEqual(store.slots().count, 1)
    }

    func testPreviousSaveKeptAndDamagedFileFallsBack() throws {
        let (store, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        var (s, _) = try legacyState()
        let cat = try TradeCatalog.bundled()
        try store.save(s, summary: store.summary(of: s, trades: cat))
        s.week = 16
        try store.save(s, summary: store.summary(of: s, trades: cat))
        XCTAssertEqual(try store.load().week, 16)
        // Damage the main file: the previous save is used.
        try "garbage".write(to: dir.appendingPathComponent("current.ledgersave"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.load().week, 15)
    }

    func testOriginalImportTextIsKeptUntouched() throws {
        let (store, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "save_cafe_week3", withExtension: "json", subdirectory: "Golden"))
        let text = try String(contentsOf: url)
        _ = try store.importLegacy(text: text)
        let kept = try FileManager.default.contentsOfDirectory(at: dir.appendingPathComponent("Imports"), includingPropertiesForKeys: nil)
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(try String(contentsOf: kept[0]), text)
    }

    func testBackupsAreLimited() throws {
        let (store, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        var (s, _) = try legacyState()
        let cat = try TradeCatalog.bundled()
        for w in 20..<30 { s.week = w; try store.backup(s, summary: store.summary(of: s, trades: cat)) }
        let files = try FileManager.default.contentsOfDirectory(at: dir.appendingPathComponent("Backups"), includingPropertiesForKeys: nil)
        XCTAssertLessThanOrEqual(files.count, 6)
    }
}
