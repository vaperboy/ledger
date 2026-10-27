import XCTest

/// A second, deeper tour of the screens the player uses most: the company screen and its sections, staff, hiring, the contract
/// discussion, group structure, projects and inbox detail. Pictures are numbered from 20 so they sit after the first tour.
/// Everything is optional: a screen that is not reachable on this device is skipped, never failed.
final class MainScreensTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-showcase"]
        app.launch()
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Pops pushed screens until the tab bar is on screen (at most 6 times), so a sub-screen that did not return cannot strand the tour.
    /// The tab bar is the floating pill bar on iPhone (buttons "tab-Home" ...), the sidebar on iPad.
    func ensureTabBar() {
        var tries = 0
        while !app.buttons["tab-Home"].isHittable && !app.tabBars.firstMatch.buttons.firstMatch.isHittable && tries < 6 {
            let before = app.navigationBars.count
            goBack(); sleep(1); tries += 1
            if before == 0 { break }
        }
    }

    func open(_ name: String) {
        ensureTabBar()
        let pill = app.buttons["tab-\(name)"]
        if pill.waitForExistence(timeout: 5) { pill.tap(); return }
        let tab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
        if tab.exists { tab.tap(); return }
        let row = app.buttons[name].firstMatch
        if row.exists { row.tap(); return }
        let t = app.staticTexts[name].firstMatch
        if t.exists { t.tap() }
    }

    func goBack() {
        let round = app.buttons["back-button"]
        if round.exists && round.isHittable { round.tap(); return }
        let bars = app.navigationBars
        for i in 0..<bars.count {
            let b = bars.element(boundBy: i).buttons.element(boundBy: 0)
            if b.exists && b.isHittable { b.tap(); return }
        }
    }

    /// Taps the first button or text whose label begins with / contains the text; returns whether something was tapped.
    @discardableResult
    func tap(_ text: String) -> Bool {
        let b = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        if b.exists && b.isHittable { b.tap(); sleep(1); return true }
        let t = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        if t.exists && t.isHittable { t.tap(); sleep(1); return true }
        return false
    }

    func scrollDown() { app.swipeUp(); sleep(1) }
    func scrollUp() { app.swipeDown(); app.swipeDown(); app.swipeDown(); sleep(1) }

    func testMainScreens() {
        XCTAssertTrue(app.staticTexts["Net worth"].firstMatch.waitForExistence(timeout: 20) || app.staticTexts["NET WORTH"].firstMatch.waitForExistence(timeout: 5))
        shot("20-home")
        scrollDown(); shot("21-home-lower")

        // Company list and one company with every section
        open("Home"); sleep(1); shot("22-home-companies")
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Café' OR label CONTAINS[c] 'Cafe'")).firstMatch
        if first.waitForExistence(timeout: 3) {
            first.tap(); sleep(1); shot("23-company-overview")
            scrollDown(); shot("24-company-overview-lower")
            scrollUp()
            var n = 25
            for section in ["Team", "Finances", "Operations", "Marketing", "Customers", "Market", "Setup"] {
                let b = app.buttons[section]
                if b.exists && b.isHittable {
                    b.tap(); sleep(1); shot("\(n)-company-\(section.lowercased())"); n += 1
                    scrollDown(); shot("\(n)-company-\(section.lowercased())-lower"); n += 1
                    scrollUp()
                    if section == "Operations" {
                        for sub in ["Suppliers", "Insurance", "Working from home"] where tap(sub) {
                            shot("\(n)-operations-\(sub.lowercased().replacingOccurrences(of: " ", with: "-"))"); n += 1
                            if !app.buttons["Operations"].isHittable { goBack(); sleep(1) }
                        }
                    }
                    if section == "Finances" {
                        for sub in ["Payroll", "Accounts", "Loans"] where tap(sub) {
                            shot("\(n)-finances-\(sub.lowercased().replacingOccurrences(of: " ", with: "-"))"); n += 1
                            // These are tabs inside the Finances page, not pushed screens: there is nothing to go back from.
                        }
                    }
                    if section == "Team" {
                        if tap("Find workers") { shot("\(n)-team-find-workers"); n += 1; if !app.buttons["Team"].isHittable { goBack(); sleep(1) } }
                    }
                }
            }
        }
        ensureTabBar()

        // Team tab and a person
        open("Team"); sleep(1); shot("40-team")
        scrollDown(); shot("41-team-lower")

        // Group
        open("Group"); sleep(1); shot("45-group")
        scrollDown(); shot("46-group-lower")
        if tap("Stand alone") { shot("47-group-stand-alone"); ensureTabBar() }

        // Projects and Inbox detail
        open("Projects"); sleep(1); shot("50-projects")
        // The Inbox is an app inside the Phone tab.
        open("Phone"); sleep(1); shot("51-phone-home")
        let inboxIcon = app.buttons["phone-app-Inbox"]
        if inboxIcon.waitForExistence(timeout: 3) { inboxIcon.tap(); sleep(1) }
        shot("52-inbox")
        let row = app.cells.firstMatch
        if row.exists && row.isHittable { row.tap(); sleep(1); shot("53-inbox-message"); ensureTabBar() }
    }
}
