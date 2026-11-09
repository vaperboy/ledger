import Foundation
import GameCore
import Countries
import Finance

/// The personal guarantee on a company loan, and the bank discussion that can release it.
/// The bank wants a higher margin in return for releasing the guarantee. The answer comes from the shared `Negotiation` module: the bank's
/// hidden reservation is a premium that grows with a weaker credit score and a company without a clean record; the player offers a premium
/// (a yearly rate added to the loan's margin). A talk that walks away locks the subject for 26 weeks. The talk is kept on the loan (`neg`).
public enum LoanGuarantee {
    public struct Terms: Equatable, Sendable, Identifiable {
        public var id: Int { loanID }
        public var loanID: Int
        public var loanName: String
        public var companyID: Int
        public var balance: Double
        public var guaranteed: Bool
        /// nil when a talk is possible; else why not.
        public var unavailable: String?
        /// The premium (yearly rate) already offered in the open talk, 0 if none.
        public var lastOffer: Double
        /// The bank's standing counter, if it made one.
        public var counter: Double?
    }

    public enum Answer: Equatable, Sendable {
        case released(extraMargin: Double)
        case counter(extraMargin: Double, isFinal: Bool)
        case refused
        case walkedAway
        case notPossible(String)
    }

    static let lockWeeks = 26

    static func unavailable(_ loan: Loan, company co: Company?, state s: GameState) -> String? {
        guard loan.companyID != 0, let co = co else { return "This loan is your own debt; there is no guarantee to release." }
        if !loan.isGuaranteed { return "This loan has no personal guarantee." }
        if loan.int("miss") > 0 { return "The bank will not talk while an instalment is missed." }
        if co.monthlyHistory.count < 3 { return "The bank wants at least three months of accounts as a limited company before it considers releasing a guarantee." }
        if Double(s.week) < loan.num("guarLock") { return "The bank will not discuss this again for now." }
        return nil
    }

    public static func terms(_ s: GameState, loanID: Int) -> Terms? {
        guard let loan = s.loans.first(where: { $0.id == loanID }) else { return nil }
        let talk = Negotiation.State.resume(loan, party: loan.id, week: s.week)
        return Terms(loanID: loan.id, loanName: loan.name, companyID: loan.companyID, balance: loan.balance, guaranteed: loan.isGuaranteed,
                     unavailable: unavailable(loan, company: s.company(loan.companyID), state: s), lastOffer: talk.lastOffer, counter: talk.counter > 0 ? talk.counter : nil)
    }

    /// The premium the bank would settle for (hidden): a base plus a share for a weaker credit score and a thinner or losing record.
    static func reservation(company co: Company, state s: GameState) -> Double {
        let weak = max(0, 100 - s.credit) / 100
        let thin = co.monthlyHistory.count < 12 ? 0.004 : 0
        let losing = (co.monthlyHistory.suffix(6).reduce(0) { $0 + $1.profit }) < 0 ? 0.008 : 0
        return 0.004 + weak * 0.03 + thin + losing
    }

    /// The player offers `extraMargin` (yearly rate added to the loan's margin) for the release of the guarantee.
    public static func offer(_ s: inout GameState, loanID: Int, extraMargin: Double) -> Answer {
        guard let li = s.loans.firstIndex(where: { $0.id == loanID }) else { return .notPossible("That loan no longer exists.") }
        var loan = s.loans[li]
        let co = s.company(loan.companyID)
        if let why = unavailable(loan, company: co, state: s) { return .notPossible(why) }
        guard let company = co, extraMargin >= 0 else { return .notPossible("The offer has to be a premium above zero.") }
        let key = "guar:\(loan.id)"
        let temper = Negotiation.temperament(personality: nil, key: key)
        var talk = Negotiation.State.resume(loan, party: loan.id, week: s.week)
        let position = Negotiation.position(reservation: reservation(company: company, state: s), direction: .higher, temperament: temper, key: key)
        let reply = Negotiation.respond(offer: extraMargin, position: position, temperament: temper, rank: "deal", state: &talk, week: s.week, step: 0.001, random: &s.random)
        switch reply.answer {
        case .accept:
            loan.isGuaranteed = false
            loan.margin += extraMargin
            loan.set("guarReleased", .number(Double(s.week)))
            Negotiation.State().store(in: &loan)
            s.loans[li] = loan
            s.note("The bank releases your personal guarantee on \(loan.name) in return for a higher margin.", tone: "good", companyID: loan.companyID)
            return .released(extraMargin: extraMargin)
        case .counter(let c):
            talk.store(in: &loan); s.loans[li] = loan
            return .counter(extraMargin: c.amount, isFinal: c.isFinal)
        case .refuse:
            talk.store(in: &loan); s.loans[li] = loan
            return .refused
        case .walkAway:
            Negotiation.State().store(in: &loan)
            loan.set("guarLock", .number(Double(s.week + lockWeeks)))
            s.loans[li] = loan
            return .walkedAway
        }
    }
}
