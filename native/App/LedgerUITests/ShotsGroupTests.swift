import XCTest

/// Screenshots of every Group screen (the four Group tabs, each entity tab and part, sale routes, Boardroom popups, chain, franchise, holding, Ventures)
/// on the showcase game. Nothing asserts: a control that is not there is noted and the tour moves on.
final class ShotsGroupTests: FeatureTourCase {
    private var count = 0

    private func snap(_ name: String) {
        count += 1
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = String(format: "Group-%02d-%@", count, name)
        a.lifetime = .keepAlways
        add(a)
    }

    /// The screen, then one screen lower when the page scrolls.
    private func snapPage(_ name: String, lower: Int = 1) {
        snap(name)
        for i in 0..<lower {
            dragPage(-560)
            snap("\(name)-lower\(i + 1)")
        }
        for _ in 0..<lower { dragPage(560) }
    }

    private func closeAll() { var n = 0; while popupUp(0.5) && n < 4 { closePopup(); n += 1 } }

    private func entityID() -> String {
        guard goGroup("Structure") else { return "" }
        if let h = find(wait: 4, { $0.id.hasPrefix("group-entity-co") && $0.type == .button && $0.label.range(of: "Caf", options: [.caseInsensitive, .diacriticInsensitive]) != nil }) { return h.id }
        return ids(prefix: "group-entity-", wait: 1).first ?? ""
    }

    private func groupTab(_ name: String) -> Bool {
        let id: String = "group-tab-\(name)"
        for i in 0..<5 {
            if let h = find(wait: i == 0 ? 2 : 0.5, { $0.id == id && $0.type == .button }), h.frame.minX >= win().minX - 1, h.frame.maxX <= win().maxX + 1 {
                touch(h); return true
            }
            guard let strip = find({ $0.id.hasPrefix("group-tab-") && $0.type == .button }) else { return false }
            let o: XCUICoordinate = app.coordinate(withNormalizedOffset: .zero)
            let w: CGRect = win()
            let toLeft: Bool = i < 3
            o.withOffset(CGVector(dx: toLeft ? w.maxX - 40 : w.minX + 40, dy: strip.frame.midY))
                .press(forDuration: 0.05, thenDragTo: o.withOffset(CGVector(dx: toLeft ? w.minX + 60 : w.maxX - 60, dy: strip.frame.midY)))
            pause(0.5)
        }
        if let h = find({ $0.id == id && $0.type == .button }) { touch(h); return true }
        return false
    }

    private func openTab(_ entity: String, _ name: String) -> Bool {
        closeAll()
        guard !entity.isEmpty, goGroup("Structure"), tapID(entity, wait: 4) else { return false }
        return groupTab(name)
    }

    private func popupShot(_ name: String) {
        if popupUp(3) { pause(0.6); snap(name); closeAll() } else { snap(name + "-nopopup") }
    }

    func testShots() {
        // The four Group tabs
        guard goTab("Group") else { snap("no-group-tab"); return }
        pause(1)
        snapPage("overview", lower: 2)
        if tapID("group-add") { popupShot("add-menu") }
        for home in ["Structure", "People", "Suppliers"] {
            if goGroup(home) { pause(0.8); snapPage("home-\(home)", lower: 2) } else { snap("home-\(home)-missing") }
        }
        if goGroup("People"), tapPrefix("group-who-", wait: 3) { popupShot("staff-manager") }
        if goGroup("Overview"), tapID("group-who-runs-what", wait: 3) { pause(0.6); snap("overview-to-staff") }
        let entity: String = entityID()
        if entity.isEmpty { snap("no-entity"); return }

        // Entity page, every tab
        for name in ["Overview", "Management", "Boardroom", "Money", "Grow"] {
            if openTab(entity, name) { pause(0.8); snapPage("entity-\(name)", lower: 2) } else { snap("entity-\(name)-missing") }
        }
        for part in ["Owners", "Sell", "Raise", "Offers"] {
            if openTab(entity, "Owners and sales"), tapID("group-ownership-\(part)") { pause(0.8); snapPage("ownership-\(part)", lower: 2) } else { snap("ownership-\(part)-missing") }
        }

        // Sale routes
        for route in ["auction", "stake", "private", "merger"] {
            if openTab(entity, "Owners and sales"), tapID("group-ownership-Sell"), tapID("sell-route-\(route)", wait: 2) {
                pause(0.8)
                if popupUp(2) { snap("sell-\(route)"); closeAll() } else { snap("sell-\(route)-page"); _ = tapBack() }
            }
        }

        // Money policy, the Boardroom page and its quarterly review
        if openTab(entity, "Money"), tapID("money-policy") { popupShot("money-policy") }
        if openTab(entity, "Boardroom") { pause(0.6); snapPage("board-room", lower: 2) }
        if openTab(entity, "Boardroom"), tapPrefix("boardroom-review-", wait: 4) {
            if popupUp(3) {
                snap("boardroom-review")
                if tapID("boardroom-choice-dir:lean", wait: 2), tapID("boardroom-review-settle", wait: 2) { pause(0.8); snap("boardroom-review-result") }
                closeAll()
            }
        }

        // Chain page (when the company is in a chain)
        if openTab(entity, "Grow"), tapText("Open the chain", wait: 2) { pause(0.8); snapPage("chain", lower: 2); _ = tapBack() }

        // Suppliers directory, Join a franchise
        closeAll()
        if goGroup("Suppliers"), tapPrefix("group-supplier-", wait: 3) { popupShot("supplier-profile") }
        if goTab("Group"), tapID("group-add"), tapID("group-add-franchise", wait: 2) { pause(1); snapPage("franchises", lower: 1); _ = tapBack() }

        // Ventures
        closeAll()
        if goTab("Ventures") || openPhoneApp("Ventures") {
            pause(1)
            snapPage("ventures", lower: 1)
            for part in ["Projects", "Portfolio", "Bids", "Done"] where tapLabel(part, wait: 2) { pause(0.6); snap("ventures-\(part)") }
        } else { snap("ventures-missing") }

        // A holding: create one over both companies, then its landing, entity page and treasury
        closeAll()
        if goTab("Group"), tapID("group-add"), tapID("group-add-holding", wait: 2) {
            pause(1)
            snap("holding-new")
            let field: XCUIElement = app.textFields.firstMatch
            if field.waitForExistence(timeout: 2) { field.tap(); field.typeText("Alex Holdings\n") }
            for h in hits() where h.type == .button && h.value == "Not selected" { touch(h) }
            if tapText("Create the holding", wait: 3) { pause(1.5); closeAll(); snapPage("holding-company-page", lower: 1) }
        }
        if goGroup("Structure") {
            pause(1)
            snapPage("companies-with-holding", lower: 1)
            if let h = find(wait: 3, { $0.id.hasPrefix("group-entity-") && $0.type == .button && $0.label.contains("Holding") }) {
                touch(h); pause(0.8); snapPage("holding-entity", lower: 1)
                if groupTab("Money") { pause(0.6); snapPage("holding-money", lower: 1) }
            }
        }
    }
}
