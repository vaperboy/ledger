import XCTest

/// A second, deeper tour of the screens the player uses most: the company screen and its sections, staff, hiring, the contract
/// discussion, group structure, projects and inbox detail. Pictures are numbered from 20 so they sit after the first tour.
/// Everything is optional: a screen that is not reachable on this device is skipped, never failed.
final class MainScreensTests: TourCase {

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
        if pill.waitForExistence(timeout: 3) { pill.tap(); return }
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
        if !waitForHome() { note("Home summary not found; continuing anyway") }
        shot("20-home")
        scrollDown(); shot("21-home-lower")

        // Company list and one company with every section
        open("Home"); sleep(1)
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Café' OR label CONTAINS[c] 'Cafe'")).firstMatch
        if first.waitForExistence(timeout: 3) {
            first.tap(); sleep(1); shot("23-company-hub")
            var n = 25
            // The five sections of the fixed bar switch in place. Pages inside a section are pushed: Back once returns to the section.
            let subpages: [String: [String]] = [
                "team": ["Find workers"],
                "manage": ["Suppliers", "Insurance", "Premises", "Where you work", "Equipment"],
                "sales": ["Marketing", "Customers", "Market"],
                "stats": ["Statements", "Ownership"],
            ]
            for section in ["overview", "team", "manage", "sales", "stats"] {
                let b = app.buttons["company-tab-" + section]
                guard b.waitForExistence(timeout: 2), b.isHittable else { note("no company hub row \(section)"); continue }
                b.tap(); sleep(1); shot("\(n)-company-\(section)"); n += 1
                scrollDown(); shot("\(n)-company-\(section)-lower"); n += 1
                scrollUp()
                for sub in subpages[section] ?? [] where tap(sub) {
                    shot("\(n)-\(section)-\(sub.lowercased().replacingOccurrences(of: " ", with: "-"))"); n += 1
                    goBack(); sleep(1)
                }
            }
            goBack(); sleep(1)
        }
        ensureTabBar()

        // Team tab and a person
        open("Team"); sleep(1); shot("40-team")
        scrollDown()

        // Group
        open("Group"); sleep(1); shot("45-group")
        scrollDown(); shot("46-group-lower")
        if tap("Stand alone") { shot("47-group-stand-alone"); ensureTabBar() }

        // Projects and Inbox detail
        open("Projects"); sleep(1); shot("50-projects")
        // The Inbox is an app inside the Phone tab.
        open("Phone"); sleep(1); shot("51-phone-home")
        let inboxIcon = app.buttons["phone-app-Inbox"]
        if inboxIcon.waitForExistence(timeout: 2) { inboxIcon.tap(); sleep(1) } else { note("no Inbox icon on the Phone") }
        shot("52-inbox")
        let row = app.cells.firstMatch
        if row.exists && row.isHittable { row.tap(); sleep(1); shot("53-inbox-message"); ensureTabBar() }
    }
}
