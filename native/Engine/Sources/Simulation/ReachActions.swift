import Foundation
import GameCore
import Finance
import Businesses

/// The last original actions that had no engine function: buying an input from a business customer (`ch39set`, `ch39off`), what a bought rival
/// becomes (`rivhow`), a new site beside a rival (`branchgo`), a purchase paid with a loan from your own bank (`rivfin27`), the answer to a rival's
/// price cut (`rm27`), a reference check on a main-office candidate (`hqref`) and a manager review of one company (`reviewnow`).
/// The ids of the original that only open a sheet or switch a tab are presentation; see docs/MISSING_ACTIONS.md for every id.
public extension GameEngine {
    // MARK: Inputs from business customers

    /// Business customers of your companies whose trade supplies this input to `buyer`, with their price and what it would save in a year.
    func accountSupplyCandidates(buyer: Int, kind: String) -> [AccountSupply.Candidate] { AccountSupply.candidates(state, buyer: buyer, kind: kind, data: data) }
    func accountSupplyLink(buyer: Int, kind: String) -> AccountSupply.Link? { AccountSupply.link(state, buyer: buyer, kind: kind) }
    func accountSupplyLinks() -> [AccountSupply.Link] { AccountSupply.links(state) }

    // MARK: Rivals: what a purchase becomes, a site beside a rival, an answer to a price cut

    /// What the choice needs in the current account on top of the price (merge and close cost extra).
    func absorbRivalExtraCost(how: RivalAbsorb.How, price: Double) -> Double { RivalAbsorb.extraCost(how, price: price) }

    /// Buy a rival and make it a branch, merge it into your company, close it down, or run it as a franchise office. As its own company, use `buyRival`.
    @discardableResult
    mutating func absorbRival(companyID: Int, rivalID: Int, price: Double, how: RivalAbsorb.How) -> RivalAbsorb.Outcome {
        var r = RivalAbsorb.Outcome.failed("Nothing happened.")
        update { s, d, c in
            r = RivalAbsorb.absorb(&s, companyID: companyID, rivalID: rivalID, price: price, how: how, data: d, context: c)
            if case .ok = r { Ambitions.countEvent(&s, "buy") }
        }
        return r
    }

    @discardableResult
    mutating func openBranchNextToRival(companyID: Int, rivalID: Int) -> RivalAbsorb.BranchResult {
        var r = RivalAbsorb.BranchResult.failed("Nothing happened.")
        update { s, d, c in r = RivalAbsorb.openBranchNextToRival(&s, companyID: companyID, rivalID: rivalID, data: d, context: c) }
        return r
    }

    /// Your own bank, if you have one, and how much it may lend you for a purchase.
    var ownBank: Company? { RivalAbsorb.ownBank(state) }
    func ownBankRoom() -> Double { RivalAbsorb.ownBank(state).map { RivalAbsorb.bankRoom(state, bankID: $0.id, data: data) } ?? 0 }

    /// Buy a rival with a loan of `amount` from your own bank. The loan is undone if the purchase is refused.
    @discardableResult
    mutating func buyRivalWithOwnBank(companyID: Int, rivalID: Int, price: Double, amount: Double) -> RivalAbsorb.FinanceResult {
        var r = RivalAbsorb.FinanceResult.bankCannotLend
        update { s, d, c in r = RivalAbsorb.buyWithOwnBank(&s, companyID: companyID, rivalID: rivalID, price: price, amount: amount, data: d, context: c) }
        return r
    }

    /// The price cut a rival has running against `companyID`, if it is on and not yet answered.
    func rivalPriceCut(companyID: Int, rivalID: Int) -> (pct: Int, end: Int, answered: String?)? { RivalAbsorb.priceCut(state, companyID: companyID, rivalID: rivalID) }

    @discardableResult
    mutating func answerPriceCut(companyID: Int, rivalID: Int, answer: RivalAbsorb.Counter) -> RivalAbsorb.CounterResult {
        var r = RivalAbsorb.CounterResult.failed("Nothing happened.")
        update { s, d, c in r = RivalAbsorb.answerPriceCut(&s, companyID: companyID, rivalID: rivalID, answer: answer, data: d, context: c) }
        return r
    }

    // MARK: Main office checks

    @discardableResult
    mutating func referenceCheckCandidate(personID: Int) -> OfficeChecks.ReferenceResult {
        var r = OfficeChecks.ReferenceResult.unknownPerson
        update { s, d, _ in r = OfficeChecks.referenceCheckCandidate(&s, personID: personID, data: d) }
        return r
    }

    @discardableResult
    mutating func reviewManagerNow(companyID: Int) -> OfficeChecks.ReviewResult {
        var r = OfficeChecks.ReviewResult.noManager
        update { s, d, _ in r = OfficeChecks.reviewManagerNow(&s, companyID: companyID, data: d) }
        return r
    }
}
