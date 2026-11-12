import XCTest

final class FeatureToursTests: FeatureTourCase {

    func testT01_TabsAndHome() {
        let tabs: [String] = tabIDs()
        step("tabs: the pill bar shows five tabs") {
            if tabs.count == 5 { return .pass(tabs.joined(separator: ",")) }
            return tabs.isEmpty ? .fail("no tab-* buttons on screen") : .fail("found \(tabs.count): \(tabs.joined(separator: ","))")
        }
        for id in tabs {
            let title: String = String(id.dropFirst(4))
            step("tab \(title): opens and is selected") {
                guard goTab(title) else { return .fail("the tab button is not there") }
                return isSelected(id) ? .pass() : .fail("tapped but the tab is not marked selected: " + tabState())
            }
            step("tab \(title): health") { health("tab \(title)", title: false) }
        }
        _ = goTab("Home")
        step("home: Next day is in view without scrolling") { primaryInView("next-day") }
        step("home: the companies list shows at most 6 rows or a 'Show all'") {
            guard goTab("Home"), find(wait: 4, { $0.id == "home-companies-box" }) != nil else { return .fail("no home-companies-box") }
            let rows: Int = hits().filter { $0.type == .button && $0.label.contains("\u{00B7}") && !$0.id.hasPrefix("home-") }.count
            if has("show-all-companies") { return .pass("\(rows) rows + Show all") }
            return rows <= 6 ? .pass("\(rows) rows") : .fail("\(rows) company rows and no Show all")
        }
        let shortcuts: [String] = ids(prefix: "home-")
        step("home: shortcuts are on screen") { shortcuts.isEmpty ? .fail("no home-* buttons") : .pass("\(shortcuts.count): \(shortcuts.joined(separator: ","))") }
        for id in shortcuts {
            step("home shortcut \(id): opens something and Back returns") {
                guard goTab("Home") else { return .fail("cannot get to Home") }
                let f: CGRect = hit(id)?.frame ?? .zero
                noteBefore = true
                let tapped: Bool = tapID(id)
                noteBefore = false
                let before: TourSig = lastBefore ?? signature()
                guard tapped else { return .skip("not tappable (off screen)") }
                if popupUp(1) { closePopup(); return waitPopupGone(3) ? .pass("opened a popup that closed") : .fail("its popup did not close") }
                pause(0.6)
                let after: TourSig = signature()
                if before.same(after) { return .fail("nothing changed after tapping it (frame \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)))") }
                let backed: Bool = tapBack()
                _ = goTab("Home")
                if !homeVisible(4) { return .fail("did not get back to Home from \(after.text)") }
                return .pass("-> \(after.text)" + (backed ? "" : " (no Back button: left by the tab bar)"))
            }
        }
        roundTrip("home: the goal strip opens Goals and Back returns to Home", prepare: { goTab("Home") }) { tapID("home-goal") }
        step("home: a Needs you row opens its object and Back/close returns to Home") {
            guard goTab("Home") else { return .fail("no Home") }
            guard tapWhere(wait: 2, { $0.id == "suggestion-row" || $0.id == "suggestion-open-company" }) else { return .skip("nothing in Needs you") }
            if popupUp(2) {
                let raw: [String] = rawProblems("needs you popup")
                closePopup(); _ = waitPopupGone(3)
                return raw.isEmpty ? .pass("popup") : .fail(raw.joined(separator: "; "))
            }
            let s: String = signature().text
            _ = tapBack()
            _ = goTab("Home")
            return homeVisible(4) ? .pass("page " + s) : .fail("could not get back to Home")
        }
        step("home: 'Inbox' link in Needs you opens the Inbox") {
            guard goTab("Home") else { return .fail("no Home") }
            guard tapID("home-open-inbox", wait: 2) else { return .skip("no decision waiting, so no Inbox link") }
            let ok: Bool = find(wait: 4, { $0.id == "inbox-row" || $0.label == "Inbox" }) != nil
            _ = tapBack()
            return ok ? .pass() : .fail("the Inbox did not open: \(signature().text)")
        }
    }

    private func tourApp(_ title: String) {
        var opened = false
        step("phone app \(title): opens") {
            guard openPhoneApp(title) else {
                return lastOpenWhy == "hidden" ? .skip("no tile on the Phone grid: locked by the unlock ladder in this game") : .fail("cannot open phone-app-\(title): \(lastOpenWhy)")
            }
            let gated: Bool = popupUp(1)
            if gated { closePopup(prefer: ["paywall-pass", "popup-close"]); _ = waitPopupGone(3) }
            let sig: TourSig = signature()
            if lastOpenWhy != "pick" && gridUp() {
                return gated ? .skip("the tile opens a popup (paywall or gate) instead of the app") : .fail("the app grid is still on screen after tapping the tile")
            }
            opened = true
            return .pass((lastOpenWhy == "pick" ? "via the Pick tab (not on the Phone grid in this game) " : "") + sig.text)
        }
        step("phone app \(title): health") { opened ? health("app \(title)") : .skip("not opened") }
        step("phone app \(title): Back returns to the grid") {
            guard opened else { return .skip("not opened") }
            if lastOpenWhy == "pick" {
                guard let t = find({ $0.id == "tab-\(title)" && $0.type == .button }) else { return .fail("the Pick tab does not carry the app's name") }
                touch(t)
                return find(wait: 2, { $0.id == "tab-\(title)" && $0.selected }) != nil ? .pass("Pick tab root") : .fail("re-selecting the Pick tab left the app")
            }
            guard tapBack() else { return .fail("no Back button on the app") }
            return gridUp(4) ? .pass() : .fail("Back did not show the app grid")
        }
    }

    func testT02_PhoneAppsA() {
        for t in ["Bank", "Inbox", "News", "Stats", "Luxury", "Rankings", "World"] { tourApp(t) }
    }

    func testT03_PhoneAppsB() {
        for t in ["Market", "Competition", "Goals", "Settings", "AirStay", "TechPro", "Insurance", "Marketplace", "Store"] { tourApp(t) }
    }

    private func groupEntity() -> String {
        guard goGroup("Overview") else { return "" }
        if let h = find(wait: 4, { $0.id.hasPrefix("group-entity-co") && $0.type == .button && $0.label.range(of: "Caf", options: [.caseInsensitive, .diacriticInsensitive]) != nil }) { return h.id }
        return ids(prefix: "group-entity-co", wait: 1).first ?? ids(prefix: "group-entity-", wait: 1).first ?? ""
    }

    private func tapGroupTab(_ name: String) -> Bool {
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

    private func openEntityTab(_ entity: String, _ name: String) -> Bool {
        guard !entity.isEmpty, goGroup("Overview") else { return false }
        guard tapID(entity, wait: 4) else { return false }
        return tapGroupTab(name)
    }

    func testT04_Group() {
        step("group tab: opens on Overview") { goTab("Group") ? (isSelected("group-home-tab-Overview") ? .pass(signature().text) : .fail("Overview not selected: " + tabState())) : .fail("no Group tab") }
        step("group tab: health") { health("Group", title: false) }
        for home in ["Overview", "People", "Suppliers"] {
            step("group tab: \(home) opens and is clean") {
                guard goGroup(home) else { return .fail("no \(home) tab") }
                if home == "Overview" && ids(prefix: "group-entity-").isEmpty { return .fail("no group-entity-* rows: " + tabState()) }
                return health("Group \(home)", title: false)
            }
        }
        let entity: String = groupEntity()
        step("group entity page: opens, Back returns to the picker") {
            guard !entity.isEmpty, tapID(entity, wait: 3) else { return .skip("no entity in the Group picker") }
            guard has("group-back", wait: 3) else { return .fail("the entity page has no group-back") }
            let h: R = health("group entity overview", title: false)
            guard tapBack() else { return .fail("Back not tappable") }
            if !has("group-back") && find(wait: 3, { $0.id.hasPrefix("group-entity-") }) != nil { return h }
            return .fail("Back did not return to the picker: \(signature().text)")
        }
        for name in ["Overview", "Management", "Boardroom", "Money"] {
            step("group entity page: \(name) tab opens, is selected and is clean") {
                guard openEntityTab(entity, name) else { return .skip("no \(name) tab on the entity page") }
                if !isSelected("group-tab-\(name)") { return .fail("tapped but not selected") }
                return health("group \(name)", title: false)
            }
        }
        step("group entity page: tab strip titles are not cut at the side") {
            guard openEntityTab(entity, "Overview") else { return .skip("no entity page") }
            let cut: [String] = hits().filter { $0.id.hasPrefix("group-tab-") && $0.type == .button && !$0.hScroll && ($0.frame.minX < win().minX - 1 || $0.frame.maxX > win().maxX + 1) }.map { $0.id }
            return cut.isEmpty ? .pass() : .fail("cut: " + cut.joined(separator: ","))
        }
        roundTrip("group money: Policy popup closes and keeps the page", prepare: { openEntityTab(entity, "Money") }) { tapID("money-policy") }
        roundTrip("group: Add menu opens and closes back to Overview", prepare: { goGroup("Overview") }) { tapID("group-add") }
        roundTrip("boardroom: the quarterly review opens and closes back to the Boardroom", prepare: { openEntityTab(entity, "Boardroom") }) { tapPrefix("boardroom-review-", wait: 4) }
        step("boardroom: the review settles a direction and a budget and ends with a result") {
            guard openEntityTab(entity, "Boardroom"), tapPrefix("boardroom-review-", wait: 4) else { return .skip("nobody to review with") }
            guard popupUp(3) else { return .fail("the review did not open") }
            tapID("boardroom-choice-dir:lean", wait: 2)
            tapID("boardroom-choice-bud:2", wait: 2)
            let settled: Bool = tapID("boardroom-review-settle", wait: 2)
            let raw: [String] = rawProblems("boardroom review")
            var n = 0
            while popupUp() && n < 3 { closePopup(); n += 1 }
            if popupUp(1) { return .fail("the review popup did not close") }
            if !isSelected("group-tab-Boardroom") { return .fail("after the review the Boardroom is not showing: \(signature().text)") }
            return raw.isEmpty ? .pass(settled ? "settled" : "nothing to change") : .fail(raw.joined(separator: "; "))
        }
    }

    func testT07_Ownership() {
        let entity: String = groupEntity()
        for part in ["Owners", "Sell", "Raise", "Offers"] {
            step("ownership: \(part) page opens and is clean") {
                guard openEntityTab(entity, "Money"), tapID("group-ownership-\(part)") else { return .skip("no Ownership > \(part) segment") }
                return health("ownership \(part)", title: false)
            }
        }
        step("ownership: Sell lists the route picker") {
            guard openEntityTab(entity, "Money"), tapID("group-ownership-Sell") else { return .skip("no Ownership > Sell segment") }
            let routes: [String] = ids(prefix: "sell-route-")
            if routes.isEmpty { return .fail("Sell shows no sell-route-* rows (a limited company with a route is expected): " + tabState()) }
            return .pass("\(routes.count) routes: " + routes.map { String($0.dropFirst(11)) }.joined(separator: ","))
        }
        for route in ["auction", "merger", "stake", "private"] {
            step("ownership: sell route \(route) opens and Cancel/close keeps Sell") {
                guard openEntityTab(entity, "Money"), tapID("group-ownership-Sell") else { return .skip("no Sell segment") }
                let before: TourSig = signature()
                guard tapID("sell-route-\(route)", wait: 2) else { return .skip("no sell-route-\(route)") }
                if popupUp(2) {
                    let raw: [String] = rawProblems("sell \(route)")
                    closePopup(prefer: ["confirm-cancel", "popup-close"])
                    guard waitPopupGone(3) else { return .fail("the \(route) popup did not close") }
                    let after: TourSig = signature()
                    if !before.same(after, strictText: false) { return .fail("closing changed the screen: \(before.text) -> \(after.text)") }
                    return raw.isEmpty ? .pass("popup") : .fail(raw.joined(separator: "; "))
                }
                let after: TourSig = signature()
                if after.back && !before.back { let h: R = health("sell \(route) page"); _ = tapBack(); return h }
                return before.same(after) ? .fail("the route did nothing") : .pass("changed in place: \(after.text)")
            }
        }
    }

    func testT06_Ventures() {
        step("ventures tab: opens") { goTab("Ventures") ? .pass(signature().text) : .fail("no Ventures tab") }
        for part in ["Projects", "Portfolio", "Bids", "Done"] {
            step("ventures: \(part) part opens and is clean") {
                guard goTab("Ventures") else { return .fail("no Ventures tab") }
                guard tapLabel(part, wait: 3) else { return .fail("no '\(part)' tab") }
                return health("ventures \(part)", title: false)
            }
        }
        step("ventures: Projects shows the Start a venture section") {
            guard goTab("Ventures"), tapLabel("Projects", wait: 3) else { return .fail("no Projects tab") }
            return has("ventures-start", wait: 3) ? .pass() : .fail("no Start a venture section: \(signature().text)")
        }
    }

    func testT05_SwipeBack() {
        step("swipe back: company page returns to Home") {
            guard openCompany("Caf") else { return .skip("no company on Home") }
            swipeBackFromEdge()
            return homeVisible(4) ? .pass() : .fail("an edge swipe did not return to Home (screen: \(signature().text))")
        }
        step("swipe back: company section then Back still needs one swipe") {
            guard openCompany("Caf") else { return .skip("no company on Home") }
            _ = tapID("company-tab-manage")
            swipeBackFromEdge()
            return homeVisible(4) ? .pass() : .fail("after switching section an edge swipe did not return to Home (\(signature().text))")
        }
        for name in ["Inbox", "Settings", "Competition", "Market"] {
            step("swipe back: Phone app \(name) returns to the grid") {
                guard openPhoneApp(name), lastOpenWhy != "pick" else { return .skip("no tile on the grid") }
                swipeBackFromEdge()
                return gridUp(4) ? .pass() : .fail("an edge swipe did not return to the app grid (\(signature().text))")
            }
        }
        step("swipe back: pushed page inside an app (Bank account) returns one level") {
            guard openPhoneApp("Bank") else { return .skip("no Bank tile") }
            guard tapPrefix("bank-pick-", wait: 4) else { return .skip("no bank-pick row") }
            let inner: TourSig = signature()
            swipeBackFromEdge()
            let after: TourSig = signature()
            if after.same(inner) { return .fail("the swipe did nothing on \(inner.text)") }
            if gridUp() { return .fail("the swipe left the whole app: \(inner.text) -> grid") }
            return has("bank-pick-personal", wait: 2) ? .pass("\(inner.text) -> chooser") : .fail("not back on the chooser: \(after.text)")
        }
        step("swipe back: hiring screen returns to the Team section") {
            guard openCompany("Caf"), tapID("company-tab-team"), tapID("team-hire-workers", wait: 4) else { return .skip("hiring screen not reachable") }
            swipeBackFromEdge()
            return isSelected("company-tab-team") ? .pass() : .fail("an edge swipe did not return to Team (\(signature().text))")
        }
    }

    func testT99_Summary() {
        let block: String = log.finish()
        let a: XCTAttachment = XCTAttachment(string: block)
        a.name = "tour-result"
        a.lifetime = .keepAlways
        add(a)
    }
}
