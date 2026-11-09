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
                return isSelected("company-tab-overview") ? .pass(signature().text) : .fail("Overview is not the selected section on open")
            }
            for sec in sections {
                step("company \(label): section \(sec) switches in place") {
                    guard opened else { return .skip("company not opened") }
                    guard tapID("company-tab-\(sec)") else { return .fail("no company-tab-\(sec) button") }
                    return isSelected("company-tab-\(sec)") ? .pass() : .fail("tapped but the section is not selected")
                }
                step("company \(label): section \(sec) health") { opened ? health("company \(label) \(sec)") : .skip("company not opened") }
            }
            for p in ["finances", "customers"] {
                step("company \(label): Stats part \(p)") {
                    guard opened else { return .skip("company not opened") }
                    _ = tapID("company-tab-overview")
                    guard tapID("stats-part-\(p)") else { return .skip("no \(p) part for this company") }
                    return health("company \(label) stats \(p)")
                }
            }
            step("company \(label): one Back returns to Home from any section") {
                guard opened else { return .skip("company not opened") }
                _ = tapID("company-tab-prices")
                guard tapBack() else { return .fail("no Back button") }
                return homeVisible(4) ? .pass() : .fail("Back did not land on Home: \(signature().text)")
            }
        }
    }

    // MARK: T11 Team: hire flow and staff

    private func openHiring() -> Bool {
        guard openCompany("Caf"), tapID("company-tab-people") else { return false }
        return tapID("team-hire-workers", wait: 4) && has("back-button", wait: 3)
    }

    /// Picks the first role chip under "Which role" (Post the ad waits for a role).
    private func pickFirstRole() -> Bool {
        guard let head = find(wait: 3, { $0.label.localizedCaseInsensitiveCompare("Which role") == .orderedSame }) else { return false }
        return tapWhere(wait: 1) { $0.type == .button && $0.frame.minY > head.frame.maxY && $0.frame.minY < head.frame.maxY + 160 && !$0.label.isEmpty }
    }

    /// Plays days from Home (closing each report) until `until` holds or `days` are played.
    func advanceDays(_ days: Int, until: () -> Bool = { false }) -> Int {
        var played = 0
        while played < days {
            guard goTab("Home"), tapID("next-day", wait: 3) else { break }
            played += 1
            var n = 0
            while n < 8 && popupUp(n == 0 ? 6 : 2) { closePopup(prefer: ["report-continue", "celebration-claim", "celebration-dismiss", "alert-continue"]); n += 1 }
            if until() { break }
        }
        return played
    }

    func testT11_TeamHiring() {
        step("team: hiring screen opens and Back returns to Team") {
            guard openHiring() else { return .skip("no company / Team section / Hire button") }
            let h: R = health("hire workers")
            guard tapBack() else { return .fail("no Back on the hiring screen") }
            return isSelected("company-tab-people") ? h : .fail("Back did not return to the Team section: \(signature().text)")
        }
        step("hire: the Post the ad button is in view without scrolling") {
            guard openHiring() else { return .skip("hiring screen not reachable") }
            return primaryInView("hire-post-ad")
        }
        step("hire: 'How to look' Agency segment switches the action to Engage the agency") {
            guard openHiring() else { return .skip("hiring screen not reachable") }
            guard tapID("segment-Agency", wait: 3) || tapLabel("Agency") else { return .skip("no Agency segment") }
            let ok: Bool = has("hire-engage-agency", wait: 2) || has("hire-engage-agency-blocked")
            _ = tapID("segment-Job ad") || tapLabel("Job ad")
            return ok ? .pass() : .fail("no hire-engage-agency after choosing Agency: " + tabState())
        }
        roundTrip("hire: Post the ad -> confirm, Cancel keeps the hiring screen", closeWith: ["confirm-cancel"], prepare: { openHiring() && pickFirstRole() }) { tapEnabled("hire-post-ad") }
        roundTrip("hire: Post the ad -> confirm, Post keeps the hiring screen (its outcome popup is closed)", closeWith: ["confirm-go"], strictText: false, prepare: { openHiring() && pickFirstRole() }) { tapEnabled("hire-post-ad") }
        step("hire: an applicant arrives within a few days of the ad") {
            if openHiring() && has("hire-talk-terms", wait: 2) { return .pass("already waiting") }
            let played: Int = advanceDays(4) { openHiring() && has("hire-talk-terms", wait: 2) }
            return (openHiring() && has("hire-talk-terms", wait: 2)) ? .pass("after \(played) day(s)") : .skip("no applicant after \(played) day(s)")
        }
        step("hire: terms page -> 'Offer the going rate' in view -> Next -> Back -> walk away") {
            guard openHiring(), tapID("hire-talk-terms", wait: 4) else { return .skip("no applicant waiting") }
            guard has("hire-quick-offer", wait: 4) else { return .fail("terms page has no 'Offer the going rate'") }
            var problems: [String] = []
            if case .fail(let m) = primaryInView("hire-quick-offer") { problems.append(m) }
            if case .fail(let m) = health("hire terms page", clip: false) { problems.append(m) }
            guard tapID("hire-next") else { return .fail("terms page has no Next (Change the offer)") }
            guard has("hire-make-offer", wait: 4) || has("hire-make-offer-blocked") else { return .fail("page 2 has no 'Make the offer'") }
            if case .fail(let m) = primaryInView("hire-make-offer") { problems.append("page 2: " + m) }
            guard tapID("hire-back") else { return .fail("page 2 has no Back") }
            guard has("hire-quick-offer", wait: 4) else { return .fail("Back did not return to page 1 (\(signature().text))") }
            _ = tapID("hire-walk-away")
            return problems.isEmpty ? .pass() : .fail(problems.joined(separator: "; "))
        }
        roundTrip("hire: Offer the going rate -> confirm, Cancel keeps the terms page", closeWith: ["confirm-cancel"], prepare: { openHiring() && tapID("hire-talk-terms", wait: 4) }) { tapEnabled("hire-quick-offer") }
        step("hire: Offer the going rate -> confirm -> the result shows and Done returns") {
            guard openHiring(), tapID("hire-talk-terms", wait: 4) else { return .skip("no applicant waiting") }
            guard tapEnabled("hire-quick-offer") else { return .fail("no 'Offer the going rate'") }
            if popupUp(2) { closePopup(prefer: ["confirm-go"]) }
            _ = waitPopupGone(3)
            var n = 0
            while n < 2 && popupUp(1) { closePopup(); n += 1 }
            let raw: [String] = rawProblems("hire result")
            if has("hire-done", wait: 4) {
                _ = tapID("hire-done")
                return raw.isEmpty ? .pass("answer page, then Done -> \(signature().text)") : .fail(raw.joined(separator: "; "))
            }
            return raw.isEmpty ? .pass("no result page: \(signature().text)") : .fail(raw.joined(separator: "; "))
        }
        step("team: a worker profile opens from the roster and Back returns to Team") {
            guard openCompany("Caf"), tapID("company-tab-people") else { return .skip("no company / Team section") }
            // The roster groups people by role ("Barista, 2 people"): open a group, then its first person.
            guard let group = bringIn({ $0.type == .button && ($0.label.contains(" people") || $0.label.contains(" person")) && !$0.label.hasPrefix("Staff") }, wait: 4) else { return .skip("no role group in the roster") }
            touch(group)
            guard tapWhere(wait: 2, { $0.type == .button && $0.frame.minY >= group.frame.maxY - 2 && $0.frame.minY < group.frame.maxY + 90 && !$0.label.contains(" people") }) else { return .fail("the role group did not list anyone") }
            guard has("back-button", wait: 3) else { return .fail("the profile did not open as a page: \(signature().text)") }
            let h: R = health("worker profile")
            guard tapBack() else { return .fail("no Back on the profile") }
            return isSelected("company-tab-people") ? h : .fail("Back did not return to the Team section: \(signature().text)")
        }
        step("team: Managers and executives pushes the entity's Management page on Home, and Back returns to Team") {
            guard openCompany("Caf"), tapID("company-tab-people") else { return .skip("no company / Team section") }
            guard tapID("team-open-management", wait: 4) else { return .skip("no management link") }
            pause(0.8)
            guard isSelected("tab-Home") else { return .fail("the link changed tab: \(tabState())") }
            guard isSelected("group-tab-Management") else { return .fail("the entity's Management page is not showing: \(signature().text)") }
            let h: R = health("team management", title: false)
            guard tapBack() else { return .fail("no Back on the entity page") }
            return isSelected("company-tab-people") ? h : .fail("Back did not return to Team: \(signature().text)")
        }
        roundTrip("team: Perks popup closes and keeps Team", prepare: { openCompany("Caf") && tapID("company-tab-people") }) { tapLabel("Perks") }
        step("team: Goals page opens and Back returns") {
            guard openCompany("Caf"), tapID("company-tab-people") else { return .skip("no company / Team section") }
            guard tapLabel("Goals") else { return .skip("no Goals row") }
            let h: R = health("team goals")
            _ = tapBack()
            return isSelected("company-tab-people") ? h : .fail("Back did not return to Team: \(signature().text)")
        }
        step("team: Applicants page opens and Back returns") {
            guard openCompany("Caf"), tapID("company-tab-people") else { return .skip("no company / Team section") }
            guard tapID("open-applicants", wait: 3) else { return .skip("no Applicants row") }
            let h: R = health("applicants")
            _ = tapBack()
            return isSelected("company-tab-people") ? h : .fail("Back did not return to Team: \(signature().text)")
        }
    }

    // MARK: T12 Manage > Operations > Suppliers (the owner's bug class)

    private func openSuppliers() -> Bool {
        guard openCompany("Caf"), tapID("company-tab-overview") else { return false }
        return tapLabel("Suppliers") && has("back-button", wait: 3)
    }

    func testT12_ManageAndSuppliers() {
        roundTrip("manage: Upkeep sheet closes and keeps Manage", prepare: { openCompany("Caf") && tapID("company-tab-overview") }) { tapText("Upkeep") }
        step("manage: Suppliers page opens, health, Back returns to Manage") {
            guard openSuppliers() else { return .skip("no Suppliers row (the company buys nothing)") }
            let h: R = health("suppliers page")
            guard tapBack() else { return .fail("no Back on Suppliers") }
            return isSelected("company-tab-overview") ? h : .fail("Back did not return to Manage: \(signature().text)")
        }
        roundTrip("suppliers: tap a supplier -> detail popup closes and keeps Suppliers", prepare: { openSuppliers() }) {
            tapID("supplier-option", wait: 4)
        }
        // A switchable provider: the row is not the one 'In use'; the popup has 'Use <name>', which asks first.
        func openSwitchConfirm() -> Bool {
            guard tapWhere(wait: 4, { $0.id == "supplier-option" && $0.type == .button && !$0.label.contains("In use") && $0.enabled }) else { return false }
            guard popupUp(2), tapLabel("Use ", wait: 2) else { if popupUp() { closePopup() }; return false }
            return has("confirm-go", wait: 4)
        }
        roundTrip("suppliers: Use <supplier> -> confirm, Cancel keeps Suppliers", closeWith: ["confirm-cancel"], prepare: { openSuppliers() }) { openSwitchConfirm() }
        roundTrip("suppliers: Use <supplier> -> confirm, Switch keeps Suppliers", closeWith: ["confirm-go"], strictText: false, prepare: { openSuppliers() }) { openSwitchConfirm() }
        step("suppliers: after the switch the new supplier is 'In use'") {
            guard openSuppliers() else { return .skip("Suppliers not reachable") }
            let inUse: Int = hits().filter { $0.id == "supplier-option" && $0.label.contains("In use") }.count
            return inUse >= 1 ? .pass("\(inUse) in use") : .fail("no supplier row says 'In use'")
        }
        step("manage: Premises page opens and Back returns to Manage") {
            guard openCompany("Caf"), tapID("company-tab-overview") else { return .skip("no Manage section") }
            guard tapLabel("Premises", wait: 3) else { return .skip("no Premises row") }
            if popupUp(1) { closePopup(); return waitPopupGone(3) ? .pass("a popup") : .fail("its popup did not close") }
            let h: R = health("premises")
            guard tapBack() else { return .fail("no Back on Premises") }
            return isSelected("company-tab-overview") ? h : .fail("Back did not return to Manage: \(signature().text)")
        }
    }

    // MARK: T13 Sales: item page, price slider, Marketing

    /// The numbers and money on screen, to see that a slider moved the readout.
    private func readout() -> String {
        allTexts().map { $0.text }.filter { (t: String) -> Bool in t.rangeOfCharacter(from: .decimalDigits) != nil }.sorted().joined(separator: "|")
    }

    /// Opens the first item of the Sales list (the rows between the Items heading and Add item).
    private func openFirstItem() -> Bool {
        guard let add = bringIn({ $0.id == "sales-add-item" }, wait: 4) else { return false }
        let head: CGFloat = find({ $0.type == .staticText && ($0.label == "Items" || $0.label == "ITEMS") })?.frame.maxY ?? (add.frame.minY - 400)
        return tapWhere(wait: 1) { $0.type == .button && $0.frame.minY > head && $0.frame.maxY < add.frame.minY && !$0.label.isEmpty } && has("back-button", wait: 3)
    }

    func testT13_SalesItemAndMarketing() {
        var onSales = false
        step("sales: section lists items") {
            guard openCompany("Caf"), tapID("company-tab-prices") else { return .skip("no company / Sales section") }
            onSales = true
            return health("sales list")
        }
        step("sales: item page opens with the price slider in view") {
            guard onSales, openCompany("Caf"), tapID("company-tab-prices") else { return .skip("Sales not reachable") }
            guard openFirstItem() else { return .fail("no item row opens a page: " + tabState()) }
            let r: R = primaryInView("sales-item-price")
            let h: R = health("sales item", clip: true)
            _ = tapBack()
            if case .fail(let m) = r { return .fail(m) }
            return h
        }
        step("sales: dragging the price slider changes the price, Back returns to Sales") {
            guard onSales, openCompany("Caf"), tapID("company-tab-prices") else { return .skip("Sales not reachable") }
            let sales: TourSig = signature()
            guard openFirstItem(), let sl = hit("sales-item-price", wait: 3) else { return .fail("no item page with a price slider") }
            let before: String = readout()
            let o: XCUICoordinate = app.coordinate(withNormalizedOffset: .zero)
            let y: CGFloat = sl.frame.midY
            o.withOffset(CGVector(dx: sl.frame.minX + sl.frame.width * 0.45, dy: y)).press(forDuration: 0.2, thenDragTo: o.withOffset(CGVector(dx: sl.frame.minX + sl.frame.width * 0.7, dy: y)))
            pause(1)
            let moved: Bool = readout() != before
            var problems: [String] = []
            if !moved { problems.append("the price readout did not change when the slider was dragged") }
            if popupUp() { problems.append("the price change raised a popup"); closePopup() }
            // Put the price back so later steps see the same game.
            if let sl2 = hit("sales-item-price") {
                o.withOffset(CGVector(dx: sl2.frame.minX + sl2.frame.width * 0.7, dy: sl2.frame.midY)).press(forDuration: 0.2, thenDragTo: o.withOffset(CGVector(dx: sl2.frame.minX + sl2.frame.width * 0.45, dy: sl2.frame.midY)))
                pause(0.8)
            }
            if !tapBack() { problems.append("no Back on the item page") }
            let after: TourSig = signature()
            if !sales.same(after, strictText: false) { problems.append("Back changed the screen: \(sales.text) -> \(after.text)") }
            return problems.isEmpty ? .pass("") : .fail(problems.prefix(3).joined(separator: "; "))
        }
        step("sales: typing a price in the price field sets it") {
            guard onSales, openCompany("Caf"), tapID("company-tab-prices"), openFirstItem() else { return .skip("no item page") }
            guard let f = bringIn({ $0.id == "typed-price" && $0.type == .textField }, wait: 3) else { return .skip("no typed-price field") }
            let before: String = readout()
            touch(f)
            let field: XCUIElement = app.textFields["typed-price"].firstMatch
            guard field.waitForExistence(timeout: 2) else { _ = tapBack(); return .fail("the field is not editable") }
            let old: String = (field.value as? String) ?? ""
            let num: Double = Double(old.filter { "0123456789.".contains($0) }) ?? 0
            guard num > 0 else { _ = tapBack(); return .skip("the field shows no price to start from ('\(old)')") }
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: max(old.count, 8)) + String(format: "%.2f", num * 1.05))
            pause(0.4)
            if !tapID("typed-price-action", wait: 1) { field.typeText("\n") }
            pause(1)
            let changed: Bool = readout() != before
            if let done = find({ $0.type == .button && $0.label == "Done" }) { touch(done) }
            _ = tapBack()
            return changed ? .pass() : .fail("typing 3.5 and return did not change the item page")
        }
        roundTrip("sales: Marketing popup closes and keeps Sales", prepare: { openCompany("Caf") && tapID("company-tab-prices") }) { tapLabel("Marketing") }
        step("marketing: switching a channel on shows its effect, switching it off again") {
            guard openCompany("Caf"), tapID("company-tab-prices"), tapLabel("Marketing", wait: 3), popupUp(2) else { return .skip("Marketing not reachable") }
            guard let sw = bringIn({ $0.type == .button && $0.value == "Off" && $0.enabled }, wait: 2) else { closePopup(); return .skip("no channel that can be switched on") }
            let before: String = readout()
            touch(sw)
            pause(1)
            let on: Bool = find({ $0.type == .button && $0.value == "On" }) != nil
            let changed: Bool = readout() != before
            if let back = find({ $0.type == .button && $0.value == "On" }) { touch(back); pause(0.8) }
            let raw: [String] = rawProblems("marketing")
            closePopup(); _ = waitPopupGone(3)
            if !on { return .fail("the switch did not turn on (blocked without a reason?)") }
            if !changed { return .fail("turning a channel on changed no figure in the popup") }
            return raw.isEmpty ? .pass() : .fail(raw.joined(separator: "; "))
        }
        step("sales: Add item opens and closes back to Sales") {
            guard openCompany("Caf"), tapID("company-tab-prices") else { return .skip("no company / Sales section") }
            let before: TourSig = signature()
            guard tapID("sales-add-item") else { return .skip("no Add item button") }
            if popupUp(2) { let raw = rawProblems("add item"); closePopup(); _ = waitPopupGone(3); return before.same(signature(), strictText: false) ? (raw.isEmpty ? .pass("popup") : .fail(raw.joined(separator: "; "))) : .fail("closing changed the screen: \(signature().text)") }
            let h: R = health("sales add item")
            _ = tapBack()
            return before.same(signature(), strictText: false) ? h : .fail("Back did not return to Sales: \(signature().text)")
        }
    }

    // MARK: T14 Company popups

    func testT14_CompanyPopups() {
        roundTrip("home: 'About' info popup closes and keeps Home", prepare: { goTab("Home") }) { tapLabel("About ") }
        roundTrip("company overview: an 'About' info popup closes and keeps the page", prepare: { openCompany("Caf") }) { tapLabel("About ") }
        roundTrip("company stats: an 'About' info popup closes and keeps the page", prepare: { openCompany("Gym") && tapID("company-tab-overview") }) { tapLabel("About ") }
    }
}
