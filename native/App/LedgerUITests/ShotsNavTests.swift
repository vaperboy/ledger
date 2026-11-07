import XCTest

/// Screenshots of moving between companies, chains and apps without changing tab, and the check that no link changes tab:
/// Home > company > its Group entity page > Back > Back; Group > entity > its company > another company (switcher) > Back;
/// Inbox > a message's company > Back to the Inbox; Phone > Bank > company account > its company > Back.
/// A step that cannot be done in this game is screenshotted and noted; the walk goes on.
final class ShotsNavTests: FeatureTourCase {
    private var problems: [String] = []

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "Nav-" + name
        a.lifetime = .keepAlways
        add(a)
    }

    private func expect(_ ok: Bool, _ what: String) {
        if !ok { problems.append(what); shot("problem-\(problems.count)") }
    }

    /// The tab the walk started on is still the selected one.
    private func sameTab(_ tab: String, _ at: String) {
        expect(isSelected("tab-\(tab)"), "\(at): the selected tab is no longer \(tab) (\(tabState()))")
    }

    /// The tab that is selected now ("Phone", or the Pick tab's app when an app was opened there).
    private func selectedTab() -> String {
        let tabs: XCUIElementQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab-'"))
        for i in 0..<tabs.count {
            let t: XCUIElement = tabs.element(boundBy: i)
            if t.isSelected { return String(t.identifier.dropFirst(4)) }
        }
        return "Phone"
    }

    private func companyShowing(_ wait: TimeInterval = 4) -> Bool { has("company-tab-overview", wait: wait) || has("company-tab-manage") }

    /// Opens a switcher menu and taps the first item whose identifier starts with `prefix`, else the first whose label passes `label`.
    private func pick(_ switcher: String, _ prefix: String, label: (String) -> Bool = { _ in false }, shotName: String) -> Bool {
        guard tapID(switcher, wait: 3) else { return false }
        pause(0.8)
        shot(shotName)
        let byID: XCUIElement = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
        if byID.waitForExistence(timeout: 2) { byID.tap(); pause(1); return true }
        let all: [XCUIElement] = app.buttons.allElementsBoundByIndex
        if let b = all.first(where: { label($0.label) && $0.isHittable }) { b.tap(); pause(1); return true }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
        pause(0.6)
        return false
    }

    func testShots() {
        homeToEntityAndBack()
        groupToCompanyAndSwitch()
        inboxToCompanyAndBack()
        bankToCompanyAndBack()
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
    }

    /// Home > company > its Group entity page > Back > Back, all on Home; then Team > Managers and executives > Back.
    private func homeToEntityAndBack() {
        guard goTab("Home") else { expect(false, "no Home tab"); return }
        shot("A0-home")
        guard openCompany("Caf") || tapWhere(wait: 3, { $0.type == .button && $0.label.contains("\u{00B7}") && !$0.id.hasPrefix("home-") && !$0.id.hasPrefix("tab-") }) else {
            expect(false, "Home: no company row to open"); return
        }
        expect(companyShowing(), "Home: the company page did not open")
        shot("A1-home-company")
        sameTab("Home", "Home > company")
        let opened: Bool = pick("company-switcher", "company-open-group", label: { $0.hasSuffix(" in Group") }, shotName: "A2-home-company-switcher")
        expect(opened, "Home > company: no Group entity link in the switcher")
        if opened {
            expect(has("group-back", wait: 4), "Home > company > entity: the entity page did not open")
            shot("A3-home-entity")
            sameTab("Home", "Home > company > entity")
            expect(tapBack(), "Home > entity: no Back")
            expect(companyShowing(), "Home > entity > Back: not on the company")
            shot("A4-home-entity-back")
            sameTab("Home", "Home > entity > Back")
        }
        expect(tapBack(), "Home > company: no Back")
        expect(homeVisible(4), "Home > company > Back: not on Home")
        shot("A5-home-back")
        sameTab("Home", "Home > company > Back")
        // Team's "Managers and executives" pushes the entity's Management page on Home too.
        if openCompany("Caf"), tapID("company-tab-team"), tapID("team-open-management", wait: 4) {
            pause(0.8)
            expect(isSelected("group-tab-Management"), "Team > management: the entity's Management page is not showing")
            shot("A6-home-team-management")
            sameTab("Home", "Team > management")
            expect(tapBack() && isSelected("company-tab-team"), "Team > management > Back: not on Team")
            shot("A7-home-team-management-back")
        } else {
            shot("A6-no-management-link")
        }
    }

    /// Group > entity > its company > another company through the switcher > Back to the entity; the entity switcher; Back to the picker.
    private func groupToCompanyAndSwitch() {
        guard goTab("Group") else { expect(false, "no Group tab"); return }
        shot("B0-group")
        guard tapPrefix("group-entity-co", wait: 4) || tapPrefix("group-entity-", wait: 2) else { expect(false, "Group: no entity row"); return }
        expect(has("group-back", wait: 4), "Group > entity: the entity page did not open")
        shot("B1-group-entity")
        sameTab("Group", "Group > entity")
        let toCompany: Bool = tapLabel("Open the", wait: 3) || pick("entity-switcher", "entity-open-company-", shotName: "B1b-group-entity-switcher")
        expect(toCompany && companyShowing(), "Group > entity: could not open its company")
        shot("B2-group-company")
        sameTab("Group", "Group > entity > company")
        if toCompany {
            let before: [String] = signature().heads
            if pick("company-switcher", "company-switch-", label: { $0.contains("\u{00B7}") && !$0.hasSuffix(" in Group") }, shotName: "B3-group-company-switcher") {
                expect(companyShowing(), "Group > company > switch: no company page after switching")
                expect(signature().heads != before, "Group > company > switch: the page still shows the same company")
                shot("B4-group-company-switched")
                sameTab("Group", "Group > company > switch")
            } else {
                shot("B4-no-other-company")
            }
            expect(tapBack(), "Group > company: no Back")
            expect(has("group-back", wait: 4), "Group > company > Back: not on the entity page")
            shot("B5-group-company-back")
            sameTab("Group", "Group > company > Back")
        }
        if pick("entity-switcher", "entity-switch-", label: { $0.contains("\u{00B7}") }, shotName: "B6-group-entity-switcher") {
            expect(has("group-back", wait: 4), "Group > entity > switch: no entity page after switching")
            shot("B7-group-entity-switched")
            sameTab("Group", "Group > entity > switch")
        }
        expect(tapBack(), "Group > entity: no Back")
        expect(find(wait: 4, { $0.id.hasPrefix("group-entity-") }) != nil, "Group > entity > Back: not on the picker")
        shot("B8-group-back")
    }

    /// Phone > Inbox > a message's company > Back to the Inbox, on the Phone tab.
    private func inboxToCompanyAndBack() {
        guard openPhoneApp("Inbox") else { expect(false, "no Inbox app"); return }
        // The app may open on the Phone tab or, when the unlock ladder keeps it off the grid, in the Pick tab: that tab must stay.
        let home: String = selectedTab()
        shot("C0-inbox")
        guard tapWhere(wait: 4, { $0.id == "open-company-link" && $0.type == .button }) else { shot("C1-no-company-link"); return }
        expect(companyShowing() || has("back-button", wait: 2), "Inbox > company link: no company page")
        shot("C1-inbox-company")
        sameTab(home, "Inbox > company")
        expect(tapBack(), "Inbox > company: no Back")
        expect(app.textFields["Search messages"].waitForExistence(timeout: 4) || has("inbox-row", wait: 2), "Inbox > company > Back: not on the Inbox")
        shot("C2-inbox-back")
        sameTab(home, "Inbox > company > Back")
    }

    /// Phone > Bank > a company account > its company > Back to the account, on the Phone tab.
    private func bankToCompanyAndBack() {
        guard openPhoneApp("Bank") else { expect(false, "no Bank app"); return }
        let home: String = selectedTab()
        shot("D0-bank")
        guard tapPrefix("bank-pick-company", wait: 4) || tapPrefix("bank-account-company", wait: 3) else { shot("D1-no-company-account"); return }
        shot("D1-bank-company-account")
        expect(tapID("bank-open-company", wait: 3), "Bank > company account: no link to the company")
        expect(companyShowing(), "Bank > company account > company: no company page")
        shot("D2-bank-company")
        sameTab(home, "Bank > company")
        expect(tapBack(), "Bank > company: no Back")
        expect(has("bank-open-company", wait: 4), "Bank > company > Back: not on the company account")
        shot("D3-bank-back")
        sameTab(home, "Bank > company > Back")
    }
}
