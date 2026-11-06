import XCTest

// Feature tours (manual CI job `ui-tours`): the helpers shared by FeatureTours*.swift.
// Nothing here asserts with XCTAssert: every check is a named `step` that records PASS, FAIL or SKIP with a one-line reason and never stops
// the tour. The result is printed between `=== TOUR RESULT ===` and `=== END TOUR RESULT ===`, and also written to the file named by the
// environment variable TOUR_OUT (CI passes it as TEST_RUNNER_TOUR_OUT) and attached to the test, so the workflow can print it.

enum TourStatus: String { case pass = "PASS", fail = "FAIL", skip = "SKIP" }

/// The outcome of one step. SKIP means "could not be reached in this game": not verified, not a failure.
enum R {
    case pass(String = "")
    case fail(String)
    case skip(String)
}

/// All results of the run, shared by every test method of the class (each test relaunches the app).
final class TourLogStore {
    static let shared = TourLogStore()
    struct Line { var status: TourStatus; var name: String; var reason: String }
    var lines: [Line] = []
    var notes: [String] = []
    var finished = false
    let path: String
    private var handle: FileHandle?

    init() {
        let env: String = ProcessInfo.processInfo.environment["TOUR_OUT"] ?? ""
        path = env.isEmpty ? NSTemporaryDirectory() + "tour-result.txt" : env
        let dir: String = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
    }

    func append(_ s: String) {
        print(s)
        if let d = (s + "\n").data(using: .utf8) { handle?.seekToEndOfFile(); handle?.write(d) }
    }

    func record(_ status: TourStatus, _ name: String, _ reason: String) {
        let one: String = reason.replacingOccurrences(of: "\n", with: " ")
        lines.append(Line(status: status, name: name, reason: one))
        append("[\(status.rawValue)] \(name)" + (one.isEmpty ? "" : " :: " + one))
    }

    func note(_ s: String) {
        notes.append(s)
        append("[NOTE] " + s)
    }

    /// The compact block: counts, every FAIL, every SKIP (not verified) and the notes.
    func summary() -> String {
        let p: Int = lines.filter { $0.status == .pass }.count
        let f: [Line] = lines.filter { $0.status == .fail }
        let s: [Line] = lines.filter { $0.status == .skip }
        var out: [String] = ["=== TOUR RESULT ==="]
        out.append("steps: \(lines.count)  pass: \(p)  fail: \(f.count)  skip: \(s.count)")
        for l in f { out.append("FAIL \(l.name) :: \(l.reason)") }
        for l in s { out.append("SKIP \(l.name) :: \(String(l.reason.prefix(100)))") }
        for n in notes.prefix(40) { out.append("NOTE \(n)") }
        out.append("=== END TOUR RESULT ===")
        return out.joined(separator: "\n")
    }

    /// Prints the block once, at the end of the class (or from the summary test, which also attaches it).
    @discardableResult
    func finish() -> String {
        let block: String = summary()
        if !finished { finished = true; append(block) }
        return block
    }
}

/// What a screen looks like for "did the popup change navigation": the header titles, whether a Back button is on screen, and which tabs
/// and company sections are selected.
struct TourSig {
    var heads: [String]
    var back: Bool
    var tabs: [String]
    var text: String {
        let headText: String = heads.joined(separator: " | ")
        let backText: String = back ? " back" : " root"
        let tabText: String = tabs.isEmpty ? "" : " sel=" + tabs.joined(separator: ",")
        return "[" + headText + "]" + backText + tabText
    }
    func same(_ o: TourSig, strictText: Bool = true) -> Bool { back == o.back && tabs == o.tabs && (!strictText || heads == o.heads) }
}

/// One element of the current screen from a single accessibility snapshot. Only elements whose frame overlaps the window are kept: the
/// tab pager keeps the other tabs alive one screen width to the side, and they must never be found or tapped.
struct Hit {
    var id: String
    var label: String
    var value: String
    var frame: CGRect
    var type: XCUIElement.ElementType
    var selected: Bool
    var enabled: Bool
    /// Inside a sideways-scrolling row (chips, tab strips): reaching past the screen edge is normal there.
    var hScroll: Bool
    var name: String { id.isEmpty ? "'\(label.prefix(30))'" : id }
    var tappable: Bool { [.button, .cell, .link, .switch, .textField, .slider, .image, .staticText, .other].contains(type) }
}

class FeatureTourCase: XCTestCase {
    var app: XCUIApplication!
    let log = TourLogStore.shared
    /// The screen just before the last tap of `driveUntilPopup` (the screen a popup belongs to).
    var lastBefore: TourSig?
    /// While a round trip opens its popup, every tap notes the screen just before it (scrolling to the trigger changes the screen).
    var noteBefore = false
    /// Time caps: one test method may spend 8 minutes, the whole run (one CI shard) 60 minutes; later steps are recorded as SKIP at once.
    static let runStart: Date = Date()
    var testDeadline: Date = Date().addingTimeInterval(720)
    /// The window frame, read once per test.
    var winCache: CGRect = .zero
    /// Buttons this test tapped that are smaller than 44 x 44 pt (name -> size), checked once at the end of the test.
    var smallTargets: [String: String] = [:]
    var tappedTargets: Set<String> = []
    /// Text in the accessibility tree with a zero-size frame (laid out but invisible), seen by any snapshot of this test.
    var zeroTexts: Set<String> = []
    static var zeroReported: Set<String> = []

    /// Every id that is only on a popup. A popup is up when any of them is on screen (GamePopup and CenterSheet are modal: the screen under
    /// them is hidden from the accessibility tree, so these are the ones that remain).
    static let popupIDs: [String] = ["popup-backdrop", "popup-close", "confirm-go", "confirm-cancel", "report-continue", "report-open", "celebration-dismiss",
                                     "celebration-claim", "celebration-next-goal", "alert-continue", "error-ok", "notice-ok", "unlock-skip", "unlock-go", "ambition-later",
                                     "conversion-keep", "paywall-buy", "paywall-pass"]
    static let closeIDs: [String] = ["popup-close", "confirm-cancel", "report-continue", "celebration-dismiss", "celebration-claim", "celebration-next-goal", "alert-continue", "error-ok",
                                     "notice-ok", "unlock-skip", "ambition-later", "conversion-keep", "paywall-pass"]

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        testDeadline = Date().addingTimeInterval(720)
        winCache = .zero
        smallTargets = [:]
        tappedTargets = []
        app = XCUIApplication()
        app.launchArguments = ["-showcase", "-showcase-rich", "-showcase-board"]
        app.launch()
        // The ambition popup at the start of a game covers Home until it is answered.
        let end: Date = Date().addingTimeInterval(30)
        var home = false
        while Date() < end && !home {
            let later: XCUIElement = app.buttons["ambition-later"].firstMatch
            if later.exists { ctap(later); pause(1) } else if popupUp() { closePopup() }
            // A popup over Home hides 'Net worth': close up to ~10 popups first, and only check Home once none is up.
            var closes = 0
            while closes < 10 && popupUp(1) { closePopup(); closes += 1 }
            if !popupUp() { _ = goTab("Home") }
            home = !popupUp() && homeVisible(3)
        }
        if !home {
            if popupUp() { popupDiag("launch"); log.record(.skip, "launch: Home summary visible", "a popup still covers Home after closing up to 10") }
            else { log.record(.fail, "launch: Home summary visible", "no 'Net worth' text 30 s after launch") }
        }
    }

    /// One step per tour: every button it tapped is at least 44 x 44 pt (Apple's minimum touch target).
    override func tearDown() {
        let tour: String = String(name.split(separator: " ").last?.dropLast() ?? "tour")
        if !tappedTargets.isEmpty {
            let small: [String] = smallTargets.keys.sorted().map { "\($0) \(smallTargets[$0] ?? "")" }
            if small.isEmpty { log.record(.pass, "tap targets \(tour): all \(tappedTargets.count) tapped buttons are 44 pt or more", "") }
            else { log.record(.fail, "tap targets \(tour): \(small.count) of \(tappedTargets.count) tapped buttons under 44 pt", small.prefix(12).joined(separator: "; ")) }
        }
        super.tearDown()
    }

    override class func tearDown() {
        TourLogStore.shared.finish()
        super.tearDown()
    }

    // MARK: Steps

    func step(_ name: String, _ body: () -> R) {
        if Date() > testDeadline || Date().timeIntervalSince(Self.runStart) > 70 * 60 {
            log.record(.skip, name, "time cap reached (12 min per test / 70 min per shard)")
            return
        }
        let t0: Date = Date()
        let r: R = body()
        let took: String = " [\(Int(Date().timeIntervalSince(t0)))s]"
        // The screen the step ended on, kept in the result bundle (the workflow exports them as tour-shots).
        let shot: XCTAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        let tour: String = String(self.name.split(separator: " ").last?.dropLast() ?? "tour")
        shot.name = "\(tour)-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
        switch r {
        case .pass(let m): log.record(.pass, name, m + took)
        case .fail(let m): log.record(.fail, name, m + took)
        case .skip(let m): log.record(.skip, name, m + took)
        }
    }

    func pause(_ s: Double = 0.6) { Thread.sleep(forTimeInterval: s) }

    // MARK: Finding and tapping

    /// Home's root is showing. A report that comes up on arriving at Home is read and closed first (it hides the page).
    func homeVisible(_ t: TimeInterval = 8) -> Bool {
        var n = 0
        while n < 3 && popupUp(n == 0 ? 0.5 : 1) { closePopup(prefer: ["report-continue"]); n += 1 }
        return find(wait: t) { $0.id == "home-companies-box" || $0.label == "Net worth" || $0.label == "NET WORTH" || $0.id == "next-day" } != nil
    }

    func elem(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    func button(_ id: String) -> XCUIElement { app.buttons[id].firstMatch }
    func buttonContaining(_ text: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch }
    func buttonPrefix(_ idPrefix: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", idPrefix)).firstMatch }

    /// The screen area of the app: the application frame (windows.firstMatch can be a small helper window, not the main one).
    func win() -> CGRect {
        if winCache.width < 200 {
            let a: CGRect = app.frame
            if a.width >= 200 { winCache = a }
            else { winCache = app.windows.allElementsBoundByIndex.map { $0.frame }.max { $0.width * $0.height < $1.width * $1.height } ?? .zero }
        }
        return winCache.width < 200 ? CGRect(x: 0, y: 0, width: 402, height: 874) : winCache
    }

    /// On screen: exists with a frame that overlaps the window (a tab kept alive to the side does not count).
    func visible(_ e: XCUIElement) -> Bool {
        guard e.exists else { return false }
        let f: CGRect = e.frame
        if f.isEmpty || f.width < 1 || f.height < 1 || f.isNull || f.isInfinite { return false }
        let r: CGRect = f.intersection(win())
        return !r.isNull && r.width >= 1 && r.height >= 1
    }

    /// Taps by coordinate (never e.tap(): its AX scroll-to-visible fails on floating tab bar buttons). Never throws or aborts the flow.
    @discardableResult
    func ctap(_ e: XCUIElement) -> Bool {
        guard visible(e) else { return false }
        e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    // MARK: Snapshot finding (one accessibility snapshot per look, only what is on the screen)

    /// Every element whose frame overlaps the window, in tree order.
    func hits() -> [Hit] {
        guard let snap = try? app.snapshot() else { return [] }
        let w: CGRect = win()
        var out: [Hit] = []
        func visit(_ n: XCUIElementSnapshot, _ inH: Bool) {
            let f: CGRect = n.frame
            var h: Bool = inH
            if n.elementType == .scrollView || n.elementType == .collectionView || n.elementType == .table {
                if n.children.contains(where: { (c: XCUIElementSnapshot) -> Bool in c.frame.maxX > f.maxX + 2 || c.frame.minX < f.minX - 2 }) { h = true }
            }
            if n.elementType == .staticText, !n.label.isEmpty, f.isNull || f.width < 1 || f.height < 1 { zeroTexts.insert(String(n.label.prefix(40))) }
            if !f.isNull, !f.isInfinite, f.width >= 1, f.height >= 1, f.maxX > w.minX + 1, f.minX < w.maxX - 1, f.maxY > w.minY, f.minY < w.maxY {
                out.append(Hit(id: n.identifier, label: n.label, value: (n.value as? String) ?? "", frame: f, type: n.elementType,
                               selected: n.isSelected, enabled: n.isEnabled, hScroll: h))
            }
            for c in n.children { visit(c, h) }
        }
        visit(snap, false)
        return out
    }

    /// The band where a tap lands on the page: under the status bar, above the floating tab bar (or the home indicator).
    func band(_ hs: [Hit]) -> (top: CGFloat, bottom: CGFloat) {
        let w: CGRect = win()
        let bar: CGFloat = hs.filter { $0.id.hasPrefix("tab-") && $0.type == .button }.map { $0.frame.minY }.min() ?? (w.maxY - 24)
        return (w.minY + 52, min(bar, w.maxY - 24) - 2)
    }

    /// The first on-screen element matching `pred` (buttons first, then the one inside the tap band), polling up to `wait` seconds.
    func find(wait: TimeInterval = 0, _ pred: (Hit) -> Bool) -> Hit? {
        let end: Date = Date().addingTimeInterval(wait)
        repeat {
            let hs: [Hit] = hits()
            let all: [Hit] = hs.filter(pred)
            if !all.isEmpty {
                let b = band(hs)
                let ranked: [Hit] = all.sorted { (a: Hit, c: Hit) -> Bool in
                    let ai: Bool = a.frame.midY >= b.top && a.frame.midY <= b.bottom, ci: Bool = c.frame.midY >= b.top && c.frame.midY <= b.bottom
                    if ai != ci { return ai }
                    let ab: Bool = a.type == .button, cb: Bool = c.type == .button
                    if ab != cb { return ab }
                    return false
                }
                return ranked[0]
            }
            if Date() >= end { break }
            pause(0.4)
        } while true
        return nil
    }

    func has(_ id: String, wait: TimeInterval = 0) -> Bool { find(wait: wait) { $0.id == id } != nil }
    func hit(_ id: String, wait: TimeInterval = 0) -> Hit? { find(wait: wait) { $0.id == id } }
    func isSelected(_ id: String) -> Bool { find { $0.id == id && $0.type == .button }?.selected ?? false }
    func onScreenText(_ s: String) -> Bool { find { $0.label.localizedCaseInsensitiveContains(s) || $0.value.localizedCaseInsensitiveContains(s) } != nil }

    /// Drags the page (no fling) by `dy` points: negative moves the content up (shows what is below).
    func dragPage(_ dy: CGFloat, x: CGFloat? = nil) {
        let w: CGRect = win()
        let from: CGFloat = dy < 0 ? w.minY + w.height * 0.68 : w.minY + w.height * 0.32
        let o: XCUICoordinate = app.coordinate(withNormalizedOffset: .zero)
        let start: XCUICoordinate = o.withOffset(CGVector(dx: x ?? w.midX, dy: from))
        let stop: XCUICoordinate = o.withOffset(CGVector(dx: x ?? w.midX, dy: from + dy))
        start.press(forDuration: 0.05, thenDragTo: stop, withVelocity: .slow, thenHoldForDuration: 0.15)
        pause(0.4)
    }

    /// Brings the first match into the tap band by dragging the page (down first, then up), and returns it as it is now.
    func bringIn(_ pred: (Hit) -> Bool, wait: TimeInterval = 3) -> Hit? {
        guard var h = find(wait: wait, pred) else { return nil }
        var tries = 0
        while tries < 8 {
            let b = band(hits())
            if h.frame.midY >= b.top && h.frame.midY <= b.bottom { return h }
            let dy: CGFloat = h.frame.midY > b.bottom ? -min(300, h.frame.midY - b.bottom + 80) : min(300, b.top - h.frame.midY + 80)
            dragPage(dy, x: max(win().minX + 30, min(win().maxX - 30, h.frame.midX)))
            guard let again = find(wait: 1, pred) else { return nil }
            h = again
            tries += 1
        }
        return nil
    }

    /// A toast lying over the target is swiped away first (it would take the tap).
    func clearBanner(over f: CGRect) {
        for _ in 0..<2 {
            guard let b = find({ $0.id == "notification-banner" }), b.frame.intersects(f.insetBy(dx: -4, dy: -4)) else { return }
            let o: XCUICoordinate = app.coordinate(withNormalizedOffset: .zero)
            o.withOffset(CGVector(dx: b.frame.midX, dy: b.frame.midY)).press(forDuration: 0.05, thenDragTo: o.withOffset(CGVector(dx: b.frame.midX, dy: b.frame.minY - 160)))
            pause(0.8)
        }
    }

    /// Taps the middle of the visible part of `h`; buttons are measured for the 44 pt check.
    @discardableResult
    func touch(_ h: Hit) -> Bool {
        let r: CGRect = h.frame.intersection(win())
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return false }
        if h.type == .button || h.type == .cell {
            let key: String = h.name
            tappedTargets.insert(key)
            if h.frame.width < 43.5 || h.frame.height < 43.5 { smallTargets[key] = "\(Int(h.frame.width))x\(Int(h.frame.height))" }
        }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: r.midX, dy: r.midY)).tap()
        pause(0.7)
        return true
    }

    /// Finds, scrolls into the tap band, clears a toast over it, then taps. False when it is not on this screen.
    @discardableResult
    func tapWhere(wait: TimeInterval = 3, _ pred: (Hit) -> Bool) -> Bool {
        guard let h = bringIn(pred, wait: wait) else { return false }
        clearBanner(over: h.frame)
        guard let now = find(pred) else { return false }
        if noteBefore { lastBefore = signature() }
        return touch(now)
    }

    @discardableResult
    func tap(_ e: XCUIElement, wait: TimeInterval = 3) -> Bool {
        guard e.waitForExistence(timeout: wait) else { return false }
        let id: String = e.identifier, label: String = e.label
        if !id.isEmpty { return tapWhere(wait: 1) { $0.id == id } }
        return tapWhere(wait: 1) { $0.label == label && ($0.type == .button || $0.type == .cell) }
    }

    @discardableResult func tapID(_ id: String, wait: TimeInterval = 3) -> Bool { tapWhere(wait: wait) { $0.id == id } }
    @discardableResult func tapText(_ text: String, wait: TimeInterval = 3) -> Bool {
        tapWhere(wait: wait) { ($0.type == .button || $0.type == .cell) && $0.label.localizedCaseInsensitiveContains(text) }
    }
    @discardableResult func tapLabel(_ prefix: String, wait: TimeInterval = 3) -> Bool {
        tapWhere(wait: wait) { ($0.type == .button || $0.type == .cell) && $0.label.hasPrefix(prefix) }
    }
    /// Taps a button only when it is enabled (a blocked primary action is reported, not tapped).
    @discardableResult func tapEnabled(_ id: String, wait: TimeInterval = 3) -> Bool { tapWhere(wait: wait) { $0.id == id && $0.type == .button && $0.enabled } }
    @discardableResult func tapPrefix(_ p: String, wait: TimeInterval = 3) -> Bool { tapWhere(wait: wait) { $0.id.hasPrefix(p) && $0.type == .button } }

    func ids(prefix: String, wait: TimeInterval = 3) -> [String] {
        _ = find(wait: wait) { $0.id.hasPrefix(prefix) }
        var out: [String] = []
        for h in hits() where h.id.hasPrefix(prefix) && h.type == .button && !out.contains(h.id) { out.append(h.id) }
        return out
    }

    /// The primary action is on screen without scrolling: inside the tap band and fully inside the window.
    func primaryInView(_ id: String, wait: TimeInterval = 3) -> R {
        guard let h = find(wait: wait, { $0.id == id || $0.id == id + "-blocked" }) else { return .fail("no \(id) on the screen") }
        let b = band(hits())
        if h.frame.minY < b.top - 8 || h.frame.maxY > b.bottom + 2 { return .fail("\(id) is off the visible area without scrolling (y \(Int(h.frame.minY))-\(Int(h.frame.maxY)), band \(Int(b.top))-\(Int(b.bottom)))") }
        return .pass(h.id.hasSuffix("-blocked") ? "shown, blocked with its reason" : "")
    }

    // MARK: Popups

    var popupElement: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", Self.popupIDs)).firstMatch
    }

    /// Cheap check: one button query, plus the backdrop.
    func popupUp(_ wait: TimeInterval = 0) -> Bool {
        let b: XCUIElement = app.buttons.matching(NSPredicate(format: "identifier IN %@", Self.popupIDs)).firstMatch
        if wait > 0 { return b.waitForExistence(timeout: wait) || popupElement.exists }
        return b.exists || app.otherElements["popup-backdrop"].exists
    }

    var diagCount = 0
    /// Diagnostic (max 8 per run): which popup ids are on screen with their frames.
    func popupDiag(_ why: String) {
        guard diagCount < 8 else { return }
        diagCount += 1
        let found: [String] = Self.popupIDs.compactMap { (id: String) -> String? in
            let e: XCUIElement = elem(id)
            return e.exists ? "\(id)@\(Int(e.frame.minX)),\(Int(e.frame.minY)),\(Int(e.frame.width))x\(Int(e.frame.height))" : nil
        }
        log.note("popup diag (\(why)): " + found.joined(separator: " "))
    }

    func waitPopupGone(_ t: TimeInterval = 3) -> Bool {
        let end: Date = Date().addingTimeInterval(t)
        while Date() < end {
            if !popupElement.exists { return true }
            pause(0.25)
        }
        return !popupElement.exists
    }

    /// Closes the popup on top with its own button (`prefer` first), else by tapping the dimmed area above the card.
    func closePopup(prefer: [String] = []) {
        let ids: [String] = prefer + Self.closeIDs
        func tapFirst() -> Bool {
            for id in prefer where ctap(button(id)) { return true }
            // One query for all close ids (tap order = tree order).
            let q: XCUIElementQuery = app.buttons.matching(NSPredicate(format: "identifier IN %@", ids))
            return ctap(q.firstMatch)
        }
        if tapFirst() { pause(0.6); return }
        // The card can be taller than the screen (the week report keeps Continue at the end of its scrolling content): scroll inside it.
        for _ in 0..<3 {
            let from: XCUICoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let to: XCUICoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            from.press(forDuration: 0.1, thenDragTo: to)
            if tapFirst() { pause(0.6); return }
        }
        // A popup whose buttons carry no id: tap one by its label, else the dimmed area (the backdrop's own top edge, then the screen top).
        let labels: [String] = ["Continue", "OK", "Done", "Close", "Got it", "Not now", "Later", "Cancel", "Dismiss", "Skip", "No thanks", "Keep", "Next"]
        for l in labels {
            let b: XCUIElement = app.buttons.matching(NSPredicate(format: "label ==[c] %@", l)).firstMatch
            if ctap(b) { pause(0.6); return }
        }
        let names: String = app.buttons.allElementsBoundByIndex.prefix(12).map { "\($0.identifier)|\($0.label)" }.joined(separator: ", ")
        popupDiag("no close button tappable after scrolling; buttons: " + names)
        let bd: XCUIElement = elem("popup-backdrop")
        if bd.exists { bd.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).tap() }
        pause(0.6)
    }

    // MARK: Navigation

    /// Taps the screen's Back: the round back button, the Group entity page's back, else a system navigation bar back button.
    func tapBack() -> Bool {
        if let h = find({ ($0.id == "back-button" || $0.id == "group-back" || $0.id == "BackButton") && $0.type == .button }) {
            clearBanner(over: h.frame)
            if let now = find({ $0.id == h.id && $0.type == .button }) { touch(now); pause(0.3); return true }
        }
        let bars: XCUIElementQuery = app.navigationBars
        for i in 0..<min(bars.count, 3) {
            let b: XCUIElement = bars.element(boundBy: i).buttons.element(boundBy: 0)
            if ctap(b) { pause(0.8); return true }
        }
        return false
    }

    /// Closes popups and pops pushed screens until a root screen is showing.
    func toRoot() {
        for _ in 0..<8 {
            if popupUp() { closePopup(); continue }
            if !tapBack() { break }
        }
    }

    /// Diagnostic: every tab button with its selected flag and frame, and the first button ids on screen.
    func tabState() -> String {
        let hs: [Hit] = hits()
        let tabs: String = hs.filter { $0.id.hasPrefix("tab-") && $0.type == .button }.map { "\($0.id)\($0.selected ? "*" : "")" }.joined(separator: " ")
        let others: [String] = hs.filter { $0.type == .button && !$0.id.hasPrefix("tab-") }.prefix(30).map { $0.name }
        return "tabs: \(tabs); buttons: \(others.joined(separator: ","))"
    }

    func tabIDs() -> [String] { ids(prefix: "tab-") }

    /// Opens a tab at its root (re-selecting a tab pops it to its root).
    @discardableResult
    func goTab(_ title: String) -> Bool {
        var n = 0
        while popupUp() && n < 4 { closePopup(); n += 1 }
        guard let t = find(wait: 4, { $0.id == "tab-\(title)" && $0.type == .button }) else { return false }
        touch(t)
        pause(0.5)
        if !(find({ $0.id == "tab-\(title)" && $0.type == .button })?.selected ?? false), let again = find({ $0.id == "tab-\(title)" && $0.type == .button }) { touch(again); pause(0.5) }
        return true
    }

    /// True while the Phone app grid is on screen (any launcher tile).
    func gridUp(_ t: TimeInterval = 0) -> Bool { find(wait: t) { $0.id.hasPrefix("phone-app-") && $0.type == .button } != nil }

    /// Why the last openPhoneApp failed: "hidden" = the grid is up but has no such tile (the unlock ladder keeps it off the Phone).
    var lastOpenWhy: String = ""

    /// Opens an app of the Phone tab; true when its tile was found and tapped.
    @discardableResult
    func openPhoneApp(_ name: String) -> Bool {
        lastOpenWhy = ""
        guard goTab("Phone") else { lastOpenWhy = "no Phone tab"; return false }
        guard gridUp(6) else { lastOpenWhy = "grid not shown"; log.note("phone grid not shown: " + tabState()); return false }
        let pred: (Hit) -> Bool = { $0.id == "phone-app-\(name)" && $0.type == .button }
        guard let tile = bringIn(pred, wait: 1.5) else {
            // Not on the Phone yet (the unlock ladder): the Pick tab can hold any app, so open it there.
            if openViaPickTab(name) { lastOpenWhy = "pick"; return true }
            lastOpenWhy = "hidden"
            log.note("no tile \(name) on the grid and not in the Pick tab picker: tiles=" + ids(prefix: "phone-app-", wait: 0).map { String($0.dropFirst(10)) }.joined(separator: ","))
            return false
        }
        if !tile.enabled { lastOpenWhy = "hidden"; return false }
        touch(tile)
        pause(0.8)
        return true
    }

    /// The fourth tab is the Pick tab; its title is the app it holds ("Pick tab" while empty).
    func customTab() -> Hit? {
        let tabs: [Hit] = hits().filter { $0.id.hasPrefix("tab-") && $0.type == .button }.sorted { $0.frame.minX < $1.frame.minX }
        return tabs.count == 5 ? tabs[3] : nil
    }

    /// Puts `name` in the Pick tab and shows it at its root. True when the app is showing.
    func openViaPickTab(_ name: String) -> Bool {
        var n = 0
        while popupUp() && n < 3 { closePopup(); n += 1 }
        if let t = find({ $0.id == "tab-\(name)" && $0.type == .button }) {
            touch(t); pause(0.5)
            if !(find({ $0.id == "tab-\(name)" && $0.type == .button })?.selected ?? false), let a = find({ $0.id == "tab-\(name)" && $0.type == .button }) { touch(a) }
            return true
        }
        guard let tab = customTab() else { return false }
        touch(tab)
        pause(0.6)
        if find(wait: 1.5, { $0.id == "custom-pick-\(name)" }) == nil, let t2 = customTab() {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: t2.frame.midX, dy: t2.frame.midY)).press(forDuration: 1.2)
            pause(0.8)
        }
        guard tapWhere(wait: 3, { $0.id == "custom-pick-\(name)" }) else { while popupUp() && n < 6 { closePopup(); n += 1 }; return false }
        pause(0.8)
        while popupUp(0.5) && n < 6 { closePopup(); n += 1 }
        return find(wait: 2, { $0.id == "tab-\(name)" && $0.type == .button }) != nil
    }

    static var companyMisses = 0

    /// Opens a company from the Home list by its trade word (rows read "Name, Trade · City ...").
    @discardableResult
    func openCompany(_ part: String) -> Bool {
        if Self.companyMisses >= 3 { return false }
        guard goTab("Home") else { return false }
        let words: [String] = [part] + (part.hasPrefix("Caf") ? ["Café", "Cafe", "Coffee"] : []) + (part.hasPrefix("Gym") ? ["Fitness"] : [])
        _ = find(wait: 4) { $0.id == "home-companies-box" }
        for w in words {
            let pred: (Hit) -> Bool = { ($0.type == .button || $0.type == .cell) && $0.label.range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) != nil && !$0.id.hasPrefix("home-") && !$0.id.hasPrefix("tab-") }
            if tapWhere(wait: 1.5, pred) {
                if find(wait: 4, { $0.id == "company-tab-overview" }) != nil { return true }
                _ = tapBack()
            }
        }
        Self.companyMisses += 1
        let rows: [String] = hits().filter { $0.type == .button && $0.label.contains("\u{00B7}") }.prefix(6).map { String($0.label.prefix(60)) }
        log.note("no company row \(part): buttons with a dot: \(rows)")
        return false
    }

    func swipeBackFromEdge() {
        let w: CGRect = win()
        let o: XCUICoordinate = app.coordinate(withNormalizedOffset: .zero)
        let start: XCUICoordinate = o.withOffset(CGVector(dx: w.minX + 3, dy: w.midY))
        let end: XCUICoordinate = o.withOffset(CGVector(dx: w.minX + w.width * 0.85, dy: w.midY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0)
        pause(1)
    }

    // MARK: Snapshot helpers

    func walk(_ s: XCUIElementSnapshot, _ f: (XCUIElementSnapshot) -> Bool) {
        if !f(s) { return }
        for c in s.children { walk(c, f) }
    }

    static let clockText: NSRegularExpression? = try? NSRegularExpression(pattern: "^[0-9]{1,2}[:.][0-9]{2}( ?[AaPp]\\.?[Mm]\\.?)?$")

    func signature() -> TourSig {
        let hs: [Hit] = hits()
        let w: CGRect = win()
        var heads: Set<String> = []
        var back = false
        var tabs: [String] = []
        for s in hs {
            if (s.id == "back-button" || s.id == "group-back" || s.id == "BackButton") && s.type == .button { back = true }
            if (s.id.hasPrefix("tab-") || s.id.hasPrefix("company-tab-") || s.id.hasPrefix("group-tab-")) && s.type == .button && s.selected { tabs.append(s.id) }
            if s.id.hasPrefix("tab-") || s.id == "notification-banner" { continue }
            if (s.type == .staticText || s.type == .other), !s.label.isEmpty, s.frame.minY >= w.minY + 50, s.frame.maxY < w.minY + 190, s.frame.height < 90 {
                let t: String = s.label.components(separatedBy: ", ")[0]
                let ns: NSString = t as NSString
                if let c = Self.clockText, c.firstMatch(in: t, options: [], range: NSRange(location: 0, length: ns.length)) != nil { continue }
                heads.insert(t)
            }
        }
        return TourSig(heads: heads.sorted(), back: back, tabs: Array(Set(tabs)).sorted())
    }

    /// All the text on screen (labels, string values), on this page only.
    func allTexts() -> [(text: String, id: String)] {
        var out: [(text: String, id: String)] = []
        for h in hits() {
            if !h.label.isEmpty { out.append((h.label, h.id)) }
            if !h.value.isEmpty, h.value != h.label { out.append((h.value, h.id)) }
        }
        return out
    }

    func waitingNumber() -> Int? {
        for t in allTexts() {
            if let r = t.text.range(of: "[0-9]+ waiting for you", options: .regularExpression) {
                return Int(t.text[r].split(separator: " ")[0])
            }
        }
        return nil
    }

    // MARK: Health checks

    static let rawPatterns: [(name: String, regex: NSRegularExpression)] = {
        let defs: [(String, String)] = [
            ("NaN", "\\bNaN\\b"), ("inf", "(?i)(?<![A-Za-z])-?inf(inity)?(?![A-Za-z])"), ("nil", "\\bnil\\b"), ("null", "\\bnull\\b"),
            ("Optional(", "Optional\\("), ("undefined", "\\bundefined\\b"), ("format token", "%@|%ld|%lld|%d\\b|%s\\b|%\\.[0-9]f"),
            ("template braces", "\\{\\{|\\}\\}|\\$\\{"), ("debug text", "(?i)\\b(debug|lorem ipsum|TODO|FIXME)\\b"), ("infinity sign", "\u{221E}")
        ]
        return defs.compactMap { (d: (String, String)) -> (name: String, regex: NSRegularExpression)? in
            guard let r = try? NSRegularExpression(pattern: d.1) else { return nil }
            return (d.0, r)
        }
    }()

    static let zeroMoney: NSRegularExpression? = try? NSRegularExpression(pattern: "^[\u{00A3}$\u{20AC}]\\s?0([.,]0+)?$")

    /// Raw debug text, NaN / inf / nil on screen, and bare zero-money labels (reported as notes, not failures: a real zero is legal).
    func rawProblems(_ screen: String) -> [String] {
        var problems: [String] = []
        var zeros: [String] = []
        for t in allTexts() {
            let ns: NSString = t.text as NSString
            let range: NSRange = NSRange(location: 0, length: ns.length)
            if t.text.hasPrefix("Debug plan") { continue }
            for p in Self.rawPatterns where p.regex.firstMatch(in: t.text, options: [], range: range) != nil {
                let item: String = "\(p.name) in '\(String(t.text.prefix(40)))'"
                if !problems.contains(item) { problems.append(item) }
            }
            if let z = Self.zeroMoney, z.firstMatch(in: t.text, options: [], range: range) != nil { zeros.append(t.text) }
        }
        if !zeros.isEmpty { log.note("\(screen): \(zeros.count) bare zero-money label(s) \(Array(Set(zeros)).prefix(3)) (check they are real zeros)") }
        return problems
    }

    /// True when the header has a non-empty title (pushed screens, Phone apps and company screens).
    func hasTitle() -> Bool {
        let s: TourSig = signature()
        return s.heads.contains { (h: String) -> Bool in !h.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Text or a button cut by the left or right screen edge (rows that scroll sideways are left out: reaching past the edge is how they work).
    func sideClips(_ hs: [Hit]) -> [String] {
        let w: CGRect = win()
        var out: [String] = []
        for h in hs where !h.hScroll && !h.label.isEmpty && (h.type == .staticText || h.type == .button) && h.frame.width < w.width + 2 {
            if h.frame.minX < w.minX - 1 || h.frame.maxX > w.maxX + 1 {
                let item: String = "'\(h.label.prefix(24))' x \(Int(h.frame.minX))-\(Int(h.frame.maxX))"
                if !out.contains(item) { out.append(item) }
            }
        }
        return out
    }

    /// Scrolls to the end of the screen (until the lowest element stops changing) and reports content that ends under the tab bar or
    /// off the screen, and text cut by the side edges. nil when fine or when the end could not be reached.
    func clipProblem() -> String? {
        let w: CGRect = win()
        var last = ""
        var swipes = 0
        var verdict: String? = nil
        var sides: [String] = []
        while swipes < 7 {
            let hs: [Hit] = hits()
            if popupUp() { break }
            for c in sideClips(hs) where !sides.contains(c) { sides.append(c) }
            let barTop: CGFloat = hs.filter { $0.id.hasPrefix("tab-") && $0.type == .button }.map { $0.frame.minY }.min() ?? w.maxY
            var lowestMax: CGFloat = 0
            var lowestLabel = ""
            var hidden: [String] = []
            let tabFrames: [CGRect] = hs.filter { $0.id.hasPrefix("tab-") && $0.type == .button }.map { $0.frame.insetBy(dx: -4, dy: -14) }
            for h in hs where !h.id.hasPrefix("tab-") && h.id != "back-button" && h.id != "notification-banner" && !tabFrames.contains(where: { $0.intersects(h.frame) }) {
                guard h.type == .staticText || h.type == .button || h.type == .textField || h.type == .switch || h.type == .slider else { continue }
                let r: CGRect = h.frame
                guard !h.label.isEmpty, r.minY >= w.minY, r.minY < w.maxY - 1 else { continue }
                if r.minY >= barTop - 1 { hidden.append(String(h.label.prefix(30))); continue }
                if r.maxY > lowestMax { lowestMax = r.maxY; lowestLabel = h.label }
            }
            let key: String = "\(lowestLabel)@\(Int(lowestMax))#\(hidden.count)"
            if key == last {
                if !hidden.isEmpty { verdict = "\(hidden.count) element(s) end under the tab bar, e.g. '\(hidden[0])'" }
                else if lowestMax > barTop + 2 { verdict = "'\(String(lowestLabel.prefix(30)))' is cut by \(Int(lowestMax - barTop)) pt at the bottom" }
                break
            }
            last = key
            dragPage(-420)
            swipes += 1
        }
        for _ in 0..<min(4, swipes) { app.swipeDown(velocity: .fast) }
        if !sides.isEmpty { verdict = (verdict.map { $0 + "; " } ?? "") + "cut at the side: " + sides.prefix(3).joined(separator: ", ") }
        return verdict
    }

    /// Screen-level health: raw text, empty title (when expected) and a clipped bottom.
    func health(_ screen: String, title: Bool = true, clip: Bool = true) -> R {
        var problems: [String] = rawProblems(screen)
        if title && !hasTitle() { problems.append("empty header title") }
        if clip, let c = clipProblem() { problems.append(c) }
        let fresh: [String] = zeroTexts.subtracting(Self.zeroReported).sorted()
        if !fresh.isEmpty {
            Self.zeroReported.formUnion(fresh)
            log.note("\(screen): \(fresh.count) text(s) with a zero-size frame (invisible): \(fresh.prefix(5))")
        }
        return problems.isEmpty ? .pass() : .fail(problems.prefix(4).joined(separator: "; "))
    }

    // MARK: Popup round trip

    /// Opens a popup with `open` (true when the tap that should show it happened), checks it shows and its text is clean, closes it and checks
    /// the SAME screen is back (header, Back button, selected tabs). With `leavesScreen` the closing action may legitimately move on (a
    /// purchase's receipt); then only a pop back to a root screen counts as a fault.
    func roundTrip(_ name: String, closeWith: [String] = [], leavesScreen: Bool = false, strictText: Bool = true,
                   prepare: () -> Bool = { true }, open: () -> Bool) {
        step(name) {
            toastCleanup()
            guard prepare() else { return .skip("screen not reachable in this game") }
            lastBefore = nil
            let before0: TourSig = signature()
            noteBefore = true
            let opened: Bool = open()
            noteBefore = false
            guard opened else { return .skip("popup trigger not reachable in this game") }
            // driveUntilPopup notes the screen just before its last tap: the popup belongs to that screen.
            let before: TourSig = lastBefore ?? before0
            guard popupUp(3) else { return .fail("the tap worked but no popup came up (screen: \(signature().text))") }
            var problems: [String] = rawProblems(name)
            closePopup(prefer: closeWith)
            guard waitPopupGone(3) else { return .fail("the popup did not close with its button") }
            // A closing action may show a notice (Done / Something went wrong): read and close it, up to twice.
            var extra = 0
            while extra < 2, popupUp(1) { problems.append(contentsOf: rawProblems(name + " (notice)")); closePopup(); extra += 1 }
            if popupUp(1) { return .fail("a popup is still up after closing it \(extra + 1) times") }
            pause(0.5)
            let after: TourSig = signature()
            if leavesScreen {
                if before.back && !after.back { return .fail("closing the popup popped the screen to a root: \(before.text) -> \(after.text)") }
            } else if !before.same(after, strictText: strictText) {
                return .fail("closing the popup changed the screen: \(before.text) -> \(after.text)")
            }
            if !problems.isEmpty { return .fail("popup text: " + problems.prefix(3).joined(separator: "; ")) }
            return .pass(leavesScreen ? "now \(after.text)" : "")
        }
    }

    /// The notification banner is not a popup; nothing to clean, but a stuck popup from an earlier step must not leak into this one.
    func toastCleanup() {
        var n = 0
        while popupUp() && n < 3 { closePopup(); n += 1 }
    }

    /// Taps the ids in order (an entry "prefix:xyz-" matches by identifier prefix) until a popup is up or nothing is left to tap.
    func driveUntilPopup(_ steps: [String]) -> Bool {
        for s in steps {
            if popupUp() { return true }
            let pre: Bool = s.hasPrefix("prefix:")
            let key: String = pre ? String(s.dropFirst(7)) : s
            let pred: (Hit) -> Bool = { pre ? ($0.id.hasPrefix(key) && $0.type == .button) : $0.id == key }
            if let h = bringIn(pred, wait: 2) { lastBefore = signature(); clearBanner(over: h.frame); if let now = find(pred) { touch(now) }; pause(0.3) }
        }
        return popupUp(2)
    }
}
