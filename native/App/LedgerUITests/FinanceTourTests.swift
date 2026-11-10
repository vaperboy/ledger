import XCTest

class FinanceTourCase: TourCase {
    func goBack() {
        let round = app.buttons["back-button"]
        if round.exists && round.isHittable { round.tap(); sleep(1); return }
        let bars = app.navigationBars
        for i in 0..<bars.count {
            let b = bars.element(boundBy: i).buttons.element(boundBy: 0)
            if b.exists && b.isHittable { b.tap(); sleep(1); return }
        }
    }

    @discardableResult
    func openPhoneApp(_ name: String) -> Bool {
        _ = waitForHome()
        let pill = app.buttons["tab-Phone"]
        if pill.waitForExistence(timeout: 5) { pill.tap() }
        let icon = app.buttons["phone-app-\(name)"]
        guard icon.waitForExistence(timeout: 5) else { note("no Phone app \(name)"); return false }
        icon.tap()
        sleep(1)
        return true
    }

    @discardableResult
    func tapID(_ id: String, wait: TimeInterval = 3) -> Bool {
        let b = app.buttons[id]
        if b.waitForExistence(timeout: wait) && b.isHittable { b.tap(); sleep(1); return true }
        note("no button \(id)")
        return false
    }

    @discardableResult
    func tapLabel(_ label: String, wait: TimeInterval = 3) -> Bool {
        let b = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        if b.waitForExistence(timeout: wait) && b.isHittable { b.tap(); sleep(1); return true }
        note("no button labelled \(label)")
        return false
    }

    @discardableResult
    func tapContaining(_ text: String, wait: TimeInterval = 3) -> Bool {
        let b = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        if b.waitForExistence(timeout: wait) && b.isHittable { b.tap(); sleep(1); return true }
        note("no button containing \(text)")
        return false
    }
}
