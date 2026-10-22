import XCTest
import GameCore
import Businesses

/// Values checked against the original JS and found to match; pinned so they stay that way.
/// Original: engine/company/company.js `buyVehCore` (lease = base * 0.0215, 80% loan over 60 months),
/// features/company/realistic_buying.js (equipment lease 0.0235). The original never reads `tw.hours`,
/// and its sold-out days (`dlast.so` / `dlast.lost`) only feed messages and the owner's reorder estimate.
final class OriginalParityPinsTests: XCTestCase {
    func testVehicleLeaseIsTwoPointOneFivePercentAMonth() {
        XCTAssertEqual(EquipmentMarket.vehicleLeaseMonthly(price: 180_000_000), 3_870_000, accuracy: 0.5)
        XCTAssertEqual(EquipmentMarket.vehicleLeaseMonthly(price: 300_000), 6_450, accuracy: 0.5)
    }

    func testEquipmentLeaseIsTwoPointThreeFivePercentAMonth() {
        XCTAssertEqual(EquipmentMarket.leaseMonthly(price: 100_000), 2_350, accuracy: 1e-6)
    }
}
