import Foundation
import GameCore
import Finance
import Businesses
import Events

public extension GameEngine {

    func startupInvestQuote(pitchID: Int, amount: Double) -> Startups.InvestQuote {
        Startups.investQuote(state, pitchID: pitchID, amount: amount, context: context)
    }
    func startupStakeSellQuote(stakeID: Int, fraction: Double) -> VentureSale.Quote {
        Startups.sellQuote(state, stakeID: stakeID, fraction: fraction)
    }
    @discardableResult
    mutating func sellStartupStake(stakeID: Int, fraction: Double, askingMultiplier: Double?) -> VentureSale.Outcome {
        var r = VentureSale.Outcome.unavailable("You hold no such stake.")
        update { s, _, _ in r = Startups.sellAsking(&s, stakeID: stakeID, fraction: fraction, askMultiplier: askingMultiplier) }
        return r
    }

    func fundCommitCheck(offerID: String, amount: Double) -> PrivateEquity.CommitCheck {
        PrivateEquity.commitCheck(state, offerID: offerID, amount: amount, data: data)
    }
    func fundSecondaryQuote(fundID: Int) -> VentureSale.Quote { PrivateEquity.sellQuote(state, fundID: fundID) }
    @discardableResult
    mutating func sellFundStake(fundID: Int, askingMultiplier: Double?) -> VentureSale.Outcome? {
        var r: VentureSale.Outcome?
        update { s, _, _ in r = PrivateEquity.sellStakeAsking(&s, fundID: fundID, askMultiplier: askingMultiplier) }
        return r
    }

    func groupStakeQuote(groupID: String, fraction: Double, multiplier: Double, chance: Double) -> GroupDeals.StakeQuote {
        GroupDeals.stakeQuote(state, groupID: groupID, fraction: fraction, multiplier: multiplier, chance: chance)
    }
    @discardableResult
    mutating func buyGroupStake(groupID: String, fraction: Double, multiplier: Double, chance: Double) -> Result<Double, GroupDeals.StakeFailure> {
        var r: Result<Double, GroupDeals.StakeFailure> = .failure(.noGroup)
        update { s, _, c in r = GroupDeals.buyStakeChecked(&s, groupID: groupID, fraction: fraction, multiplier: multiplier, chance: chance, context: c) }
        return r
    }
}
