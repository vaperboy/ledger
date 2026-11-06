import XCTest

/// Feature tours: day and week reports, rewards, the Inbox decision, the shopping and insurance apps, the Bank loan, Settings and Luxury.
/// The rule behind most steps: a popup must never change navigation. Cancel paths must leave exactly the same screen; confirm paths may
/// move on (a receipt) but must never pop the player back to a root screen.
extension FeatureToursTests {

    /// Reads and closes every popup that follows an action (the reports, a reward, notices), one after the other.
    /// Returns what was seen, the faults found, and the result of a reward claim when one appeared.
    private func drainPopups(firstWait: TimeInterval, limit: Int = 8) -> (seen: [String], problems: [String], reward: R?) {
        var seen: [String] = []
        var problems: [String] = []
        var reward: R? = nil
        var rounds = 0
        while rounds < limit {
            guard popupUp(seen.isEmpty ? firstWait : 3) else { break }
            rounds += 1
            let kinds: [String] = ["report-open", "celebration-claim", "report-continue", "celebration-dismiss", "alert-continue", "error-ok", "notice-ok", "unlock-skip", "ambition-later", "popup-close", "confirm-go"]
            let kind: String = kinds.first { (k: String) -> Bool in button(k).exists } ?? "unknown"
            seen.append(kind)
            problems.append(contentsOf: rawProblems("popup \(kind)"))
            if kind == "report-open" {
                // The week report: open the detail, page through it, then leave with Continue.
                _ = tapID("report-open", wait: 2)
                var pages = 0
                while pages < 5 && tapID("report-next", wait: 1) { pages += 1 }
                closePopup(prefer: ["report-continue"])
            } else if kind == "celebration-claim" {
                let before: TourSig = signature()
                _ = tapID("celebration-claim", wait: 2)
                let gone: Bool = waitPopupGone(3)
                let after: TourSig = signature()
                if !gone { reward = .fail("the reward popup did not close after Claim") }
                else if !before.same(after, strictText: false) { reward = .fail("claiming changed the screen: \(before.text) -> \(after.text)") }
                else { reward = .pass() }
            } else {
                closePopup()
            }
            pause(0.5)
        }
        if popupUp() { problems.append("a popup is still up after \(rounds) closes (\(seen.last ?? "?"))") }
        return (seen, problems, reward)
    }

    // MARK: T20 Next day, week report, reward

    func testT20_DayAndReports() {
        var reward: R = .skip("no reward popup appeared in the days played")
        for day in 1...3 {
            step("home: Next day #\(day): report popups close and Home stays") {
                guard goTab("Home") else { return .fail("no Home tab") }
                let before: TourSig = signature()
                guard tapID("next-day") else { return .skip("no next-day button") }
                let d = drainPopups(firstWait: 6)
                if let r = d.reward { reward = r }
                _ = homeVisible(3)
                let after: TourSig = signature()
                var problems: [String] = d.problems
                // The day label changes, so only the structure (tab, no Back button) is compared.
                if !before.same(after, strictText: false) { problems.append("screen changed: \(before.text) -> \(after.text)") }
                return problems.isEmpty ? .pass(d.seen.isEmpty ? "no popup that day" : "popups: " + d.seen.joined(separator: ",")) : .fail(problems.prefix(3).joined(separator: "; "))
            }
        }
        step("home: Play week: week report pages close and Home stays") {
            guard goTab("Home") else { return .fail("no Home tab") }
            let before: TourSig = signature()
            guard tapID("play-week", wait: 5) else { return .skip("no play-week button") }
            let d = drainPopups(firstWait: 40, limit: 10)
            if let r = d.reward { reward = r }
            if d.seen.isEmpty { return .fail("no report or popup within 40 s of Play week") }
            _ = homeVisible(3)
            let after: TourSig = signature()
            var problems: [String] = d.problems
            if !before.same(after, strictText: false) { problems.append("screen changed: \(before.text) -> \(after.text)") }
            return problems.isEmpty ? .pass("popups: " + d.seen.joined(separator: ",")) : .fail(problems.prefix(3).joined(separator: "; "))
        }
        step("reward: Claim closes the popup and keeps the screen") { reward }
        step("home: health after the days played") { health("Home after days", title: false) }
    }

    // MARK: T21 Inbox

    func testT21_Inbox() {
        var opened = false
        step("inbox: opens with rows or an empty state") {
            guard openPhoneApp("Inbox") else { return lastOpenWhy == "hidden" ? .skip("Inbox locked by the unlock ladder") : .fail("no Inbox tile: \(lastOpenWhy)") }
            opened = true
            let rows: Int = app.buttons.matching(identifier: "inbox-row").count
            return .pass("rows on screen: \(rows), waiting: \(waitingNumber() ?? 0)")
        }
        step("inbox: health") { opened ? health("Inbox") : .skip("Inbox not opened") }
        step("inbox: Needs you / Handled / All segments switch and show their rows") {
            guard opened else { return .skip("Inbox not opened") }
            var counts: [String] = []
            for seg in ["Needs you", "Handled", "All"] {
                guard tapID("segment-\(seg)", wait: 3) || tapText(seg) else { return .fail("no '\(seg)' segment") }
                pause(0.5)
                counts.append("\(seg)=\(app.buttons.matching(identifier: "inbox-row").count)")
            }
            _ = tapID("segment-Needs you")
            return .pass(counts.joined(separator: " ") + ", waiting \(waitingNumber() ?? 0)")
        }
        step("inbox: Handled rows say who handled them; Needs you holds no handled row") {
            guard opened else { return .skip("Inbox not opened") }
            guard tapID("segment-Handled", wait: 3) else { return .fail("no Handled segment") }
            let handled: [String] = allTexts().map { $0.text }.filter { $0.hasPrefix("Handled by ") }
            _ = tapID("segment-Needs you")
            let leaked: Int = allTexts().filter { $0.text.hasPrefix("Handled by ") }.count
            if leaked > 0 { return .fail("\(leaked) 'Handled by' row(s) are in Needs you") }
            return handled.isEmpty ? .skip("no handled message in this game") : .pass("\(handled.count) handled, e.g. \(handled[0])")
        }
        roundTrip("inbox: open a message, closing the detail keeps the Inbox", prepare: { openPhoneApp("Inbox") }) { tap(button("inbox-row"), wait: 4) }
        step("inbox: answer a decision -> popup closes, the waiting count drops") {
            guard openPhoneApp("Inbox") else { return lastOpenWhy == "hidden" ? .skip("Inbox locked by the unlock ladder") : .fail("no Inbox tile: \(lastOpenWhy)") }
            guard let before = waitingNumber(), before > 0 else { return .skip("no decision waiting (\(waitingNumber() ?? 0))") }
            guard tap(button("inbox-row"), wait: 4) else { return .skip("no row to open") }
            guard button("inbox-option").waitForExistence(timeout: 4) else { toRoot(); return .fail("the opened message has no answer buttons") }
            var problems: [String] = rawProblems("inbox detail")
            guard tap(button("inbox-option"), wait: 2) else { return .fail("answer button not tappable") }
            if popupUp(2), button("confirm-go").exists {
                problems.append(contentsOf: rawProblems("inbox confirm"))
                _ = tapID("confirm-go", wait: 2)
            }
            guard waitPopupGone(4) else { return .fail("the popup did not close after answering") }
            var n = 0
            while n < 2, popupUp(1) { closePopup(); n += 1 }
            let landed: String = homeVisible(3) ? "Home" : signature().text
            guard openPhoneApp("Inbox") else { return .fail("could not reopen the Inbox (landed on \(landed))") }
            let after: Int = waitingNumber() ?? 0
            if after >= before { problems.append("waiting count \(before) -> \(after): the list did not update") }
            return problems.isEmpty ? .pass("waiting \(before) -> \(after); after answering the app showed \(landed)") : .fail(problems.prefix(3).joined(separator: "; "))
        }
    }

    // MARK: T22 Shopping, insurance, second-hand market

    func testT22_ShopsAndInsurance() {
        // Marketplace
        let buy: [String] = ["mk-buy"]
        roundTrip("marketplace: Buy -> confirm, Cancel keeps the listing", closeWith: ["confirm-cancel"], prepare: { openPhoneApp("Marketplace") && tapPrefix("mk-listing-", wait: 5) }) {
            driveUntilPopup(buy)
        }
        roundTrip("marketplace: Buy -> confirm, Buy never pops to a root", closeWith: ["confirm-go"], leavesScreen: true,
                  prepare: { openPhoneApp("Marketplace") && tapPrefix("mk-listing-", wait: 5) }) { driveUntilPopup(buy) }
        // AirStay
        roundTrip("airstay: Rent -> confirm, Cancel keeps the listing", closeWith: ["confirm-cancel"], prepare: { openPhoneApp("AirStay") && tapPrefix("stay-listing-", wait: 5) }) {
            driveUntilPopup(["stay-rent", "stay-continue"])
        }
        roundTrip("airstay: Rent -> confirm, Rent it never pops to a root", closeWith: ["confirm-go"], leavesScreen: true,
                  prepare: { openPhoneApp("AirStay") && tapPrefix("stay-listing-", wait: 5) }) { driveUntilPopup(["stay-rent", "stay-continue"]) }
        // TechPro: basket, checkout, then the pay question
        let checkout: [String] = ["tp-view-basket", "tp-checkout", "tp-continue", "tp-pay"]
        func fillBasket() -> Bool {
            guard openPhoneApp("TechPro Store") else { return false }
            _ = tapID("tp-shop-now", wait: 3)
            guard tapPrefix("tp-tile-", wait: 5) else { return false }
            return tapID("tp-add", wait: 4)
        }
        roundTrip("techpro: checkout Pay -> confirm, Cancel keeps checkout", closeWith: ["confirm-cancel"], prepare: { fillBasket() }) { driveUntilPopup(checkout) }
        roundTrip("techpro: checkout Pay -> confirm, Pay never pops to a root", closeWith: ["confirm-go"], leavesScreen: true, prepare: { fillBasket() }) { driveUntilPopup(checkout) }
        // Atlas: cancel a policy (the quote flow has its own confirm)
        roundTrip("atlas: cancel a policy -> confirm, Cancel keeps Atlas", closeWith: ["confirm-cancel"], prepare: { openPhoneApp("Atlas Insurance") }) {
            driveUntilPopup(["prefix:atlas-cancel-"])
        }
        roundTrip("atlas: cancel a policy -> confirm, Cancel policy never pops to a root", closeWith: ["confirm-go"], leavesScreen: true, prepare: { openPhoneApp("Atlas Insurance") }) {
            driveUntilPopup(["prefix:atlas-cancel-"])
        }
        roundTrip("atlas: get a quote -> confirm, Cancel keeps Atlas", closeWith: ["confirm-cancel"], prepare: { openPhoneApp("Atlas Insurance") }) {
            driveUntilPopup(["atlas-get-quote", "atlas-confirm"])
        }
    }

    // MARK: T23 Bank loan

    func testT23_BankLoan() {
        step("bank: accounts and wealth overview open") {
            guard openPhoneApp("Bank") else { return lastOpenWhy == "hidden" ? .skip("Bank locked by the unlock ladder") : .fail("no Bank tile: \(lastOpenWhy)") }
            guard tap(buttonPrefix("bank-pick-"), wait: 5) else { return .skip("no account picker row") }
            let h: R = health("bank account")
            _ = tapBack()
            return h
        }
        step("bank: loan apply -> confirmation page; Take the loan keeps a coherent screen") {
            guard openPhoneApp("Bank"), tap(buttonPrefix("bank-pick-"), wait: 5) else { return .skip("no account picker row") }
            let loans: XCUIElement = app.buttons.matching(NSPredicate(format: "label == 'Loans'")).firstMatch
            guard tap(loans, wait: 4) else { return .skip("no Loans tab") }
            guard tapID("bank-apply-loan") else { return .skip("no Apply for a loan button") }
            if elem("bank-loan-refused").exists || app.staticTexts["The bank would not lend now"].exists { return .pass("the bank refused this borrower and said so") }
            guard tapID("bank-loan-choose", wait: 4) else { return .fail("the offer page has no 'Choose amount'") }
            _ = tapID("bank-loan-chip-50%")
            guard tapID("bank-loan-continue") else { return .fail("no Continue on the amount page") }
            _ = tapID("bank-loan-agree")
            guard button("bank-loan-confirm").waitForExistence(timeout: 4) else { return .fail("no 'Take the loan' button on the agreement page") }
            let before: TourSig = signature()
            let h: R = health("loan agreement", clip: false)
            guard tapID("bank-loan-confirm") else { return .fail("'Take the loan' is not tappable (agreed?)") }
            var problems: [String] = []
            if popupUp(2) {
                problems.append(contentsOf: rawProblems("loan confirm"))
                closePopup(prefer: ["confirm-cancel"])
                guard waitPopupGone(3) else { return .fail("the loan question did not close with Cancel") }
                if !before.same(signature()) { problems.append("closing the loan question changed the screen: \(before.text) -> \(signature().text)") }
            } else {
                guard button("bank-loan-done").waitForExistence(timeout: 4) else { return .fail("loan taken but no 'Done' page followed (\(signature().text))") }
                _ = tapID("bank-loan-done")
            }
            if case .fail(let m) = h { problems.append(m) }
            return problems.isEmpty ? .pass(popupUp() ? "" : "ended on \(signature().text)") : .fail(problems.prefix(3).joined(separator: "; "))
        }
    }

    // MARK: T24 Settings, Luxury, Ventures popups

    func testT24_OtherPopups() {
        roundTrip("settings: Ledger Pro paywall closes and keeps Settings", closeWith: ["paywall-pass", "popup-close"], prepare: { openPhoneApp("Settings") }) { tapID("settings-ledger-pro") }
        step("settings: Redeem a code with an invalid code shows the refusal") {
            guard openPhoneApp("Settings") else { return .skip("Settings not opened") }
            guard tapID("settings-redeem", wait: 4) else { return .skip("no Redeem a code row") }
            guard popupUp(3) else { return .fail("Redeem a code did not open a popup") }
            let field: XCUIElement = app.textFields["redeem-code"].firstMatch
            guard field.waitForExistence(timeout: 3) else { closePopup(); return .fail("no field redeem-code in the popup") }
            ctap(field); pause(0.5)
            field.typeText("ZZZZ-0000-0000-0000\n")
            pause(0.8)
            var seen: Bool = allTexts().contains { $0.text.localizedCaseInsensitiveContains("not valid") }
            if !seen, ctap(button("redeem-code-action")) { pause(0.8); seen = allTexts().contains { $0.text.localizedCaseInsensitiveContains("not valid") } }
            let raw: [String] = rawProblems("redeem popup")
            closePopup()
            _ = waitPopupGone(3)
            if !seen { return .fail("typed an invalid code but no 'not valid' refusal appeared") }
            return raw.isEmpty ? .pass() : .fail("popup text: " + raw.joined(separator: "; "))
        }
        roundTrip("luxury: item sheet closes and keeps the showroom", prepare: { openPhoneApp("Luxury") }) { tap(elem("luxury-hero"), wait: 4) }
        roundTrip("market: open a listing -> deal popup closes and keeps the listing", prepare: { openPhoneApp("Marketplace") && tapPrefix("mk-listing-", wait: 5) }) { tapID("mk-discuss", wait: 3) }
        roundTrip("ventures: Launch / price popup closes and keeps Ventures", prepare: { goTab("Ventures") }) { tapText("Change price") || tapText("Set price") }
        step("home: New company page opens and Back returns to Home") {
            guard goTab("Home") else { return .fail("no Home tab") }
            guard tapID("New company", wait: 4) else { return .skip("no New company button") }
            let h: R = health("new company trades")
            _ = tapBack()
            return homeVisible(4) ? h : .fail("Back did not return to Home: \(signature().text)")
        }
    }
}
