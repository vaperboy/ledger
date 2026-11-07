import XCTest

/// Screenshots of every company screen (CI job native-tours on a ui-tours-* branch): a café with months of history, then a clothing
/// boutique, a vehicle dealership and a used car dealer started through the real New company flow and played until they open.
/// Each screen is attached as "Company-<company>-<screen>". Nothing asserts: a screen that cannot be reached is shot as it is and the run goes on.
final class ShotsCompanyTests: FeatureTourCase {

    override func setUp() {
        continueAfterFailure = true
        testDeadline = Date().addingTimeInterval(80 * 60)
        winCache = .zero
        app = XCUIApplication()
        // Pro in a debug build: the dealerships cost more than the free start-up line.
        app.launchArguments = ["-showcase", "-showcase-rich", "-ledger.debugEntitlements", "pro"]
        app.launch()
        let end: Date = Date().addingTimeInterval(40)
        while Date() < end {
            let later: XCUIElement = app.buttons["ambition-later"].firstMatch
            if later.exists { ctap(later); pause(1) }
            var n = 0
            while n < 10 && popupUp(1) { closePopup(); n += 1 }
            _ = goTab("Home")
            if !popupUp() && homeVisible(3) { break }
        }
    }

    // MARK: Helpers

    private var shotCount = 0

    func shot(_ name: String) {
        pause(0.9)
        shotCount += 1
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = String(format: "Company-%03d-", shotCount) + name
        a.lifetime = .keepAlways
        add(a)
        log.record(.pass, "shot " + name, "")
    }

    /// What the screen shows, to stop scrolling once the page no longer moves.
    private func pageKey() -> String {
        hits().filter { $0.type == .staticText && !$0.label.isEmpty }.prefix(40).map { "\($0.label.prefix(20))@\(Int($0.frame.minY))" }.joined(separator: "|")
    }

    /// The screen, then each further screenful down to the end (at most `pages`), then back to the top.
    func shotScrolled(_ name: String, pages: Int = 4) {
        shot(name)
        var last: String = pageKey()
        var moved = 0
        for i in 0..<pages {
            dragPage(-560)
            let now: String = pageKey()
            if now == last { break }
            last = now
            moved += 1
            shot(name + "-\(i + 2)")
        }
        for _ in 0..<(moved + 1) { dragPage(700) }
    }

    /// A popup: shot, one screenful further down inside it, then closed.
    func shotPopup(_ name: String) {
        guard popupUp(2) || app.buttons["popup-close"].exists else { shot(name + "-nopopup"); return }
        shot(name)
        dragPage(-420)
        shot(name + "-2")
        var n = 0
        while n < 3 && (popupUp(1) || app.buttons["popup-close"].exists) { closePopup(); n += 1 }
    }

    /// Back to the company screen after a pushed page or a popup (a popup hides the screen under it, so the section bar is not found).
    func backToCompany() {
        for _ in 0..<5 {
            if has("company-tab-overview", wait: 1) { return }
            if popupUp(0.5) || app.buttons["popup-close"].exists || app.buttons["Close"].exists { closePopup(); continue }
            if !tapBack() { closePopup() }
        }
    }

    /// Opens a company from Home by a word of its row; true on its company screen (a company still being set up shows Setup).
    @discardableResult
    func openCo(_ words: [String]) -> Bool {
        guard goTab("Home") else { return false }
        _ = find(wait: 4) { $0.id == "home-companies-box" }
        for w in words {
            let pred: (Hit) -> Bool = { ($0.type == .button || $0.type == .cell) && $0.label.range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) != nil && !$0.id.hasPrefix("home-") && !$0.id.hasPrefix("tab-") }
            if tapWhere(wait: 2, pred) {
                pause(1)
                if has("company-tab-overview", wait: 3) || has("back-button", wait: 1) { return true }
            }
        }
        log.note("no company row for \(words)")
        return false
    }

    func onSection(_ id: String) -> Bool {
        if !has("company-tab-overview", wait: 1) { backToCompany() }
        return tapID("company-tab-\(id)", wait: 3)
    }

    /// Opens a row of the current section by the start of its label (or the text it contains), shots the page or popup, and comes back.
    func visit(_ tag: String, _ section: String, _ labels: [String], scroll: Bool = true, then: (() -> Void)? = nil) {
        for l in labels {
            guard onSection(section) else { return }
            guard tapLabel(l, wait: 2) || tapText(l, wait: 1) else { continue }
            pause(0.8)
            let name: String = "\(tag)-\(section)-" + l.lowercased().replacingOccurrences(of: " ", with: "_")
            if popupUp(1.5) || app.buttons["popup-close"].exists { shotPopup(name) } else if scroll { shotScrolled(name) } else { shot(name) }
            then?()
            backToCompany()
        }
    }

    /// The first row between the Items heading and Add item (lists without row ids).
    func firstListedItem() -> Bool {
        guard let add = bringIn({ $0.id == "sales-add-item" }, wait: 2) else { return false }
        let head: CGFloat = find({ $0.type == .staticText && ($0.label.uppercased().hasPrefix("YOUR ") || $0.label.uppercased() == "ITEMS") })?.frame.maxY ?? (add.frame.minY - 300)
        return tapWhere(wait: 1) { $0.type == .button && $0.frame.minY > head && $0.frame.maxY < add.frame.minY && !$0.label.isEmpty }
    }

    /// Every section and page of one company.
    func tourCompany(_ tag: String, _ words: [String], dealer: Bool = false) {
        guard openCo(words) else { shot("\(tag)-not-found"); return }
        if !has("company-tab-overview", wait: 2) { shotScrolled("\(tag)-setup"); return }
        shotScrolled("\(tag)-overview")
        if onSection("team") { shot("\(tag)-team") }
        if onSection("manage") { shotScrolled("\(tag)-manage") }
        visit(tag, "manage", ["Upkeep", "Licences", "Suppliers", "Equipment", "Properties", "Plant", "Fish"]) {
            // Suppliers: one supplier's popup.
            if self.tapID("supplier-option", wait: 1) { self.shotPopup("\(tag)-supplier-detail") }
        }
        if onSection("sales") { shotScrolled("\(tag)-sales", pages: 5) }
        // The first item of the list opens the item page.
        if onSection("sales") {
            if tapWhere(wait: 2, { $0.id.hasPrefix("sales-item-") && $0.type == .button }) || tapWhere(wait: 1, { $0.id.hasPrefix("dealer-") && $0.type == .button }) || firstListedItem() {
                pause(1)
                if popupUp(1) { shotPopup("\(tag)-item") } else { shotScrolled("\(tag)-item-page", pages: 5) }
                backToCompany()
            }
        }
        if onSection("sales") && tapID("sales-add-item", wait: 2) { pause(1.5); if popupUp(2) || app.buttons["popup-close"].exists { shotPopup("\(tag)-new-item") } else { shot("\(tag)-new-item") }; backToCompany() }
        visit(tag, "sales", ["Marketing", "Develop", "New ", "Research", "Warranty", "Order cars", "Brand contract"])
        if dealer {
            visit(tag, "sales", ["Cars", "Stock", "Order", "Buy"])
        }
        if onSection("stats") { shotScrolled("\(tag)-stats", pages: 5) }
        visit(tag, "stats", ["Settings", "Legal form"])
        if onSection("stats") && tapID("stats-part-customers", wait: 2) { shotScrolled("\(tag)-customers") }
        _ = tapBack()
    }

    /// New company: picks the trade by its name, continues, reviews and pays. Shots each step and the setup screen it lands on.
    func startCompany(_ tag: String, _ trade: String) {
        guard goTab("Home"), tapLabel("New company", wait: 4) || tapText("New company", wait: 2) else { shot("\(tag)-no-new-company"); return }
        pause(1)
        let pred: (Hit) -> Bool = { [.button, .cell, .other, .staticText].contains($0.type) && $0.label.localizedCaseInsensitiveContains(trade) }
        guard tapWhere(wait: 4, pred) else { shot("\(tag)-trade-missing"); toRoot(); return }
        pause(0.8)
        if popupUp(1) { shotPopup("\(tag)-trade-popup") }
        guard tapWhere(wait: 3, { $0.type == .button && $0.id.hasPrefix("Continue") && $0.enabled }) else { shot("\(tag)-no-continue"); toRoot(); return }
        pause(1)
        guard tapEnabled("new-company-start", wait: 4) else { shot("\(tag)-step2-blocked"); toRoot(); return }
        pause(1)
        guard tapEnabled("new-company-pay", wait: 4) else { shot("\(tag)-review-blocked"); toRoot(); return }
        pause(2)
        if popupUp(1) { closePopup(prefer: ["confirm-go"]) }
        pause(1.5)
        shotScrolled("\(tag)-setup-screen")
        toRoot()
    }

    /// Plays `days` days from Home, closing the reports.
    func playDays(_ days: Int) {
        for _ in 0..<days {
            guard goTab("Home"), tapID("next-day", wait: 3) else { return }
            var n = 0
            while n < 8 && popupUp(n == 0 ? 4 : 1.5) { closePopup(prefer: ["report-continue", "celebration-claim", "celebration-dismiss", "alert-continue"]); n += 1 }
        }
    }

    // MARK: The run

    func testShots() {
        tourCompany("cafe", ["Caf", "Café", "Coffee"])
        startCompany("boutique", "Clothing boutique")
        startCompany("dealer", "Vehicle dealership")
        startCompany("usedcar", "Used car dealer")
        // Documents and fit-out take a few weeks; the dealers and the shop open by themselves once ready.
        for round in 0..<5 {
            playDays(7)
            if openCo(["boutique"]) && has("company-tab-overview", wait: 2) && round >= 2 { break }
        }
        tourCompany("boutique", ["boutique"])
        tourCompany("dealer", ["dealership"], dealer: true)
        tourCompany("usedcar", ["Used car"], dealer: true)
    }
}
