import XCTest
@testable import Ledger

@MainActor
final class PushTokenTests: XCTestCase {
    func testTokenBytesBecomeLowercaseHex() {
        let p = PushTokenPayload(deviceToken: Data([0x00, 0xAB, 0x0F, 0xFF]), environment: "sandbox", categories: [])
        XCTAssertEqual(p.token, "00ab0fff")
    }

    func testRPCParamsCarryTokenEnvironmentAndCategories() {
        let p = PushTokenPayload(token: "abc", environment: "production", categories: [.auction, .gift])
        let params = p.rpcParams
        XCTAssertEqual(params["p_token"] as? String, "abc")
        XCTAssertEqual(params["p_environment"] as? String, "production")
        XCTAssertEqual(params["p_categories"] as? [String], ["auction", "gift"])
    }

    func testOnlyEnabledCategoriesAreSent() {
        let keys = PushCategory.allCases.map { "push." + $0.rawValue }
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { UserDefaults.standard.set(v, forKey: k) } }
        for k in keys { UserDefaults.standard.set(true, forKey: k) }
        UserDefaults.standard.set(false, forKey: "push.race")
        XCTAssertEqual(Set(PushAlerts.enabledCategories.map(\.rawValue)), ["auction", "supplier", "gift", "daily"])
    }
}
