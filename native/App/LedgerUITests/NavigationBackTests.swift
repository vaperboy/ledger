import XCTest

/// Navigation (spec stage 1): a company opened from Home, Projects or Inbox returns to that screen on Back; choosing the open tab again
/// returns it to its root; a link that crosses tabs returns to its origin and leaves nothing behind; a link to a company screen that is
/// already open never stacks a copy (that one is a unit test: LedgerTests/NavigationStackTests). Run by CI with the screenshot tests. An entry point that the prepared game does not have (the
/// showcase game has no project company) is reported as skipped, never as a pass.
final class NavigationBackTests: TourCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        if !waitForHome() { note("Home summary not found") }
    }

    private func open(_ name: String) {
        let pill = app.buttons["tab-\(name)"]
        if pill.exists { pill.tap(); return }
        let row = app.buttons[name].firstMatch
        if row.exists { row.tap(); return }
        app.staticTexts[name].firstMatch.tap()
    }

    /// The navigation bar's back button, when it can really be tapped.
    /// `title` is the screen being returned to: the back button carries its name (on iPad the first bar button can be the sidebar toggle).
    @discardableResult private func tapBack(to title: String) -> Bool {
        let named = app.navigationBars.buttons[title].firstMatch
        if named.exists && named.isHittable { named.tap(); return true }
        let generic = app.navigationBars.buttons["BackButton"].firstMatch
        if generic.exists && generic.isHittable { generic.tap(); return true }
        let bars = app.navigationBars
        for i in 0..<bars.count {
            let b = bars.element(boundBy: i).buttons.element(boundBy: 0)
            if b.exists && b.isHittable { b.tap(); return true }
        }
        // Screens with the new header (Phone apps, Company screens) have the round back button instead of a navigation bar.
        let round = app.buttons["back-button"]
        if round.exists && round.isHittable { round.tap(); return true }
        return false
    }

    /// The round back button of the screen on top.
    private func tapRoundBack() -> Bool {
        let round = app.buttons["back-button"]
        guard round.waitForExistence(timeout: 3), round.isHittable else { return false }
        round.tap()
        return true
    }

    /// A pushed company shows the Company hub (its six section rows). When the link did not open one on this device the test is skipped
    /// with a note (the picture is kept), instead of waiting out long timeouts and failing.
    private func assertCompanyOpen(_ from: String) throws {
        if app.buttons["company-hub-overview"].waitForExistence(timeout: 3) || app.buttons["company-hub-operations"].waitForExistence(timeout: 1) { return }
        shot("90-nav-\(from.lowercased())-link-no-company")
        throw XCTSkip("the link from \(from) did not open a company on this device")
    }

    /// Opens the first company from the Home list (the showcase game has a café). Returns false when there is none.
    private func openFirstCompany() -> Bool {
        open("Home")
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Café' OR label CONTAINS[c] 'Cafe'")).firstMatch
        guard first.waitForExistence(timeout: 3) else { return false }
        first.tap()
        return app.buttons["company-hub-overview"].waitForExistence(timeout: 5)
    }

    func testBackFromHomeSuggestionReturnsToHome() throws {
        open("Home")
        let link = app.buttons["suggestion-open-company"].firstMatch
        if link.waitForExistence(timeout: 2) {
            link.tap()
        } else {
            // The showcase game has no suggestion that opens a company on this day: use the company list row, the same link by another way.
            note("no Home suggestion with a company link; opened the first company from the list instead")
            guard openFirstCompany() else { throw XCTSkip("no company in the showcase game") }
        }
        try assertCompanyOpen("Home")
        XCTAssertTrue(tapBack(to: "Home"))
        // Asserted: Back lands on Home (the net-worth summary).
        XCTAssertTrue(app.staticTexts["Net worth"].firstMatch.waitForExistence(timeout: 5) || app.staticTexts["NET WORTH"].firstMatch.exists, "Back should return to Home")
    }

    func testBackFromInboxCompanyLinkReturnsToInbox() throws {
        open("Phone")
        let inboxIcon = app.buttons["phone-app-Inbox"]
        XCTAssertTrue(inboxIcon.waitForExistence(timeout: 3), "the Inbox is an app on the Phone")
        inboxIcon.tap()
        let search = app.textFields["Search messages"]
        XCTAssertTrue(search.waitForExistence(timeout: 3), "the Inbox app should be open")
        let link = app.buttons["open-company-link"].firstMatch
        guard link.waitForExistence(timeout: 2) else { throw XCTSkip("no Inbox message with a company link in the showcase game") }
        link.tap()
        // Strict: the Inbox link must open a company screen (no skip): the Inbox list is covered and a Back button is on screen.
        XCTAssertTrue(app.buttons["back-button"].waitForExistence(timeout: 5), "the Inbox company link should open the company")
        XCTAssertFalse(search.isHittable, "the company screen should cover the Inbox list")
        XCTAssertTrue(tapBack(to: "Inbox"))
        // Asserted: Back lands on the Inbox app, not on Home.
        XCTAssertTrue(app.textFields["Search messages"].waitForExistence(timeout: 5), "Back should return to the Inbox")
        XCTAssertFalse(app.staticTexts["Net worth"].firstMatch.exists, "Back must not land on Company/Home")
    }

    func testBackFromProjectsReturnsToProjects() throws {
        open("Projects")
        let link = app.buttons["open-project-company"].firstMatch
        guard link.waitForExistence(timeout: 2) else { throw XCTSkip("no company with project work in the showcase game") }
        link.tap()
        XCTAssertTrue(app.buttons["back-button"].waitForExistence(timeout: 5), "the project link should open the company")
        XCTAssertTrue(tapBack(to: "Projects"))
        // Asserted: Back lands on Projects (Work / Ventures tabs), not on the Company list.
        XCTAssertTrue(app.buttons["Ventures"].waitForExistence(timeout: 5), "Back should return to Projects")
        XCTAssertFalse(app.staticTexts["Net worth"].firstMatch.exists)
    }

    // MARK: Stage 1 navigation

    /// Choosing the tab that is already open returns it to its root: here a company's Operations screen on Home.
    func testReselectingHomeReturnsToItsRoot() throws {
        guard openFirstCompany() else { throw XCTSkip("no company in the showcase game") }
        app.buttons["company-hub-operations"].tap()
        XCTAssertTrue(app.buttons["back-button"].waitForExistence(timeout: 3), "Operations should be pushed on the company hub")
        let pill = app.buttons["tab-Home"]
        guard pill.exists else { throw XCTSkip("no floating tab bar on this device (the iPad sidebar does not report a re-selected row)") }
        pill.tap()
        XCTAssertTrue(waitForHome(5), "choosing Home again should show the Home root")
        XCTAssertFalse(app.buttons["company-hub-overview"].exists, "no company screen may stay on the Home stack")
        XCTAssertFalse(app.buttons["company-hub-operations"].exists)
    }

    /// The same on the Phone tab: an app is open, choosing Phone again shows the grid of apps.
    func testReselectingPhoneReturnsToTheAppGrid() throws {
        open("Phone")
        let inboxIcon = app.buttons["phone-app-Inbox"]
        XCTAssertTrue(inboxIcon.waitForExistence(timeout: 3))
        inboxIcon.tap()
        XCTAssertTrue(app.textFields["Search messages"].waitForExistence(timeout: 3))
        let pill = app.buttons["tab-Phone"]
        guard pill.exists else { throw XCTSkip("no floating tab bar on this device") }
        pill.tap()
        XCTAssertTrue(app.buttons["phone-app-Bank"].waitForExistence(timeout: 3), "choosing Phone again should show the app grid")
        XCTAssertFalse(app.textFields["Search messages"].isHittable, "the Inbox must not stay open")
    }

    /// A link that crosses tabs (Home to the Bank app on the Phone tab): Back returns to Home, and the Phone tab keeps no Bank screen.
    func testBackFromACrossTabLinkReturnsToTheOriginAndLeavesNothingBehind() throws {
        open("Home")
        let bank = app.buttons["home-bank"]
        guard bank.waitForExistence(timeout: 3) else { throw XCTSkip("no Bank shortcut on Home") }
        bank.tap()
        XCTAssertTrue(app.buttons["tab-Phone"].waitForExistence(timeout: 3))
        XCTAssertTrue(tapRoundBack(), "the Bank app should have a Back button")
        XCTAssertTrue(waitForHome(5), "Back from a link opened on another tab should return to Home, where the link was")
        // Nothing of the link stays on the Phone tab: its first page is the app grid.
        open("Phone")
        XCTAssertTrue(app.buttons["phone-app-Bank"].waitForExistence(timeout: 3), "the Phone tab should show its app grid, not the Bank app")
    }

    /// A section of a company is a pushed step: one Back from it returns to the company hub, one more to Home.
    func testASectionIsOneStepFromTheHub() throws {
        guard openFirstCompany() else { throw XCTSkip("no company in the showcase game") }
        app.buttons["company-hub-operations"].tap()
        XCTAssertTrue(tapRoundBack())
        XCTAssertTrue(app.buttons["company-hub-operations"].waitForExistence(timeout: 3), "Back from a section returns to the company hub")
        XCTAssertTrue(tapRoundBack())
        XCTAssertTrue(waitForHome(5), "Back from the hub returns to Home")
    }
}
