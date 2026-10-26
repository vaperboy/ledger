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
    func explorationCost() -> Double { EnergyModel.explorationCost(inflation: state.economy.inflation, week: state.week) }
    func oilPricePerBarrel(companyID: Int) -> Double {
        let sell = state.company(companyID)?.value("knob")["sell"].int ?? 0
        return EnergyModel.oilPrice(contracts: sell == 1, economyOil: state.economy.oil, inflation: state.economy.inflation, week: state.week)
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
    @discardableResult mutating func moveToHolding(companyID: Int, holdingID: Int) -> Bool {
        var ok = false; update { s, d, _ in ok = HoldingModel.move(&s, companyID: companyID, into: holdingID, data: d) }; return ok
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
    mutating func buyClub(clubID: String, price: Double) -> FootballModel.BuyResult {
        var r = FootballModel.BuyResult.notAvailable
        update { s, d, c in r = FootballModel.buy(&s, clubID: clubID, price: price, data: d, context: c) }
        return r
    }
    mutating func foundClub(countryCode: String) -> FootballModel.BuyResult {
        var r = FootballModel.BuyResult.notAvailable
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
            if state.economy.oil < 0.8 { out.append(Insight(id: "oilprice", symbol: "arrow.down.right", text: "The oil price is low (\(Int((state.economy.oil * 100).rounded()))% of normal). Term contracts would cushion it.", tone: .warn)) }
        case "salmon":
            let c = SalmonModel.cohorts(co)
            if c.isEmpty { out.append(Insight(id: "nofish", symbol: "fish", text: "No fish in the pens. A new cohort is stocked when the cash allows.", tone: .warn)) }
            else if let r = c.map({ $0.readyShare }).max() { out.append(Insight(id: "fish", symbol: "fish", text: r >= 0.9 ? "A cohort is nearly ready for harvest." : "The oldest cohort has reached \(Int((r * 100).rounded()))% of harvest weight.", tone: r >= 0.9 ? .good : .neutral)) }
            if state.economy.salmon < 0.8 { out.append(Insight(id: "salmonprice", symbol: "arrow.down.right", text: "The salmon price is low (\(Int((state.economy.salmon * 100).rounded()))% of normal).", tone: .warn)) }
        case "hold":
            let o = HoldingModel.consolidated(co, state, trades: data.catalog)
            out.append(Insight(id: "holdvalue", symbol: "building.columns", text: "The holding is worth \(cur.short(o.holdingValue)): \(cur.short(o.companiesValue)) in companies, \(cur.short(o.indexFund)) in the index fund, \(cur.short(co.cash)) in cash.", tone: .neutral))
            if o.groupCovered > 0 { out.append(Insight(id: "taxgroup", symbol: "arrow.triangle.merge", text: "Profits cover \(cur.short(o.groupCovered)) of sister companies' losses this year, saving tax.", tone: .good)) }
        case "club":
            if let c = FootballModel.summary(co, state, data: data) {
                if c.wageToRevenue > 0.75 { out.append(Insight(id: "clubwages", symbol: "banknote", text: "Player and coach wages take \(Int((c.wageToRevenue * 100).rounded()))% of revenue.", tone: .warn)) }
                if c.coach == nil { out.append(Insight(id: "nocoach", symbol: "person.fill.questionmark", text: "The club has no manager.", tone: .bad)) }
                else if c.coach?.interim == true { out.append(Insight(id: "interim", symbol: "person.fill.questionmark", text: "A temporary manager is in charge. Hire a permanent one.", tone: .warn)) }
                if c.position > 0, c.clubs > 3, c.division == 1, c.position > c.clubs - 3, c.played > 10 { out.append(Insight(id: "relegation", symbol: "arrow.down.circle", text: "In the relegation places: \(c.position) of \(c.clubs).", tone: .bad)) }
            }
        default: break
        }
        return out
    }
}
