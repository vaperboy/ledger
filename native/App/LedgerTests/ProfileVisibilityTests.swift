import XCTest
@testable import Ledger

final class ProfileVisibilityTests: XCTestCase {
    private func profile(_ privacy: PrivacyLevel) -> PlayerProfile {
        PlayerProfile(id: "p1", code: "ABC-1234", displayName: "Ingrid Solheim", avatarColour: 2, countryCode: "NO", level: 14, badges: ["Early player"], privacy: privacy,
                      companyCount: 3, companies: [OnlineCompany(id: "c1", name: "Solheim Bakery", trade: "Bakery", city: "Oslo", countryCode: "NO", health: .thriving)],
                      gameWeek: 200, tradesCompleted: 9, relation: .none, avatarIcon: nil, lastSeen: 5)
    }

    func testPrivateShowsNameOnly() {
        let v = ProfileVisibility.apply(profile(.onlyMe), relation: .friend)
        XCTAssertEqual(v.displayName, "Ingrid Solheim")
        XCTAssertNil(v.level)
        XCTAssertTrue(v.badges.isEmpty)
        XCTAssertNil(v.companyCount)
        XCTAssertNil(v.companies)
        XCTAssertNil(v.gameWeek)
        XCTAssertNil(v.tradesCompleted)
        XCTAssertNil(v.lastSeen)
    }

    func testPublicStrangerSeesLevelBadgesCountButNoCompanies() {
        let v = ProfileVisibility.apply(profile(.everyone), relation: .none)
        XCTAssertEqual(v.level, 14)
        XCTAssertEqual(v.badges, ["Early player"])
        XCTAssertEqual(v.companyCount, 3)
        XCTAssertNil(v.companies)
    }

    func testPublicFriendSeesCompanies() {
        XCTAssertNotNil(ProfileVisibility.apply(profile(.everyone), relation: .friend).companies)
    }

    func testFriendsOnlyHidesCountFromStrangers() {
        let v = ProfileVisibility.apply(profile(.friends), relation: .none)
        XCTAssertEqual(v.level, 14)
        XCTAssertNil(v.companyCount)
        XCTAssertNil(v.companies)
        XCTAssertNil(v.tradesCompleted)
    }

    func testBlockedShowsNameOnly() {
        let v = ProfileVisibility.apply(profile(.everyone), relation: .blocked)
        XCTAssertNil(v.level)
        XCTAssertNil(v.companies)
    }

    func testOwnProfileIsUntouched() {
        XCTAssertEqual(ProfileVisibility.apply(profile(.onlyMe), relation: .you).level, 14)
    }

    func testBoardFigureHiddenOnlyForPrivate() {
        XCTAssertFalse(ProfileVisibility.showsBoardFigure(.onlyMe))
        XCTAssertTrue(ProfileVisibility.showsBoardFigure(.friends))
        XCTAssertTrue(ProfileVisibility.showsBoardFigure(.everyone))
    }

    func testRivalProfileFollowsTheSameRules() {
        for n in ["Erik Holm", "Astrid Jensen", "Mikkel Weber", "Freja Bakker", "Eino Rossi", "Aino Bell"] {
            let p = BoardProfiles.rivalProfile(id: "rival-" + n, name: n)
            XCTAssertNil(p.companies)
            XCTAssertEqual(p.countryCode, "")
            if p.privacy == .onlyMe { XCTAssertNil(p.level); XCTAssertTrue(p.badges.isEmpty) } else { XCTAssertNotNil(p.level) }
        }
    }
}
