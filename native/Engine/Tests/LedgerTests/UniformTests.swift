import XCTest
import GameCore
import Employees
@testable import Businesses
@testable import Simulation

final class UniformTests: XCTestCase {
    func testEveryMappedUniformExistsAndEveryTradeIsKnown() throws {
        let (data, _, _) = try GameEngine.loadResources()
        let ids: Set<String> = Set(Uniforms.all.map(\.id))
        XCTAssertGreaterThanOrEqual(ids.count, 12)
        XCTAssertEqual(ids.count, Uniforms.all.count, "uniform ids are unique")
        for (trade, uni) in Uniforms.tradeMap {
            XCTAssertNotNil(data.catalog[trade], "uniforms.json names trade \(trade), which does not exist")
            XCTAssertTrue(ids.contains(uni), "\(trade) wears \(uni), which is not defined")
        }
    }

    func testTradesGetTheClothesTheirWorkCalls() throws {
        let (data, _, _) = try GameEngine.loadResources()
        func wear(_ trade: String, _ role: String = "cook") -> String { Uniforms.id(trade: data.catalog[trade], role: role) }
        XCTAssertEqual(wear("restaurant"), "chef")
        XCTAssertEqual(wear("cafe", "barista"), "barista")
        XCTAssertEqual(wear("plumber", "plumber"), "overalls")
        XCTAssertEqual(wear("construction", "labour"), "hivis")
        XCTAssertEqual(wear("dental", "nurse"), "scrubs")
        XCTAssertEqual(wear("law", "lawyer"), "suit")
        XCTAssertEqual(wear("gym", "trainer"), "sport")
        XCTAssertEqual(wear("resrent", "caretaker"), "suit", "family fallback")
        XCTAssertEqual(wear("restaurant", "acct"), "", "office roles keep their own clothes")
        XCTAssertEqual(wear("startup"), "", "a trade without a uniform keeps its own clothes")
        XCTAssertEqual(Uniforms.id(trade: nil, role: "cook"), "")
    }

    func testTheFaceKeyCarriesTheUniformAndStillReadsAsTheSameCell() {
        var p = Person(raw: ["face": .string("w12")])
        XCTAssertEqual(p.faceKey, "w12")
        p.set("uni", "chef")
        XCTAssertEqual(p.faceKey, "w12.uchef")
        XCTAssertEqual(FaceKey(p.faceKey), FaceKey(sheet: .workers, cell: 12))
        XCTAssertEqual(FaceKey(p.faceKey)?.string, "w12")
        p.set("uni", "")
        XCTAssertEqual(p.faceKey, "w12")
    }
}
