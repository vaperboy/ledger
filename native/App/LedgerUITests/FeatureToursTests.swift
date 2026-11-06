import XCTest

/// Feature tours (manual CI job `ui-tours`, see .github/workflows/native-ios.yml). One class so one summary covers every tour; the tours
/// are separate test methods (each relaunches the app on the prepared `-showcase -showcase-rich -showcase-board` game) so one crash or one
/// long screen cannot take the others down. Methods run in name order; testT99 prints the summary. See FeatureToursKit for the step rules.
final class FeatureToursTests: FeatureTourCase {

    // MARK: T01 tabs and Home

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
                return button(id).isSelected ? .pass() : .fail("tapped but the tab is not marked selected: " + tabState())
            }
            step("tab \(title): health") { health("tab \(title)", title: false) }
        }
        // Home shortcuts: each one opens something and a Back (or the Home tab) returns.
        _ = goTab("Home")
        let shortcuts: [String] = ids(prefix: "home-")
        step("home: shortcuts are on screen") { shortcuts.isEmpty ? .fail("no home-* buttons") : .pass("\(shortcuts.count): \(shortcuts.joined(separator: ","))") }
        for id in shortcuts {
            step("home shortcut \(id): opens something and Back returns") {
                guard goTab("Home") else { return .fail("cannot get to Home") }
                let before: TourSig = signature()
                guard tapID(id) else { return .skip("not tappable (off screen)") }
                if popupUp() { closePopup(); return .pass("opened a popup") }
                let after: TourSig = signature()
                if before.same(after) { return .fail("nothing changed after the tap") }
                _ = tapBack()
                toRoot()
                _ = goTab("Home")
                return homeVisible(4) ? .pass("-> \(after.text)") : .fail("did not get back to Home from \(after.text)")
            }
        }
    }

    // MARK: T02 and T03 Phone apps

    private func tourApp(_ title: String) {
        var opened = false
        step("phone app \(title): opens") {
            guard openPhoneApp(title) else { return .fail("no tile phone-app-\(title) on the Phone grid") }
            if popupUp() { closePopup() }
            let sig: TourSig = signature()
            let gridStillThere: Bool = title != "Bank" ? visible(button("phone-app-Bank")) : visible(button("phone-app-Inbox"))
            if gridStillThere { return .fail("the app grid is still on screen after tapping the tile") }
            opened = true
            return .pass(sig.text)
        }
        step("phone app \(title): health") { opened ? health("app \(title)") : .skip("not opened") }
        step("phone app \(title): Back returns to the grid") {
            guard opened else { return .skip("not opened") }
            guard tapBack() else { return .fail("no Back button on the app") }
            return button("phone-app-Bank").waitForExistence(timeout: 4) ? .pass() : .fail("Back did not show the app grid")
        }
    }

    func testT02_PhoneAppsA() {
        for t in ["Bank", "Accounting", "Inbox", "News", "Weather", "Stats", "World", "Luxury", "Rich list"] { tourApp(t) }
    }

    func testT03_PhoneAppsB() {
        for t in ["Market", "Reviews", "Achievements", "Settings", "AirStay", "TechPro Store", "Atlas Insurance", "Marketplace"] { tourApp(t) }
    }

    // MARK: T04 Ventures, Group and Stats pages

    func testT04_VenturesGroupStats() {
        step("ventures tab: opens") {
            guard goTab("Ventures") else { return .fail("no Ventures tab") }
            return .pass(signature().text)
        }
        step("ventures tab: health") { health("Ventures", title: false) }
        roundTrip("ventures: 'Found a startup' popup closes and keeps Ventures") { tapText("Found a startup") }

        step("group tab: opens") { goTab("Group") ? .pass(signature().text) : .fail("no Group tab") }
        step("group tab: health") { health("Group", title: false) }
        let entity: String = ids(prefix: "group-entity-").first ?? ""
        for name in ["Management", "Boardroom", "Money", "Expansion", "Ownership"] {
            step("group entity page: \(name) tab") {
                guard !entity.isEmpty else { return .skip("no entity in the Group picker") }
                _ = goTab("Group")
                if !button("group-tab-\(name)").exists { _ = tapID(entity) }
                guard tapID("group-tab-\(name)") else { return .skip("no \(name) tab on the entity page") }
                let r: R = health("group \(name)", title: false)
                return r
            }
        }
        roundTrip("group money: Policy popup closes and keeps the page", prepare: {
            guard !entity.isEmpty else { return false }
            _ = goTab("Group")
            if !button("group-tab-Money").exists { _ = tapID(entity) }
            return tapID("group-tab-Money")
        }) { tapID("money-policy") }
        step("group: Suppliers directory opens and Back returns") {
            guard goTab("Group") else { return .fail("no Group tab") }
            guard tapID("group-suppliers") else { return .skip("no group-suppliers link") }
            let h: R = health("group suppliers")
            _ = tapBack()
            return h
        }
        // Board: seat removal asks first; Cancel and Remove must both keep the Board screen.
        func openBoardRoom() -> Bool {
            guard !entity.isEmpty else { return false }
            _ = goTab("Group")
            if !button("group-tab-Boardroom").exists { _ = tapID(entity) }
            guard tapID("group-tab-Boardroom") else { return false }
            return tapID("group-board-room") || tapText("Board room")
        }
        step("board room: opens") {
            guard openBoardRoom() else { return .skip("no board room (needs the -showcase-board game and a co-owner)") }
            return health("board room")
        }
        // Boardroom tab: talk to a manager (a popup), call the board round (a popup).
        func openBoardroomTab() -> Bool {
            guard !entity.isEmpty else { return false }
            _ = goTab("Group")
            if !button("group-tab-Boardroom").exists { _ = tapID(entity) }
            return tapID("group-tab-Boardroom")
        }
        roundTrip("boardroom: Talk to a manager opens a popup and closes back to the Boardroom", prepare: { openBoardroomTab() }) { tapPrefix("boardroom-talk-", wait: 4) }
        roundTrip("boardroom: Call the board opens a popup and closes back to the Boardroom", prepare: { openBoardroomTab() }) { tapPrefix("boardroom-call-", wait: 4) }
        // Ownership: Owners | Sell | Raise | Offers, and the route picker under Sell.
        func openOwnership(_ part: String) -> Bool {
            guard !entity.isEmpty else { return false }
            _ = goTab("Group")
            if !button("group-tab-Ownership").exists { _ = tapID(entity) }
            guard tapID("group-tab-Ownership") else { return false }
            return tapID("group-ownership-\(part)")
        }
        for part in ["Owners", "Sell", "Raise", "Offers"] {
            step("ownership: \(part) page opens and is clean") {
                guard openOwnership(part) else { return .skip("no Ownership > \(part) segment") }
                return health("ownership \(part)", title: false)
            }
        }
        step("ownership: Sell lists the route picker") {
            guard openOwnership("Sell") else { return .skip("no Ownership > Sell segment") }
            let routes: [String] = ids(prefix: "sell-route-")
            if routes.isEmpty { return .fail("Sell shows no sell-route-* rows (a limited company with a route is expected): " + tabState()) }
            return .pass("\(routes.count) routes: " + routes.map { String($0.dropFirst(11)) }.joined(separator: ","))
        }
        roundTrip("ownership: a sell route opens a confirm or sheet and Cancel keeps Sell", closeWith: ["confirm-cancel", "popup-close"], prepare: { openOwnership("Sell") }) { tapPrefix("sell-route-", wait: 4) }
        roundTrip("board room: Remove from board -> Cancel keeps the Board screen", closeWith: ["confirm-cancel"], prepare: { openBoardRoom() }) { tapID("board-remove-seat") }
        roundTrip("board room: Remove from board -> confirm keeps the Board screen", closeWith: ["confirm-go"], prepare: { openBoardRoom() }) { tapID("board-remove-seat") }
    }

    // MARK: T05 swipe back from pushed screens

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
        for name in ["Bank", "Accounting", "Settings", "Atlas Insurance"] {
            step("swipe back: Phone app \(name) returns to the grid") {
                guard openPhoneApp(name) else { return .skip("no tile") }
                swipeBackFromEdge()
                return button("phone-app-Bank").waitForExistence(timeout: 4) ? .pass() : .fail("an edge swipe did not return to the app grid (\(signature().text))")
            }
        }
        step("swipe back: pushed page inside an app (Bank account) returns one level") {
            guard openPhoneApp("Bank") else { return .skip("no Bank tile") }
            let pick: XCUIElement = buttonPrefix("bank-pick-")
            guard tap(pick, wait: 4) else { return .skip("no bank-pick row") }
            let inner: TourSig = signature()
            swipeBackFromEdge()
            let after: TourSig = signature()
            if after.same(inner) { return .fail("the swipe did nothing on \(inner.text)") }
            return button("phone-app-Bank").exists ? .fail("the swipe left the whole app: \(inner.text) -> grid") : .pass("\(inner.text) -> \(after.text)")
        }
    }

    // MARK: T99 summary

    func testT99_Summary() {
        let block: String = log.finish()
        let a: XCTAttachment = XCTAttachment(string: block)
        a.name = "tour-result"
        a.lifetime = .keepAlways
        add(a)
    }
}
