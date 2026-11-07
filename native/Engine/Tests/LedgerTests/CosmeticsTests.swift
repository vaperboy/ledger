import XCTest
@testable import Simulation

/// Cosmetics unlock rules and the Home progress maths.
final class CosmeticsTests: XCTestCase {
    func testDefaultsAreAlwaysFree() {
        XCTAssertTrue(Cosmetics.isBadgeUnlocked(Cosmetics.defaultBadgeID, earned: [], pro: false))
        XCTAssertTrue(Cosmetics.isThemeUnlocked(Cosmetics.defaultThemeID, pro: false))
    }

    func testCareerBadgesAreFreeOnceEarned() {
        XCTAssertFalse(Cosmetics.isBadgeUnlocked("logo.star", earned: [], pro: false))
        XCTAssertTrue(Cosmetics.isBadgeUnlocked("logo.star", earned: ["logo.star"], pro: false))
        XCTAssertFalse(Cosmetics.isBadgeUnlocked("logo.star", earned: [], pro: true))
    }

    func testPremiumNeedsPro() {
        XCTAssertFalse(Cosmetics.isBadgeUnlocked("pro.bolt", earned: ["pro.bolt"], pro: false))
        XCTAssertTrue(Cosmetics.isBadgeUnlocked("pro.bolt", earned: [], pro: true))
        XCTAssertFalse(Cosmetics.isThemeUnlocked("emerald", pro: false))
        XCTAssertTrue(Cosmetics.isThemeUnlocked("emerald", pro: true))
        XCTAssertFalse(Cosmetics.isThemeUnlocked("nope", pro: true))
    }

    func testLapsedProFallsBack() {
        XCTAssertEqual(Cosmetics.resolvedBadge("pro.bolt", earned: [], pro: false).id, Cosmetics.defaultBadgeID)
        XCTAssertEqual(Cosmetics.resolvedTheme("violet", pro: false).id, Cosmetics.defaultThemeID)
        XCTAssertEqual(Cosmetics.resolvedTheme("violet", pro: true).id, "violet")
        XCTAssertEqual(Cosmetics.resolvedBadge(nil, earned: [], pro: true).id, Cosmetics.defaultBadgeID)
    }

    func testEveryCareerBadgeIsInTheCatalogue() {
        for id in ["logo.star", "logo.coin", "logo.laurel", "logo.cup", "logo.banner", "logo.diamond", "logo.crown", "logo.skyline", "logo.bell", "logo.seal", "logo.crest"] {
            XCTAssertTrue(Cosmetics.badges.contains { $0.id == id }, id)
        }
        XCTAssertEqual(Cosmetics.careerBadgesLeft(earned: []), 11)
        XCTAssertEqual(Set(Cosmetics.badges.map { $0.id }).count, Cosmetics.badges.count)
    }

    func testPercentAndClamp() {
        XCTAssertEqual(HomeProgress.percent(0.999), 99)
        XCTAssertEqual(HomeProgress.percent(1), 100)
        XCTAssertEqual(HomeProgress.percent(-3), 0)
        XCTAssertEqual(HomeProgress.percent(Double.nan), 0)
    }

    func testRunway() {
        XCTAssertEqual(HomeProgress.runwayDays(cash: [100, 90, 80, 70, 60]), 6)
        XCTAssertNil(HomeProgress.runwayDays(cash: [10, 20, 30]))
        XCTAssertNil(HomeProgress.runwayDays(cash: [5, 4]))
    }

    func testNormalised() {
        XCTAssertEqual(HomeProgress.normalised([2, 4, 6]), [0, 0.5, 1])
        XCTAssertEqual(HomeProgress.normalised([3, 3]), [0.5, 0.5])
        XCTAssertEqual(HomeProgress.normalised([]), [])
    }
}
