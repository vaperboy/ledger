import XCTest
@testable import Ledger

/// The account rules on the offline stand-in: no profile without the 18+ confirmation, the link reward once, and no administrator
/// without the server saying so.
@MainActor
final class AccountFlowTests: XCTestCase {
    private func service() -> MockOnlineService {
        MockOnlineService(suiteName: "test.accounts." + UUID().uuidString, key: "k", latencyMilliseconds: 0)
    }

    func testSigningInMakesNoProfileUntilTheAdultConfirmation() async throws {
        let s = service()
        _ = try await s.signIn(with: .apple)
        let before = try await s.accountStatus()
        XCTAssertFalse(before.hasProfile)
        XCTAssertFalse(before.adultConfirmed)
        do {
            _ = try await s.createProfile(adultConfirmed: false)
            XCTFail("a profile must not be created without the confirmation")
        } catch {
            XCTAssertEqual(error as? OnlineError, .adultRequired)
        }
        let still = try await s.accountStatus()
        XCTAssertFalse(still.hasProfile)
        _ = try await s.createProfile(adultConfirmed: true)
        let after = try await s.accountStatus()
        XCTAssertTrue(after.hasProfile)
        XCTAssertTrue(after.adultConfirmed)
    }

    func testTheLinkRewardIsPaidOnce() async throws {
        let s = service()
        _ = try await s.signIn(with: .google)
        do {
            _ = try await s.claimLinkReward()
            XCTFail("no reward before a profile exists")
        } catch {
            XCTAssertEqual(error as? OnlineError, .notSignedIn)
        }
        _ = try await s.createProfile(adultConfirmed: true)
        let first = try await s.claimLinkReward()
        XCTAssertTrue(first.granted)
        XCTAssertEqual(first.gold, MockOnlineService.linkRewardGold)
        let second = try await s.claimLinkReward()
        XCTAssertFalse(second.granted)
        XCTAssertEqual(second.gold, 0)
    }

    func testNobodyIsAnAdministratorWithoutTheServer() async throws {
        let s = service()
        _ = try await s.signIn(with: .apple)
        _ = try await s.createProfile(adultConfirmed: true)
        let status = try await s.accountStatus()
        XCTAssertEqual(status.isAdmin, MockOnlineService.previewAdmin)
        if !MockOnlineService.previewAdmin {
            let r = try await s.redeemAdminCode("ANY-CODE-AT-ALL-123")
            XCTAssertEqual(r, .invalid)
            do {
                _ = try await s.adminSnapshot()
                XCTFail("an ordinary account must not read the admin data")
            } catch {
                XCTAssertEqual(error as? OnlineError, .notAdmin)
            }
            do {
                try await s.adminSetRule(key: "print.single_limit", value: 0.06, reason: "test")
                XCTFail("an ordinary account must not change a rule")
            } catch {
                XCTAssertEqual(error as? OnlineError, .notAdmin)
            }
        }
    }

    func testSigningInCreatesTheProfileAndPaysTheRewardOnce() async {
        let online = OnlineSession(service: service())
        let ok = await online.signIn(with: .apple)
        XCTAssertTrue(ok)
        XCTAssertFalse(online.awaitingAdultConfirmation)
        XCTAssertNotNil(online.profile)
        XCTAssertEqual(online.linkReward?.granted, true)
    }

    func testTheRulesKeepInsideTheirFixedLimits() throws {
        var book = MockAdminBook()
        XCTAssertThrowsError(try book.setRule(key: "print.single_limit", value: 0.5, reason: "too much"))
        XCTAssertThrowsError(try book.setRule(key: "print.single_limit", value: 0.06, reason: ""))
        try book.setRule(key: "print.single_limit", value: 0.06, reason: "a little more room")
        XCTAssertEqual(book.rules.first { $0.key == "print.single_limit" }?.value, 0.06)
        XCTAssertEqual(book.audit.count, 1)
        XCTAssertEqual(book.audit.first?.action, "rule_change")
        // A single printing may never exceed the whole window.
        XCTAssertThrowsError(try book.setRule(key: "print.window_limit", value: 0.03, reason: "window below the single limit"))
    }
}
