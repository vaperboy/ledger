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

    /// Part 1: Home, the company hub and every section of one company.
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
                "team": ["Find workers"],
                "manage": ["Suppliers", "Insurance", "Premises", "Where you work", "Equipment"],
                "sales": ["Pricing", "Marketing"],
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

    /// Part 2: the Team tab and the Group tab with its Structure parts (Authority: who manages whom) and the Board.
    func testMainScreensTeamAndGroup() {
        if !waitForHome() { note("Home summary not found; continuing anyway") }
        open("Team"); sleep(1); shot("40-team")
        scrollDown()

        open("Group"); sleep(1); shot("45-group")
        scrollDown(); shot("46-group-lower")
        scrollUp()
        // Structure > Authority: every company with who runs it and what authority they have.
        let structure = app.buttons["group-tab-Structure"]
        if structure.waitForExistence(timeout: 3), structure.isHittable {
            structure.tap(); sleep(1); shot("47-group-structure")
            let authority = app.buttons["group-structure-Authority"]
            if authority.waitForExistence(timeout: 2), authority.isHittable {
                authority.tap(); sleep(1); shot("48-group-authority")
            } else { note("no Authority part in Group > Structure") }
            let chains = app.buttons["group-structure-Chains"]
            if chains.exists && chains.isHittable { chains.tap(); sleep(1); shot("49-group-chains") }
        } else { note("no Structure tab in Group") }
        // Board: the agenda (or the line saying why no meeting is due), the seats and the minutes.
        let board = app.buttons["group-tab-Board"]
        if board.waitForExistence(timeout: 2), board.isHittable {
            board.tap(); sleep(1); shot("49-group-board")
            if tap("Open the board") || tap("Seat someone") {
                shot("49-board-page"); scrollDown(); shot("49-board-page-lower"); ensureTabBar()
            }
        } else { note("no Board tab in Group") }
    }

    /// Part 3: Projects, the Phone grid and the Inbox.
    func testMainScreensProjectsAndInbox() {
        if !waitForHome() { note("Home summary not found; continuing anyway") }
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

/// Group > Board with a meeting that has a point on its agenda (the `-showcase-board` game: a co-owner, a CFO and three loss months), and the
/// board page with the point's effect, cost and risk, the seats, the rhythm and the minutes. Group > Structure > Authority is in MainScreensTests.
final class BoardTourTests: TourCase {
    override var extraLaunchArguments: [String] { ["-showcase-board"] }

    func testBoardWithAnAgenda() {
        if !waitForHome() { note("Home summary not found; continuing anyway") }
        let group = app.buttons["tab-Group"]
        if group.waitForExistence(timeout: 3) { group.tap(); sleep(1) } else { note("no Group tab"); return }
        shot("60-group-with-board-point")
        let board = app.buttons["group-tab-Board"]
        guard board.waitForExistence(timeout: 2), board.isHittable else { note("no Board tab in Group"); return }
        board.tap(); sleep(1); shot("61-group-board-decision")
        let open = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Open the board")).firstMatch
        guard open.waitForExistence(timeout: 2), open.isHittable else { note("no board decision card"); return }
        open.tap(); sleep(1); shot("62-board-page-agenda")
        app.swipeUp(); sleep(1); shot("63-board-page-lower")
        app.swipeUp(); sleep(1); shot("64-board-page-minutes")
    }
}
