import Foundation
import GameCore
import Countries
import Businesses

public enum LuxuryGate: Equatable, Sendable {
    case notApplied
    case accepted
    case declined(week: Int)
}

public extension GameEngine {
    var luxuryGateThreshold: Double {
        let rates = ExchangeRates(drift: state.exchangeRates.values)
        let perCode = ["USD", "EUR"].compactMap { code -> Double? in
            data.countries.countries.first { $0.currencyCode == code }.map { 10_000_000 * Currency(country: $0, rates: rates).rate }
        }
        return perCode.min() ?? 10_000_000
    }

    var luxuryGate: LuxuryGate {
        let g = state.rest["luxGate"] ?? .null
        switch g["st"].string {
        case "accepted": return .accepted
        case "declined": return .declined(week: g["w"].int)
        default: return .notApplied
        }
    }

    var luxuryGateCanApply: Bool {
        switch luxuryGate {
        case .accepted: return false
        case .notApplied: return true
        case .declined(let w): return state.week > w
        }
    }

    func luxuryGatePasses(netWorth: Double) -> Bool { netWorth >= luxuryGateThreshold }

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

    static var luxuryDownShare: Double { 0.2 }
    static var luxuryFinanceTermMonths: Int { 60 }

    struct LuxuryFinanceQuote: Equatable, Sendable {
        public var down: Double
        public var loan: Double
        public var fee: Double
        public var monthlyPayment: Double
        public var yearlyRate: Double
        public var termMonths: Int
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
    func luxurySellQuote(pieceID: Int) -> Double? {
        guard let p = luxuryPieces.first(where: { $0.id == pieceID }) else { return nil }
        if p.use == "museum" && p.until > state.week { return nil }
        return jsRound(p.value * (1 - Luxury.sellFee))
    }
}
