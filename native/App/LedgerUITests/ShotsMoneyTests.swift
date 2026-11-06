import XCTest

/// Screenshots of every Money screen (Phone home, Bank, Accounting, new company, Stats, Goals, World, Settings and the rest).
/// A missing control is noted and the walk goes on; nothing here fails the run.
final class ShotsMoneyTests: FeatureTourCase {

    /// Attaches the screen as "Money-<name>" and records a step so the tours workflow counts the run.
    private func snap(_ name: String) {
        pause(0.5)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "Money-\(name)"
        a.lifetime = .keepAlways
        add(a)
        log.record(.pass, "Money-\(name)", "")
    }

    /// Top of the screen, then one page further down.
    private func snapScroll(_ name: String) {
        snap(name)
        dragPage(-520)
        snap(name + "-more")
        dragPage(900)
    }

    private func miss(_ what: String) {
        log.note("Money shots: \(what): " + tabState())
        snap("miss-" + what)
    }

    private func closeAll() {
        var n = 0
        while popupUp(0.5) && n < 4 { closePopup(); n += 1 }
    }

    private func bankTab(_ t: String) -> Bool {
        tapWhere(wait: 3) { $0.type == .button && ($0.label == t || $0.label.hasPrefix(t + ",") || $0.label.hasPrefix(t + " ")) && $0.frame.minY < self.win().minY + 320 }
    }

    private func openBank(_ acc: String) -> Bool {
        guard openPhoneApp("Bank") else { return false }
        return tapPrefix("bank-pick-\(acc)", wait: 4)
    }

    func testShots() {
        testDeadline = Date().addingTimeInterval(80 * 60)
        if goTab("Phone"), gridUp(6) { snap("phone-home") } else { miss("phone-home") }

        // Bank
        if openPhoneApp("Bank") { closeAll(); snap("bank-chooser") } else { miss("bank") }
        if openBank("personal") {
            snapScroll("bank-personal")
            for t in ["Bills", "Loans", "Deposits", "Statements"] {
                if bankTab(t) { snapScroll("bank-personal-\(t)") } else { miss("bank-tab-\(t)") }
            }
            _ = bankTab("Account")
            if tapLabel("Transfer") { snap("bank-transfer"); closeAll() } else { miss("bank-transfer") }
            if tapLabel("Deposit") { snap("bank-deposit"); closeAll() }
        } else { miss("bank-personal") }
        if openBank("personal"), bankTab("Loans"), tapID("bank-apply-loan", wait: 3) {
            snap("bank-loan-offer")
            if tapID("bank-loan-choose", wait: 4) {
                snap("bank-loan-amount")
                _ = tapID("bank-loan-chip-50%")
                if tapEnabled("bank-loan-continue") { snap("bank-loan-agreement"); dragPage(-500); snap("bank-loan-agreement-more") }
            }
            closeAll()
            for _ in 0..<4 { _ = tapBack() }
        } else { miss("bank-loan-apply") }
        if openBank("company") {
            snapScroll("bank-company")
            if bankTab("Loans") {
                snap("bank-company-loans")
                if tapWhere(wait: 2, { $0.type == .button && $0.label.localizedCaseInsensitiveContains("loan") && !$0.id.hasPrefix("bank-apply") && $0.frame.minY > self.win().minY + 250 }) {
                    snap("bank-loan-detail"); closeAll()
                }
            }
        } else { miss("bank-company") }
        if openBank("investments") {
            snapScroll("bank-investments")
            if tapWhere(wait: 4, { $0.type == .button && $0.label.contains("%") && $0.frame.minY > self.win().minY + 200 }) {
                snap("bank-asset")
                if tapLabel("Buy", wait: 3) { snap("bank-buy") }
            }
        } else { miss("bank-investments") }

        // Accounting
        if openPhoneApp("Accounting") {
            closeAll()
            snapScroll("acct-home")
            let rows: [String] = ids(prefix: "acct-row-")
            for r in rows {
                guard openPhoneApp("Accounting"), tapID(r, wait: 4) else { miss(r); continue }
                closeAll()
                snapScroll(String(r.dropFirst(4)))
                if r == "acct-row-payroll" {
                    for t in ["Employees", "Timesheets", "Run payroll"] {
                        if tapWhere(wait: 3, { $0.type == .button && ($0.label == t || $0.label.hasPrefix(t + ",")) }) { snap("payroll-\(t)") }
                    }
                }
            }
        } else { miss("accounting") }

        // New company
        if goTab("Home"), tapLabel("New company", wait: 4) {
            snapScroll("newco-trade")
            if tapWhere(wait: 4, { $0.type == .button && $0.enabled && $0.frame.minY > self.win().minY + 200 && $0.label.contains("\u{00A3}") }) {
                snap("newco-trade-picked")
                if tapWhere(wait: 2, { $0.type == .button && $0.id.hasPrefix("Continue") && $0.enabled }) {
                    snapScroll("newco-company")
                    if tapID("new-company-detail", wait: 3) { snapScroll("newco-customise"); _ = tapBack() }
                    if tapEnabled("new-company-start", wait: 3) { snapScroll("newco-review") }
                }
            }
            for _ in 0..<4 { _ = tapBack() }
        } else { miss("new-company") }

        // The other Money apps
        if openPhoneApp("Stats") {
            snapScroll("stats")
            if tapText("Activity") { snapScroll("activity"); _ = tapBack() }
            if tapText("Goals") { snapScroll("goals"); _ = tapBack() }
        } else { miss("stats") }
        if openPhoneApp("Achievements") { snapScroll("achievements") } else { miss("achievements") }
        if openPhoneApp("News") {
            snapScroll("news")
            if tapID("news-paper-link", wait: 3) { snap("news-paper"); _ = tapBack() }
        } else { miss("news") }
        if openPhoneApp("Rich list") { snapScroll("richlist") } else { miss("richlist") }
        if openPhoneApp("World") {
            snapScroll("world")
            for p in ["Around you", "Biggest companies", "Records"] {
                if tapText(p, wait: 2) { snapScroll("world-\(p.replacingOccurrences(of: " ", with: "-"))"); _ = tapBack() }
            }
        } else { miss("world") }
        if openPhoneApp("Weather") { snapScroll("weather") } else { miss("weather") }
        if openPhoneApp("Settings") {
            snapScroll("settings")
            if tapText("Save slots", wait: 3) { snapScroll("save-slots"); _ = tapBack() }
        } else { miss("settings") }
    }
}
