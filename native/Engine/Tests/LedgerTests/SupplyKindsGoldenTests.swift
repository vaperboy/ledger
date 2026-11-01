import XCTest
import GameCore
import Businesses

/// The supply kinds (what your own companies can supply to each other) are data (`Resources/supply_kinds.json`). This pins them to the list
/// that used to be written in code, so moving them changed no behaviour. New kinds and trades are data-only: add them to the data file and here.
final class SupplyKindsGoldenTests: XCTestCase {
    static func snapshot() -> JSONValue {
        .array(IntercompanySupply.kinds.map { k in
            .object(["id": .string(k.id), "name": .string(k.name), "suppliers": .array(k.suppliers.map { .string($0) }), "local": .bool(k.local),
                     "category": .string(k.category), "noCapacity": .bool(k.noCapacity), "delivered": .bool(k.delivered),
                     "buyers": .object(k.buyers.mapValues { .number($0) })])
        })
    }

    func testKindsAreExactlyTheGoldenList() throws {
        let golden = try Golden.load("supply_kinds")
        XCTAssertEqual(Self.snapshot(), golden)
        XCTAssertEqual(IntercompanySupply.kinds.count, 16)
        XCTAssertEqual(IntercompanySupply.kinds.map(\.id), golden.array.map { $0["id"].string }, "order is part of the behaviour (first matching supplier kind wins)")
    }
}
