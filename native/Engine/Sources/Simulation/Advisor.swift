import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// What the Home screen offers the player right now: a short, ranked list of things worth doing, each with a real action,
/// and a "first steps" tracker. Everything is derived from the state, so it cannot disagree with the books.
public struct Suggestion: Identifiable, Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case openMessage(Int)
        case openCompany(Int)
        case openLoans
        case openInvest
        case openTax
        case newCompany
    }
    public enum Tone: String, Sendable { case good, warn, bad, neutral }

    public var id: String
    public var symbol: String          // an SF Symbol name
    public var title: String
    public var detail: String
    public var tone: Tone
    public var action: Action
    public var actionLabel: String
}

public struct FirstStep: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var done: Bool
}

public extension GameEngine {
    /// Ranked suggestions: decisions waiting, money problems, then opportunities. At most `limit`.
    func suggestions(limit: Int = 5) -> [Suggestion] {
        var out: [Suggestion] = []
        let cur = homeCurrency
        let s = state

        for m in openDecisions.prefix(3) {
            var detail = localized(m.body, companyID: m.companyID)
            if let exp = m.expiresWeek { let left = exp - s.week; detail += left > 0 ? " · expires in \(left) wk" : " · expires this week" }
            out.append(Suggestion(id: "msg\(m.id)", symbol: "envelope.badge", title: localized(m.title, companyID: m.companyID), detail: detail, tone: m.tone == "bad" ? .bad : .warn,
                                  action: .openMessage(m.id), actionLabel: "Decide"))
        }
        if s.cash < 0 {
            out.append(Suggestion(id: "overdraft", symbol: "exclamationmark.triangle", title: "Your account is overdrawn",
                                  detail: "\(cur.display(-s.cash)) overdrawn. Move savings in, borrow, or take money from a company.", tone: .bad, action: .openLoans, actionLabel: "Open bank"))
        }
        for co in s.liveCompanies {
            if co.cash < 0 {
                out.append(Suggestion(id: "negcash\(co.id)", symbol: "banknote", title: "\(co.name) is out of cash",
                                      detail: "It cannot pay its bills. Put money in or it will fall behind.", tone: .bad, action: .openCompany(co.id), actionLabel: "Open"))
            } else if co.status == .setup {
                out.append(Suggestion(id: "setup\(co.id)", symbol: "checklist", title: "Finish setting up \(co.name)",
                                      detail: "It cannot trade until documents, premises and equipment are in place.", tone: .warn, action: .openCompany(co.id), actionLabel: "Continue"))
            }
        }
        let est = PersonalFinance.taxEstimate(s, context: context)
        if s.tax.pending > 0 {
            out.append(Suggestion(id: "tax", symbol: "doc.text", title: "Tax to pay", detail: "\(cur.display(s.tax.pending)) will fall due. Keep cash for it.", tone: .warn, action: .openTax, actionLabel: "See tax"))
        } else if est > 0, s.week % 13 == 0 {
            out.append(Suggestion(id: "taxest", symbol: "doc.text", title: "Tax estimate", detail: "About \(cur.display(est)) so far this year.", tone: .neutral, action: .openTax, actionLabel: "See tax"))
        }
        if s.companies.isEmpty {
            out.append(Suggestion(id: "first", symbol: "building.2", title: "Start your first business",
                                  detail: "Pick a trade you can afford; the next screen shows the full start-up cost before you commit.", tone: .good, action: .newCompany, actionLabel: "Choose a trade"))
        }
        let idle = s.cash - 0
        if idle > cur.scaledPrice(150_000), s.loans.contains(where: { $0.balance > 0 && $0.companyID == 0 && $0.kind != "start" }) {
            out.append(Suggestion(id: "idle", symbol: "percent", title: "Idle cash while you owe money",
                                  detail: "Paying part of a loan back would cut your interest.", tone: .neutral, action: .openLoans, actionLabel: "Open bank"))
        }
        return Array(out.prefix(limit))
    }

    /// The first-steps tracker. No rewards, just a guide.
    func firstSteps() -> [FirstStep] {
        let cos = state.companies
        func traded(_ c: Company) -> Bool { (c.books.total["rev"] ?? 0) > 0 }
        return [
            FirstStep(id: "start", title: "Start a business", detail: "Tap + on the Company tab and choose a trade.", done: !cos.isEmpty),
            FirstStep(id: "open", title: "Get it open", detail: "Documents, premises and equipment must be ready.", done: cos.contains { $0.openedWeek != nil }),
            FirstStep(id: "sale", title: "Make your first sales", detail: "Press Next day and watch the money come in.", done: cos.contains(where: traded)),
            FirstStep(id: "hire", title: "Hire someone", detail: "More hands mean more customers served.", done: cos.contains { !$0.staff.isEmpty }),
            FirstStep(id: "market", title: "Try marketing", detail: "A small campaign raises awareness, but results vary.", done: cos.contains { !$0.value("mkt").object.isEmpty }),
            FirstStep(id: "month", title: "Close a month", detail: "Wages, tax and VAT are settled at month end.", done: cos.contains { !$0.monthlyHistory.isEmpty }),
            FirstStep(id: "profit", title: "Make a profitable month", detail: "Revenue above all costs, tax included.", done: cos.contains { $0.monthlyHistory.contains { $0.profit > 0 } }),
        ]
    }
}
