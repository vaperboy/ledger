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

class FeatureTourCase: XCTestCase {
    var app: XCUIApplication!
    let log = TourLogStore.shared
    /// The screen just before the last tap of `driveUntilPopup` (the screen a popup belongs to).
    var lastBefore: TourSig?
    /// Time caps: one test method may spend 5 minutes, the whole run 62 minutes (CI limit 90); later steps are recorded as SKIP at once.
    static let runStart: Date = Date()
    var testDeadline: Date = Date().addingTimeInterval(300)

    /// Every id that is only on a popup. A popup is up when any of them is on screen (GamePopup and CenterSheet are modal: the screen under
    /// them is hidden from the accessibility tree, so these are the ones that remain).
    static let popupIDs: [String] = ["popup-backdrop", "popup-close", "confirm-go", "confirm-cancel", "report-continue", "report-open", "celebration-dismiss",
                                     "celebration-claim", "alert-continue", "error-ok", "notice-ok", "unlock-skip", "unlock-go", "ambition-later",
                                     "conversion-keep", "paywall-buy", "paywall-pass"]
    static let closeIDs: [String] = ["popup-close", "confirm-cancel", "report-continue", "celebration-dismiss", "alert-continue", "error-ok",
                                     "notice-ok", "unlock-skip", "ambition-later", "conversion-keep", "paywall-pass"]

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        testDeadline = Date().addingTimeInterval(300)
        app = XCUIApplication()
        app.launchArguments = ["-showcase", "-showcase-rich", "-showcase-board"]
        app.launch()
        // The ambition popup at the start of a game covers Home until it is answered.
        let end: Date = Date().addingTimeInterval(30)
        var home = false
        while Date() < end && !home {
            let later: XCUIElement = app.buttons["ambition-later"].firstMatch
            if later.exists { ctap(later); pause(1) } else if popupUp() { closePopup() }
            home = homeVisible(2) && !popupUp()
        }
        if !home { log.record(.fail, "launch: Home summary visible", "no 'Net worth' text 30 s after launch") }
    }

    override class func tearDown() {
        TourLogStore.shared.finish()
        super.tearDown()
    }

    // MARK: Steps

    func step(_ name: String, _ body: () -> R) {
        if Date() > testDeadline || Date().timeIntervalSince(Self.runStart) > 62 * 60 {
            log.record(.skip, name, "time cap reached (5 min per test / 62 min total)")
            return
        }
        let t0: Date = Date()
        let r: R = body()
        let took: String = " [\(Int(Date().timeIntervalSince(t0)))s]"
        switch r {
        case .pass(let m): log.record(.pass, name, m + took)
        case .fail(let m): log.record(.fail, name, m + took)
        case .skip(let m): log.record(.skip, name, m + took)
        }
    }

    func pause(_ s: Double = 0.6) { Thread.sleep(forTimeInterval: s) }

    // MARK: Finding and tapping

    func homeVisible(_ t: TimeInterval = 8) -> Bool {
        app.staticTexts["Net worth"].firstMatch.waitForExistence(timeout: t) || app.staticTexts["NET WORTH"].firstMatch.waitForExistence(timeout: 1)
    }

    func elem(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    func button(_ id: String) -> XCUIElement { app.buttons[id].firstMatch }
    func buttonContaining(_ text: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch }
    func buttonPrefix(_ idPrefix: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", idPrefix)).firstMatch }

    /// On screen: exists with a non-empty frame inside the window (isHittable is avoided: overlay/tab-bar elements trigger AX scroll failures).
    func visible(_ e: XCUIElement) -> Bool {
        guard e.exists else { return false }
        let f: CGRect = e.frame
        let w: CGRect = app.windows.firstMatch.frame
        if f.isEmpty || f.width < 1 || f.height < 1 || f.isNull || f.isInfinite { return false }
        return w.isEmpty ? true : w.intersects(f)
    }

    /// Taps by coordinate (never e.tap(): its AX scroll-to-visible fails on floating tab bar buttons). Never throws or aborts the flow.
    @discardableResult
    func ctap(_ e: XCUIElement) -> Bool {
        guard visible(e) else { return false }
        e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    /// Scrolls (up, then down) until the element is on screen.
    func reveal(_ e: XCUIElement) -> Bool {
        if visible(e) { return true }
        for _ in 0..<4 { app.swipeUp(); if visible(e) { return true } }
        for _ in 0..<8 { app.swipeDown(); if visible(e) { return true } }
        return false
    }

    @discardableResult
    func tap(_ e: XCUIElement, wait: TimeInterval = 3) -> Bool {
        guard e.waitForExistence(timeout: wait), reveal(e) else { return false }
        guard ctap(e) else { return false }
        pause(0.7)
        return true
    }

    @discardableResult func tapID(_ id: String, wait: TimeInterval = 3) -> Bool { tap(button(id), wait: wait) }
    @discardableResult func tapText(_ text: String, wait: TimeInterval = 3) -> Bool { tap(buttonContaining(text), wait: wait) }
    @discardableResult func tapPrefix(_ p: String, wait: TimeInterval = 3) -> Bool { tap(buttonPrefix(p), wait: wait) }

    func ids(prefix: String) -> [String] {
        let q: XCUIElementQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        guard q.firstMatch.waitForExistence(timeout: 3) else { return [] }
        var out: [String] = []
        for e in q.allElementsBoundByIndex where !out.contains(e.identifier) { out.append(e.identifier) }
        return out
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
        for id in prefer + Self.closeIDs {
            let b: XCUIElement = button(id)
            if ctap(b) { pause(0.6); return }
        }
        // The card can be taller than the screen (the week report keeps Continue at the end of its scrolling content): scroll inside it.
        for _ in 0..<6 {
            let from: XCUICoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let to: XCUICoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            from.press(forDuration: 0.1, thenDragTo: to)
            for id in prefer + Self.closeIDs {
                let b: XCUIElement = button(id)
                if ctap(b) { pause(0.6); return }
            }
        }
        popupDiag("no close button tappable after scrolling")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).tap()
        pause(0.6)
    }

    // MARK: Navigation

    func tapBack() -> Bool {
        let round: XCUIElement = button("back-button")
        if ctap(round) { pause(0.8); return true }
        let bars: XCUIElementQuery = app.navigationBars
        for i in 0..<bars.count {
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
        let tabs: String = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab-'")).allElementsBoundByIndex
            .map { "\($0.identifier)\($0.isSelected ? "*" : "")@\(Int($0.frame.minX)),\(Int($0.frame.minY))" }.joined(separator: " ")
        let others: [String] = app.buttons.allElementsBoundByIndex.prefix(40).map { $0.identifier }.filter { !$0.hasPrefix("tab-") && !$0.isEmpty }
        return "tabs: \(tabs); buttons: \(others.prefix(25).joined(separator: ","))"
    }

    func tabIDs() -> [String] { ids(prefix: "tab-") }

    @discardableResult
    func goTab(_ title: String) -> Bool {
        toRoot()
        let p: XCUIElement = button("tab-\(title)")
        guard p.waitForExistence(timeout: 4) else { return false }
        guard ctap(p) else { return false }
        pause(0.9)
        return true
    }

    /// Opens an app of the Phone tab; true when its tile was found and tapped.
    @discardableResult
    func openPhoneApp(_ name: String) -> Bool {
        guard goTab("Phone") else { return false }
        let tile: XCUIElement = button("phone-app-\(name)")
        guard tap(tile, wait: 5) else { log.note("no tile \(name): " + tabState()); return false }
        pause(0.6)
        return true
    }

    @discardableResult
    func openCompany(_ part: String) -> Bool {
        guard goTab("Home") else { return false }
        let c: XCUIElement = buttonContaining(part)
        guard tap(c, wait: 5) else { return false }
        return button("company-tab-overview").waitForExistence(timeout: 5)
    }

    func swipeBackFromEdge() {
        let start: XCUICoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
        let end: XCUICoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        pause(1)
    }

    // MARK: Snapshot helpers

    func walk(_ s: XCUIElementSnapshot, _ f: (XCUIElementSnapshot) -> Bool) {
        if !f(s) { return }
        for c in s.children { walk(c, f) }
    }

    func signature() -> TourSig {
        guard let snap = try? app.snapshot() else { return TourSig(heads: ["?"], back: false, tabs: []) }
        var heads: Set<String> = []
        var back = false
        var tabs: [String] = []
        walk(snap) { (s: XCUIElementSnapshot) -> Bool in
            if s.identifier == "back-button" || s.identifier == "BackButton" { back = true }
            if (s.identifier.hasPrefix("tab-") || s.identifier.hasPrefix("company-tab-")) && s.isSelected { tabs.append(s.identifier) }
            if s.identifier.hasPrefix("tab-") { return false }
            if (s.elementType == .staticText || s.elementType == .other), !s.label.isEmpty, s.frame.minY >= 0, s.frame.maxY < 175, s.frame.height < 90 {
                heads.insert(s.label.components(separatedBy: ", ")[0])
            }
            return true
        }
        return TourSig(heads: heads.sorted(), back: back, tabs: tabs.sorted())
    }

    /// All the text on screen (labels, string values, titles).
    func allTexts() -> [(text: String, id: String)] {
        guard let snap = try? app.snapshot() else { return [] }
        var out: [(text: String, id: String)] = []
        walk(snap) { (s: XCUIElementSnapshot) -> Bool in
            if !s.label.isEmpty { out.append((s.label, s.identifier)) }
            if let v = s.value as? String, !v.isEmpty, v != s.label { out.append((v, s.identifier)) }
            if !s.title.isEmpty, s.title != s.label { out.append((s.title, s.identifier)) }
            return true
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

    /// Scrolls to the end of the screen (until the lowest element stops changing) and reports content that ends under the tab bar or
    /// off the screen. nil when fine or when the screen is a long list that could not be scrolled to its end.
    func clipProblem() -> String? {
        let win: CGRect = app.windows.firstMatch.frame
        guard win.height > 0 else { return nil }
        var barTop: CGFloat = win.maxY
        let bar: XCUIElement = button("tab-Home")
        if visible(bar) { barTop = bar.frame.minY }
        var last = ""
        var swipes = 0
        var verdict: String? = nil
        var reachedEnd = false
        while swipes < 8 {
            guard let snap = try? app.snapshot() else { return nil }
            var lowestMax: CGFloat = 0
            var lowestLabel = ""
            var hidden: [String] = []
            walk(snap) { (s: XCUIElementSnapshot) -> Bool in
                if s.identifier.hasPrefix("tab-") || s.identifier == "back-button" { return false }
                let t: XCUIElement.ElementType = s.elementType
                guard t == .staticText || t == .button || t == .textField || t == .switch || t == .slider else { return true }
                let r: CGRect = s.frame
                guard !s.label.isEmpty, r.width > 1, r.height > 1, r.minY >= 0, r.minY < win.maxY - 1, r.minX < win.maxX else { return true }
                if r.minY >= barTop - 1 { hidden.append(String(s.label.prefix(30))); return true }
                if r.maxY > lowestMax { lowestMax = r.maxY; lowestLabel = s.label }
                return true
            }
            let key: String = "\(lowestLabel)@\(Int(lowestMax))#\(hidden.count)"
            if key == last {
                reachedEnd = true
                if !hidden.isEmpty { verdict = "\(hidden.count) element(s) end under the tab bar, e.g. '\(hidden[0])'" }
                else if lowestMax > barTop + 2 { verdict = "'\(String(lowestLabel.prefix(30)))' is cut by \(Int(lowestMax - barTop)) pt at the bottom" }
                break
            }
            last = key
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        for _ in 0..<(swipes + 1) { app.swipeDown(velocity: .fast) }
        return reachedEnd ? verdict : nil
    }

    /// Screen-level health: raw text, empty title (when expected) and a clipped bottom.
    func health(_ screen: String, title: Bool = true, clip: Bool = true) -> R {
        var problems: [String] = rawProblems(screen)
        if title && !hasTitle() { problems.append("empty header title") }
        if clip, let c = clipProblem() { problems.append(c) }
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
            guard open() else { return .skip("popup trigger not reachable in this game") }
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
            let e: XCUIElement = s.hasPrefix("prefix:") ? buttonPrefix(String(s.dropFirst(7))) : button(s)
            if e.waitForExistence(timeout: 2), reveal(e) { lastBefore = signature(); ctap(e); pause(0.8) }
        }
        return popupUp(2)
    }
}
