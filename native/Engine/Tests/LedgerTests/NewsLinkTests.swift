import XCTest
import GameCore
import Simulation

/// News items can carry the company of yours they are about, so the news app can link to it.
final class NewsLinkTests: XCTestCase {
    func testNewsKeepsTheCompanyItIsAbout() throws {
        var e = try GameEngine.newGame(countryCode: "DE", playerName: "T", seed: 21)
        e.update { s, _, _ in
            s.news("A rival opens nearby.")
            s.news("Your shop is in the paper.", tone: "good", companyID: 7)
        }
        let list = e.news
        XCTAssertEqual(list.first?.companyID, 7)
        XCTAssertEqual(list.first?.tone, "good")
        XCTAssertEqual(list.dropFirst().first?.companyID, 0, "an item without a company stays unlinked")
    }
}
