import XCTest

final class ScreenShotsTests: FeatureTourCase {
    static let seenFlags: [String] = ["firstRun.tour.group", "firstRun.tour.ventures", "firstRun.tour.phone", "firstRun.tour.custom", "firstRun.tour.company",
                                      "firstRun.appHelp.bank", "firstRun.appHelp.market", "firstRun.appHelp.atlas", "firstRun.appHelp.inbox", "firstRun.appHelp.news",
                                      "firstRun.appHelp.competition", "firstRun.appHelp.techPro", "firstRun.appHelp.airStay", "firstRun.appHelp.luxury",
                                      "firstRun.appHelp.marketplace", "firstRun.appHelp.auctions"]
    static let coachIDs: [String] = ["coach-skip", "coach-next"]
    static let closeFirst: [String] = ["report-continue", "daily-continue", "locked-ok", "recap-ok", "review-later", "purchase-notice-dismiss"]

    // The showcase game with every first-visit coach tour marked as seen, so the screens are not dimmed.
    // The key and value pairs come first so the bare flags after them cannot be read as a value.
    static var showcaseArguments: [String] {
        var out: [String] = []
        for key in seenFlags {
            out.append("-" + key)
            out.append("YES")
        }
        return out + ["-showcase", "-showcase-rich", "-showcase-board"]
    }

    // Outside the showcase the app signs up on the game server once the terms are accepted, so the first-run walk is opt-in.
    static var firstRunAllowed: Bool { ProcessInfo.processInfo.environment["SCREENS_FIRST_RUN"] == "1" }

    var letter: String = "X"
    var shotNumber: Int = 0
    var stopped: String?
    var keepCoach: Bool = false
    var appOpen: Bool = false
    var companyOpen: Bool = false

    override func setUp() {
        continueAfterFailure = true
        testDeadline = Date().addingTimeInterval(13 * 60)
        winCache = .zero
        smallTargets = [:]
        tappedTargets = []
        app = XCUIApplication()
        let fresh: Bool = name.contains("FirstLaunch")
        if fresh && !Self.firstRunAllowed { return }
        app.launchArguments = fresh ? [] : Self.showcaseArguments
        app.launch()
        if !fresh && !reachHome() { stopped = "Home did not show within 45 s of launch" }
    }

    private func reachHome() -> Bool {
        let end: Date = Date().addingTimeInterval(45)
        var home = false
        while Date() < end && !home {
            let later: XCUIElement = app.buttons["ambition-later"].firstMatch
            if later.exists { ctap(later); pause(1) } else if popupUp() { closePopup() }
            var closes = 0
            while closes < 10 && popupUp(1) { closePopup(); closes += 1 }
            if !popupUp() { _ = goTab("Home") }
            home = !popupUp() && homeVisible(3)
        }
        return home
    }

    func tag(_ name: String) -> String { letter + String(format: "%02d", shotNumber) + "-" + name }

    func keep(_ label: String) {
        let a: XCTAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = label
        a.lifetime = .keepAlways
        add(a)
    }

    func skipped(_ label: String, _ why: String) {
        let a: XCTAttachment = XCTAttachment(string: "SKIPPED " + label + ": " + why)
        a.name = "SKIPPED-" + label
        a.lifetime = .keepAlways
        add(a)
    }

    func ok(_ done: Bool, _ why: String) -> String? {
        if done { return nil }
        return why
    }

    // One numbered screen: reach returns nil when the screen is up, or the reason it could not be reached.
    @discardableResult
    func screen(_ name: String, settle: Double = 1.2, _ reach: () -> String?) -> Bool {
        shotNumber += 1
        let label: String = tag(name)
        if let why = stopped { skipped(label, why); return false }
        if Date() > testDeadline { skipped(label, "the time cap for this test was reached"); return false }
        if !keepCoach { skipCoach() }
        if let why = reach() { skipped(label, why); return false }
        pause(settle)
        if !keepCoach { skipCoach() }
        keep(label)
        return true
    }

    func act(_ body: () -> Void) {
        if stopped == nil && Date() <= testDeadline { body() }
    }

    func popup(_ name: String, _ reach: () -> String?) {
        screen(name) {
            if let why = reach() { return why }
            return ok(popupUp(3), "its popup did not open")
        }
        act { clearPopups() }
    }

    // A pushed page: it counts only when the screen changed, and Back is tapped afterwards only then.
    func page(_ name: String, _ reach: () -> String?) {
        let shown: Bool = screen(name) {
            let before: TourSig = signature()
            if let why = reach() { return why }
            pause(0.6)
            if popupUp() { return nil }
            let after: TourSig = signature()
            return ok(!before.same(after), "tapping it did not open a page")
        }
        act {
            if popupUp() { clearPopups() } else if shown { _ = tapBack(); pause(0.4) }
        }
    }

    func lower(_ name: String, on: Bool, why: String) {
        let shown: Bool = screen(name) {
            guard on else { return why }
            dragPage(-420)
            return nil
        }
        act { if shown { dragPage(420) } }
    }

    func skipCoach() {
        let q: XCUIElementQuery = app.buttons.matching(NSPredicate(format: "identifier IN %@", Self.coachIDs))
        var n = 0
        while n < 4 {
            let b: XCUIElement = q.firstMatch
            guard b.exists, ctap(b) else { break }
            pause(0.5)
            n += 1
        }
    }

    func clearPopups(_ limit: Int = 6) {
        var n = 0
        while n < limit && popupUp(n == 0 ? 0.6 : 1) {
            closePopup(prefer: Self.closeFirst)
            n += 1
        }
    }

    func openTab(_ title: String) -> Bool {
        clearPopups(4)
        let id: String = "tab-" + title
        guard let t = find(wait: 5, { (h: Hit) -> Bool in h.type == .button && h.id == id }) else { return false }
        touch(t)
        pause(0.6)
        return true
    }

    // Taps what the predicate finds, scrolling the page down a few times when it is below the fold.
    func seek(wait: TimeInterval = 2, _ pred: (Hit) -> Bool) -> Bool {
        if tapWhere(wait: wait, pred) { return true }
        var moved = 0
        while moved < 4 {
            dragPage(-360)
            moved += 1
            if tapWhere(wait: 0.2, pred) { return true }
        }
        for _ in 0..<moved { dragPage(360) }
        return false
    }

    func seekID(_ id: String) -> Bool { seek { (h: Hit) -> Bool in h.id == id } }
    func seekPrefix(_ prefix: String) -> Bool { seek { (h: Hit) -> Bool in h.type == .button && h.id.hasPrefix(prefix) } }
    func seekEnabled(_ id: String) -> Bool { seek { (h: Hit) -> Bool in h.type == .button && h.enabled && h.id == id } }
    func seekLabel(_ label: String) -> Bool { seek { (h: Hit) -> Bool in h.type == .button && h.label == label } }
    func seekLabelPrefix(_ prefix: String) -> Bool { seek { (h: Hit) -> Bool in h.type == .button && h.label.hasPrefix(prefix) } }
    func seekText(_ text: String) -> Bool {
        seek { (h: Hit) -> Bool in (h.type == .button || h.type == .cell) && h.label.localizedCaseInsensitiveContains(text) }
    }

    // Taps a popup's own button where it stands: popup footers can sit lower than the tab bar.
    func pressButton(_ id: String, wait: TimeInterval = 2) -> Bool {
        let b: XCUIElement = button(id)
        guard b.waitForExistence(timeout: wait) else { return false }
        return ctap(b)
    }

    func buttonUp(prefix: String, wait: TimeInterval) -> Bool {
        let found: Hit? = find(wait: wait, { (h: Hit) -> Bool in h.type == .button && h.id.hasPrefix(prefix) })
        return found != nil
    }

    // Taps a button in a horizontal strip, dragging the strip sideways when the button is off the edge.
    func tapInStrip(_ id: String, stripPrefix: String) -> Bool {
        let w: CGRect = win()
        for i in 0..<6 {
            let wait: TimeInterval = i == 0 ? 2 : 0.4
            if let h = find(wait: wait, { (x: Hit) -> Bool in x.type == .button && x.id == id }), h.frame.minX >= w.minX - 1, h.frame.maxX <= w.maxX + 1 {
                touch(h)
                return true
            }
            guard let strip = find({ (x: Hit) -> Bool in x.type == .button && x.id.hasPrefix(stripPrefix) }) else { return false }
            let toLeft: Bool = i < 4
            let fromX: CGFloat = toLeft ? w.maxX - 40 : w.minX + 40
            let toX: CGFloat = toLeft ? w.minX + 60 : w.maxX - 60
            let o: XCUICoordinate = app.coordinate(withNormalizedOffset: .zero)
            let from: XCUICoordinate = o.withOffset(CGVector(dx: fromX, dy: strip.frame.midY))
            from.press(forDuration: 0.05, thenDragTo: o.withOffset(CGVector(dx: toX, dy: strip.frame.midY)))
            pause(0.5)
        }
        if let h = find({ (x: Hit) -> Bool in x.type == .button && x.id == id }) {
            touch(h)
            return true
        }
        return false
    }

    // Opens the n-th company row of the Home list, whatever the company is called.
    func openCompanyRow(_ n: Int) -> Bool {
        guard goTab("Home"), has("home-companies-box", wait: 6) else { return false }
        let all: [Hit] = hits()
        var box: CGRect = .null
        for h in all where h.id == "home-companies-box" { box = box.union(h.frame) }
        let area: CGRect = box.insetBy(dx: -2, dy: -2)
        var rows: [Hit] = []
        for h in all where h.type == .button && (h.id.isEmpty || h.id == "home-companies-box") {
            if area.contains(CGPoint(x: h.frame.midX, y: h.frame.midY)) { rows.append(h) }
        }
        rows.sort { (a: Hit, b: Hit) -> Bool in a.frame.minY < b.frame.minY }
        guard n < rows.count else { return false }
        touch(rows[n])
        return has("company-tab-overview", wait: 6) || has("back-button")
    }

    func when(_ on: Bool, off: String, _ why: String, _ body: () -> Bool) -> String? {
        guard on else { return off }
        return ok(body(), why)
    }

    func inCompany(_ why: String, _ body: () -> Bool) -> String? {
        when(companyOpen, off: "the company page did not open", why, body)
    }

    func inApp(_ why: String, _ body: () -> Bool) -> String? {
        when(appOpen, off: "its app did not open", why, body)
    }

    func companyTab(_ name: String, _ tab: String) {
        screen(name) {
            inCompany("no company-tab-\(tab) button") {
                if !buttonUp(prefix: "company-tab-", wait: 0) { _ = tapBack() }
                return tapInStrip("company-tab-" + tab, stripPrefix: "company-tab-")
            }
        }
    }

    func openApp(_ title: String) -> String? {
        guard openPhoneApp(title) else {
            if lastOpenWhy == "hidden" { return "no \(title) tile on the Phone grid in this game (hidden or locked by progress)" }
            return "could not open phone-app-\(title) (\(lastOpenWhy))"
        }
        pause(1)
        clearPopups()
        if lastOpenWhy != "pick" && gridUp() { return "the \(title) tile did not open the app (locked in this game)" }
        return nil
    }

    func phoneApp(_ title: String, _ name: String) {
        screen(name) {
            let why: String? = openApp(title)
            appOpen = why == nil
            return why
        }
    }

    func appPart(_ name: String, _ id: String, strip: String) {
        screen(name) { inApp("no \(id) button") { tapInStrip(id, stripPrefix: strip) } }
    }

    func testA_FirstLaunch() {
        letter = "A"
        keepCoach = true
        if !Self.firstRunAllowed {
            stopped = "the first-run walk is off: it needs SCREENS_FIRST_RUN=1, set only where the game server is unreachable, because accepting the terms creates an online account"
        }
        screen("terms") { ok(has("terms-accept", wait: 25), "no terms screen: the terms were already accepted on this simulator") }
        act {
            let field: XCUIElement = app.textFields["terms-name"].firstMatch
            if field.waitForExistence(timeout: 2), ctap(field) {
                pause(0.8)
                field.typeText("Reviewer\n")
                pause(0.6)
            }
        }
        screen("terms-username") { ok(has("terms-accept"), "no terms screen") }
        act { _ = tapEnabled("terms-accept", wait: 2) }
        screen("start") { ok(has("start-new", wait: 15), "the start screen did not show") }
        act {
            if has("start-continue") { stopped = "a saved game is on this simulator and is not replaced, so the new-game walk is left out" }
        }
        screen("setup-1-country") {
            guard tapID("start-new") else { return "no start-new button" }
            return ok(buttonUp(prefix: "country-", wait: 8), "the country step did not open")
        }
        screen("setup-2-trade") {
            guard tapPrefix("country-", wait: 2) else { return "no country row" }
            return ok(buttonUp(prefix: "trade-", wait: 25), "no trade rows loaded")
        }
        screen("setup-3-trade-detail") {
            let picked: Bool = has("trade-cafe") ? tapID("trade-cafe") : tapPrefix("trade-", wait: 2)
            guard picked else { return "no trade row" }
            return ok(has("trade-open", wait: 5), "the trade detail did not open")
        }
        screen("setup-4-name") {
            guard tapID("trade-open") else { return "no trade-open button" }
            return ok(has("setup-next", wait: 5), "the name step did not open")
        }
        act { _ = tapID("keyboard-done", wait: 1) }
        screen("setup-5-options") {
            guard tapEnabled("setup-next") else { return "Next is not enabled on the name step" }
            return ok(has("setup-start", wait: 5), "the options step did not open")
        }
        screen("first-home", settle: 3) {
            guard tapID("setup-start") else { return "no setup-start button" }
            return ok(buttonUp(prefix: "tab-", wait: 30), "the game did not start")
        }
        act { clearPopups(8) }
        screen("home-one-company") { ok(homeVisible(8), "Home did not show") }
        screen("tutorial-company") {
            companyOpen = openCompanyRow(0)
            return ok(companyOpen, "the first company did not open from Home")
        }
        screen("tutorial-first-product") {
            inCompany("no first-product picker on Sales") {
                tapInStrip("company-tab-sales", stripPrefix: "company-tab-") && has("first-item-confirm", wait: 5)
            }
        }
        screen("tutorial-supplier") {
            guard companyOpen else { return "the company page did not open" }
            let row: (Hit) -> Bool = { (h: Hit) -> Bool in h.type == .button && h.id.hasPrefix("first-item-") && h.id != "first-item-confirm" }
            guard tapWhere(wait: 2, row) else { return "no product row to pick" }
            guard seekEnabled("first-item-confirm") else { return "no enabled Start with this product button" }
            return ok(has("item-supplier-keep", wait: 5) || has("item-supplier-done"), "no supplier question for the first product")
        }
        act {
            if !pressButton("item-supplier-keep", wait: 1) { _ = pressButton("item-supplier-done", wait: 1) }
            pause(0.8)
        }
        screen("tutorial-price") { ok(has("item-keep-price", wait: 6) || has("item-price-done"), "the price sheet did not open") }
        act {
            if !pressButton("item-keep-price", wait: 1) { _ = pressButton("item-price-done", wait: 1) }
            pause(0.8)
            clearPopups()
        }
        screen("tutorial-next-day") {
            guard goTab("Home") else { return "no Home tab" }
            return ok(has("next-day", wait: 6), "Next day is not on Home")
        }
        screen("first-day-report", settle: 2.5) {
            guard tapID("next-day") else { return "no next-day button" }
            return ok(popupUp(20), "no report popup after the first day")
        }
        act { clearPopups(8) }
        screen("home-after-first-day") {
            guard goTab("Home") else { return "no Home tab" }
            return ok(homeVisible(6), "Home did not show after the first day")
        }
        screen("tutorial-phone") {
            guard goTab("Phone") else { return "no Phone tab" }
            return ok(gridUp(6), "the Phone grid did not show")
        }
        screen("tutorial-inbox") {
            guard tapID("phone-app-Inbox") else { return "no Inbox tile on the Phone grid" }
            pause(1)
            return ok(!gridUp(), "the Inbox did not open")
        }
        act {
            keepCoach = false
            clearPopups()
            skipCoach()
        }
        screen("fresh-home") {
            guard goTab("Home") else { return "no Home tab" }
            return ok(homeVisible(6), "Home did not show")
        }
        screen("fresh-company-overview") {
            companyOpen = openCompanyRow(0)
            return ok(companyOpen, "the company did not open from Home")
        }
        companyTab("fresh-company-team", "team")
        companyTab("fresh-company-manage", "manage")
        companyTab("fresh-company-sales", "sales")
        companyTab("fresh-company-stats", "stats")
        screen("fresh-tab-ventures") { ok(openTab("Ventures"), "no Ventures tab") }
        act { clearPopups() }
        screen("fresh-tab-group") { ok(goTab("Group"), "no Group tab") }
        screen("fresh-tab-store") { ok(goTab("Store"), "no Store tab") }
        screen("fresh-phone-grid") {
            guard goTab("Phone") else { return "no Phone tab" }
            return ok(gridUp(6), "the Phone grid did not show")
        }
    }

    func testB_HomeAndTabs() {
        letter = "B"
        screen("home-two-companies") {
            guard goTab("Home") else { return "no Home tab" }
            return ok(homeVisible(6), "Home did not show")
        }
        popup("home-goals") { ok(tapID("home-goal", wait: 2), "no home-goal on Home") }
        page("home-new-company") {
            guard goTab("Home"), tapID("home-new-company", wait: 2) else { return "no Start a company button on Home in this game" }
            return ok(has("back-button", wait: 4), "the new company page did not open")
        }
        var ventures = false
        screen("tab-ventures") {
            guard openTab("Ventures") else { return "no Ventures tab" }
            ventures = !popupUp(1.2)
            return nil
        }
        act { clearPopups() }
        for part in ["Portfolio", "Bids", "Done"] {
            screen("ventures-" + part.lowercased()) { when(ventures, off: "Ventures is locked in this game", "no \(part) part") { tapLabel(part, wait: 2) } }
        }
        screen("tab-group") { ok(goTab("Group"), "no Group tab") }
        for part in ["Overview", "People", "Suppliers"] {
            screen("group-" + part.lowercased()) { ok(goGroup(part), "no group-home-tab-\(part)") }
        }
        var entity = false
        screen("group-company") {
            guard goGroup("Overview"), tapPrefix("group-entity-", wait: 4) else { return "no company in the Group structure" }
            entity = has("group-back", wait: 4)
            return ok(entity, "the group company page did not open")
        }
        for part in ["Management", "Boardroom", "Money"] {
            screen("group-company-" + part.lowercased()) {
                when(entity, off: "the group company page did not open", "no group-tab-\(part)") { tapInStrip("group-tab-" + part, stripPrefix: "group-tab-") }
            }
        }
        popup("group-add-menu") {
            guard goGroup("Overview") else { return "no Group overview" }
            return ok(tapID("group-add", wait: 2), "no group-add button")
        }
        screen("tab-store") { ok(goTab("Store"), "no Store tab") }
        screen("tab-phone") {
            guard goTab("Phone") else { return "no Phone tab" }
            return ok(gridUp(6), "the Phone grid did not show")
        }
    }

    func testC_Company() {
        letter = "C"
        screen("company-overview") {
            companyOpen = openCompanyRow(0)
            return ok(companyOpen, "no company row on Home")
        }
        lower("company-overview-lower", on: companyOpen, why: "the company page did not open")
        companyTab("company-team", "team")
        lower("company-team-lower", on: companyOpen, why: "the company page did not open")
        page("company-hire") { inCompany("no team-hire-workers button") { seekID("team-hire-workers") && has("back-button", wait: 4) } }
        popup("company-perks") { inCompany("no team-perks row") { seekID("team-perks") } }
        page("company-worker") { inCompany("no worker row in the roster") { seekPrefix("team-worker-") } }
        companyTab("company-manage", "manage")
        lower("company-manage-lower", on: companyOpen, why: "the company page did not open")
        popup("company-upkeep") { inCompany("no manage-upkeep row") { seekID("manage-upkeep") } }
        page("company-suppliers") { inCompany("no manage-suppliers row") { seekID("manage-suppliers") && has("back-button", wait: 4) } }
        page("company-equipment") { inCompany("no manage-equipment row for this trade") { seekID("manage-equipment") && has("back-button", wait: 4) } }
        page("company-licences") { inCompany("no manage-licences row for this trade") { seekID("manage-licences") && has("back-button", wait: 4) } }
        companyTab("company-sales", "sales")
        lower("company-sales-lower", on: companyOpen, why: "the company page did not open")
        popup("company-sales-item") { inCompany("no sales-item row") { seekPrefix("sales-item-") } }
        popup("company-marketing") { inCompany("no Marketing row") { seekLabelPrefix("Marketing") } }
        companyTab("company-stats", "stats")
        lower("company-stats-lower", on: companyOpen, why: "the company page did not open")
        screen("company-stats-customers") { inCompany("no stats-part-customers segment") { seekID("stats-part-customers") } }
        var look = false
        screen("company-customise-card") {
            guard companyOpen else { return "the company page did not open" }
            look = tapID("company-customise") && has("company-look-card", wait: 4)
            return ok(look, "no company-customise button, or its page did not open")
        }
        for part in ["backdrop", "colours", "badge", "logo", "plate"] {
            screen("company-customise-" + part) {
                when(look, off: "the company customise page did not open", "no company-look-\(part) segment") { tapInStrip("company-look-" + part, stripPrefix: "company-look-") }
            }
        }
        screen("second-company-overview") {
            companyOpen = openCompanyRow(1)
            return ok(companyOpen, "no second company row on Home")
        }
        companyTab("second-company-manage", "manage")
        companyTab("second-company-sales", "sales")
    }
}
