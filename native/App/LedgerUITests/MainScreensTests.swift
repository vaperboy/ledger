import XCTest

/// A second, deeper tour of the screens the player uses most: the company screen and its sections, staff, hiring, the contract
/// discussion, group structure, projects and inbox detail. Pictures are numbered from 20 so they sit after the first tour.
/// Everything is optional: a screen that is not reachable on this device is skipped, never failed.
/// The tour is three tests, not one: CI gives every test 150 s (240 s at most), and on the iOS 26 simulator the single long tour ran past
/// that and was killed by the time limit (the log showed "0 failures" but the test listed as failing). Each part starts a fresh app.
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

    /// Home, the company hub and every section of one company.
    func testMainScreensCompany() {
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
                "team": ["Hire"],
                // Premises, Where you work and Insurance now open the AirStay and Atlas Insurance apps on the Phone (see NavigationBackTests).
                "manage": ["Suppliers", "Equipment"],
                // Sales rows open centred popups (price, Marketing), not pushed pages: nothing to go back from here.
                "stats": ["Ownership"],
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
    }

    /// The Team tab and the Group tab: the picker, an entity page with its tabs, and the Suppliers directory.
    func testMainScreensTeamAndGroup() {
        if !waitForHome() { note("Home summary not found; continuing anyway") }
        open("Group"); sleep(1); shot("40-group-first")
        scrollDown()

        open("Group"); sleep(1); shot("45-group")
        scrollDown(); shot("46-group-lower")
        scrollUp()
        // The picker: open the first entity, then its Management, Board, Money (with Dividends inside) and Expansion tabs.
        let entity = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "group-entity-")).firstMatch
        if entity.waitForExistence(timeout: 3), entity.isHittable {
            entity.tap(); sleep(1); shot("47-group-entity")
            for name in ["Management", "Boardroom", "Money", "Expansion", "Ownership"] {
                let tab = app.buttons["group-tab-\(name)"]
                if tab.waitForExistence(timeout: 2), tab.isHittable { tab.tap(); sleep(1); shot("48-group-\(name.lowercased())") } else { note("no \(name) tab on the entity page") }
            }
            let moneyTab = app.buttons["group-tab-Money"]
            if moneyTab.exists && moneyTab.isHittable {
                moneyTab.tap(); sleep(1)
                shot("48-group-money")
                let policy = app.buttons["money-policy"]
                if policy.waitForExistence(timeout: 2), policy.isHittable { policy.tap(); sleep(1); shot("48-group-money-policy"); if app.buttons["Close"].exists { app.buttons["Close"].tap() } } else { note("no Policy button in Money") }
            }
            let back = app.buttons["group-back"]
            if back.exists && back.isHittable { back.tap(); sleep(1) }
        } else { note("no entity in the Group picker") }
        let suppliers = app.buttons["group-suppliers"]
        if suppliers.waitForExistence(timeout: 2), suppliers.isHittable { suppliers.tap(); sleep(1); shot("49-group-suppliers"); ensureTabBar() }
    }

    /// Projects, the Phone grid and the Inbox.
    func testMainScreensProjectsAndInbox() {
        if !waitForHome() { note("Home summary not found; continuing anyway") }
        open("Ventures"); sleep(1); shot("50-projects")
        // The Inbox is an app inside the Phone tab.
        open("Phone"); sleep(1); shot("51-phone-home")
        let inboxIcon = app.buttons["phone-app-Inbox"]
        if inboxIcon.waitForExistence(timeout: 2) { inboxIcon.tap(); sleep(1) } else { note("no Inbox icon on the Phone") }
        shot("52-inbox")
        let row = app.cells.firstMatch
        if row.exists && row.isHittable { row.tap(); sleep(1); shot("53-inbox-message"); ensureTabBar() }
    }
}

/// Group > Board with a meeting that has a point on its agenda (the `-showcase-board` game: a co-owner, a CFO and three loss months), and the
/// board page with the point's effect, cost and risk, the seats, the rhythm and the minutes. The entity pages are toured in MainScreensTests.
final class BoardTourTests: TourCase {
    override var extraLaunchArguments: [String] { ["-showcase-board"] }

    func testBoardWithAnAgenda() {
        if !waitForHome() { note("Home summary not found; continuing anyway") }
        let group = app.buttons["tab-Group"]
        if group.waitForExistence(timeout: 3) { group.tap(); sleep(1) } else { note("no Group tab"); return }
        shot("60-group-with-board-point")
        let entity = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "group-entity-")).firstMatch
        guard entity.waitForExistence(timeout: 2), entity.isHittable else { note("no entity in the Group picker"); return }
        entity.tap(); sleep(1)
        let board = app.buttons["group-tab-Boardroom"]
        guard board.waitForExistence(timeout: 2), board.isHittable else { note("no Board tab on the entity page"); return }
        board.tap(); sleep(1); shot("61-group-board-decision")
        let open = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Board room")).firstMatch
        guard open.waitForExistence(timeout: 2), open.isHittable else { note("no board decision card"); return }
        open.tap(); sleep(1); shot("62-board-page-agenda")
        app.swipeUp(); sleep(1); shot("63-board-page-lower")
        app.swipeUp(); sleep(1); shot("64-board-page-minutes")
    }
}
