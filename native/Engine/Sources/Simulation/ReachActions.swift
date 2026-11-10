import Foundation
import GameCore
import Finance
import Businesses

public extension GameEngine {

    func accountSupplyCandidates(buyer: Int, kind: String) -> [AccountSupply.Candidate] { AccountSupply.candidates(state, buyer: buyer, kind: kind, data: data) }
    func accountSupplyLink(buyer: Int, kind: String) -> AccountSupply.Link? { AccountSupply.link(state, buyer: buyer, kind: kind) }
    func accountSupplyLinks() -> [AccountSupply.Link] { AccountSupply.links(state) }

    func absorbRivalExtraCost(how: RivalAbsorb.How, price: Double) -> Double { RivalAbsorb.extraCost(how, price: price) }

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

    var ownBank: Company? { RivalAbsorb.ownBank(state) }
    var playerMainBankIsOwn: Bool { RivalAbsorb.ownBank(state) != nil }
    func ownBankRoom() -> Double { RivalAbsorb.ownBank(state).map { RivalAbsorb.bankRoom(state, bankID: $0.id, data: data) } ?? 0 }

    @discardableResult
    mutating func buyRivalWithOwnBank(companyID: Int, rivalID: Int, price: Double, amount: Double) -> RivalAbsorb.FinanceResult {
        var r = RivalAbsorb.FinanceResult.bankCannotLend
        update { s, d, c in r = RivalAbsorb.buyWithOwnBank(&s, companyID: companyID, rivalID: rivalID, price: price, amount: amount, data: d, context: c) }
        return r
    }

    func rivalPriceCut(companyID: Int, rivalID: Int) -> (pct: Int, end: Int, answered: String?)? { RivalAbsorb.priceCut(state, companyID: companyID, rivalID: rivalID) }

    @discardableResult
    mutating func answerPriceCut(companyID: Int, rivalID: Int, answer: RivalAbsorb.Counter) -> RivalAbsorb.CounterResult {
        var r = RivalAbsorb.CounterResult.failed("Nothing happened.")
        update { s, d, c in r = RivalAbsorb.answerPriceCut(&s, companyID: companyID, rivalID: rivalID, answer: answer, data: d, context: c) }
        return r
    }

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
