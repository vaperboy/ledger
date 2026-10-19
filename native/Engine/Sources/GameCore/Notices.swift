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

    /// A news item, newest first, at most 60. Original: `news(txt, tone)`.
    public mutating func news(_ text: String, tone: String = "n") {
        var list = rest["news"]?.array ?? []
        list.insert(.object(["w": .number(Double(week)), "t": .string(text), "tone": .string(tone)]), at: 0)
        if list.count > 60 { list.removeLast(list.count - 60) }
        rest["news"] = .array(list)
    }

    /// Put a message in the inbox. Original: `addMsg`.
    @discardableResult
    public mutating func addMessage(kind: String = "info", from: String, title: String, body: String, companyID: Int = 0,
                                    tone: String = "n", status: String = "done", options: [JSONValue] = [], action: String? = nil,
                                    data: JSONValue = .null, expiresWeek: Int? = nil) -> Int {
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
        inbox.insert(m, at: 0)
        return m.id
    }

    /// Does the player's head office employ this role? Original: `hasHQ(role)`.
    public func hasHeadOffice(_ role: String) -> Bool {
        (rest["office"]?["staff"].array ?? []).contains { $0["role"].string == role }
    }
}
