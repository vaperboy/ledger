import Foundation

/// Where a message is delivered. Every message is classified once, when it is made.
public enum MessageRoute: String, Sendable, CaseIterable {
    /// A question with answers: a Home popup, one at a time; "Later" moves it to the inbox.
    case decision
    /// Serious news with no answer: pops up once, then stays as a message.
    case alert
    /// A plain message.
    case inbox
    /// One line in the weekly report and the day's summary; no message.
    case report
    /// Nothing: the same fact is already shown somewhere else.
    case drop
}

extension Message {
    public var route: MessageRoute {
        get {
            if let r = MessageRoute(rawValue: str("rt")) { return r }
            if status == "open" && !options.isEmpty { return .decision }
            return isAlert ? .alert : .inbox
        }
        set { set("rt", newValue.rawValue) }
    }

    /// The player chose "Later" on the Home popup: the decision now waits in the inbox.
    public var deferred: Bool { get { flag("later") } set { set("later", newValue) } }

    /// An alert's popup has been shown.
    public var alertShown: Bool { get { flag("seen") } set { set("seen", newValue) } }
}

public struct FeedLine: Equatable, Sendable {
    public var week: Int
    public var day: Int
    public var text: String
    public var tone: String
    public var companyID: Int
}

public enum MessageRoutes {
    /// Senders whose bad news is always serious enough for a popup.
    static let alertSenders: Set<String> = ["Bank", "Creditors", "Your lenders", "Tax office", "Lawyer for the staff",
                                            "Competition authority", "Consumer authority", "Authorities", "Your broker"]
    /// Routine reports that belong in the weekly report rather than the inbox.
    static let reportPrefixes: [String] = ["Monthly report from your", "Targets in ", "New booking: ", "Delivered: ",
                                           "Award: ", "Not awarded: ", "Supplier gone: ", "Late fees at ", "Late payment: ", "Last week's plan", "Rival call handled by "]
    static let reportSuffixes: [String] = [": what I did", " against the budgets"]
    static let reportTitles: Set<String> = ["Manager scorecards", "Quarterly strategy memo", "Supply ended", "Supplier ended the supply", "New supplier",
                                            "Your routine is settling in", "You are on the rich list",
                                            "Weekly briefing", "Monthly briefing"]
    static let reportSenders: Set<String> = ["Deliveries", "Market"]
    /// Shown elsewhere already: payday is a bank line, trophies and milestones have their own celebration.
    static let dropSenders: Set<String> = ["Trophy wall"]

    public static func classify(kind: String, from: String, title: String, status: String, hasOptions: Bool, tone: String, sev: Int, ownerAddressed: Bool) -> MessageRoute {
        if status == "open" && hasOptions { return ownerAddressed ? .decision : .inbox }
        if dropSenders.contains(from) || (from == "Payroll" && title.hasPrefix("Payday: ")) || title == "Supplier lists changed"
            || (from == "Ambition" && title.hasPrefix("Milestone: ")) { return .drop }
        if ownerAddressed && (from == "Your broker" || from == "Your lenders" || from == "Tax office") { return .alert }
        if ownerAddressed && tone == "bad" && (sev >= 3 || alertSenders.contains(from) || title.hasPrefix("Investigation at ") || title.hasSuffix(" has gone bankrupt")
                                               || title.hasSuffix(" was sold by creditors") || title.hasSuffix(" is about to be sold")) { return .alert }
        if kind == "doc" { return .inbox }
        if reportSenders.contains(from) || reportTitles.contains(title) { return .report }
        if reportPrefixes.contains(where: { (p: String) -> Bool in title.hasPrefix(p) }) { return .report }
        if reportSuffixes.contains(where: { (p: String) -> Bool in title.hasSuffix(p) }) { return .report }
        return .inbox
    }
}

extension GameState {
    public mutating func note(_ text: String, tone: String = "n", companyID: Int = 0) {
        var rep = rest["rep"] ?? .object(["ev": .array([]), "w": .number(Double(week))])
        var ev = rep["ev"].array
        if ev.contains(where: { (x: JSONValue) -> Bool in x["t"].string == text }) { return }
        if ev.count < 300 {
            ev.append(.object(["t": .string(text), "tone": .string(tone), "co": .number(Double(companyID))]))
            rep["ev"] = .array(ev)
            rest["rep"] = rep
        }
    }

    public mutating func news(_ text: String, tone: String = "n", companyID: Int = 0) {
        var list = rest["news"]?.array ?? []
        var item: [String: JSONValue] = ["w": .number(Double(week)), "t": .string(text), "tone": .string(tone)]
        if companyID != 0 { item["co"] = .number(Double(companyID)) }
        list.insert(.object(item), at: 0)
        if list.count > 60 { list.removeLast(list.count - 60) }
        rest["news"] = .array(list)
    }

    static let feedKey = "feedD"
    static let feedKeep = 150

    /// A line for today's summary and the Home feed, for news that does not need a message.
    public mutating func feedLine(_ text: String, tone: String = "n", companyID: Int = 0) {
        var list: [JSONValue] = rest[Self.feedKey]?.array ?? []
        list.append(.object(["w": .number(Double(week)), "d": .number(Double(day)), "t": .string(text), "tone": .string(tone), "co": .number(Double(companyID))]))
        if list.count > Self.feedKeep { list.removeFirst(list.count - Self.feedKeep) }
        rest[Self.feedKey] = .array(list)
    }

    /// Recent report lines, oldest first.
    public var feedLines: [FeedLine] {
        (rest[Self.feedKey]?.array ?? []).map { (x: JSONValue) -> FeedLine in
            FeedLine(week: x["w"].int, day: x["d"].int, text: x["t"].string, tone: x["tone"].string, companyID: x["co"].int)
        }
    }

    /// Report lines from the current day.
    public func feedToday() -> [FeedLine] { feedLines.filter { (l: FeedLine) -> Bool in l.week == week && l.day == day } }

    /// Makes a message and delivers it by its route: decisions and alerts pop up, routine news goes to the report, the rest to the inbox.
    @discardableResult
    public mutating func addMessage(kind: String = "info", from: String, title: String, body: String, companyID: Int = 0,
                                    tone: String = "n", status: String = "done", options: [JSONValue] = [], action: String? = nil,
                                    data: JSONValue = .null, expiresWeek: Int? = nil, app: String? = nil,
                                    sev: Int? = nil, aud: String? = nil, handledBy: String? = nil, route: MessageRoute? = nil) -> Int {
        let owner: Bool = (aud ?? "").isEmpty || aud == "owner"
        let r: MessageRoute = route ?? MessageRoutes.classify(kind: kind, from: from, title: title, status: status, hasOptions: !options.isEmpty,
                                                              tone: tone, sev: sev ?? 0, ownerAddressed: owner)
        let id: Int = makeID()
        switch r {
        case .drop:
            return id
        case .report:
            note(title, tone: tone, companyID: companyID)
            feedLine(title, tone: tone, companyID: companyID)
            return id
        case .decision, .alert, .inbox:
            break
        }
        var m = Message(raw: [:])
        m.id = id
        m.kind = kind
        m.from = from
        m.title = title
        m.body = body
        m.companyID = companyID
        m.tone = tone
        m.status = status
        m.week = week
        m.isRead = false
        m.route = r
        if !options.isEmpty { m.set("opts", .array(options)) }
        if let a = action { m.actionID = a }
        if !data.isNull { m.set("data", data) }
        m.expiresWeek = expiresWeek
        if let sev, sev > 0 { m.sev = min(4, sev) }
        if let aud, !aud.isEmpty, aud != "owner" { m.audience = aud }
        if let handledBy, !handledBy.isEmpty { m.handledBy = handledBy }
        let link: String = app ?? (companyID == 0 ? Self.senderApp(from) : "")
        if !link.isEmpty { m.appLink = link }
        inbox.insert(m, at: 0)
        return m.id
    }

    static func senderApp(_ from: String) -> String {
        switch from {
        case "Your insurer": return "atlas"
        case "Your bank", "Bank": return "bank"
        case "The tax office", "Your accountant": return "accounting"
        case "Weather service": return "news"
        case "Supplier": return "techPro"
        case "Trophy wall": return "profile"
        default: return ""
        }
    }

    public func hasHeadOffice(_ role: String) -> Bool {
        (rest["office"]?["staff"].array ?? []).contains { $0["role"].string == role }
    }
}
