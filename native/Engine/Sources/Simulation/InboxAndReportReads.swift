import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

/// One movement in a company's bank account, as the company keeps it (`co.tx`: the latest 40, newest first).
public struct CompanyMovement: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case payroll, bills, tax, owner, other
        public var title: String {
            switch self { case .payroll: return "Payroll"; case .bills: return "Rent and bills"; case .tax: return "Tax"; case .owner: return "Owner"; case .other: return "Other" }
        }
    }
    public var id: String
    public var companyID: Int
    public var companyName: String
    public var week: Int
    public var amount: Double
    public var label: String
    public var kind: Kind
}

/// Read-only helpers for the Inbox and Reports screens. Nothing here changes the game: every value is read from the state with
/// the same rules the engine applies (expiry of messages, the yacht dinner, contracts and capacity).
public extension GameEngine {
    // MARK: Company movements

    /// How many movements each company keeps (the original's `co.tx`).
    static let movementsKept = 40

    /// The kind of a movement, from the label the engine writes (Payday, MonthEnd, Payments).
    static func movementKind(_ label: String) -> CompanyMovement.Kind {
        if label.hasPrefix("Payroll") || label.hasPrefix("Back pay") { return .payroll }
        if label == "Rent" || label.hasPrefix("Monthly bills") || label.hasPrefix("Suppliers and costs") { return .bills }
        if label.hasPrefix("Corporate tax") || label.hasPrefix("VAT settlement") || label.hasPrefix("Tax office") { return .tax }
        if label == "Owner investment" || label == "Owner drawing" || label == "Dividend" || label == "Share capital paid in" { return .owner }
        return .other
    }

    /// The movements the companies keep, newest first: one company or all of them, optionally only within some weeks.
    func companyMovements(companyID: Int? = nil, weeks: ClosedRange<Int>? = nil) -> [CompanyMovement] {
        var out: [CompanyMovement] = []
        for co in state.companies where companyID == nil ? co.isOpenOrClosed : co.id == companyID {
            for (n, t) in co.transactions.enumerated() {
                let w = t["w"].int
                if let r = weeks, !r.contains(w) { continue }
                let label = t["l"].string
                out.append(CompanyMovement(id: "\(co.id)-\(n)", companyID: co.id, companyName: co.name, week: w, amount: t["a"].double,
                                           label: label, kind: Self.movementKind(label)))
            }
        }
        // Stable: within a week, each company's own order (newest first) is kept.
        return out.enumerated().sorted { a, b in a.element.week != b.element.week ? a.element.week > b.element.week : a.offset < b.offset }.map { $0.element }
    }

    // MARK: Inbox

    /// What happens to an open message if it is left until it expires (the rules of `EventEngine.expire`). Nil when it does not expire.
    func expiryOutcome(_ m: Message) -> String? {
        guard m.status == "open", m.expiresWeek != nil else { return nil }
        if m.kind == "decision" {
            var bestIndex = 0, best = -Double.infinity
            for (n, o) in m.options.enumerated() {
                let v = -abs(o["fx"]["cash"].double)
                if v > best { best = v; bestIndex = n }
            }
            let label = m.options.indices.contains(bestIndex) ? localized(m.options[bestIndex]["l"].string, companyID: m.companyID) : ""
            return label.isEmpty ? "If you leave it, the cheapest answer is taken." : "If you leave it, the cheapest answer is taken: \(label)."
        }
        if m.actionID == StrategicDecisions.action { return "If you leave it, the default answer is taken." }
        if m.actionID == Shareholders.action { return "If you leave it, it counts as a refusal." }
        if !m.actionID.isEmpty { return "If you leave it, the offer lapses and nothing changes." }
        return nil
    }

    /// For an answered message: what was chosen, or that it lapsed. Nil while it is open or when it never needed an answer.
    func answeredOutcome(_ m: Message) -> String? {
        guard m.status != "open", !m.value("pick").isNull, !m.options.isEmpty else { return nil }
        let pick = m.int("pick", -1)
        let auto = m.value("auto").bool
        if pick < 0 || !m.options.indices.contains(pick) { return auto ? "Lapsed without an answer" : nil }
        let label = localized(m.options[pick]["l"].string, companyID: m.companyID)
        return (auto ? "Taken when time ran out: " : "You chose: ") + label
    }

    /// Facts an offer's options do not spell out, read from the company it concerns. Empty when there is nothing to add.
    func messageFacts(_ m: Message) -> [String] {
        guard m.status == "open", let co = state.company(m.companyID) else { return [] }
        var out: [String] = []
        if m.actionID == VolumeContracts.action {
            let d = m.value("data")
            let lw = co.value("lastW")
            let cap = lw["cap"].double
            let units = d["u"].double
            func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
            if cap > 0 && units > 0 {
                let committed = VolumeContracts.committedUnits(co)
                if d["k"].string == "offer" {
                    out.append("Needs about \(pct(units / cap)) of one week's capacity at \(co.name).")
                } else {
                    out.append("Takes about \(pct(units / cap)) of \(co.name)'s weekly capacity" + (committed > 0 ? ", on top of the \(pct(committed / cap)) contracts already take." : "."))
                }
                let util = lw["util"].double
                if util > 0 { out.append("Last week \(co.name) ran at \(pct(util)) of capacity" + (util + units / cap > 1 ? ": it may not have room, and missed deliveries bring warnings and penalties." : ".")) }
            } else {
                out.append("\(co.name) has no full week of figures yet, so how much room this needs is not known.")
            }
            if m.options.count > 1 { out.append("Declining changes nothing at \(co.name).") }
        }
        return out
    }

    // MARK: Luxury

    /// What a dinner on your yacht costs now, and the weeks until another is possible (0 = now). Nil without a yacht.
    /// The same figures as `Luxury.hostDinner`: the most valuable yacht, once every four weeks.
    func yachtDinnerQuote() -> (cost: Double, waitWeeks: Int)? {
        guard let y = luxuryPieces.filter({ $0.item.category == "yachts" }).max(by: { $0.value < $1.value }) else { return nil }
        let cost = max(homeCurrency.scaledPrice(15000), jsRound(y.value * 0.002))
        var wait = 0
        if let last = state.rest["din56"], !last.isNull { wait = max(0, 4 - (state.week - last.int)) }
        return (cost, wait)
    }
}
