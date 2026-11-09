import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// What the player can do with energy companies, the salmon farm, holding companies and football clubs, and what screens read about them.
public extension GameEngine {
    // MARK: Energy and salmon

    @discardableResult
    mutating func exploreForOil(companyID: Int) -> EnergyModel.DealResult {
        var r = EnergyModel.DealResult.cash
        update { s, d, _ in if let i = s.companyIndex(companyID), s.companies[i].type == "oilgas" { r = EnergyModel.explore(&s, i, data: d) } }
        return r
    }

    @discardableResult
    mutating func buyOilStake(companyID: Int, thousandBarrels: Double) -> EnergyModel.DealResult {
        var r = EnergyModel.DealResult.cash
        update { s, d, _ in if let i = s.companyIndex(companyID), s.companies[i].type == "oilgas" { r = EnergyModel.acquire(&s, i, kbbl: thousandBarrels, data: d) } }
        return r
    }

    /// Price of one more MW of turbines today, and ordering them (they produce when built). Original: buying 'turb' + `FAM.energy.afterBuy`.
    func turbinePrice(companyID: Int) -> Double {
        guard let co = state.company(companyID), let e = data.catalog[co.type]?.equipment.first(where: { $0.id == "turb" }) else { return 0 }
        return CompanySetup.equipmentPrice(e, company: co, World(state: state, data: data))
    }
    @discardableResult
    mutating func orderTurbines(companyID: Int, megawatts: Double) -> Bool {
        var ok = false
        update { s, d, _ in ok = CompanySetup.buyEquipment(&s, companyID: companyID, equipmentID: "turb", quantity: megawatts, data: d) }
        return ok
    }

    func oilStakePrice(thousandBarrels: Double) -> Double { EnergyModel.stakePrice(kbbl: thousandBarrels, economyOil: state.economy.oil) }
    func explorationCost() -> Double { EnergyModel.explorationCost(inflationIndex: state.economy.inflationIndex) }
    func oilPricePerBarrel(companyID: Int) -> Double {
        let sell = state.company(companyID)?.value("knob")["sell"].int ?? 0
        return EnergyModel.oilPrice(contracts: sell == 1, economyOil: state.economy.oil, inflationIndex: state.economy.inflationIndex)
    }
    func powerPlant(companyID: Int) -> EnergyModel.PlantSummary? { state.company(companyID).map { EnergyModel.plant($0) } }
    func oilFields(companyID: Int) -> [EnergyModel.FieldInfo] { state.company(companyID).map { EnergyModel.fields($0) } ?? [] }
    func salmonCohorts(companyID: Int) -> [SalmonModel.FishCohort] { state.company(companyID).map { SalmonModel.cohorts($0) } ?? [] }
    func salmonPricePerKilo() -> Double { SalmonModel.spotPerKilo(economy: state.economy.salmon) }

    /// Stop or restart stocking new fish and harvesting ripe ones.
    mutating func setSalmonAutomation(companyID: Int, stocking: Bool, harvesting: Bool) {
        update { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            var f = s.companies[i].value("flags")
            f["autoStock"] = stocking ? 1 : 0; f["harvest"] = harvesting ? 1 : 0
            s.companies[i].set("flags", f)
        }
    }

    // MARK: Holding company

    mutating func createHolding(name: String?, companies: [Int], accountantID: Int? = nil) -> Result<Int, HoldingModel.Failure> {
        var r: Result<Int, HoldingModel.Failure> = .failure(.notAllowed)
        update { s, d, c in r = HoldingModel.create(&s, name: name, accountantID: accountantID, companies: companies, data: d, context: c) }
        return r
    }
    /// Register a holding and put the chosen part of each company under it (`percent` of the whole company from your own shares; 100 is all of it).
    mutating func createHolding(name: String?, stakes: [HoldingModel.StakeInput], accountantID: Int? = nil) -> Result<Int, HoldingModel.Failure> {
        var r: Result<Int, HoldingModel.Failure> = .failure(.notAllowed)
        update { s, d, c in r = HoldingModel.create(&s, name: name, accountantID: accountantID, stakes: stakes, data: d, context: c) }
        return r
    }
    @discardableResult mutating func moveToHolding(companyID: Int, holdingID: Int) -> Bool {
        var ok = false; update { s, d, _ in ok = HoldingModel.move(&s, companyID: companyID, into: holdingID, data: d) }; return ok
    }
    /// Put only `percent` of the company (from your own shares) under the holding; you keep the rest personally. 100 is the whole company.
    @discardableResult
    mutating func moveToHolding(companyID: Int, holdingID: Int, percent: Double) -> Result<Double, HoldingStakes.Failure> {
        var r: Result<Double, HoldingStakes.Failure> = .failure(.notFound)
        update { s, d, _ in r = HoldingStakes.moveShare(&s, companyID: companyID, into: holdingID, percent: percent, data: d) }
        return r
    }
    /// Take the shares a holding bought or was given (not the whole-company move) back to you.
    @discardableResult
    mutating func holdingReleaseStake(holdingID: Int, companyID: Int) -> Bool {
        var ok = false; update { s, d, _ in ok = HoldingStakes.releaseStake(&s, companyID: companyID, from: holdingID, data: d) }; return ok
    }
    @discardableResult mutating func releaseFromHolding(companyID: Int) -> Bool {
        var ok = false; update { s, d, _ in ok = HoldingModel.release(&s, companyID: companyID, data: d) }; return ok
    }
    @discardableResult mutating func holdingInvest(holdingID: Int, amount: Double) -> Bool {
        var ok = false; update { s, _, _ in ok = HoldingModel.invest(&s, holdingID: holdingID, amount: amount) }; return ok
    }
    @discardableResult mutating func holdingDivest(holdingID: Int, amount: Double) -> Bool {
        var ok = false; update { s, _, _ in ok = HoldingModel.divest(&s, holdingID: holdingID, amount: amount) }; return ok
    }
    var holdingCompanies: [Company] { HoldingModel.holdings(in: state) }
    func holdingOverview(companyID: Int) -> HoldingModel.Consolidated? {
        state.company(companyID).map { HoldingModel.consolidated($0, state, trades: data.catalog) }
    }
    /// Limited companies that can still be put under a holding.
    var companiesForHolding: [Company] {
        state.companies.filter { $0.status.isLive && $0.type != "hold" && $0.holdingID == 0 && $0.form == .limited }
    }

    // MARK: Holding stakes (buying other companies in whole or in part)

    /// Companies and rivals a holding could buy shares of, with their value and asking price per percent.
    func holdingStakeOffers(holdingID: Int) -> [HoldingStakes.Offer] { HoldingStakes.offers(state, holdingID: holdingID, data: data) }
    func holdingStakeQuote(holdingID: Int, companyID: Int, percent: Double, from source: HoldingStakes.Source = .auto) -> Result<HoldingStakes.Quote, HoldingStakes.Failure> {
        HoldingStakes.quote(state, holdingID: holdingID, companyID: companyID, percent: percent, from: source, data: data)
    }
    func holdingRivalStakeQuote(holdingID: Int, rivalID: Int, percent: Double) -> Result<HoldingStakes.Quote, HoldingStakes.Failure> {
        HoldingStakes.rivalQuote(state, holdingID: holdingID, rivalID: rivalID, percent: percent, data: data)
    }
    /// The holding pays from its own cash (put cash in first with `injectCash(companyID:amount:)`). The owner's shares go first, at fair value.
    @discardableResult
    mutating func holdingBuyStake(holdingID: Int, companyID: Int, percent: Double, from source: HoldingStakes.Source = .auto) -> Result<HoldingStakes.Deal, HoldingStakes.Failure> {
        var r: Result<HoldingStakes.Deal, HoldingStakes.Failure> = .failure(.notFound)
        update { s, d, _ in r = HoldingStakes.buy(&s, holdingID: holdingID, companyID: companyID, percent: percent, from: source, data: d) }
        return r
    }
    /// The loan a holding would need for the part of the price its cash does not cover: size, rate (policy rate plus margins), instalment, lender and
    /// the holding's debt after. `allowed` is false with a `reason` when the lender would refuse.
    func holdingBuyLoanQuote(holdingID: Int, companyID: Int, percent: Double, from source: HoldingStakes.Source = .auto, termMonths: Int = 60) -> Result<HoldingStakes.BorrowTerms, HoldingStakes.Failure> {
        HoldingStakes.borrowTerms(state, holdingID: holdingID, companyID: companyID, percent: percent, from: source, termMonths: termMonths, data: data, context: context)
    }
    /// Buy the stake, borrowing the shortfall. The loan is the holding's own (shown in its debt, instalments taken monthly from its account);
    /// nothing changes when it is refused.
    @discardableResult
    mutating func holdingBuyStakeWithLoan(holdingID: Int, companyID: Int, percent: Double, from source: HoldingStakes.Source = .auto, termMonths: Int = 60) -> Result<HoldingStakes.LoanDeal, HoldingStakes.Failure> {
        var r: Result<HoldingStakes.LoanDeal, HoldingStakes.Failure> = .failure(.notFound)
        update { s, d, c in r = HoldingStakes.buyWithLoan(&s, holdingID: holdingID, companyID: companyID, percent: percent, from: source, termMonths: termMonths, data: d, context: c) }
        return r
    }
    @discardableResult
    mutating func holdingBuyRivalStake(holdingID: Int, rivalID: Int, percent: Double) -> Result<HoldingStakes.Deal, HoldingStakes.Failure> {
        var r: Result<HoldingStakes.Deal, HoldingStakes.Failure> = .failure(.notFound)
        update { s, d, _ in r = HoldingStakes.buyRival(&s, holdingID: holdingID, rivalID: rivalID, percent: percent, data: d) }
        return r
    }
    func holdingSellStakeQuote(holdingID: Int, companyID: Int, percent: Double, to buyer: HoldingStakes.Buyer = .market) -> Result<HoldingStakes.Quote, HoldingStakes.Failure> {
        HoldingStakes.sellQuote(state, holdingID: holdingID, companyID: companyID, percent: percent, to: buyer, data: data)
    }
    @discardableResult
    mutating func holdingSellStake(holdingID: Int, companyID: Int, percent: Double, to buyer: HoldingStakes.Buyer = .market) -> Result<HoldingStakes.Deal, HoldingStakes.Failure> {
        var r: Result<HoldingStakes.Deal, HoldingStakes.Failure> = .failure(.notFound)
        update { s, d, _ in r = HoldingStakes.sell(&s, holdingID: holdingID, companyID: companyID, percent: percent, to: buyer, data: d) }
        return r
    }
    @discardableResult
    mutating func holdingSellRivalStake(holdingID: Int, rivalID: Int, percent: Double) -> Result<HoldingStakes.Deal, HoldingStakes.Failure> {
        var r: Result<HoldingStakes.Deal, HoldingStakes.Failure> = .failure(.notFound)
        update { s, d, _ in r = HoldingStakes.sellRival(&s, holdingID: holdingID, rivalID: rivalID, percent: percent, data: d) }
        return r
    }
    /// The holding's share of a company in percent (bought shares plus your shares moved under it) and the tier that share gives.
    func holdingStakePercent(holdingID: Int, companyID: Int) -> Double {
        state.company(companyID).map { HoldingStakes.sharePercent(of: $0, holdingID: holdingID) } ?? 0
    }
    func holdingStakeTier(holdingID: Int, companyID: Int) -> HoldingStakes.Tier { HoldingStakes.tier(state, holdingID: holdingID, companyID: companyID) }
    func holdingRivalStakes(holdingID: Int) -> [HoldingStakes.RivalStake] { state.company(holdingID).map { HoldingStakes.rivalStakes($0) } ?? [] }
    /// Every company the holding owns shares of, with its stake in percent, largest first.
    func holdingStakes(holdingID: Int) -> [(company: Company, percent: Double, tier: HoldingStakes.Tier)] {
        HoldingStakes.stakeCompanies(of: holdingID, in: state).map { c -> (company: Company, percent: Double, tier: HoldingStakes.Tier) in
            let p = HoldingStakes.sharePercent(of: c, holdingID: holdingID)
            return (c, p, HoldingStakes.tier(forPercent: p))
        }.sorted { $0.percent > $1.percent }
    }
    func holdingMergeTerms(holdingID: Int, companyID: Int) -> HoldingStakes.MergeTerms { HoldingStakes.mergeTerms(state, holdingID: holdingID, companyID: companyID, data: data) }
    /// Buy out every other owner at fair value and make the holding the only owner. Returns what the holding paid.
    @discardableResult
    mutating func holdingMergeStake(holdingID: Int, companyID: Int) -> Result<Double, HoldingStakes.Failure> {
        var r: Result<Double, HoldingStakes.Failure> = .failure(.notFound)
        update { s, d, _ in r = HoldingStakes.merge(&s, holdingID: holdingID, companyID: companyID, data: d) }
        return r
    }
    /// What turning the company into a division of the holding (or of `hostID`, another company the holding owns outright) would mean. Nothing is changed.
    func holdingDivisionTerms(holdingID: Int, companyID: Int, hostID: Int? = nil) -> HoldingStakes.DivisionTerms {
        HoldingStakes.divisionTerms(state, holdingID: holdingID, companyID: companyID, hostID: hostID, data: data)
    }
    /// The company stops being a separate company: it keeps trade, staff, items and cash, and its value stays in the group.
    @discardableResult
    mutating func holdingMakeDivision(holdingID: Int, companyID: Int, hostID: Int? = nil) -> Result<HoldingStakes.DivisionTerms, HoldingStakes.Failure> {
        var r: Result<HoldingStakes.DivisionTerms, HoldingStakes.Failure> = .failure(.notFound)
        update { s, d, _ in r = HoldingStakes.makeDivision(&s, holdingID: holdingID, companyID: companyID, hostID: hostID, data: d) }
        return r
    }
    /// The divisions of a holding or of one of its companies.
    func holdingDivisions(hostID: Int) -> [Company] { HoldingStakes.divisions(of: hostID, in: state) }

    /// Companies the holding sits on the board of (a controlling stake, or a seat it took), where its owner can talk to the people.
    func holdingSeatedCompanies(holdingID: Int) -> [Company] {
        HoldingStakes.stakeCompanies(of: holdingID, in: state).filter { HoldingStakes.seatStatus(state, holdingID: holdingID, companyID: $0.id).hasSeat }
    }
    private func seatedCompany(_ holdingID: Int, _ companyID: Int) -> HoldingStakes.Failure? {
        let seat = HoldingStakes.seatStatus(state, holdingID: holdingID, companyID: companyID)
        if seat.hasSeat { return nil }
        return HoldingStakes.Failure.refused(seat.reason.isEmpty ? "The holding has no seat on this board." : seat.reason)
    }
    /// The talks at a board the holding sits on: the same people, topics and scenes as `ownerCounterparts` and the rest, for the company's id.
    func holdingOwnerCounterparts(holdingID: Int, companyID: Int) -> Result<[OwnerMeetings.Counterpart], HoldingStakes.Failure> {
        if let f = seatedCompany(holdingID, companyID) { return .failure(f) }
        return .success(ownerCounterparts(companyID: companyID))
    }
    func holdingOwnerTopics(holdingID: Int, companyID: Int, personID: Int) -> Result<[OwnerMeetings.Topic], HoldingStakes.Failure> {
        if let f = seatedCompany(holdingID, companyID) { return .failure(f) }
        return .success(ownerTopics(companyID: companyID, personID: personID))
    }
    func holdingOwnerScene(holdingID: Int, companyID: Int, personID: Int, topic: String) -> Result<OwnerMeetings.Scene, HoldingStakes.Failure> {
        if let f = seatedCompany(holdingID, companyID) { return .failure(f) }
        guard let sc = ownerScene(companyID: companyID, personID: personID, topic: topic) else { return .failure(.notFound) }
        return .success(sc)
    }
    @discardableResult
    mutating func holdingOwnerChoose(holdingID: Int, companyID: Int, personID: Int, topic: String, choice: String) -> Result<OwnerMeetings.Outcome, HoldingStakes.Failure> {
        if let f = seatedCompany(holdingID, companyID) { return .failure(f) }
        guard let o = ownerChoose(companyID: companyID, personID: personID, topic: topic, choice: choice) else { return .failure(.notFound) }
        return .success(o)
    }
    func holdingBoardSeat(holdingID: Int, companyID: Int) -> HoldingStakes.SeatStatus { HoldingStakes.seatStatus(state, holdingID: holdingID, companyID: companyID) }
    @discardableResult
    mutating func holdingTakeBoardSeat(holdingID: Int, companyID: Int) -> Result<Void, HoldingStakes.Failure> {
        var r: Result<Void, HoldingStakes.Failure> = .failure(.notFound)
        update { s, _, _ in r = HoldingStakes.takeSeat(&s, holdingID: holdingID, companyID: companyID) }
        return r
    }
    @discardableResult
    mutating func holdingLeaveBoardSeat(holdingID: Int, companyID: Int) -> Result<Void, HoldingStakes.Failure> {
        var r: Result<Void, HoldingStakes.Failure> = .failure(.notFound)
        update { s, _, _ in r = HoldingStakes.leaveSeat(&s, holdingID: holdingID, companyID: companyID) }
        return r
    }
    /// The boardroom round of a company the holding sits on the board of (the same round the owner gets). Talks with the people go on through
    /// `ownerCounterparts`, `ownerTopics`, `ownerScene` and `ownerChoose` with the company's id.
    func holdingBoardRound(holdingID: Int, companyID: Int) -> Result<[OwnerMeetings.RoundLine], HoldingStakes.Failure> {
        let seat = HoldingStakes.seatStatus(state, holdingID: holdingID, companyID: companyID)
        guard seat.hasSeat else { return .failure(.refused(seat.reason.isEmpty ? "The holding has no seat on this board." : seat.reason)) }
        return .success(OwnerMeetings.boardRound(state, companyID: companyID, data: data))
    }
    /// What the board and the owners say to a sale, a closing or a loan (kind "sell", "close" or "loan"); the holding's shares vote with yours.
    func holdingBoardVote(holdingID: Int, companyID: Int, kind: String, amount: Double = 0) -> Result<ManagerModel.BoardVote, HoldingStakes.Failure> {
        let seat = HoldingStakes.seatStatus(state, holdingID: holdingID, companyID: companyID)
        guard seat.hasSeat else { return .failure(.refused(seat.reason.isEmpty ? "The holding has no seat on this board." : seat.reason)) }
        return .success(ManagerModel.boardVote(state, kind: kind, companyID: companyID, amount: amount, advisory: true))
    }

    // MARK: Football

    func leagueCountries() -> [Country] { FootballModel.countriesWithLeague(data) }
    func leagueInfo(countryCode: String) -> FootballModel.LeagueInfo? { data.countries[countryCode].flatMap { FootballModel.leagueInfo($0) } }
    func clubsForSale(countryCode: String) -> [FootballModel.ClubInfo] {
        data.countries[countryCode].map { FootballModel.clubList(state, country: $0) } ?? []
    }
    func foundingCost(countryCode: String) -> Double? { data.countries[countryCode].flatMap { FootballModel.foundingValue($0) }.map { ($0 * 0.4).rounded() } }

    private mutating func prepareLeague(_ countryCode: String) {
        update { s, d, _ in if let c = d.countries[countryCode] { FootballModel.ensureClubs(&s, c) } }
    }

    mutating func offerForClub(clubID: String, multiple: Double) -> FootballModel.Offer {
        let code = String(clubID.split(separator: ":").first ?? "")
        prepareLeague(code)
        var r = FootballModel.Offer(answer: .ignore, price: nil, debt: 0, message: "")
        update { s, d, c in r = FootballModel.propose(&s, clubID: clubID, multiple: multiple, currency: c.currency(code, s)) }
        return r
    }
    func clubPurchasePlan(clubID: String, price: Double) -> FootballModel.PurchasePlan? { FootballModel.purchasePlan(state, clubID: clubID, price: price) }
    /// Football clubs are hidden from the game: only a test or a tool passes `allowRetired`.
    mutating func buyClub(clubID: String, price: Double, allowRetired: Bool = false) -> FootballModel.BuyResult {
        var r = FootballModel.BuyResult.notAvailable
        guard allowRetired || !SpecialFamilies.retiredTrades.contains("club") else { return r }
        update { s, d, c in r = FootballModel.buy(&s, clubID: clubID, price: price, data: d, context: c) }
        return r
    }
    mutating func foundClub(countryCode: String, allowRetired: Bool = false) -> FootballModel.BuyResult {
        var r = FootballModel.BuyResult.notAvailable
        guard allowRetired || !SpecialFamilies.retiredTrades.contains("club") else { return r }
        update { s, d, _ in if let c = d.countries[countryCode] { r = FootballModel.found(&s, country: c, cityID: nil, data: d) } }
        return r
    }
    func clubSummary(companyID: Int) -> FootballModel.Summary? { state.company(companyID).flatMap { FootballModel.summary($0, state, data: data) } }
    mutating func setClubWageShare(companyID: Int, share: Double) { update { s, _, _ in FootballModel.setWageShare(&s, companyID: companyID, share: share) } }
    mutating func setClubTicketLevel(companyID: Int, level: Int) { update { s, _, _ in FootballModel.setTicketLevel(&s, companyID: companyID, level: level) } }
    @discardableResult mutating func signSponsor(companyID: Int, slot: String, offerID: Int) -> FootballModel.SponsorResult {
        var r = FootballModel.SponsorResult.gone
        update { s, _, _ in if let i = s.companyIndex(companyID) { r = FootballModel.takeSponsor(&s, companyIndex: i, slot: slot, offerID: offerID) } }
        return r
    }
    mutating func clubCandidates(companyID: Int, kind: String) -> [FootballModel.Coach] {
        var r: [FootballModel.Coach] = []
        update { s, d, _ in r = FootballModel.candidates(&s, companyID: companyID, kind: kind, data: d) }
        return r
    }
    /// True when the coach was taken on (the company is a club).
    @discardableResult
    mutating func hireCoach(companyID: Int, coach: FootballModel.Coach, kind: String) -> Bool {
        var ok = false
        update { s, _, _ in ok = FootballModel.hire(&s, companyID: companyID, coach: coach, kind: kind) }
        return ok
    }
    /// True when there was someone in the post to let go.
    @discardableResult
    mutating func dismissCoach(companyID: Int, kind: String) -> Bool {
        var ok = false
        update { s, d, _ in
            guard let i = s.companyIndex(companyID) else { return }
            let fm = s.companies[i].value("fm")
            ok = kind == "coach" ? !fm["coach"].isNull : !fm["asst"].isNull
            if kind == "coach" { FootballModel.sackManager(&s, companyIndex: i, reason: "your decision", data: d) } else { FootballModel.dismissAssistant(&s, companyID: companyID) }
        }
        return ok
    }
    func transferWindow(companyID: Int) -> (name: String?, weeksToOpen: Int) { FootballModel.window(state, companyID: companyID) }
    func signingFee(companyID: Int, tier: Int) -> Double { FootballModel.signingFee(state, companyID: companyID, tier: tier) }
    @discardableResult mutating func signPlayer(companyID: Int, tier: Int) -> FootballModel.SignResult {
        var r = FootballModel.SignResult.closed
        update { s, _, _ in r = FootballModel.sign(&s, companyID: companyID, tier: tier) }
        return r
    }

    // MARK: Insights

    internal func specialInsights(for co: Company) -> [Insight] {
        var out: [Insight] = []
        let cur = currency(for: co)
        guard co.status == .open else { return out }
        switch co.type {
        case "power":
            let p = EnergyModel.plant(co)
            if p.building > 0 { out.append(Insight(id: "build", symbol: "hammer", text: "\(Int(p.building)) MW under construction\(p.weeksToReady.map { ", the first ready in \($0) weeks" } ?? "").", tone: .neutral)) }
            if p.megawatts == 0 && p.building == 0 { out.append(Insight(id: "nomw", symbol: "bolt.slash", text: "No generating capacity yet. Order turbines under Assets.", tone: .warn)) }
            if co.value("knob")["hedge"].int == 0, p.megawatts > 0 { out.append(Insight(id: "spot", symbol: "chart.line.uptrend.xyaxis", text: "All output is sold at the spot price, so income follows the power market.", tone: .neutral)) }
        case "oilgas":
            let f = EnergyModel.fields(co)
            let dev = f.filter { $0.state == "dev" }, prod = f.filter { $0.state == "prod" }
            if prod.isEmpty && dev.isEmpty { out.append(Insight(id: "nofield", symbol: "drop", text: "No field yet. Buy a stake in a producing field or drill an exploration well.", tone: .warn)) }
            if let d = dev.first { out.append(Insight(id: "dev", symbol: "hammer", text: "\(d.name) is in development, \(d.weeksToProduction) weeks to first oil.", tone: .neutral)) }
            if state.economy.oil < 0.8 { out.append(Insight(id: "oilprice", symbol: "arrow.down.right", text: "The oil price is low (\(Int(saturating: (state.economy.oil * 100).rounded()))% of normal). Term contracts would cushion it.", tone: .warn)) }
        case "salmon":
            let c = SalmonModel.cohorts(co)
            if c.isEmpty { out.append(Insight(id: "nofish", symbol: "fish", text: "No fish in the pens. A new cohort is stocked when the cash allows.", tone: .warn)) }
            else if let r = c.map({ $0.readyShare }).max() { out.append(Insight(id: "fish", symbol: "fish", text: r >= 0.9 ? "A cohort is nearly ready for harvest." : "The oldest cohort has reached \(Int(saturating: (r * 100).rounded()))% of harvest weight.", tone: r >= 0.9 ? .good : .neutral)) }
            if state.economy.salmon < 0.8 { out.append(Insight(id: "salmonprice", symbol: "arrow.down.right", text: "The salmon price is low (\(Int(saturating: (state.economy.salmon * 100).rounded()))% of normal).", tone: .warn)) }
        case "hold":
            let o = HoldingModel.consolidated(co, state, trades: data.catalog)
            out.append(Insight(id: "holdvalue", symbol: "building.columns", text: "The holding is worth \(cur.short(o.holdingValue)): \(cur.short(o.companiesValue)) in companies, \(cur.short(o.indexFund)) in the index fund, \(cur.short(co.cash)) in cash.", tone: .neutral))
            if o.groupCovered > 0 { out.append(Insight(id: "taxgroup", symbol: "arrow.triangle.merge", text: "Profits cover \(cur.short(o.groupCovered)) of sister companies' losses this year, saving tax.", tone: .good)) }
        case "club":
            if let c = FootballModel.summary(co, state, data: data) {
                if c.wageToRevenue > 0.75 { out.append(Insight(id: "clubwages", symbol: "banknote", text: "Player and coach wages take \(Int(saturating: (c.wageToRevenue * 100).rounded()))% of revenue.", tone: .warn)) }
                if c.coach == nil { out.append(Insight(id: "nocoach", symbol: "person.fill.questionmark", text: "The club has no manager.", tone: .bad)) }
                else if c.coach?.interim == true { out.append(Insight(id: "interim", symbol: "person.fill.questionmark", text: "A temporary manager is in charge. Hire a permanent one.", tone: .warn)) }
                if c.position > 0, c.clubs > 3, c.division == 1, c.position > c.clubs - 3, c.played > 10 { out.append(Insight(id: "relegation", symbol: "arrow.down.circle", text: "In the relegation places: \(c.position) of \(c.clubs).", tone: .bad)) }
            }
        default: break
        }
        return out
    }
}
