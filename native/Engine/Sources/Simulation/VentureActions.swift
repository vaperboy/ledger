import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

public extension GameEngine {

    mutating func askBuyer(companyID: Int, offerID: Int, question: String) { update { s, _, _ in CompanySale.talkAsk(&s, companyID: companyID, offerID: offerID, question: question) } }
    @discardableResult
    mutating func counterBuyer(companyID: Int, offerID: Int, price: Double) -> CompanySale.TalkResult {
        var r = CompanySale.TalkResult.unchanged
        update { s, _, _ in r = CompanySale.talkCounter(&s, companyID: companyID, offerID: offerID, price: price) }
        return r
    }

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
    @discardableResult
    mutating func counterFundingOffer(companyID: Int, index: Int) -> SettingResult {
        applySetting(probe: { .object($0.rest) }) { s, d, _ in Funding.counterOffer(&s, companyID: companyID, index: index, data: d) }
    }
    @discardableResult
    mutating func declineFundingOffer(companyID: Int, index: Int) -> SettingResult {
        applySetting(probe: { .object($0.rest) }) { s, _, _ in Funding.declineOffer(&s, companyID: companyID, index: index) }
    }
    @discardableResult
    mutating func declineSaleOffer(companyID: Int, offerID: Int) -> SettingResult {
        applySetting(probe: { s in .object(["offers": .number(Double(CompanySale.listing(s, companyID: companyID)?.offers.count ?? -1))]) }) { s, _, _ in CompanySale.decline(&s, companyID: companyID, offerID: offerID) }
    }
    func isListed(companyID: Int) -> Bool { PublicRules.isListed(state, companyID: companyID) }

    func owners(companyID: Int) -> [Shareholders.Holder] { Shareholders.holders(state, companyID: companyID) }
    func ownersPower(companyID: Int) -> (kind: Shareholders.Power, text: String)? { state.company(companyID).map { Shareholders.power($0) } }
    func dividendPolicy(companyID: Int) -> String { state.company(companyID).map { Shareholders.policy($0) } ?? "none" }
    func lastDividendDecision(companyID: Int) -> (week: Int, paid: Double, profit: Double)? {
        guard let d = state.company(companyID)?.value("dq27"), !d.isNull else { return nil }
        return (d["w"].int, d["paid"].double, d["pr"].double)
    }
    @discardableResult
    mutating func setDividendPolicy(companyID: Int, policy: String) -> SettingResult {
        applySetting(refuse: { s in
            if s.company(companyID) == nil { return "That company no longer exists." }
            if policy != "none", let why = JointVenture.payoutBlock(s, companyID: companyID) { return why }
            return Shareholders.policies.contains(policy) ? nil : "That is not a dividend policy."
        }, probe: { $0.company(companyID)?.value("dp27") ?? .null }) { s, _, _ in Shareholders.setPolicy(&s, companyID: companyID, policy: policy) }
    }
    func buyBackPrice(companyID: Int, holder: String) -> Double? { Shareholders.buyBackPrice(state, companyID: companyID, holder: holder, data: data) }
    @discardableResult
    mutating func buyBackStake(companyID: Int, holder: String) -> Bool { var ok = false; update { s, d, _ in ok = Shareholders.buyBack(&s, companyID: companyID, holder: holder, data: d) }; return ok }

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
    @discardableResult
    mutating func declineStartupRound(startupID: Int, index: Int) -> SettingResult {
        applySetting(probe: { .object($0.rest) }) { s, _, _ in Startups.declineRound(&s, startupID: startupID, index: index) }
    }
    @discardableResult
    @discardableResult
    mutating func shutDownStartup(startupID: Int) -> Bool { var r = false; update { s, _, _ in r = Startups.shutDown(&s, startupID: startupID) }; return r }
    @discardableResult
    mutating func changeBuilders(startupID: Int, by delta: Int) -> SettingResult {
        applySetting(refuse: { s in
            guard let f = (s.rest["founded"]?.array ?? []).first(where: { $0["id"].int == startupID }), !f["sw16"].isNull else { return "This startup has no product to build." }
            let n = (s.company(startupID).map { StartupModel.developers($0) } ?? f["sw16"]["devs"].int) + delta
            if n > 10 { return "Ten builders is the most." }
            if n < 0 { return "No builders left to let go." }
            return nil
        }, probe: { .object(["n": .number(Double($0.company(startupID)?.staff.count ?? 0))]) }) { s, d, _ in Startups.setBuilders(&s, startupID: startupID, delta: delta, data: d) }
    }

    @discardableResult
    mutating func acceptBuyerOffer(companyID: Int, offerID: Int) -> Double? {
        var r: Double?
        update { s, d, c in r = CompanySale.accept(&s, companyID: companyID, offerID: offerID, data: d, context: c) }
        return r
    }

    @discardableResult
    mutating func launchStartup(startupID: Int, price: Double, marketingChannel: String? = nil, marketingWeekly: Double = 0) -> Startups.LaunchResult {
        var r = Startups.LaunchResult.notReady
        update { s, _, _ in r = Startups.launch(&s, startupID: startupID, price: price) }
        if r == .ok, let ch = marketingChannel, marketingWeekly > 0 { _ = setCampaign(companyID: startupID, channel: ch, weeklyBudget: marketingWeekly) }
        return r
    }
    @discardableResult
    mutating func setStartupPrice(startupID: Int, price: Double) -> Bool { var ok = false; update { s, _, _ in ok = Startups.setPrice(&s, startupID: startupID, price: price) }; return ok }
    func startupLaunchPreview(startupID: Int, price: Double) -> StartupModel.Funnel? {
        Startups.launchPreview(state, startupID: startupID, price: price, data: data, context: context)
    }

    func capTable(companyID: Int) -> CapTable.Table? { state.company(companyID).map { CapTable.table($0) } }
    func fundingOfferTerms(companyID: Int, offerIndex: Int) -> CapTable.DealTerms? {
        guard let co = state.company(companyID), let o = Funding.offers(state, companyID: companyID).first(where: { $0.id == offerIndex }) else { return nil }
        var conditions: [String] = [o.says]
        if o.kind == "fund" { conditions.append("A seat on the board for the fund.") }
        conditions.append("Another round cannot be pitched for four weeks.")
        return CapTable.issueTerms(co, preMoney: o.preMoney, amount: o.amount, buyer: o.name, conditions: conditions)
    }
    @discardableResult
    mutating func toggleOwnerHoursOnProduct(startupID: Int) -> Bool { var ok = false; update { s, _, _ in ok = Startups.toggleOwnerHours(&s, startupID: startupID) }; return ok }
    @discardableResult
    mutating func toggleProductUse(startupID: Int, companyID: Int) -> Bool { var ok = false; update { s, _, _ in ok = Startups.toggleUse(&s, startupID: startupID, companyID: companyID) }; return ok }
    mutating func setProductInternalPrice(startupID: Int, percent: Double) { update { s, _, _ in Startups.setInternalPrice(&s, startupID: startupID, percent: percent) } }
    func rivalTargetsForProduct(startupID: Int) -> [Startups.RivalTarget] { Startups.rivalTargets(state, startupID: startupID, data: data) }
    @discardableResult
    mutating func pitchProductToRival(startupID: Int, rivalID: Int) -> Bool? { var r: Bool?; update { s, d, _ in r = Startups.pitchToRival(&s, startupID: startupID, rivalID: rivalID, data: d) }; return r }

    var startupStakes: [Startups.Stake] { Startups.stakes(state) }
    @discardableResult
    mutating func investInStartup(pitchID: Int, amount: Double) -> Startups.InvestResult { var r = Startups.InvestResult.gone; update { s, _, c in r = Startups.invest(&s, pitchID: pitchID, amount: amount, context: c) }; return r }
    @discardableResult
    mutating func helpStartupOnBoard(stakeID: Int) -> Bool { var ok = false; update { s, _, _ in ok = Startups.help(&s, stakeID: stakeID) }; return ok }
    @discardableResult
    mutating func sellStartupStake(stakeID: Int, fraction: Double) -> Double { var v = 0.0; update { s, _, _ in v = Startups.sellStake(&s, stakeID: stakeID, fraction: fraction) }; return v }

    var startupPitchesOnOffer: [Startups.Pitch] { Startups.pitchesOnOffer(state) }
    var privateEquityOffersOnTable: [PrivateEquity.Offer] { PrivateEquity.offersOnTable(state) }

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
}
