import XCTest

enum TourStatus: String { case pass = "PASS", fail = "FAIL", skip = "SKIP" }

enum R {
    case pass(String = "")
    case fail(String)
    case skip(String)
}

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

    @discardableResult
    func finish() -> String {
        let block: String = summary()
        if !finished { finished = true; append(block) }
        return block
    }
}

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

struct Hit {
    var id: String
    var label: String
    var value: String
    var frame: CGRect
    var type: XCUIElement.ElementType
    var selected: Bool
    var enabled: Bool
    var hScroll: Bool
    var name: String { id.isEmpty ? "'\(label.prefix(30))'" : id }
    var tappable: Bool { [.button, .cell, .link, .switch, .textField, .slider, .image, .staticText, .other].contains(type) }
}

class FeatureTourCase: XCTestCase {
    var app: XCUIApplication!
    let log = TourLogStore.shared
    var lastBefore: TourSig?
    var noteBefore = false
    static let runStart: Date = Date()
    var testDeadline: Date = Date().addingTimeInterval(720)
    var winCache: CGRect = .zero
    var smallTargets: [String: String] = [:]
    var tappedTargets: Set<String> = []
    var zeroTexts: Set<String> = []
    static var zeroReported: Set<String> = []

    static let popupIDs: [String] = ["popup-backdrop", "popup-close", "confirm-go", "confirm-cancel", "report-continue", "report-open", "celebration-dismiss",
                                     "celebration-claim", "celebration-next-goal", "alert-continue", "error-ok", "notice-ok", "outcome-ok", "unlock-skip", "unlock-go", "ambition-later",
                                     "paywall-pass"]
    static let closeIDs: [String] = ["popup-close", "confirm-cancel", "report-continue", "celebration-dismiss", "celebration-claim", "celebration-next-goal", "alert-continue", "error-ok",
                                     "notice-ok", "outcome-ok", "unlock-skip", "ambition-later", "paywall-pass"]

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
        let end: Date = Date().addingTimeInterval(30)
        var home = false
        while Date() < end && !home {
            let later: XCUIElement = app.buttons["ambition-later"].firstMatch
            if later.exists { ctap(later); pause(1) } else if popupUp() { closePopup() }
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

    func step(_ name: String, _ body: () -> R) {
        if Date() > testDeadline || Date().timeIntervalSince(Self.runStart) > 70 * 60 {
            log.record(.skip, name, "time cap reached (12 min per test / 70 min per shard)")
            return
        }
        let t0: Date = Date()
        let r: R = body()
        let took: String = " [\(Int(Date().timeIntervalSince(t0)))s]"
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

    func homeVisible(_ t: TimeInterval = 8) -> Bool {
        var n = 0
        while n < 3 && popupUp(n == 0 ? 0.5 : 1) { closePopup(prefer: ["report-continue"]); n += 1 }
        return find(wait: t) { $0.id == "home-companies-box" || $0.label == "Net worth" || $0.label == "NET WORTH" || $0.id == "next-day" } != nil
    }

    func elem(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    func button(_ id: String) -> XCUIElement { app.buttons[id].firstMatch }

    func win() -> CGRect {
        if winCache.width < 200 {
            let a: CGRect = app.frame
            if a.width >= 200 { winCache = a }
            else { winCache = app.windows.allElementsBoundByIndex.map { $0.frame }.max { $0.width * $0.height < $1.width * $1.height } ?? .zero }
        }
        return winCache.width < 200 ? CGRect(x: 0, y: 0, width: 402, height: 874) : winCache
    }

    func visible(_ e: XCUIElement) -> Bool {
        guard e.exists else { return false }
        let f: CGRect = e.frame
        if f.isEmpty || f.width < 1 || f.height < 1 || f.isNull || f.isInfinite { return false }
        let r: CGRect = f.intersection(win())
        return !r.isNull && r.width >= 1 && r.height >= 1
    }

    @discardableResult
    func ctap(_ e: XCUIElement) -> Bool {
        guard visible(e) else { return false }
        let c: XCUICoordinate = e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        if e.identifier == "confirm-go" { c.press(forDuration: 1.5) } else { c.tap() }
        return true
    }

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

    func band(_ hs: [Hit]) -> (top: CGFloat, bottom: CGFloat) {
        let w: CGRect = win()
        let bar: CGFloat = hs.filter { $0.id.hasPrefix("tab-") && $0.type == .button }.map { $0.frame.minY }.min() ?? (w.maxY - 24)
        return (w.minY + 52, min(bar, w.maxY - 24) - 2)
    }

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

    func dragPage(_ dy: CGFloat, x: CGFloat? = nil) {
        let w: CGRect = win()
        let from: CGFloat = dy < 0 ? w.minY + w.height * 0.68 : w.minY + w.height * 0.32
        let o: XCUICoordinate = app.coordinate(withNormalizedOffset: .zero)
        let start: XCUICoordinate = o.withOffset(CGVector(dx: x ?? w.midX, dy: from))
        let stop: XCUICoordinate = o.withOffset(CGVector(dx: x ?? w.midX, dy: from + dy))
        start.press(forDuration: 0.05, thenDragTo: stop, withVelocity: .slow, thenHoldForDuration: 0.15)
        pause(0.4)
    }

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

    @discardableResult
    func tapWhere(wait: TimeInterval = 3, _ pred: (Hit) -> Bool) -> Bool {
        guard bringIn(pred, wait: wait) != nil else { return false }
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
    @discardableResult func tapEnabled(_ id: String, wait: TimeInterval = 3) -> Bool { tapWhere(wait: wait) { $0.id == id && $0.type == .button && $0.enabled } }
    @discardableResult func tapPrefix(_ p: String, wait: TimeInterval = 3) -> Bool { tapWhere(wait: wait) { $0.id.hasPrefix(p) && $0.type == .button } }

    func ids(prefix: String, wait: TimeInterval = 3) -> [String] {
        _ = find(wait: wait) { $0.id.hasPrefix(prefix) }
        var out: [String] = []
        for h in hits() where h.id.hasPrefix(prefix) && h.type == .button && !out.contains(h.id) { out.append(h.id) }
        return out
    }

    func primaryInView(_ id: String, wait: TimeInterval = 3) -> R {
        guard let h = find(wait: wait, { $0.id == id || $0.id == id + "-blocked" }) else { return .fail("no \(id) on the screen") }
        let b = band(hits())
        if h.frame.minY < b.top - 8 || h.frame.maxY > b.bottom + 2 { return .fail("\(id) is off the visible area without scrolling (y \(Int(h.frame.minY))-\(Int(h.frame.maxY)), band \(Int(b.top))-\(Int(b.bottom)))") }
        return .pass(h.id.hasSuffix("-blocked") ? "shown, blocked with its reason" : "")
    }

    var popupElement: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", Self.popupIDs)).firstMatch
    }

    func popupUp(_ wait: TimeInterval = 0) -> Bool {
        let b: XCUIElement = app.buttons.matching(NSPredicate(format: "identifier IN %@", Self.popupIDs)).firstMatch
        if wait > 0 { return b.waitForExistence(timeout: wait) || popupElement.exists }
        return b.exists || app.otherElements["popup-backdrop"].exists
    }

    var diagCount = 0
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

    func closePopup(prefer: [String] = []) {
        let ids: [String] = prefer + Self.closeIDs
        func tapFirst() -> Bool {
            for id in ids {
                let b: XCUIElement = app.buttons[id].firstMatch
                if visible(b) {
                    if id == "confirm-go" { b.press(forDuration: 1.5) } else { b.tap() }
                    return true
                }
            }
            for id in prefer where ctap(button(id)) { return true }
            let q: XCUIElementQuery = app.buttons.matching(NSPredicate(format: "identifier IN %@", ids))
            return ctap(q.firstMatch)
        }
        if tapFirst() { pause(0.6); return }
        for _ in 0..<3 {
            let from: XCUICoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let to: XCUICoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            from.press(forDuration: 0.1, thenDragTo: to)
            if tapFirst() { pause(0.6); return }
        }
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

    func tapBack() -> Bool {
        if let h = find({ ($0.id == "back-button" || $0.id == "group-back" || $0.id == "BackButton") && $0.type == .button }) {
            if let now = find({ $0.id == h.id && $0.type == .button }) { touch(now); pause(0.3); return true }
        }
        let bars: XCUIElementQuery = app.navigationBars
        for i in 0..<min(bars.count, 3) {
            let b: XCUIElement = bars.element(boundBy: i).buttons.element(boundBy: 0)
            if ctap(b) { pause(0.8); return true }
        }
        return false
    }

    func toRoot() {
        for _ in 0..<8 {
            if popupUp() { closePopup(); continue }
            if !tapBack() { break }
        }
    }

    func tabState() -> String {
        let hs: [Hit] = hits()
        let tabs: String = hs.filter { $0.id.hasPrefix("tab-") && $0.type == .button }.map { "\($0.id)\($0.selected ? "*" : "")" }.joined(separator: " ")
        let others: [String] = hs.filter { $0.type == .button && !$0.id.hasPrefix("tab-") }.prefix(30).map { $0.name }
        return "tabs: \(tabs); buttons: \(others.joined(separator: ","))"
    }

    func tabIDs() -> [String] { ids(prefix: "tab-") }

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

    @discardableResult
    func goGroup(_ home: String) -> Bool {
        guard goTab("Group") else { return false }
        return tapID("group-home-tab-\(home)", wait: 3)
    }

    func gridUp(_ t: TimeInterval = 0) -> Bool { find(wait: t) { $0.id.hasPrefix("phone-app-") && $0.type == .button } != nil }

    var lastOpenWhy: String = ""

    @discardableResult
    func openPhoneApp(_ name: String) -> Bool {
        lastOpenWhy = ""
        guard goTab("Phone") else { lastOpenWhy = "no Phone tab"; return false }
        guard gridUp(6) else { lastOpenWhy = "grid not shown"; log.note("phone grid not shown: " + tabState()); return false }
        let pred: (Hit) -> Bool = { $0.id == "phone-app-\(name)" && $0.type == .button }
        guard let tile = bringIn(pred, wait: 1.5) else {
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

    func customTab() -> Hit? {
        let tabs: [Hit] = hits().filter { $0.id.hasPrefix("tab-") && $0.type == .button }.sorted { $0.frame.minX < $1.frame.minX }
        return tabs.count == 5 ? tabs[3] : nil
    }

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
            if s.id.hasPrefix("tab-") { continue }
            if (s.type == .staticText || s.type == .other), !s.label.isEmpty, s.frame.minY >= w.minY + 50, s.frame.maxY < w.minY + 190, s.frame.height < 90 {
                let t: String = s.label.components(separatedBy: ", ")[0]
                let ns: NSString = t as NSString
                if let c = Self.clockText, c.firstMatch(in: t, options: [], range: NSRange(location: 0, length: ns.length)) != nil { continue }
                heads.insert(t)
            }
        }
        return TourSig(heads: heads.sorted(), back: back, tabs: Array(Set(tabs)).sorted())
    }

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

    func hasTitle() -> Bool {
        let s: TourSig = signature()
        return s.heads.contains { (h: String) -> Bool in !h.trimmingCharacters(in: .whitespaces).isEmpty }
    }

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
            for h in hs where !h.id.hasPrefix("tab-") && h.id != "back-button" && !tabFrames.contains(where: { $0.intersects(h.frame) }) {
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
            let before: TourSig = lastBefore ?? before0
            guard popupUp(3) else { return .fail("the tap worked but no popup came up (screen: \(signature().text))") }
            var problems: [String] = rawProblems(name)
            closePopup(prefer: closeWith)
            guard waitPopupGone(3) else { return .fail("the popup did not close with its button") }
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

    func toastCleanup() {
        var n = 0
        while popupUp() && n < 3 { closePopup(); n += 1 }
    }

    func driveUntilPopup(_ steps: [String]) -> Bool {
        for s in steps {
            if popupUp() { return true }
            let pre: Bool = s.hasPrefix("prefix:")
            let key: String = pre ? String(s.dropFirst(7)) : s
            let pred: (Hit) -> Bool = { pre ? ($0.id.hasPrefix(key) && $0.type == .button) : $0.id == key }
            if bringIn(pred, wait: 2) != nil { lastBefore = signature(); if let now = find(pred) { touch(now) }; pause(0.3) }
        }
        return popupUp(2)
    }
}
