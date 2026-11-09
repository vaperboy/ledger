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

    func testWalletRemembersUsedSerialsMergesCopiesAndNeverMovesTheClockBack() throws {
        var w = GiftWallet()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let code = GiftCodes.make(kind: 1, serial: 11)
        XCTAssertEqual(w.redeem("nonsense", now: now), .invalid)
        XCTAssertEqual(w.redeem(code, now: now), .ok(until: now.addingTimeInterval(365 * 86_400)))
        XCTAssertEqual(w.redeem(code, now: now), .used)
        // The phone clock is set back a year: the gift is still counted from the newest date seen.
        let back = now.addingTimeInterval(-365 * 86_400)
        XCTAssertEqual(w.trustedNow(back), now)
        XCTAssertEqual(w.redeem(GiftCodes.make(kind: 1, serial: 12), now: back), .ok(until: now.addingTimeInterval(2 * 365 * 86_400)))
        // One copy lost (defaults wiped): the other still knows the serial.
        var other = GiftWallet(); other.serials = [99]
        let both = GiftWallet().merged(w).merged(other)
        XCTAssertEqual(both.serials, [11, 12, 99]); XCTAssertEqual(both.expires, w.expires)
        var fresh = both
        XCTAssertEqual(fresh.redeem(code, now: now), .used)
        XCTAssertEqual(try JSONDecoder().decode(GiftWallet.self, from: JSONEncoder().encode(both)), both)
    }
}
