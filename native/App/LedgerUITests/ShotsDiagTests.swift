import XCTest

/// Diagnostic: what is on screen right after a showcase launch, and whether the launch popups close by id.
final class ShotsDiagTests: XCTestCase {
    func testShots() {
        let app = XCUIApplication()
        app.launchArguments = ["-showcase", "-showcase-rich", "-showcase-board"]
        app.launch()
        sleep(4)
        func shot(_ n: String) { let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = "Diag-" + n; a.lifetime = .keepAlways; add(a) }
        shot("0-launch")
        print("DIAG tree:\n" + app.debugDescription.split(separator: "\n").prefix(160).joined(separator: "\n"))
        for i in 1...8 {
            let ids = ["report-continue", "celebration-dismiss", "celebration-claim", "unlock-skip", "ambition-later", "notice-ok", "alert-continue", "popup-close", "confirm-cancel"]
            var tapped = ""
            for id in ids {
                let b = app.buttons[id].firstMatch
                if b.exists { print("DIAG \(i) found \(id) frame \(b.frame) hittable \(b.isHittable)"); b.tap(); tapped = id; break }
            }
            sleep(2)
            shot("\(i)-after-\(tapped.isEmpty ? "none" : tapped)")
            if tapped.isEmpty { break }
        }
        print("DIAG end tree:\n" + app.debugDescription.split(separator: "\n").prefix(60).joined(separator: "\n"))
    }
}
