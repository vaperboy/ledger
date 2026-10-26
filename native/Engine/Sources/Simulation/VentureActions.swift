import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

/// What the player can do about ownership and ventures, and what screens read: selling part of your shares and the buyer talk, raising money from
/// investors, private share sales, listing a holding and issuing its shares, the owners of a company (mood, dividend policy, buy-back), startups you
/// found and startups you invest in, private equity funds, the big meeting and stakes in other groups, the crisis centre. The models are `Funding`,
/// `CompanySale`, `Shareholders`, `Startups`, `PrivateEquity`, `BigMeeting`, `GroupDeals` (all in Events). Decisions that come to the inbox
/// (a group's bid, an owners' demand, a pro-rata round, bridge money) are answered with `answer(messageID:option:)` as always.
public extension GameEngine {
    // MARK: Selling part of your shares (quiet sale or broker) and the buyer talk

    /// Put a percentage of YOUR shares on the market (10, 25, 34, 49). Limited companies only.
    @discardableResult
    mutating func listSharesForSale(companyID: Int, percent: Int, broker: Bool) -> Bool {
        var ok = false
        update { s, _, _ in ok = CompanySale.startListing(&s, companyID: companyID, broker: broker, pct: percent) }
        return ok
    }
    mutating func askBuyer(companyID: Int, offerID: Int, question: String) { update { s, _, _ in CompanySale.talkAsk(&s, companyID: companyID, offerID: offerID, question: question) } }
    @discardableResult
    mutating func counterBuyer(companyID: Int, offerID: Int, price: Double) -> CompanySale.TalkResult {
        var r = CompanySale.TalkResult.unchanged
        update { s, _, _ in r = CompanySale.talkCounter(&s, companyID: companyID, offerID: offerID, price: price) }
        return r
    }

    // MARK: Raising money from investors (new shares into the company) and private share sales

    func canRaiseFunding(companyID: Int) -> Bool { Funding.canRaise(state, companyID: companyID) }
    func investorInterest(companyID: Int) -> (word: String, tone: String) { Funding.interestWord(Funding.companyInterest(state, companyID: companyID, data: data)) }
    var founderRecord: Funding.Record { Funding.record(state) }
    func fundingOffers(companyID: Int) -> [Funding.FundOffer] { Funding.offers(state, companyID: companyID) }
    func weeksUntilNextPitch(companyID: Int) -> Int { Funding.weeksUntilPitch(state, companyID: companyID) }
    func suggestedFundingAmount(companyID: Int) -> Double { Funding.suggestedAmount(state, companyID: companyID, data: data, context: context) }
    @discardableResult
    mutating func pitchToInvestors(companyID: Int, amount: Double) -> Funding.PitchResult {
        var r = Funding.PitchResult.notLimited
        update { s, d, c in r = Funding.pitch(&s, companyID: companyID, amount: amount, data: d, context: c) }
        return r
    }
    @discardableResult
    mutating func acceptFundingOffer(companyID: Int, index: Int) -> Bool { var ok = false; update { s, _, _ in ok = Funding.acceptOffer(&s, companyID: companyID, index: index) }; return ok }
    /// `unchanged` means the offer had already gone or was already countered.
    @discardableResult
    mutating func counterFundingOffer(companyID: Int, index: Int) -> SettingResult {
        applySetting(probe: { .object($0.rest) }) { s, d, _ in Funding.counterOffer(&s, companyID: companyID, index: index, data: d) }
    }
    /// `unchanged` means the offer had already gone.
    @discardableResult
    mutating func declineFundingOffer(companyID: Int, index: Int) -> SettingResult {
        applySetting(probe: { .object($0.rest) }) { s, _, _ in Funding.declineOffer(&s, companyID: companyID, index: index) }
    }
    /// Turn down a buyer's offer for a company you listed. `unchanged` means it had already gone.
    @discardableResult
    mutating func declineSaleOffer(companyID: Int, offerID: Int) -> SettingResult {
        applySetting(probe: { s in .object(["offers": .number(Double(CompanySale.listing(s, companyID: companyID)?.offers.count ?? -1))]) }) { s, _, _ in CompanySale.decline(&s, companyID: companyID, offerID: offerID) }
    }
    func shareOffers(companyID: Int) -> [Funding.ShareOffer] { Funding.shareOffers(state, companyID: companyID, data: data) }
    /// mode "primary" (new shares, the money goes into the company) or "secondary" (you sell some of yours).
    @discardableResult
    mutating func sellPrivateShares(companyID: Int, percent: Double, mode: String) -> Funding.ShareResult {
        var r = Funding.ShareResult.notLimited
        update { s, d, c in r = Funding.sellShares(&s, companyID: companyID, pct: percent, mode: mode, data: d, context: c) }
        return r
    }

    // MARK: Holding companies: list on the exchange, issue shares

    func holdingValue(companyID: Int) -> Double { Funding.holdingValue(state, holdingID: companyID, data: data) }
    var listingMinimumValue: Double { Funding.listingMinimum(state, context) }
    var listingFee: Double { homeCurrency.scaledPrice(Funding.listingFee) }
    func isListed(companyID: Int) -> Bool { state.company(companyID).map { Funding.isListed($0) } ?? false }
    @discardableResult
    mutating func listHoldingOnExchange(companyID: Int) -> Funding.ListResult {
        var r = Funding.ListResult.notAHolding
        update { s, d, c in r = Funding.listHolding(&s, holdingID: companyID, data: d, context: c) }
        return r
    }
    func raisePlan(holdingID: Int, goal: Double, publicOffering: Bool) -> Funding.RaisePlan {
        Funding.raisePlan(state, holdingID: holdingID, goal: goal, mode: publicOffering ? "public" : "private", data: data, context: context)
    }
    @discardableResult
    mutating func raiseMoneyForHolding(holdingID: Int, goal: Double, publicOffering: Bool) -> Double? {
        var r: Double?
        update { s, d, c in r = Funding.raiseForHolding(&s, holdingID: holdingID, goal: goal, mode: publicOffering ? "public" : "private", data: d, context: c) }
        return r
    }

    // MARK: The owners of a company

    func owners(companyID: Int) -> [Shareholders.Holder] { Shareholders.holders(state, companyID: companyID) }
    func ownersPower(companyID: Int) -> (kind: Shareholders.Power, text: String)? { state.company(companyID).map { Shareholders.power($0) } }
    func dividendPolicy(companyID: Int) -> String { state.company(companyID).map { Shareholders.policy($0) } ?? "none" }
    @discardableResult
    mutating func setDividendPolicy(companyID: Int, policy: String) -> SettingResult {
        applySetting(refuse: { s in
            if s.company(companyID) == nil { return "That company no longer exists." }
            return Shareholders.policies.contains(policy) ? nil : "That is not a dividend policy."
        }, probe: { $0.company(companyID)?.value("dp27") ?? .null }) { s, _, _ in Shareholders.setPolicy(&s, companyID: companyID, policy: policy) }
    }
    func buyBackPrice(companyID: Int, holder: String) -> Double? { Shareholders.buyBackPrice(state, companyID: companyID, holder: holder, data: data) }
    @discardableResult
    mutating func buyBackStake(companyID: Int, holder: String) -> Bool { var ok = false; update { s, d, _ in ok = Shareholders.buyBack(&s, companyID: companyID, holder: holder, data: d) }; return ok }

    // MARK: Startups you found

    var foundedStartups: [Startups.Founded] { Startups.founded(state) }
    func startupPlan(sector: String, who: String, seedMultiple: Double) -> Startups.Plan? { Startups.plan(state, sector: sector, who: who, seedMultiple: seedMultiple, context: context) }
    func startupInterest(startupID: Int) -> (word: String, tone: String) { Funding.interestWord(Startups.investorInterest(state, startupID: startupID)) }
    func companiesThatCanUseProduct(startupID: Int) -> [(company: Company, effect: StartupProducts.Effect)] {
        guard let f = Startups.founded(state, id: startupID), let p = f.product else { return [] }
        return Startups.companiesThatCanUse(state, sector: p.sector, product: p.product, data: data)
    }
    @discardableResult
    mutating func foundStartup(name: String?, sector: String, product: String, model: String, who: String, seedMultiple: Double) -> Startups.FoundResult {
        var r = Startups.FoundResult.unknownSector
        update { s, d, c in r = Startups.found(&s, name: name, sector: sector, product: product, model: model, who: who, seedMultiple: seedMultiple, data: d, context: c) }
        return r
    }
    @discardableResult
    mutating func pitchStartupRound(startupID: Int) -> Startups.RoundResult { var r = Startups.RoundResult.notLive; update { s, d, _ in r = Startups.pitchRound(&s, startupID: startupID, data: d) }; return r }
    @discardableResult
    mutating func acceptStartupRound(startupID: Int, index: Int) -> Bool { var ok = false; update { s, _, _ in ok = Startups.acceptRound(&s, startupID: startupID, index: index) }; return ok }
    /// `unchanged` means the offer had already gone.
    @discardableResult
    mutating func declineStartupRound(startupID: Int, index: Int) -> SettingResult {
        applySetting(probe: { .object($0.rest) }) { s, _, _ in Startups.declineRound(&s, startupID: startupID, index: index) }
    }
    @discardableResult
    mutating func putMoneyIntoStartup(startupID: Int, amount: Double) -> Bool { var ok = false; update { s, _, _ in ok = Startups.topUp(&s, startupID: startupID, amount: amount) }; return ok }
    @discardableResult
    mutating func shutDownStartup(startupID: Int) -> Double? { var r: Double?; update { s, _, _ in r = Startups.shutDown(&s, startupID: startupID) }; return r }
    @discardableResult
    mutating func changeBuilders(startupID: Int, by delta: Int) -> SettingResult {
        applySetting(refuse: { s in
            guard let f = (s.rest["founded"]?.array ?? []).first(where: { $0["id"].int == startupID }), !f["sw16"].isNull else { return "This startup has no product to build." }
            let n = f["sw16"]["devs"].int + delta
            if n > 10 { return "Ten builders is the most." }
            if n < 0 { return "No builders left to let go." }
            return nil
        }, probe: { .object($0.rest) }) { s, _, c in Startups.setBuilders(&s, startupID: startupID, delta: delta, context: c) }
    }
    @discardableResult
    mutating func toggleOwnerHoursOnProduct(startupID: Int) -> Bool { var ok = false; update { s, _, _ in ok = Startups.toggleOwnerHours(&s, startupID: startupID) }; return ok }
    @discardableResult
    mutating func toggleProductUse(startupID: Int, companyID: Int) -> Bool { var ok = false; update { s, _, _ in ok = Startups.toggleUse(&s, startupID: startupID, companyID: companyID) }; return ok }
    mutating func setProductInternalPrice(startupID: Int, percent: Double) { update { s, _, _ in Startups.setInternalPrice(&s, startupID: startupID, percent: percent) } }
    func rivalTargetsForProduct(startupID: Int) -> [Startups.RivalTarget] { Startups.rivalTargets(state, startupID: startupID, data: data) }
    @discardableResult
    mutating func pitchProductToRival(startupID: Int, rivalID: Int) -> Bool? { var r: Bool?; update { s, d, _ in r = Startups.pitchToRival(&s, startupID: startupID, rivalID: rivalID, data: d) }; return r }

    // MARK: Startups of other people you invest in

    var startupStakes: [Startups.Stake] { Startups.stakes(state) }
    @discardableResult
    mutating func investInStartup(pitchID: Int, amount: Double) -> Startups.InvestResult { var r = Startups.InvestResult.gone; update { s, _, c in r = Startups.invest(&s, pitchID: pitchID, amount: amount, context: c) }; return r }
    @discardableResult
    mutating func helpStartupOnBoard(stakeID: Int) -> Bool { var ok = false; update { s, _, _ in ok = Startups.help(&s, stakeID: stakeID) }; return ok }
    @discardableResult
    mutating func sellStartupStake(stakeID: Int, fraction: Double) -> Double { var v = 0.0; update { s, _, _ in v = Startups.sellStake(&s, stakeID: stakeID, fraction: fraction) }; return v }

    /// Read-only lists for screens.
    var startupPitchesOnOffer: [Startups.Pitch] { Startups.pitchesOnOffer(state) }
    var privateEquityOffersOnTable: [PrivateEquity.Offer] { PrivateEquity.offersOnTable(state) }

    // MARK: Private equity

    /// This year's funds (a new set each calendar year).
    mutating func privateEquityOffers() -> [PrivateEquity.Offer] { var out: [PrivateEquity.Offer] = []; update { s, _, c in out = PrivateEquity.offers(&s, context: c) }; return out }
    var privateEquityFunds: [PrivateEquity.Fund] { PrivateEquity.funds(state) }
    func secondaryPrice(fundID: Int) -> Double { PrivateEquity.secondaryPrice(state, fundID: fundID) }
    func secondaryDiscount(fundID: Int) -> Double { PrivateEquity.secondaryDiscount(state, fundID: fundID) }
    @discardableResult
    mutating func commitToFund(offerID: String, amount: Double) -> PrivateEquity.CommitResult {
        var r = PrivateEquity.CommitResult.gone
        update { s, d, c in r = PrivateEquity.commit(&s, offerID: offerID, amount: amount, data: d, context: c) }
        return r
    }
    @discardableResult
    mutating func sellFundStake(fundID: Int) -> Double? { var r: Double?; update { s, _, _ in r = PrivateEquity.sellStake(&s, fundID: fundID) }; return r }

    // MARK: The big meeting, stakes in groups

    var bigMeetingOffer: BigMeeting.Offer? { BigMeeting.offer(state) }
    var bigMeetingStakes: [BigMeeting.Stake] { BigMeeting.stakes(state) }
    func bigMeetingFinancing(price: Double) -> (own: Double, borrow: Double) { BigMeeting.financing(state, price: price, context: context) }
    func bigMeetingRatesWarning() -> Bool { BigMeeting.offer(state).map { BigMeeting.ratesWarning(state, $0) } ?? false }
    @discardableResult
    mutating func acceptBigMeetingOffer() -> BigMeeting.AcceptResult { var r = BigMeeting.AcceptResult.noOffer; update { s, _, c in r = BigMeeting.accept(&s, context: c) }; return r }
    @discardableResult
    mutating func counterBigMeetingOffer() -> Bool? { var r: Bool?; update { s, _, _ in r = BigMeeting.counter(&s) }; return r }
    @discardableResult
    mutating func walkAwayFromBigMeeting() -> SettingResult {
        applySetting(probe: { $0.rest["bigOff"] ?? .null }) { s, _, _ in BigMeeting.walkAway(&s) }
    }
    var groupStakes: [GroupDeals.Stake] { GroupDeals.stakes(state) }

    // MARK: The crisis centre

    /// Open decisions that are bad news or need an answer, soonest deadline first. Answer one with `answer(messageID:option:)`.
    var crisisCentre: [Message] { Ventures.crises(state) }
}
