import Foundation
import GameCore
import Countries

public struct Desk: Equatable, Sendable {
    public var name: String
    public var title: String
    public var label: String { "\(name), \(title)" }
}

public extension Delegation {
    static let desks: Set<String> = ["finance", "hr", "ops", "sales"]

    static func desk(_ audience: String, in co: Company, state s: GameState, data: GameData) -> Desk? {
        guard desks.contains(audience) else { return nil }
        if audience == "finance" {
            if let emp = co.staff.first(where: { $0.role == "acct" }) { return Desk(name: s.people[emp.id]?.name ?? "The accountant", title: "accountant") }
            let acc = co.value("acc")
            if !acc.isNull, !acc["id"].isNull { return Desk(name: acc["name"].string.isEmpty ? "The accountant" : acc["name"].string, title: "accountant") }
        }
        let title: [String: String] = ["mgr": "manager", "region": "regional manager", "chainmgr": "chain manager", "ceo56": "CEO", "mdir": "director", "md": "managing director"]
        let chain = ManagerModel.decisionChain(s, co, data: data)
        if let b = chain.first(where: { $0.kind == "mgr" && $0.level >= 1 }) ?? chain.first(where: { $0.kind != "mgr" }) {
            return Desk(name: b.name, title: title[b.kind] ?? "manager")
        }
        return nil
    }

    static func severity(of m: Message, netWorth nw: Double = 0) -> Int {
        if m.isAlert || m.sev > 0 { return m.severity }
        if (m.kind == "ask" || m.kind == "decision") && m.status == "open" { return min(4, level(of: m, netWorth: nw)) }
        return m.severity
    }
}

public extension GameState {
    @discardableResult
    mutating func addDeskNotice(_ audience: String, company co: Company, data: GameData?, from: String? = nil, title: String, body: String, tone: String = "bad", sev: Int = 2) -> Int {
        let desk = data.flatMap { Delegation.desk(audience, in: co, state: self, data: $0) }
        return addMessage(from: from ?? co.name, title: title, body: body, companyID: co.id, tone: tone, sev: sev, aud: desk == nil ? "owner" : audience, handledBy: desk?.label)
    }
}
