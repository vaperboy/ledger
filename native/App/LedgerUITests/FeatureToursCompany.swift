import XCTest

/// Feature tours: the company screens (every section of every company), the Team, Manage (Operations > Suppliers) and Sales flows.
extension FeatureToursTests {

    private var sections: [String] { ["overview", "team", "manage", "sales", "stats"] }

    // MARK: T10 every section of every company

    func testT10_CompanySections() {
        for (part, label) in [("Caf", "Cafe"), ("Gym", "Gym")] {
            var opened = false
            step("company \(label): opens on Overview") {
                guard openCompany(part) else { return .skip("no \(label) on Home") }
                opened = true
                return button("company-tab-overview").isSelected ? .pass(signature().text) : .fail("Overview is not the selected section on open")
            }
            for sec in sections {
                step("company \(label): section \(sec) switches in place") {
                    guard opened else { return .skip("company not opened") }
                    guard tapID("company-tab-\(sec)") else { return .fail("no company-tab-\(sec) button") }
                    return button("company-tab-\(sec)").isSelected ? .pass() : .fail("tapped but the section is not selected")
                }
                step("company \(label): section \(sec) health") { opened ? health("company \(label) \(sec)") : .skip("company not opened") }
            }
            for p in ["finances", "customers"] {
                step("company \(label): Stats part \(p)") {
                    guard opened else { return .skip("company not opened") }
                    _ = tapID("company-tab-stats")
                    guard tapID("stats-part-\(p)") else { return .skip("no \(p) part for this company") }
                    return health("company \(label) stats \(p)")
                }
            }
            step("company \(label): one Back returns to Home from any section") {
                guard opened else { return .skip("company not opened") }
                _ = tapID("company-tab-sales")
                guard tapBack() else { return .fail("no Back button") }
                return homeVisible(4) ? .pass() : .fail("Back did not land on Home: \(signature().text)")
            }
        }
    }

    // MARK: T11 Team: hire flow and staff

    func testT11_TeamHiring() {
        step("team: hiring screen opens and Back returns to Team") {
            guard openCompany("Caf"), tapID("company-tab-team") else { return .skip("no company / Team section") }
            guard tapID("team-hire-workers") else { return .skip("no team-hire-workers button") }
            let h: R = health("hire workers")
            guard tapBack() else { return .fail("no Back on the hiring screen") }
            return button("company-tab-team").isSelected ? h : .fail("Back did not return to the Team section: \(signature().text)")
        }
        step("team: hire flow terms -> offer -> Back -> walk away") {
            guard openCompany("Caf"), tapID("company-tab-team"), tapID("team-hire-workers") else { return .skip("hiring screen not reachable") }
            guard tapID("hire-talk-terms", wait: 5) else { return .skip("no applicant waiting (ads answer over days)") }
            guard button("hire-quick-offer").waitForExistence(timeout: 4) else { return .fail("terms page has no 'Offer the going rate'") }
            let terms: R = health("hire terms page")
            guard tapID("hire-next") else { return .fail("terms page has no Next") }
            guard button("hire-make-offer").waitForExistence(timeout: 4) else { return .fail("page 2 has no 'Make the offer'") }
            guard tapID("hire-back") else { return .fail("page 2 has no Back") }
            guard button("hire-quick-offer").waitForExistence(timeout: 4) else { return .fail("Back did not return to page 1 (\(signature().text))") }
            _ = tapID("hire-walk-away")
            return terms
        }
        step("team: staff profile opens and Back returns") {
            guard openCompany("Caf"), tapID("company-tab-team") else { return .skip("no company / Team section") }
            let person: XCUIElement = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'a month' AND label CONTAINS[c] 'company'")).firstMatch
            guard tap(person, wait: 4) else { return .skip("no staff member listed") }
            let h: R = health("staff profile")
            guard tapBack() else { return .fail("no Back on the profile") }
            return button("company-tab-team").isSelected ? h : .fail("Back did not return to the Team section: \(signature().text)")
        }
        step("team: Management opens and Back returns") {
            guard openCompany("Caf"), tapID("company-tab-team") else { return .skip("no company / Team section") }
            guard tapID("team-open-management") else { return .skip("no management link") }
            let h: R = health("team management")
            _ = tapBack()
            return h
        }
    }

    // MARK: T12 Manage > Operations > Suppliers (the owner's bug class)

    private func openSuppliers() -> Bool {
        guard openCompany("Caf"), tapID("company-tab-manage") else { return false }
        return tapText("Suppliers")
    }

    func testT12_ManageAndSuppliers() {
        roundTrip("manage: Upkeep sheet closes and keeps Manage", prepare: { openCompany("Caf") && tapID("company-tab-manage") }) { tapText("Upkeep") }
        step("manage: Suppliers page opens, health, Back returns to Manage") {
            guard openSuppliers() else { return .skip("no Suppliers row (the company buys nothing)") }
            let h: R = health("suppliers page")
            guard tapBack() else { return .fail("no Back on Suppliers") }
            return button("company-tab-manage").isSelected ? h : .fail("Back did not return to Manage: \(signature().text)")
        }
        roundTrip("suppliers: tap a supplier -> detail popup closes and keeps Suppliers", prepare: { openSuppliers() }) {
            tapID("supplier-option", wait: 4)
        }
        // A switchable provider: the row is not the one 'In use'; the popup has 'Use <name>', which asks first.
        func openSwitchConfirm() -> Bool {
            let other: XCUIElement = app.buttons.matching(NSPredicate(format: "identifier == 'supplier-option' AND NOT label CONTAINS[c] 'In use'")).firstMatch
            guard tap(other, wait: 4) else { return false }
            let use: XCUIElement = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Use '")).firstMatch
            guard tap(use, wait: 3) else { return false }
            return button("confirm-go").waitForExistence(timeout: 4)
        }
        roundTrip("suppliers: Use <supplier> -> confirm, Cancel keeps Suppliers", closeWith: ["confirm-cancel"], prepare: { openSuppliers() }) { openSwitchConfirm() }
        roundTrip("suppliers: Use <supplier> -> confirm, Switch keeps Suppliers", closeWith: ["confirm-go"], prepare: { openSuppliers() }) { openSwitchConfirm() }
    }

    // MARK: T13 Sales: item page, price slider, Marketing

    /// The numbers and money on screen, to see that a slider moved the readout.
    private func readout() -> String {
        allTexts().map { $0.text }.filter { (t: String) -> Bool in t.rangeOfCharacter(from: .decimalDigits) != nil }.sorted().joined(separator: "|")
    }

    func testT13_SalesItemAndMarketing() {
        var onSales = false
        step("sales: section lists items") {
            guard openCompany("Caf"), tapID("company-tab-sales") else { return .skip("no company / Sales section") }
            onSales = true
            return health("sales list")
        }
        step("sales: item page opens, the price slider moves the price, closing returns to Sales") {
            guard onSales else { return .skip("Sales not reachable") }
            let sales: TourSig = signature()
            guard tapText("vs market") || tapText("At market") else { return .skip("no item row on the Sales list") }
            guard elem("sales-item-price").waitForExistence(timeout: 4) else { return .fail("the item screen has no price slider (sales-item-price); screen: \(signature().text)") }
            let isPopup: Bool = popupUp()
            var problems: [String] = rawProblems("sales item")
            let before: String = readout()
            let slider: XCUIElement = elem("sales-item-price")
            slider.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).press(forDuration: 0.2, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
            pause(1)
            let moved: Bool = readout() != before
            // Put the price back (same drag the other way) so later steps see the same game.
            slider.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).press(forDuration: 0.2, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)))
            pause(0.8)
            var guardN = 0
            while popupUp() && !isPopup && guardN < 3 { closePopup(); guardN += 1 }   // a confirm raised by the price change is not part of this check
            if isPopup { closePopup(); _ = waitPopupGone(3) } else if !tapBack() { problems.append("no Back on the item page") }
            pause(0.6)
            let after: TourSig = signature()
            if !sales.same(after) { problems.append("closing the item changed the screen: \(sales.text) -> \(after.text)") }
            if !moved { problems.append("the price readout did not change when the slider was dragged") }
            return problems.isEmpty ? .pass(isPopup ? "item shown as a popup" : "item shown as a page") : .fail(problems.prefix(3).joined(separator: "; "))
        }
        roundTrip("sales: Marketing popup closes and keeps Sales", prepare: { openCompany("Caf") && tapID("company-tab-sales") }) { tapText("Marketing") }
        step("sales: Add item opens and Back returns") {
            guard openCompany("Caf"), tapID("company-tab-sales") else { return .skip("no company / Sales section") }
            let before: TourSig = signature()
            guard tapID("sales-add-item") else { return .skip("no Add item button") }
            if popupUp() { closePopup(); return before.same(signature()) ? .pass("popup") : .fail("closing changed the screen") }
            let h: R = health("sales add item")
            _ = tapBack()
            return before.same(signature()) ? h : .fail("Back did not return to Sales: \(signature().text)")
        }
    }

    // MARK: T14 Conversion preview and other company popups

    func testT14_CompanyPopups() {
        roundTrip("company: legal form conversion preview closes and keeps the page", closeWith: ["popup-close", "conversion-keep"], prepare: {
            guard openCompany("Caf"), tapID("company-tab-stats") else { return false }
            return tapText("Legal form and trading")
        }) { tapID("company-convert-review") }
        roundTrip("home: 'About' info popup closes and keeps Home", prepare: { goTab("Home") }) {
            let i: XCUIElement = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'About '")).firstMatch
            return tap(i, wait: 3)
        }
        roundTrip("team: Appoint a manager sheet closes and keeps the screen", prepare: { openCompany("Caf") && tapID("company-tab-team") }) { tapID("decide-appoint-manager") }
    }
}
