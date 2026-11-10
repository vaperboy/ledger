import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses
import Investments
import Events

public extension GameEngine {
    enum ActionResult: Equatable { case done, refused(String) }

    mutating func startCompany(tradeID: String, cityID: String, size: Double? = nil, name: String? = nil, countryCode: String? = nil,
                               accountantID: Int? = nil, quickSetup: Bool = true, allowRetired: Bool = false) -> Result<Int, CompanySetup.StartError> {
        var result: Result<Int, CompanySetup.StartError> = .failure(.notAllowedHere)
        guard let trade = data.catalog[tradeID],
              SpecialFamilies.isStartable(trade) || (allowRetired && SpecialFamilies.isRetired(trade) && CompanyWeek.isSupported(trade)) else { return .failure(.notYetAvailable) }
        update { s, data, ctx in
            result = CompanySetup.create(&s, tradeID: tradeID, cityID: cityID, size: size, name: name, countryCode: countryCode, accountantID: accountantID, data: data, context: ctx)
            if case .success(let id) = result {
                if quickSetup && Tutorial.isComplete(s) { _ = CompanySetup.quickSetup(&s, companyID: id, data: data) }
                s.note("You started \(s.company(id)?.name ?? "a company").", tone: "good", companyID: id)
            }
        }
        return result
    }

    @discardableResult
    mutating func setPriceLevel(companyID: Int, level: Double) -> SettingResult {
        applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.companySnapshot(companyID) }) { s, _, _ in
            if let i = s.companyIndex(companyID) { s.companies[i].priceLevel = clamp(level, -3, 3); s.companies[i].set("chose", 1) }
        }
    }

    @discardableResult
    mutating func setOwnerHours(companyID: Int, hours: Double) -> SettingResult {
        applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.companySnapshot(companyID) }) { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            let others = CapacityModel.ownerHoursCommitted(s, except: companyID)
            s.companies[i].ownerHours = max(0, min(hours, 80 - others))
        }
    }

    @discardableResult
    mutating func setWorksHere(companyID: Int, works: Bool) -> SettingResult {
        applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.companySnapshot(companyID) }) { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            if works {
                s.companies[i].raw["ownOut"] = nil
                let room = max(0, OwnerHours.weeklyCap - CapacityModel.ownerHoursCommitted(s, except: companyID))
                s.companies[i].ownerHours = min(40, room)
            } else {
                s.companies[i].set("ownOut", true)
                s.companies[i].ownerHours = 0
            }
        }
    }

    mutating func setMaintenance(companyID: Int, level: Int) { update { s, _, _ in if let i = s.companyIndex(companyID) { s.companies[i].maintenance = min(2, max(0, level)) } } }
    mutating func setStockPolicy(companyID: Int, level: Int) { update { s, _, _ in if let i = s.companyIndex(companyID) { s.companies[i].set("stockPol", min(2, max(0, level))) } } }

    @discardableResult
    mutating func toggleKnobOption(companyID: Int, knob: String, option: Int, on: Bool) -> ActionResult {
        var result = ActionResult.done
        update { s, data, _ in
            guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type],
                  let k = bd.knobs.first(where: { $0.id == knob }), k.isMulti, k.options.indices.contains(option) else { result = .refused("not a choice of this business"); return }
            let now = KnobChange.currentValue(s.companies[i], k)
            let mask = Knobs.mask(now, option: option, on: on)
            if mask == now { return }
            if case .refused(let why) = KnobChange.apply(&s, data, companyID: companyID, knob: knob, value: mask) { result = .refused(why) }
        }
        return result
    }

    func knobChangeQuote(companyID: Int, knob: String, option: Int) -> KnobChangeQuote? {
        KnobChange.quote(state, data, companyID: companyID, knob: knob, value: option)
    }

    func knobToggleQuote(companyID: Int, knob: String, option: Int, on: Bool) -> KnobChangeQuote? {
        guard let co = state.company(companyID), let k = data.catalog[co.type]?.knobs.first(where: { $0.id == knob }), k.isMulti else { return nil }
        return KnobChange.quote(state, data, companyID: companyID, knob: knob, value: Knobs.mask(KnobChange.currentValue(co, k), option: option, on: on))
    }

    func knobOptionMonthlyCost(companyID: Int, knob: String, option: Int) -> Double? {
        guard let co = state.company(companyID), let k = data.catalog[co.type]?.knobs.first(where: { $0.id == knob }), k.options.indices.contains(option) else { return nil }
        return KnobChange.monthlyRunningCost(state, data, option: k.options[option])
    }

    func knobChangePreview(companyID: Int, knob: String, option: Int) -> KnobPreview? {
        KnobChange.preview(state, data, marketing: marketing, companyID: companyID, knob: knob, value: option)
    }

    func knobTogglePreview(companyID: Int, knob: String, option: Int, on: Bool) -> KnobPreview? {
        guard let co = state.company(companyID), let k = data.catalog[co.type]?.knobs.first(where: { $0.id == knob }), k.isMulti else { return nil }
        return knobChangePreview(companyID: companyID, knob: knob, option: Knobs.mask(KnobChange.currentValue(co, k), option: option, on: on))
    }

    func knobGovernedBy(companyID: Int, knob: String) -> String? { state.company(companyID).flatMap { KnobChange.governedBy(state, $0, knob: knob) } }

    @discardableResult
    mutating func changeKnob(companyID: Int, knob: String, option: Int) -> KnobChangeOutcome {
        var out = KnobChangeOutcome.refused("not a choice of this business")
        update { s, data, _ in
            guard let co = s.company(companyID), let k = data.catalog[co.type]?.knobs.first(where: { $0.id == knob }), !k.isMulti else { return }
            out = KnobChange.apply(&s, data, companyID: companyID, knob: knob, value: option)
        }
        return out
    }

    mutating func setCampaign(companyID: Int, channel: String, weeklyBudget: Double, weeks: Int? = nil) -> ActionResult {
        var result = ActionResult.done
        let channels = marketing.channels
        update { s, data, _ in
            guard let i = s.companyIndex(companyID), let c = channels[channel] else { result = .refused("unknown channel"); return }
            if c.offered(in: World(state: s, data: data).country(s.companies[i])) == nil { result = .refused("not available in this country"); return }
            if let only = c.onlyInCountry, only != s.companies[i].countryCode { result = .refused("not available in this country"); return }
            if weeklyBudget > 0, let why = FranchiseStandards.campaignRefusal(s.companies[i], channel: channel) { result = .refused(why); return }
            if Marketing.runByChain(s.companies[i], channel: channel, state: s) { result = .refused("the chain runs this marketing"); return }
            var mkt = s.companies[i].value("mkt")
            var mktEnd = s.companies[i].value("mktEnd")
            let cur = mkt[channel]
            if let w = weeks, w > 0, weeklyBudget > 0 {
                if w < c.minimumWeeks { result = .refused("this channel needs at least \(c.minimumWeeks) weeks"); return }
                if !cur.isNull, !cur["lock"].isNull, Double(s.week + w) < cur["lock"].double { result = .refused("locked for \(Int(cur["lock"].double) - s.week) more weeks"); return }
            }
            if weeklyBudget <= 0 {
                if !cur.isNull, !cur["lock"].isNull, Double(s.week) < cur["lock"].double { result = .refused("locked for \(Int(cur["lock"].double) - s.week) more weeks"); return }
                mkt = Marketing.removing(mkt, channel)
                mktEnd = Marketing.removing(mktEnd, channel)
            } else if !cur.isNull {
                if weeklyBudget < cur["b"].double, !cur["lock"].isNull, Double(s.week) < cur["lock"].double { result = .refused("locked for \(Int(cur["lock"].double) - s.week) more weeks"); return }
                mkt[channel]["b"] = .number(weeklyBudget)
            } else {
                mkt[channel] = .object(["b": .number(weeklyBudget), "since": .number(Double(s.week)), "lock": .number(Double(s.week + c.minimumWeeks))])
                mktEnd = Marketing.removing(mktEnd, channel)
            }
            if weeklyBudget > 0, let w = weeks {
                if w > 0 { mktEnd[channel] = .number(Double(s.week + w)) } else { mktEnd = Marketing.removing(mktEnd, channel) }
            }
            s.companies[i].set("mkt", mkt)
            s.companies[i].set("mktEnd", mktEnd)
        }
        return result
    }

    func marketingChannels(companyID: Int) -> [MarketingChannel] {
        guard let co = state.company(companyID) else { return [] }
        let country = World(state: state, data: data).country(co)
        return marketing.channels.values.compactMap { $0.offered(in: country) }
            .filter { $0.onlyInCountry == nil || $0.onlyInCountry == co.countryCode }
            .sorted { $0.isPrimeTime != $1.isPrimeTime ? !$0.isPrimeTime : $0.name < $1.name }
    }

    func campaignPlan(companyID: Int, channel: String, weeklyBudget: Double, weeks: Int?) -> CampaignPlan? {
        guard let co = state.company(companyID), let c = marketing.channels[channel] else { return nil }
        let cur = co.value("mkt")[channel]
        let left = cur.isNull || cur["lock"].isNull ? 0 : max(0, Int(cur["lock"].double) - state.week)
        let w = (weeks ?? 0) > 0 ? weeks : nil
        let util = co.value("lastW")["util"].double
        return CampaignPlan(lockedWeeks: cur.isNull ? c.minimumWeeks : left, weeks: w, totalCost: w.map { weeklyBudget * Double($0) },
                            nearCapacity: util > 0.9, runByChain: Marketing.runByChain(co, channel: channel, state: state),
                            blocked: FranchiseStandards.campaignRefusal(co, channel: channel))
    }

    mutating func searchWorkers(companyID: Int, role: String, mode: Hiring.SearchMode) -> [Person] {
        var out: [Person] = []
        update { s, data, _ in
            guard let co = s.company(companyID) else { return }
            let fee = Hiring.searchFee(mode)
            if fee > 0 { Payments.companyPays(&s, companyID: companyID, amount: fee, category: "oth", label: "Search for staff") }
            out = Hiring.search(role: role, company: co, mode: mode, state: &s, data: data)
        }
        return out
    }

    mutating func takeLoan(kind: String, amount: Double, termMonths: Int, companyID: Int?) -> Banking.LoanOfferResult {
        var out = Banking.LoanOfferResult.declined
        update { s, data, ctx in
            let nw = Valuation.netWorth(s, trades: data.catalog).total
            let co = companyID.flatMap { s.company($0) }
            let value = co.map { Valuation.companyValue($0, state: s, trades: data.catalog) }
            if let co, let v = value, amount > v * PublicRules.largeLoanShare, let why = PublicRules.restriction(s, companyID: co.id, change: .largeLoan) { s.note(why, tone: "n", companyID: co.id); return }
            let collateral = Luxury.collateral(s)
            switch Banking.take(kind: kind, amount: amount, termMonths: termMonths, company: co, guaranteed: false, state: &s, netWorth: nw, collateral: collateral,
                                companyValue: value, context: ctx) {
            case .ok: out = .ok
            case .declined: out = .declined
            case .tooSmall: out = .tooSmall
            }
        }
        return out
    }

    func loanOffer(kind: String, amount: Double, companyID: Int?) -> LoanOffer {
        Banking.offer(kind: kind, amount: amount, company: companyID.flatMap { state.company($0) }, state: state, netWorth: netWorth.total, collateral: Luxury.collateral(state),
                       companyValue: companyID.flatMap { state.company($0) }.map { Valuation.companyValue($0, state: state, trades: data.catalog) }, context: context)
    }

    mutating func repayLoan(id: Int, amount: Double) -> Bool {
        var ok = false
        update { s, _, ctx in ok = Banking.repay(loanID: id, amount: amount, state: &s, context: ctx) }
        return ok
    }

    var classicStartUnlocked: Bool { PlayerGoals.ladderFlag(state, "classic") }

    mutating func buyInvestment(_ kind: Brokerage.Kind, symbol: String, amount: Double) -> Brokerage.BuyResult {
        if kind == .stock { return .delisted }
        var r = Brokerage.BuyResult.notEnoughCash
        update { s, _, ctx in r = Brokerage.buy(&s, kind, symbol, amount: amount, currency: ctx.homeCurrency(s)) }
        return r
    }
    mutating func sellInvestment(_ kind: Brokerage.Kind, symbol: String, fraction: Double) {
        update { s, _, ctx in
            Brokerage.sell(&s, kind, symbol, fraction: fraction, currency: ctx.homeCurrency(s))
            PersonalFinance.withholdNow(&s, context: ctx)
        }
    }
    mutating func openDeposit(amount: Double, weeks: Int) -> Bool {
        var ok = false
        update { s, _, _ in ok = Brokerage.openDeposit(&s, amount: amount, weeks: weeks) }
        return ok
    }

}

public extension Banking {
    enum LoanOfferResult: Equatable { case ok, declined, tooSmall }
}

public extension GameEngine {
    func openingChecklist(companyID: Int) -> [OpeningChecklist.Item] {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return [] }
        return OpeningChecklist.items(co, bd, World(state: state, data: data))
    }

    @discardableResult
    mutating func quickSetupWithinBudget(companyID: Int) -> CompanySetup.SetupReport {
        var rep = CompanySetup.SetupReport()
        guard tutorialComplete else { return rep }
        update { s, d, _ in rep = CompanySetup.quickSetupReport(&s, companyID: companyID, data: d, options: .careful) }
        return rep
    }
    mutating func quickSetup(companyID: Int) -> [String] {
        var bought: [String] = []
        guard tutorialComplete else { return bought }
        update { s, data, _ in bought = CompanySetup.quickSetup(&s, companyID: companyID, data: data) }
        return bought
    }

    @discardableResult
    mutating func openCompany(companyID: Int) -> OpeningChecklist.OpenResult {
        var r = OpeningChecklist.OpenResult.missing
        update { s, data, _ in if let i = s.companyIndex(companyID) { r = OpeningChecklist.open(&s, companyIndex: i, data: data) } }
        return r
    }

    func hireableRoles(companyID: Int) -> [String] {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return [] }
        var roles = bd.standardStaff.map { $0.role }
        if MarketMap.market(of: co, state, data: data) != nil, !roles.contains("mktan") { roles.append("mktan") }
        return roles
    }

    func tradeInfo(companyID: Int) -> Trade? { state.company(companyID).flatMap { data.catalog[$0.type] } }
}
