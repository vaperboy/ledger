import XCTest
import Simulation
@testable import Ledger

final class RememberedDetailsTests: XCTestCase {
    private func details(_ holder: String, _ number: String) -> BankPaymentDetails {
        BankPaymentDetails(holder: holder, accountName: "Company account", accountNumber: number, bankName: "Bank")
    }

    func testRememberedOnlyForThatGameAndCompanyAndOwnDetails() {
        RememberedDetails.clearAll()
        let own = details("Cafe", "1234 5678")
        RememberedDetails.save(app: "techpro", game: "g1", companyID: 3, own: own, on: true)
        XCTAssertEqual(RememberedDetails.load(app: "techpro", game: "g1", companyID: 3, own: own), own)
        XCTAssertNil(RememberedDetails.load(app: "techpro", game: "g2", companyID: 3, own: own))
        XCTAssertNil(RememberedDetails.load(app: "techpro", game: "g1", companyID: 4, own: own))
        XCTAssertNil(RememberedDetails.load(app: "techpro", game: "g1", companyID: 3, own: details("Other", "9999 0000")))
        RememberedDetails.clearAll()
        XCTAssertNil(RememberedDetails.load(app: "techpro", game: "g1", companyID: 3, own: own))
    }
}
