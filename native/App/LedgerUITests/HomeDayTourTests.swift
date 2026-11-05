import XCTest

/// Tour (pictures 120 and up): the Home command centre, Next day with its progress state and day chip, the shortcut
/// editor, the Inbox detail, a swipe back and a swipe between segments. Everything is optional: a control that is not on screen is
/// noted and skipped, never failed. One short test so it fits the per-test time limit.
final class HomeDayTourTests: TourCase {
    func testHomeNextDayInboxAndSwipes() {
        XCTAssertTrue(waitForHome(), "the Home summary shows")
        shot("120-home-command-centre")

        // Shortcut editor: reached with the context action on a box.
        let box = app.buttons["home-bank"]
        if box.waitForExistence(timeout: 3) {
            box.press(forDuration: 1.0)
            let edit = app.buttons["Edit shortcuts"]
            if edit.waitForExistence(timeout: 2) { edit.tap(); sleep(1); shot("121-home-shortcut-editor"); app.buttons["Done"].firstMatch.tap() } else { note("no edit shortcuts menu") }
        } else { note("no bank shortcut box") }

        // Next day: the button shows progress, then the day chip appears beside the week bar.
        let next = app.buttons["next-day"]
        if next.waitForExistence(timeout: 3) {
            next.tap()
            shot("122-next-day-running")
            sleep(2)
            shot("123-next-day-chip")
            // A report sheet or a reward popup may be waiting: read it with one tap.
            let cont = app.buttons["report-continue"]
            if cont.waitForExistence(timeout: 2) { shot("124-report-sheet"); cont.tap() }
            let nice = app.buttons["celebration-dismiss"]
            if nice.waitForExistence(timeout: 2) { shot("125-reward-popup"); nice.tap() }
        } else { note("no next day button") }

        // Inbox from the priorities footer, then a swipe back from the left edge.
        let inbox = app.buttons["home-open-inbox"]
        if inbox.waitForExistence(timeout: 3) {
            inbox.tap(); sleep(1)
            shot("126-inbox")
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: end)
            sleep(1)
            shot("127-after-swipe-back")
        } else { note("no inbox footer link: nothing is waiting") }
    }
}
