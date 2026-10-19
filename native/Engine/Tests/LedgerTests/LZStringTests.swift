import XCTest
import GameCore
import SaveSystem

final class LZStringTests: XCTestCase {
    func testUnpacksPackedSavesFromTheOriginalGame() throws {
        let g = try Golden.load("lz_pack")
        for (plain, lz1, lz64) in [(g["t"], g["lz1"], g["lz64"]), (g["small"], g["smallLz1"], g["smallLz64"])] {
            XCTAssertEqual(LZString.jsonText(fromSaveText: lz1.string), plain.string, "LZ1")
            XCTAssertEqual(LZString.jsonText(fromSaveText: lz64.string), plain.string, "LZ64")
            XCTAssertEqual(LZString.jsonText(fromSaveText: plain.string), plain.string, "plain JSON passes through")
        }
    }
}
