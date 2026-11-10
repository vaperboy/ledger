import XCTest
@testable import Ledger

final class UsernameRulesTests: XCTestCase {
    func testLengthLimits() {
        XCTAssertNotNil(ProfileRules.problem(with: "ab"))
        XCTAssertNil(ProfileRules.problem(with: "abc"))
        XCTAssertNil(ProfileRules.problem(with: "abcdefghijklmnop"))
        XCTAssertNotNil(ProfileRules.problem(with: "abcdefghijklmnopq"))
    }

    func testOnlyLettersDigitsAndUnderscore() {
        XCTAssertNil(ProfileRules.problem(with: "Tiger_7"))
        XCTAssertNotNil(ProfileRules.problem(with: "bad name"))
        XCTAssertNotNil(ProfileRules.problem(with: "dot.name"))
        XCTAssertNotNil(ProfileRules.problem(with: "d\u{00E5}rlig"))
    }

    func testMustStartWithALetter() {
        XCTAssertNotNil(ProfileRules.problem(with: "7tiger"))
        XCTAssertNotNil(ProfileRules.problem(with: "_tiger"))
    }

    func testReservedAndBlockedWordsAreRefused() {
        XCTAssertNotNil(ProfileRules.problem(with: "Admin_one"))
        XCTAssertNotNil(ProfileRules.problem(with: "ledger_team"))
    }

    func testTheStandInServerHandsOutEachNameOnce() async throws {
        let service = MockOnlineService(suiteName: "test.names." + UUID().uuidString, key: "k", latencyMilliseconds: 0)
        _ = try await service.signIn(with: .apple)
        _ = try await service.createProfile(adultConfirmed: true)
        let first: UsernameResult = try await service.claimUsername("Tiger_7")
        XCTAssertEqual(first, .ok)
        let again: UsernameResult = try await service.usernameAvailable("tiger_7")
        XCTAssertEqual(again, .ok, "your own name stays yours")
        let bad: UsernameResult = try await service.claimUsername("no")
        XCTAssertEqual(bad, .invalid)
    }
}
