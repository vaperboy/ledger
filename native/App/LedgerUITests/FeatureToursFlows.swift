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
            let kinds: [String] = ["report-continue", "celebration-claim", "celebration-dismiss", "alert-continue", "error-ok", "notice-ok", "unlock-skip", "ambition-later", "popup-close", "confirm-go"]
            let hs: [Hit] = hits()
            let kind: String = kinds.first { (k: String) -> Bool in hs.contains { $0.id == k } } ?? "unknown"
            seen.append(kind)
            problems.append(contentsOf: rawProblems("popup \(kind)"))
            if kind == "report-continue" {
                // The report: leave with Continue (Full report and the suggested action navigate away on purpose).
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
            let d = drainPopups(firstWait: 75, limit: 10)
            if let r = d.reward { reward = r }
            if d.seen.isEmpty { return .fail("no report or popup within 75 s of Play week (\(signature().text))") }
            _ = homeVisible(3)
            let after: TourSig = signature()
            var problems: [String] = d.problems
            if !before.same(after, strictText: false) { problems.append("screen changed: \(before.text) -> \(after.text)") }
            return problems.isEmpty ? .pass("popups: " + d.seen.joined(separator: ",")) : .fail(problems.prefix(3).joined(separator: "; "))
        }
        step("reward: Claim closes the popup and keeps the screen") { reward }
        step("report: 'Full report' opens the Reports app and Back returns") {
            guard goTab("Home"), tapID("next-day", wait: 3) else { return .skip("no next-day button") }
            guard popupUp(8), tapID("report-open", wait: 3) else { var n = 0; while n < 6 && popupUp(1) { closePopup(); n += 1 }; return .skip("no report with Full report after a day") }
            _ = waitPopupGone(3)
            var n = 0
            while n < 4 && popupUp(1) { closePopup(prefer: ["report-continue"]); n += 1 }
            let page: TourSig = signature()
            let h: R = health("reports app")
            guard page.back, tapBack() else { return .fail("Full report did not open a page with Back: \(page.text)") }
            return h
        }
        step("home: health after the days played") { health("Home after days", title: false) }
    }

    // MARK: T21 Inbox

    private func inboxSegment(_ seg: String) -> Bool {
        tapWhere(wait: 3) { $0.type == .button && ($0.id == "segment-\(seg)" || $0.label == seg || $0.label.hasPrefix(seg + ",") || $0.label.hasPrefix(seg + " ")) }
    }

    /// Opens the Inbox with at least one decision waiting, playing up to `days` days for one to arrive.
    private func inboxWithDecision(days: Int = 4) -> Int? {
        if openPhoneApp("Inbox"), let n = waitingNumber(), n > 0 { return n }
        _ = advanceDays(days) { openPhoneApp("Inbox") && (waitingNumber() ?? 0) > 0 }
        if openPhoneApp("Inbox"), let n = waitingNumber(), n > 0 { return n }
        return nil
    }

    func testT21_Inbox() {
        var opened = false
        step("inbox: opens with rows or an empty state") {
            guard openPhoneApp("Inbox") else { return lastOpenWhy == "hidden" ? .skip("Inbox locked by the unlock ladder") : .fail("no Inbox tile: \(lastOpenWhy)") }
            opened = true
            let rows: Int = hits().filter { $0.id == "inbox-row" }.count
            return .pass("rows on screen: \(rows), waiting: \(waitingNumber() ?? 0)")
        }
        step("inbox: health") { opened ? health("Inbox") : .skip("Inbox not opened") }
        step("inbox: Needs you / Handled / All tabs switch and show their rows") {
            guard opened, openPhoneApp("Inbox") else { return .skip("Inbox not opened") }
            var counts: [String] = []
            for seg in ["Needs you", "Handled", "All"] {
                guard inboxSegment(seg) else { return .fail("no '\(seg)' tab: " + tabState()) }
                pause(0.5)
                counts.append("\(seg)=\(hits().filter { $0.id == "inbox-row" }.count)")
            }
            _ = inboxSegment("Needs you")
            return .pass(counts.joined(separator: " ") + ", waiting \(waitingNumber() ?? 0)")
        }
        step("inbox: Handled rows say who handled them; Needs you holds no handled row") {
            guard opened, openPhoneApp("Inbox") else { return .skip("Inbox not opened") }
            guard inboxSegment("Handled") else { return .fail("no Handled tab") }
            let handled: [String] = allTexts().map { $0.text }.filter { $0.contains("Handled by ") }
            _ = inboxSegment("Needs you")
            let leaked: Int = allTexts().filter { $0.text.contains("Handled by ") }.count
            if leaked > 0 { return .fail("\(leaked) 'Handled by' row(s) are in Needs you") }
            return handled.isEmpty ? .skip("no handled message in this game") : .pass("\(handled.count) handled, e.g. \(handled[0].prefix(60))")
        }
        roundTrip("inbox: open a message, closing the detail keeps the Inbox", prepare: { openPhoneApp("Inbox") && inboxSegment("All") }) { tapID("inbox-row", wait: 4) }
        var waiting: Int? = nil
        step("inbox: a decision is waiting (playing up to 4 days for one)") {
            waiting = inboxWithDecision()
            return waiting.map { .pass("\($0) waiting") } ?? .skip("no decision arrived in 4 days")
        }
        step("inbox: answer inline in the list -> a toast, no popup, the waiting count drops") {
            guard let before = inboxWithDecision(days: 2) else { return .skip("no decision waiting") }
            guard let opt = bringIn({ $0.id == "inbox-inline-option" && $0.type == .button }, wait: 3) else { return .skip("no decision with inline options (2-3 options, no document)") }
            touch(opt)
            var problems: [String] = []
            if popupUp(1.5) {
                if has("confirm-go") { closePopup(prefer: ["confirm-go"]) } else { problems.append("answering raised a popup (a toast was expected)"); closePopup() }
            }
            let toast: String = find(wait: 3, { $0.id == "notification-banner" })?.label ?? ""
            pause(0.8)
            let after: Int = waitingNumber() ?? 0
            if after >= before { problems.append("waiting count \(before) -> \(after): the list did not update") }
            if toast.isEmpty { problems.append("no toast after answering") }
            return problems.isEmpty ? .pass("waiting \(before) -> \(after); toast '\(toast.prefix(50))'") : .fail(problems.prefix(3).joined(separator: "; "))
        }
        step("inbox: answer in the detail -> the detail closes, the waiting count drops") {
            guard let before = inboxWithDecision(days: 2) else { return .skip("no decision waiting") }
            guard tapID("inbox-row", wait: 4) else { return .skip("no row to open") }
            guard let opt = bringIn({ $0.id == "inbox-option" && $0.type == .button }, wait: 4) else { toRoot(); return .skip("the first message has no answer buttons") }
            var problems: [String] = rawProblems("inbox detail")
            touch(opt)
            if popupUp(1), has("confirm-go") { problems.append(contentsOf: rawProblems("inbox confirm")); closePopup(prefer: ["confirm-go"]) }
            guard waitPopupGone(4) else { return .fail("the detail did not close after answering") }
            let after: Int = waitingNumber() ?? 0
            if after >= before { problems.append("waiting count \(before) -> \(after): the list did not update") }
            if !has("inbox-row", wait: 1) && signature().heads.contains("Inbox") == false { problems.append("left the Inbox after answering: \(signature().text)") }
            return problems.isEmpty ? .pass("waiting \(before) -> \(after)") : .fail(problems.prefix(3).joined(separator: "; "))
        }
        step("home: answer a decision from Needs you -> a toast, no OK popup") {
            guard goTab("Home") else { return .fail("no Home") }
            guard tapWhere(wait: 2, { $0.id == "suggestion-row" }) else { return .skip("no decision row in Needs you") }
            guard popupUp(2) else { return .skip("the row opened a page, not a decision (\(signature().text))") }
            guard let opt = find(wait: 2, { $0.id == "inbox-option" && $0.type == .button }) else { closePopup(); return .skip("the popup is not a decision") }
            touch(opt)
            if popupUp(1), has("confirm-go") { closePopup(prefer: ["confirm-go"]) }
            let gone: Bool = waitPopupGone(3)
            let toast: String = find(wait: 2, { $0.id == "notification-banner" })?.label ?? ""
            if !gone { closePopup(); return .fail("a popup stayed up after answering (an OK popup?)") }
            return homeVisible(3) ? .pass(toast.isEmpty ? "no toast seen" : "toast '\(toast.prefix(50))'") : .fail("not on Home after answering: \(signature().text)")
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

    // MARK: T23 Bank: chooser, account tabs, move money, trade, loan

    private func openBankAccount(_ acc: String) -> Bool {
        guard openPhoneApp("Bank") else { return false }
        return tapID("bank-pick-\(acc)", wait: 4) && has("back-button", wait: 3)
    }

    private func bankTab(_ t: String) -> Bool {
        tapWhere(wait: 3) { $0.type == .button && ($0.label == t || $0.label.hasPrefix(t + ",") || $0.label.hasPrefix(t + " ")) && $0.frame.minY < self.win().minY + 260 }
    }

    func testT23_Bank() {
        step("bank: opens on the account chooser (no log-in)") {
            guard openPhoneApp("Bank") else { return lastOpenWhy == "hidden" ? .skip("Bank locked by the unlock ladder") : .fail("no Bank tile: \(lastOpenWhy)") }
            let picks: [String] = ids(prefix: "bank-pick-")
            if picks.isEmpty { return .fail("no bank-pick-* rows: " + tabState()) }
            return .pass(picks.map { String($0.dropFirst(10)) }.joined(separator: ","))
        }
        for acc in ["personal"] {
            step("bank: \(acc) account opens, health, Back returns to the chooser") {
                guard openBankAccount(acc) else { return .skip("no bank-pick-\(acc)") }
                let h: R = health("bank \(acc)")
                guard tapBack() else { return .fail("no Back on the account") }
                return has("bank-pick-\(acc)", wait: 3) ? h : .fail("Back did not return to the chooser: \(signature().text)")
            }
        }
        for t in ["Account", "Bills", "Loans", "Deposits", "Statements"] {
            step("bank personal: \(t) tab opens and is clean") {
                guard openBankAccount("personal") else { return .skip("no personal account") }
                guard bankTab(t) else { return .fail("no '\(t)' tab: " + tabState()) }
                pause(0.5)
                return health("bank \(t)")
            }
        }
        step("bank company account: tabs Account, Bills, Loans, Statements open") {
            guard openPhoneApp("Bank"), tapPrefix("bank-pick-company", wait: 4) else { return .skip("no company account") }
            var missing: [String] = []
            for t in ["Bills", "Loans", "Statements", "Account"] where !bankTab(t) { missing.append(t) }
            let h: R = health("bank company account")
            return missing.isEmpty ? h : .fail("missing tabs: " + missing.joined(separator: ","))
        }
        // Moving money: Transfer, Deposit and Withdraw open a popup whose button is in view; Half then the button moves money.
        for tile in ["Transfer", "Deposit", "Withdraw"] {
            roundTrip("bank: \(tile) popup closes and keeps the account", prepare: { openBankAccount("personal") }) { tapLabel(tile) }
        }
        step("bank: Transfer -> Half -> move (confirm if asked) -> toast, popup stays usable") {
            guard openBankAccount("personal"), tapLabel("Transfer"), popupUp(2) else { return .skip("no Transfer popup") }
            var problems: [String] = []
            if case .fail(let m) = primaryInView("bank-move-go") { problems.append(m) }
            guard tapLabel("Half", wait: 2) else { closePopup(); return .skip("nothing to move (no Half button)") }
            guard tapEnabled("bank-move-go", wait: 2) else { closePopup(); return .fail("bank-move-go not tappable after Half (blocked?)") }
            if has("confirm-go", wait: 1.5) { closePopup(prefer: ["confirm-go"]) }
            let toast: String = find(wait: 3, { $0.id == "notification-banner" })?.label ?? ""
            if toast.isEmpty { problems.append("no toast after moving money") }
            problems.append(contentsOf: rawProblems("bank move"))
            var n = 0
            while popupUp() && n < 3 { closePopup(); n += 1 }
            if !has("back-button", wait: 2) { problems.append("not on the account after closing: \(signature().text)") }
            return problems.isEmpty ? .pass("toast '\(toast.prefix(50))'") : .fail(problems.prefix(3).joined(separator: "; "))
        }
        step("market invest: Buy -> asset -> amount -> Review -> Confirm -> Done") {
            guard openPhoneApp("Market"), tapID("market-tab-Invest", wait: 4) else { return .skip("no Market app") }
            guard tapID("invest-buy", wait: 4) else { return .fail("no Buy on Invest: \(signature().text)") }
            guard tapPrefix("trade-asset-fund:", wait: 4) else { return .fail("no fund to buy: \(signature().text)") }
            if tapID("trade-owner-me", wait: 1.5) { pause(0.3) }
            guard let field = find(wait: 3, { $0.type == .textField }) else { return .fail("the buy page has no amount field") }
            touch(field)
            pause(0.6)
            app.typeText("500")
            if let d = find({ $0.type == .button && $0.label == "Done" }) { touch(d) }
            var problems: [String] = []
            if case .fail(let m) = primaryInView("trade-review") { problems.append("amount: " + m) }
            guard tapEnabled("trade-review", wait: 2) else { return .fail("Review not tappable after typing 500 (\(find({ $0.id == "trade-review-blocked" }) != nil ? "blocked" : "missing"))") }
            if case .fail(let m) = primaryInView("trade-confirm") { problems.append("review: " + m) }
            problems.append(contentsOf: rawProblems("market trade review"))
            guard tapEnabled("trade-confirm", wait: 2) else { return .fail("Confirm purchase not tappable") }
            guard tapID("trade-done", wait: 4) else { return .fail("no Done after confirming: \(signature().text)") }
            if !has("back-button", wait: 2) { problems.append("Done left no Back: \(signature().text)") }
            return problems.isEmpty ? .pass("now \(signature().text)") : .fail(problems.prefix(3).joined(separator: "; "))
        }
        step("bank: loan apply -> offer -> amount -> agreement; Take the loan in view") {
            guard openBankAccount("personal"), bankTab("Loans") else { return .skip("no Loans tab") }
            guard tapID("bank-apply-loan", wait: 3) else { return .skip("no Apply for a loan button") }
            if onScreenText("would not lend") { return .pass("the bank refused this borrower and said so") }
            guard tapID("bank-loan-choose", wait: 4) else { return .fail("the offer page has no 'Choose an amount'") }
            _ = tapID("bank-loan-chip-50%")
            guard tapEnabled("bank-loan-continue") else { return .fail("no Continue on the amount page") }
            _ = tapID("bank-loan-agree")
            guard has("bank-loan-confirm", wait: 4) else { return .fail("no 'Take the loan' button on the agreement page") }
            var problems: [String] = []
            if case .fail(let m) = primaryInView("bank-loan-confirm") { problems.append(m) }
            if case .fail(let m) = health("loan agreement", clip: false) { problems.append(m) }
            guard tapEnabled("bank-loan-confirm") else { return .fail("'Take the loan' is not tappable (agreed?)") }
            if popupUp(2) { closePopup(prefer: ["confirm-go"]) }
            guard has("bank-loan-done", wait: 4) else { return .fail("loan taken but no 'Done' page followed (\(signature().text))") }
            _ = tapID("bank-loan-done")
            return problems.isEmpty ? .pass("ended on \(signature().text)") : .fail(problems.prefix(3).joined(separator: "; "))
        }
    }

    // MARK: T25 Accounting: payroll, pay day, the Bank link

    private func openPayroll() -> Bool {
        guard openPhoneApp("Accounting") else { return false }
        return tapID("acct-row-payroll", wait: 4) && has("acct-payroll-tabs", wait: 3)
    }

    func testT25_AccountingPayroll() {
        step("accounting: home lists the sections") {
            guard openPhoneApp("Accounting") else { return .fail("no Accounting tile: \(lastOpenWhy)") }
            let rows: [String] = ids(prefix: "acct-row-")
            return rows.count >= 6 ? .pass(rows.map { String($0.dropFirst(9)) }.joined(separator: ",")) : .fail("only \(rows.count) sections: \(rows)")
        }
        for row in ["transactions", "invoices", "suppliers", "balance", "cashflow", "documents", "settings"] {
            step("accounting: \(row) opens, is clean, Back returns") {
                guard openPhoneApp("Accounting"), tapID("acct-row-\(row)", wait: 4) else { return .skip("no acct-row-\(row)") }
                let h: R = health("accounting \(row)")
                guard tapBack() else { return .fail("no Back") }
                return has("acct-row-payroll", wait: 3) ? h : .fail("Back did not return to Accounting home: \(signature().text)")
            }
        }
        step("payroll: opens on Overview, health") {
            guard openPayroll() else { return .fail("Accounting > Payroll not reachable") }
            return health("payroll overview")
        }
        for t in ["Employees", "Timesheets", "Run payroll", "Overview"] {
            step("payroll: \(t) tab opens and is clean") {
                guard openPayroll() else { return .skip("payroll not reachable") }
                guard tapWhere(wait: 3, { $0.type == .button && ($0.label == t || $0.label.hasPrefix(t + ",")) }) else { return .fail("no '\(t)' tab") }
                return health("payroll \(t)")
            }
        }
        step("payroll: pay day choices are listed in Overview") {
            guard openPayroll() else { return .skip("payroll not reachable") }
            let days: [String] = ids(prefix: "acct-payday-")
            if days.isEmpty { _ = bringIn({ $0.id.hasPrefix("acct-payday-") }, wait: 1) }
            let all: [String] = days.isEmpty ? ids(prefix: "acct-payday-", wait: 1) : days
            return all.isEmpty ? .fail("no acct-payday-* rows") : .pass(all.map { String($0.dropFirst(12)) }.joined(separator: ","))
        }
        step("payroll: choosing another pay day shows a toast and marks it") {
            guard openPayroll() else { return .skip("payroll not reachable") }
            guard tapWhere(wait: 3, { $0.id.hasPrefix("acct-payday-") && $0.type == .button && !$0.label.contains("Current") && !$0.label.contains("Queued") }) else { return .skip("no other pay day to choose") }
            let toast: String = find(wait: 3, { $0.id == "notification-banner" })?.label ?? ""
            let marked: Bool = hits().contains { $0.id.hasPrefix("acct-payday-") && $0.label.contains("Queued") } || !toast.isEmpty
            if popupUp(1) { closePopup(); return .fail("choosing a pay day raised a popup") }
            return marked ? .pass("toast '\(toast.prefix(60))'") : .fail("no toast and no 'Queued' mark after choosing a pay day")
        }
        step("payroll: Run payroll button goes to the Run tab with its action in view") {
            guard openPayroll(), tapID("acct-payroll-run", wait: 3) else { return .skip("no Run payroll button") }
            return primaryInView("acct-payroll-confirm")
        }
        roundTrip("payroll: Approve -> confirm, Cancel keeps the Run tab", closeWith: ["confirm-cancel"], prepare: { openPayroll() && tapID("acct-payroll-run", wait: 3) }) {
            guard let b = find(wait: 2, { $0.id == "acct-payroll-confirm" }), b.enabled else { return false }
            return tapEnabled("acct-payroll-confirm")
        }
        step("payroll: 'Move money in the Bank' opens the company account") {
            guard openPayroll() else { return .skip("payroll not reachable") }
            guard tapID("acct-payroll-move-money", wait: 2) else { return .skip("cash covers the payroll: no move-money link") }
            pause(0.8)
            return onScreenText("Company account") || has("bank-alert-payroll") ? .pass(signature().text) : .fail("the Bank company account did not open: \(signature().text)")
        }
        step("bank: the payroll alert's Run payroll opens Accounting payroll") {
            guard openPhoneApp("Bank"), tapPrefix("bank-pick-company", wait: 4) else { return .skip("no company account") }
            guard tapID("bank-alert-payroll", wait: 2) else { return .skip("no payroll alert on the company account") }
            pause(0.8)
            return has("acct-payroll-tabs", wait: 4) ? .pass() : .fail("Accounting payroll did not open: \(signature().text)")
        }
    }

    // MARK: T26 New company: trade, company, review

    func testT26_NewCompany() {
        func toStep2() -> Bool {
            guard goTab("Home"), tapLabel("New company", wait: 4) else { return false }
            // Step 1: pick the first trade that can be chosen, then Continue.
            guard tapWhere(wait: 4, { $0.type == .button && $0.enabled && $0.frame.minY > self.win().minY + 200 && $0.label.contains("\u{00A3}") }) else { return false }
            return tapWhere(wait: 2) { $0.type == .button && $0.id.hasPrefix("Continue") && $0.enabled }
        }
        step("new company: step 1 opens with the trade table, Back returns Home") {
            guard goTab("Home"), tapLabel("New company", wait: 4) else { return .fail("no New company button on Home") }
            let h: R = health("new company trades")
            guard tapBack() else { return .fail("no Back on step 1") }
            return homeVisible(4) ? h : .fail("Back did not return to Home: \(signature().text)")
        }
        step("new company: Continue is blocked until a trade is picked, with its reason") {
            guard goTab("Home"), tapLabel("New company", wait: 4) else { return .fail("no New company button") }
            let blocked: Bool = find(wait: 2, { $0.id.hasPrefix("Continue") && $0.id.hasSuffix("-blocked") }) != nil
            let reason: Bool = onScreenText("Pick a trade")
            return blocked || reason ? .pass() : .skip("a trade was already picked")
        }
        step("new company: picking a trade -> Continue -> step 2 (name, cost, Review in view)") {
            guard toStep2() else { return .fail("could not pick a trade and continue: " + tabState()) }
            guard has("new-company-start", wait: 4) || has("new-company-start-blocked") else { return .fail("step 2 has no new-company-start: \(signature().text)") }
            var problems: [String] = []
            if case .fail(let m) = primaryInView("new-company-start") { problems.append(m) }
            if case .fail(let m) = health("new company step 2") { problems.append(m) }
            return problems.isEmpty ? .pass() : .fail(problems.joined(separator: "; "))
        }
        step("new company: Customise opens the detailed set-up with Review in view") {
            guard toStep2() else { return .skip("step 2 not reachable") }
            guard tapID("new-company-detail", wait: 3) else { return .skip("no Customise link") }
            var problems: [String] = []
            if case .fail(let m) = primaryInView("new-company-review") { problems.append(m) }
            if case .fail(let m) = health("new company customise") { problems.append(m) }
            guard tapBack() else { return .fail("no Back on Customise") }
            if !has("new-company-start", wait: 3) && !has("new-company-start-blocked") { problems.append("Back did not return to step 2") }
            return problems.isEmpty ? .pass() : .fail(problems.joined(separator: "; "))
        }
        step("new company: Review -> step 3 shows the total and Pay in view; Back x3 returns Home without paying") {
            guard toStep2() else { return .skip("step 2 not reachable") }
            guard tapEnabled("new-company-start", wait: 3) else { return .fail("Review on step 2 is not tappable (blocked?)") }
            guard has("new-company-pay", wait: 4) || has("new-company-pay-blocked") else { return .fail("no review step (new-company-pay): \(signature().text)") }
            var problems: [String] = []
            if case .fail(let m) = primaryInView("new-company-pay") { problems.append(m) }
            if case .fail(let m) = health("new company review") { problems.append(m) }
            for _ in 0..<3 { _ = tapBack() }
            if !homeVisible(4) { problems.append("three Backs did not return to Home: \(signature().text)") }
            return problems.isEmpty ? .pass() : .fail(problems.joined(separator: "; "))
        }
    }

    // MARK: T24 Settings, Luxury, Ventures popups

    func testT24_OtherPopups() {
        step("settings: Ledger Pro opens the paywall and it closes back to Settings") {
            guard openPhoneApp("Settings") else { return .skip("Settings not opened") }
            let before: TourSig = signature()
            guard tapID("settings-ledger-pro", wait: 4) else { return .skip("no Ledger Pro row (already Pro?)") }
            let raw: [String] = rawProblems("paywall")
            if popupUp(2) {
                closePopup(prefer: ["paywall-pass", "popup-close"])
                guard waitPopupGone(3) else { return .fail("the paywall popup did not close") }
            } else if signature().back && !before.same(signature()) {
                guard tapBack() else { return .fail("the paywall page has no Back") }
            } else { return .fail("the tap opened neither a popup nor a page (\(signature().text))") }
            if !before.same(signature(), strictText: false) { return .fail("closing changed the screen: \(before.text) -> \(signature().text)") }
            return raw.isEmpty ? .pass() : .fail(raw.joined(separator: "; "))
        }
        step("settings: Redeem a code with an invalid code shows the refusal") {
            guard openPhoneApp("Settings") else { return .skip("Settings not opened") }
            guard tapID("settings-redeem", wait: 4) else { return .skip("no Redeem a code row") }
            guard popupUp(3) else { return .fail("Redeem a code did not open a popup") }
            guard let fh = find(wait: 3, { $0.id == "redeem-code" && $0.type == .textField }) else { closePopup(); return .fail("no field redeem-code in the popup") }
            touch(fh)
            let field: XCUIElement = app.textFields["redeem-code"].firstMatch
            guard field.waitForExistence(timeout: 3) else { closePopup(); return .fail("the field cannot be typed in") }
            field.typeText("ZZZZ-0000-0000-0000")
            pause(0.4)
            var problems: [String] = []
            if case .fail(let m) = primaryInView("redeem-code-action", wait: 1) { problems.append("with the keyboard up: " + m) }
            if !tapEnabled("redeem-code-action", wait: 1) { field.typeText("\n") }
            pause(0.8)
            let seen: Bool = allTexts().contains { $0.text.localizedCaseInsensitiveContains("not valid") }
            let raw: [String] = rawProblems("redeem popup")
            closePopup()
            _ = waitPopupGone(3)
            if !seen { return .fail("typed an invalid code but no 'not valid' refusal appeared") }
            problems.append(contentsOf: raw)
            return problems.isEmpty ? .pass() : .fail(problems.joined(separator: "; "))
        }
        roundTrip("luxury: item sheet closes and keeps the showroom", prepare: { openPhoneApp("Luxury") }) { tapPrefix("luxury-inspect-", wait: 4) || tapID("luxury-hero", wait: 2) }
        roundTrip("market: open a listing -> deal popup closes and keeps the listing", prepare: { openPhoneApp("Marketplace") && tapPrefix("mk-listing-", wait: 5) }) { tapID("mk-discuss", wait: 3) }
        roundTrip("settings: Wardrobe popup closes and keeps Settings", prepare: { openPhoneApp("Settings") }) { tapID("settings-wardrobe", wait: 4) }
        step("settings: the custom tab can be chosen from Settings") {
            guard openPhoneApp("Settings"), tapID("settings-custom-tab", wait: 4) else { return .skip("no settings-custom-tab row") }
            if popupUp(2) { let raw = rawProblems("custom tab picker"); closePopup(); return waitPopupGone(3) ? (raw.isEmpty ? .pass("popup") : .fail(raw.joined(separator: "; "))) : .fail("the picker did not close") }
            let h: R = health("custom tab picker")
            _ = tapBack()
            return h
        }
        step("news: the business paper link opens and Back returns") {
            guard openPhoneApp("News"), tapID("news-paper-link", wait: 4) else { return .skip("no paper link") }
            let h: R = health("news paper")
            guard tapBack() else { return .fail("no Back on the paper") }
            return h
        }
        step("weather: city switcher opens and closes") {
            guard openPhoneApp("Weather"), tapID("weather-city-switcher", wait: 4) else { return .skip("no city switcher") }
            if popupUp(2) { closePopup(); return waitPopupGone(3) ? .pass("popup") : .fail("did not close") }
            return .pass("in place: \(signature().text)")
        }
    }
}
