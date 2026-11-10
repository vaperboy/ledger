import XCTest
import GameCore
import Businesses

final class OriginalParityPinsTests: XCTestCase {
    func testVehicleLeaseIsTwoPointOneFivePercentAMonth() {
        XCTAssertEqual(EquipmentMarket.vehicleLeaseMonthly(price: 180_000_000), 3_870_000, accuracy: 0.5)
        XCTAssertEqual(EquipmentMarket.vehicleLeaseMonthly(price: 300_000), 6_450, accuracy: 0.5)
    }

    func testEquipmentLeaseIsTwoPointThreeFivePercentAMonth() {
        XCTAssertEqual(EquipmentMarket.leaseMonthly(price: 100_000), 2_350, accuracy: 1e-6)
    }
}
