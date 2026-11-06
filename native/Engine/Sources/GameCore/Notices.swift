import Foundation

/// Things the player is told about: the activity log of the current week, the news, and inbox messages.
extension GameState {
    /// A line in this week's report (the activity log). Original: `note(txt, tone, coId)`. Tone: "good", "bad" or "n".
    public mutating func note(_ text: String, tone: String = "n", companyID: Int = 0) {
        var rep = rest["rep"] ?? .object(["ev": .array([]), "w": .number(Double(week))])
        var ev = rep["ev"].array
        if ev.count < 300 {
            ev.append(.object(["t": .string(text), "tone": .string(tone), "co": .number(Double(companyID))]))
            rep["ev"] = .array(ev)
            rest["rep"] = rep
        }
    }

    /// A news item, newest first, at most 60. `companyID` (0 = none) is the company of yours the item is about, for the link in the news app.
    public mutating func news(_ text: String, tone: String = "n", companyID: Int = 0) {
        var list = rest["news"]?.array ?? []
        var item: [String: JSONValue] = ["w": .number(Double(week)), "t": .string(text), "tone": .string(tone)]
        if companyID != 0 { item["co"] = .number(Double(companyID)) }
        list.insert(.object(item), at: 0)
        if list.count > 60 { list.removeLast(list.count - 60) }
        rest["news"] = .array(list)
    }

    /// Put a message in the inbox. Original: `addMsg`.
    @discardableResult
    public mutating func addMessage(kind: String = "info", from: String, title: String, body: String, companyID: Int = 0,
                                    tone: String = "n", status: String = "done", options: [JSONValue] = [], action: String? = nil,
                                    data: JSONValue = .null, expiresWeek: Int? = nil, app: String? = nil,
                                    sev: Int? = nil, aud: String? = nil, handledBy: String? = nil) -> Int {
        var m = Message(raw: [:])
        m.id = makeID()
        m.kind = kind
        m.from = from
        m.title = title
        m.body = body
        m.companyID = companyID
        m.tone = tone
        m.status = status
        m.week = week
        m.isRead = false
        if !options.isEmpty { m.set("opts", .array(options)) }
        if let a = action { m.actionID = a }
        if !data.isNull { m.set("data", data) }
        m.expiresWeek = expiresWeek
        if let sev, sev > 0 { m.sev = min(4, sev) }
        if let aud, !aud.isEmpty, aud != "owner" { m.audience = aud }
        if let handledBy, !handledBy.isEmpty { m.handledBy = handledBy }
        // A message about no company opens the app of its sender (insurer, bank, tax office ...) unless the caller names one.
        let link: String = app ?? (companyID == 0 ? Self.senderApp(from) : "")
        if !link.isEmpty { m.appLink = link }
        inbox.insert(m, at: 0)
        return m.id
    }

    /// The Phone app a company-less sender belongs to; empty for a sender with no app.
    static func senderApp(_ from: String) -> String {
        switch from {
        case "Your insurer": return "atlas"
        case "Your bank", "Bank": return "bank"
        case "The tax office", "Your accountant": return "accounting"
        case "Weather service": return "weather"
        case "Supplier": return "techPro"
        default: return ""
        }
    }

    /// Does the player's head office employ this role? Original: `hasHQ(role)`.
    public func hasHeadOffice(_ role: String) -> Bool {
        (rest["office"]?["staff"].array ?? []).contains { $0["role"].string == role }
    }
}
