import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses
import Investments

/// Everything the player can do. Each action is one function here, so a button in the app is always one call, and
/// every action can be tested without any screen. Original: the `ACT.*` handlers in the HTML game (the ones ported so far).
public extension GameEngine {
    enum ActionResult: Equatable { case done, refused(String) }

    // MARK: Companies

    /// Create a company and set it up with standard choices. Returns its id.
    mutating func startCompany(tradeID: String, cityID: String, form: LegalForm, size: Double? = nil, name: String? = nil, countryCode: String? = nil,
                               accountantID: Int? = nil, fundWith amount: Double, quickSetup: Bool = true) -> Result<Int, CompanySetup.StartError> {
        var result: Result<Int, CompanySetup.StartError> = .failure(.notAllowedHere)
        // Trades whose weekly model is not ported yet would sit inert, so they cannot be started (see docs/KNOWN_GAPS.md).
        guard let trade = data.catalog[tradeID], SpecialFamilies.isStartable(trade) else { return .failure(.notYetAvailable) }
        update { s, data, ctx in
            result = CompanySetup.create(&s, tradeID: tradeID, cityID: cityID, form: form, size: size, name: name, countryCode: countryCode, accountantID: accountantID, data: data, context: ctx)
            if case .success(let id) = result {
                if amount > 0 { Payments.injectCash(&s, companyID: id, amount: min(amount, Payments.liquid(s))) }
                if quickSetup { _ = CompanySetup.quickSetup(&s, companyID: id, data: data) }
                s.note("You started \(s.company(id)?.name ?? "a company").", tone: "good", companyID: id)
            }
        }
        return result
    }

    @discardableResult
    mutating func setPriceLevel(companyID: Int, level: Double) -> SettingResult {
        applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.companySnapshot(companyID) }) { s, _, _ in
            if let i = s.companyIndex(companyID) { s.companies[i].priceLevel = clamp(level, -3, 3) }
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

    mutating func setMaintenance(companyID: Int, level: Int) { update { s, _, _ in if let i = s.companyIndex(companyID) { s.companies[i].maintenance = min(2, max(0, level)) } } }
    mutating func setStockPolicy(companyID: Int, level: Int) { update { s, _, _ in if let i = s.companyIndex(companyID) { s.companies[i].set("stockPol", min(2, max(0, level))) } } }

    /// Switch one add-on of a multi-choice knob on or off. Several add-ons can run together: the knob is a bit mask,
    /// so this sets or clears that option's bit and leaves the others alone. An add-on that needs a licence applies for it
    /// (fee paid now); a chain standard or franchise agreement that fixes the knob refuses.
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

    /// What changing a single-choice knob to option `option` (or a multi-choice knob to the bit mask `option`) costs and commits you to.
    func knobChangeQuote(companyID: Int, knob: String, option: Int) -> KnobChangeQuote? {
        KnobChange.quote(state, data, companyID: companyID, knob: knob, value: option)
    }

    /// The same for switching one add-on of a multi-choice knob on or off.
    func knobToggleQuote(companyID: Int, knob: String, option: Int, on: Bool) -> KnobChangeQuote? {
        guard let co = state.company(companyID), let k = data.catalog[co.type]?.knobs.first(where: { $0.id == knob }), k.isMulti else { return nil }
        return KnobChange.quote(state, data, companyID: companyID, knob: knob, value: Knobs.mask(KnobChange.currentValue(co, k), option: option, on: on))
    }

    /// A read-only before/after estimate of that change (customers, capacity, price, sales, what is left after direct costs), as ranges
    /// over the weeks ahead, worked out by the engine's own demand, price, capacity and cost functions. Nil where the trade has no
    /// ordinary weekly sales model. `option` is an option index, or the bit mask of a multi-choice knob.
    func knobChangePreview(companyID: Int, knob: String, option: Int) -> KnobPreview? {
        KnobChange.preview(state, data, marketing: marketing, companyID: companyID, knob: knob, value: option)
    }

    /// The same estimate for switching one add-on of a multi-choice knob on or off.
    func knobTogglePreview(companyID: Int, knob: String, option: Int, on: Bool) -> KnobPreview? {
        guard let co = state.company(companyID), let k = data.catalog[co.type]?.knobs.first(where: { $0.id == knob }), k.isMulti else { return nil }
        return knobChangePreview(companyID: companyID, knob: knob, option: Knobs.mask(KnobChange.currentValue(co, k), option: option, on: on))
    }

    /// Who fixes this knob for the company (its chain's standard, its franchise agreement), or nil when the owner decides.
    func knobGovernedBy(companyID: Int, knob: String) -> String? { state.company(companyID).flatMap { KnobChange.governedBy(state, $0, knob: knob) } }

    /// Change how the business sells (a single-choice knob): pays the changeover and any licences, then trades at reduced
    /// capacity for a few weeks. Nothing is promised about the result.
    @discardableResult
    mutating func changeKnob(companyID: Int, knob: String, option: Int) -> KnobChangeOutcome {
        var out = KnobChangeOutcome.refused("not a choice of this business")
        update { s, data, _ in
            guard let co = s.company(companyID), let k = data.catalog[co.type]?.knobs.first(where: { $0.id == knob }), !k.isMulti else { return }
            out = KnobChange.apply(&s, data, companyID: companyID, knob: knob, value: option)
        }
        return out
    }

    /// Start, change or stop a marketing campaign. A campaign cannot be cut before its minimum length.
    /// `weeks`: how long it runs from now (at least the channel's minimum); 0 = until you stop it; nil = a new campaign
    /// runs until stopped and a running one keeps its end date. Original: `setMkt` + the planner's `plgo`.
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

    /// The channels this company can buy, as its country offers them (a country-media channel carries the country's own name).
    /// The prime-time channel comes last; managers never pick it (they choose search or social ads only).
    func marketingChannels(companyID: Int) -> [MarketingChannel] {
        guard let co = state.company(companyID) else { return [] }
        let country = World(state: state, data: data).country(co)
        return marketing.channels.values.compactMap { $0.offered(in: country) }
            .filter { $0.onlyInCountry == nil || $0.onlyInCountry == co.countryCode }
            .sorted { $0.isPrimeTime != $1.isPrimeTime ? !$0.isPrimeTime : $0.name < $1.name }
    }

    /// What starting this campaign commits you to; shown before the player confirms. Nil for an unknown company or channel.
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

    // MARK: People

    mutating func searchWorkers(companyID: Int, role: String, mode: Hiring.SearchMode) -> [Person] {
        var out: [Person] = []
        update { s, data, _ in
            guard let co = s.company(companyID) else { return }
            let cost = mode == .agency ? 0.0 : 0.0
            _ = cost
            out = Hiring.search(role: role, company: co, mode: mode, state: &s, data: data)
        }
        return out
    }

    /// Mark a paperwork item as done for a team member. It is free; missing items can be fined in an inspection.
    /// Returns how many items were missing and are now ticked (0 when the person is not on the payroll or nothing was missing).
    @discardableResult
    mutating func completePaperwork(companyID: Int, personID: Int, key: String? = nil) -> Int {
        var done = 0
        update { s, _, _ in
            guard let i = s.companyIndex(companyID), let k = s.companies[i].staff.firstIndex(where: { $0.id == personID }) else { return }
            var staff = s.companies[i].staff
            let before = StaffExtras.missing(staff[k]).count
            for it in StaffExtras.items(role: staff[k].role) where key == nil || it.key == key { StaffExtras.tick(&staff[k], key: it.key) }
            done = before - StaffExtras.missing(staff[k]).count
            s.companies[i].staff = staff
        }
        return done
    }

    // MARK: Money

    mutating func takeLoan(kind: String, amount: Double, termMonths: Int, companyID: Int?) -> Banking.LoanOfferResult {
        var out = Banking.LoanOfferResult.declined
        update { s, data, ctx in
            let nw = Valuation.netWorth(s, trades: data.catalog).total
            let co = companyID.flatMap { s.company($0) }
            switch Banking.take(kind: kind, amount: amount, termMonths: termMonths, company: co, guaranteed: co?.form == .soleTrader, state: &s, netWorth: nw, collateral: Luxury.collateral(s), context: ctx) {
            case .ok: out = .ok
            case .declined: out = .declined
            case .tooSmall: out = .tooSmall
            }
        }
        return out
    }

    func loanOffer(kind: String, amount: Double, companyID: Int?) -> LoanOffer {
        Banking.offer(kind: kind, amount: amount, company: companyID.flatMap { state.company($0) }, state: state, netWorth: netWorth.total, collateral: Luxury.collateral(state), context: context)
    }

    mutating func repayLoan(id: Int, amount: Double) -> Bool {
        var ok = false
        update { s, _, _ in ok = Banking.repay(loanID: id, amount: amount, state: &s) }
        return ok
    }

    mutating func putMoneyInto(companyID: Int, amount: Double) -> Bool {
        var ok = false
        update { s, _, _ in ok = Payments.injectCash(&s, companyID: companyID, amount: amount) }
        return ok
    }

    mutating func takeMoneyOut(companyID: Int, amount: Double) -> Payments.WithdrawResult {
        var r = Payments.WithdrawResult.notEnoughCash
        update { s, _, _ in r = Payments.withdrawCash(&s, companyID: companyID, amount: amount) }
        return r
    }

    mutating func payDividend(companyID: Int, amount: Double) -> Payments.DividendResult {
        var r = Payments.DividendResult.notEnoughCash
        update { s, _, ctx in r = Payments.payDividend(&s, companyID: companyID, amount: amount, context: ctx) }
        return r
    }

    @discardableResult
    mutating func setOwnerSalary(companyID: Int, monthly: Double) -> SettingResult {
        applySetting(refuse: { s in
            guard let co = s.company(companyID) else { return "That company no longer exists." }
            return co.form == .limited ? nil : "Only a limited company can pay its owner a salary."
        }, probe: { $0.companySnapshot(companyID) }) { s, data, ctx in
            guard let i = s.companyIndex(companyID), s.companies[i].form == .limited else { return }
            s.companies[i].ownerMonthlySalary = max(0, ctx.currency(s.companies[i].countryCode, s).roundedStep(monthly, about: 100))
        }
    }

    // MARK: Investing

    mutating func buyInvestment(_ kind: Brokerage.Kind, symbol: String, amount: Double) -> Brokerage.BuyResult {
        var r = Brokerage.BuyResult.notEnoughCash
        update { s, _, _ in r = Brokerage.buy(&s, kind, symbol, amount: amount) }
        return r
    }
    mutating func sellInvestment(_ kind: Brokerage.Kind, symbol: String, fraction: Double) {
        update { s, _, _ in Brokerage.sell(&s, kind, symbol, fraction: fraction) }
    }
    mutating func moveToSavings(_ amount: Double) -> Bool {
        var ok = false
        update { s, _, _ in ok = Brokerage.moveToSavings(&s, amount) }
        return ok
    }
    mutating func openDeposit(amount: Double, weeks: Int) -> Bool {
        var ok = false
        update { s, _, _ in ok = Brokerage.openDeposit(&s, amount: amount, weeks: weeks) }
        return ok
    }

    // MARK: Policies

    /// The owner's standing instructions (see `ManagementPolicy`).
    mutating func setPolicy(_ policy: ManagementPolicy) { update { s, _, _ in s.policy = policy } }

    // MARK: Payroll

    /// Change a company's pay day (1, 5, 10, 12, 15, 20, 25, 28 or 0 = last day). The change is queued until this month's payroll is paid.
    @discardableResult
    mutating func setPayday(companyID: Int, day: Int) -> Payday.PaydayChange {
        var r = Payday.PaydayChange.noCompany
        update { s, _, _ in
            r = Payday.setPayday(&s, companyID: companyID, day: day, today: Payday.dayNumber(week: s.week, day: s.day))
        }
        return r
    }

    /// Who runs payroll at a company: the owner (approves each month), the accountant, or the manager.
    @discardableResult
    mutating func setPayrollMode(companyID: Int, mode: Payday.Mode?) -> SettingResult {
        applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.companySnapshot(companyID) }) { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            let t = Payday.dayNumber(week: s.week, day: s.day)
            var cfg = Payday.config(s.companies[i], today: t)
            cfg.mode = mode
            s.companies[i].set("pr29", cfg.json)
        }
    }
}

public extension Banking {
    enum LoanOfferResult: Equatable { case ok, declined, tooSmall }
}

// MARK: Reading for screens, and setup

public extension GameEngine {
    func openingChecklist(companyID: Int) -> [OpeningChecklist.Item] {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return [] }
        return OpeningChecklist.items(co, bd, World(state: state, data: data))
    }

    /// Fill in whatever is missing with standard choices (documents, premises, equipment). Returns what was bought.
    @discardableResult
    mutating func quickSetup(companyID: Int) -> [String] {
        var bought: [String] = []
        update { s, data, _ in bought = CompanySetup.quickSetup(&s, companyID: companyID, data: data) }
        return bought
    }

    @discardableResult
    mutating func openCompany(companyID: Int) -> OpeningChecklist.OpenResult {
        var r = OpeningChecklist.OpenResult.missing
        update { s, data, _ in if let i = s.companyIndex(companyID) { r = OpeningChecklist.open(&s, companyIndex: i, data: data) } }
        return r
    }

    func maximumDividend(companyID: Int) -> Double {
        state.company(companyID).map { Payments.maximumDividend($0, state: state, context: context) } ?? 0
    }

    /// Roles this company can hire for, from its trade's standard staff.
    func hireableRoles(companyID: Int) -> [String] {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return [] }
        var roles = bd.standardStaff.map { $0.role }
        // A market analyst can be added to any company with a market share to measure (not part of the standard staff).
        if MarketMap.market(of: co, state, data: data) != nil, !roles.contains("mktan") { roles.append("mktan") }
        return roles
    }

    /// The trade definition behind a company.
    func tradeInfo(companyID: Int) -> Trade? { state.company(companyID).flatMap { data.catalog[$0.type] } }
}
