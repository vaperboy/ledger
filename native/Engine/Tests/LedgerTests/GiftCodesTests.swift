import XCTest
@testable import Simulation

final class GiftCodesTests: XCTestCase {
    private func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }

    func testHashesMatchPublishedVectors() {
        XCTAssertEqual(hex(SHA256.hash(Array("abc".utf8))), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let key: [UInt8] = [UInt8](repeating: 0x0b, count: 20)
        XCTAssertEqual(hex(HMAC.sha256(key: key, message: Array("Hi There".utf8))), "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
    }

    func testACodeRoundTripsAndForgivesTyping() {
        let code: String = GiftCodes.make(kind: 1, serial: 7)
        XCTAssertEqual(code.count, 19)
        XCTAssertEqual(GiftCodes.check(code), GiftCodes.Gift(serial: 7, days: 365, title: "A year of the full game"))
        XCTAssertEqual(GiftCodes.check(code.lowercased().replacingOccurrences(of: "-", with: " "))?.serial, 7)
    }

    func testAChangedOrMadeUpCodeIsRefused() {
        let code: String = GiftCodes.make(kind: 1, serial: 7)
        var chars: [Character] = Array(code)
        chars[0] = chars[0] == "A" ? "B" : "A"
        XCTAssertNil(GiftCodes.check(String(chars)))
        XCTAssertNil(GiftCodes.check("AAAA-AAAA-AAAA-AAAA"))
        XCTAssertNil(GiftCodes.check(""))
        XCTAssertNil(GiftCodes.check("1234"))
    }

    func testAGiftOpensTheFullGameUntilItEnds() {
        let now = Date()
        let on = EntitlementSnapshot(giftExpires: now.addingTimeInterval(100))
        XCTAssertTrue(on.isPro(now: now)); XCTAssertTrue(on.isAdFree(now: now)); XCTAssertEqual(on.saveSlots(now: now), 3)
        XCTAssertFalse(on.isPro(now: now.addingTimeInterval(200)))
        XCTAssertFalse(EntitlementSnapshot.free.isPro(now: now))
    }

    /// Prints the codes the owner hands out: LEDGER_PRINT_CODES=1 swift test --filter GiftCodesTests/testPrintTheCodes
    func testPrintTheCodes() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LEDGER_PRINT_CODES"] == "1")
        print("OWNER " + GiftCodes.make(kind: 2, serial: 1))
        for s in 101...104 { print("GIFT " + GiftCodes.make(kind: 1, serial: s)) }
    }
}
