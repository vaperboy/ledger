import Foundation

extension GameState {
    public mutating func note(_ text: String, tone: String = "n", companyID: Int = 0) {
        var rep = rest["rep"] ?? .object(["ev": .array([]), "w": .number(Double(week))])
        var ev = rep["ev"].array
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
