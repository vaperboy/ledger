import Foundation
import GameCore
import Countries
import Businesses

/// Entry to the Luxury phone app (a private-sales app for the very rich) and the financed purchase of a piece.
public enum LuxuryGate: Equatable, Sendable {
    case notApplied
    case accepted
    /// Declined in game week `week`; may apply again from the following week.
    case declined(week: Int)
}

public extension GameEngine {
    /// Net worth needed, in accounting units: 10 million in US dollars or in euros (whichever is the lower), converted at today's rates.
    /// The screens never show it.
    var luxuryGateThreshold: Double {
        let rates = ExchangeRates(drift: state.exchangeRates.values)
        let perCode = ["USD", "EUR"].compactMap { code -> Double? in
            data.countries.countries.first { $0.currencyCode == code }.map { 10_000_000 * Currency(country: $0, rates: rates).rate }
        }
        return perCode.min() ?? 10_000_000
    }

    /// The stored result: accepted stays accepted, a decline is remembered with its week.
    var luxuryGate: LuxuryGate {
        let g = state.rest["luxGate"] ?? .null
        switch g["st"].string {
        case "accepted": return .accepted
        case "declined": return .declined(week: g["w"].int)
        default: return .notApplied
        }
    }

    /// Whether the player may send an application now (never applied, or declined in an earlier week).
    var luxuryGateCanApply: Bool {
        switch luxuryGate {
        case .accepted: return false
        case .notApplied: return true
        case .declined(let w): return state.week > w
        }
    }

    /// The pure check: is this net worth enough?
    func luxuryGatePasses(netWorth: Double) -> Bool { netWorth >= luxuryGateThreshold }

    /// Apply for entry. Accepted if net worth reaches the threshold; the result is saved. Does nothing once accepted or if a decline is
    /// from this same week.
    @discardableResult
    mutating func applyForLuxuryAccess() -> LuxuryGate {
        guard luxuryGateCanApply else { return luxuryGate }
        let ok = luxuryGatePasses(netWorth: netWorth.total)
        let week = state.week
        update { s, _, _ in
            s.rest["luxGate"] = .object(ok ? ["st": .string("accepted"), "w": .number(Double(week))]
                                           : ["st": .string("declined"), "w": .number(Double(week))])
        }
        return luxuryGate
    }

    // MARK: Financed purchase

    /// Share of the price paid in cash when a piece is financed.
    static var luxuryDownShare: Double { 0.2 }
    static var luxuryFinanceTermMonths: Int { 60 }

    struct LuxuryFinanceQuote: Equatable, Sendable {
        public var down: Double
        public var loan: Double
        public var fee: Double
        public var monthlyPayment: Double
        public var yearlyRate: Double
        public var termMonths: Int
        /// Cash needed at closing: the deposit plus the bank's arrangement fee.
        public var dueAtClosing: Double { down + fee }
        public var refusal: String?
    }

    func luxuryFinanceQuote(itemID: String) -> LuxuryFinanceQuote? {
        guard let it = Luxury.item(itemID) else { return nil }
        let loan = (it.price * (1 - Self.luxuryDownShare)).rounded()
        let q = loanApplicationQuote(kind: "cons", amount: loan, termMonths: Self.luxuryFinanceTermMonths, companyID: nil)
        return LuxuryFinanceQuote(down: it.price - loan, loan: loan, fee: q.fee, monthlyPayment: q.monthlyPayment, yearlyRate: q.yearlyRate,
                                  termMonths: q.termMonths, refusal: q.refusal)
    }

    enum LuxuryFinanceResult: Equatable, Sendable { case ok, refused(String), notEnoughCash, unknownItem }

    /// Buy with a loan for 80%: the bank's own application (same checks and fee as the Bank app), then the purchase. Nothing happens
    /// if the cash for the deposit and fee is missing or the bank refuses.
    @discardableResult
    mutating func buyLuxuryFinanced(itemID: String) -> LuxuryFinanceResult {
        guard let it = Luxury.item(itemID), let q = luxuryFinanceQuote(itemID: itemID) else { return .unknownItem }
        if let r = q.refusal { return .refused(r) }
        if state.cash < q.dueAtClosing { return .notEnoughCash }
        let docs = LoanDocuments(fullName: state.player.name, incomeProof: .bankStatements)
        switch applyForLoan(kind: "cons", amount: q.loan, termMonths: q.termMonths, companyID: nil, documents: docs, agreed: true) {
        case .refused(let why): return .refused(why)
        case .approved: break
        }
        return buyLuxury(itemID: it.id) == .ok ? .ok : .refused("The purchase could not be completed.")
    }
}

public extension GameEngine {
    /// What selling a piece pays today after the selling costs; nil when it cannot be sold now (lent to a museum).
    func luxurySellQuote(pieceID: Int) -> Double? {
        guard let p = luxuryPieces.first(where: { $0.id == pieceID }) else { return nil }
        if p.use == "museum" && p.until > state.week { return nil }
        return jsRound(p.value * (1 - Luxury.sellFee))
    }
}
