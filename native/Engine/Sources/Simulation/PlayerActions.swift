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

    mutating func setPriceLevel(companyID: Int, level: Double) {
        update { s, _, _ in if let i = s.companyIndex(companyID) { s.companies[i].priceLevel = clamp(level, -3, 3) } }
    }

    mutating func setOwnerHours(companyID: Int, hours: Double) {
        update { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            let others = CapacityModel.ownerHoursCommitted(s, except: companyID)
            s.companies[i].ownerHours = max(0, min(hours, 80 - others))
        }
    }

    mutating func setMaintenance(companyID: Int, level: Int) { update { s, _, _ in if let i = s.companyIndex(companyID) { s.companies[i].maintenance = min(2, max(0, level)) } } }
    mutating func setStockPolicy(companyID: Int, level: Int) { update { s, _, _ in if let i = s.companyIndex(companyID) { s.companies[i].set("stockPol", min(2, max(0, level))) } } }

    /// Choose a business option (a "knob"), e.g. the café concept. Needs the documents the option requires.
    mutating func setKnob(companyID: Int, knob: String, option: Int) {
        update { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            var k = s.companies[i].value("knob"); k[knob] = .number(Double(option)); s.companies[i].set("knob", k)
        }
    }

    /// Start, change or stop a marketing campaign. A campaign cannot be cut before its minimum length.
    /// Original: `setMkt`.
    mutating func setCampaign(companyID: Int, channel: String, weeklyBudget: Double) -> ActionResult {
        var result = ActionResult.done
        let channels = marketing.channels
        update { s, _, _ in
            guard let i = s.companyIndex(companyID), let c = channels[channel] else { result = .refused("unknown channel"); return }
            if let only = c.onlyInCountry, only != s.companies[i].countryCode { result = .refused("not available in this country"); return }
            var mkt = s.companies[i].value("mkt")
            let cur = mkt[channel]
            if weeklyBudget <= 0 {
                if !cur.isNull, !cur["lock"].isNull, Double(s.week) < cur["lock"].double { result = .refused("locked for \(Int(cur["lock"].double) - s.week) more weeks"); return }
                mkt = Marketing.removing(mkt, channel)
            } else if !cur.isNull {
                if weeklyBudget < cur["b"].double, !cur["lock"].isNull, Double(s.week) < cur["lock"].double { result = .refused("locked for \(Int(cur["lock"].double) - s.week) more weeks"); return }
                mkt[channel]["b"] = .number(weeklyBudget)
            } else {
                mkt[channel] = .object(["b": .number(weeklyBudget), "since": .number(Double(s.week)), "lock": .number(Double(s.week + c.minimumWeeks))])
            }
            s.companies[i].set("mkt", mkt)
        }
        return result
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

    /// `ownCar`: the person uses their own car and you pay mileage instead of providing a company car (estate agents). Original: `ACT.offer` + `carc`.
    mutating func hire(personID: Int, companyID: Int, monthlyWage: Double, ownCar: Bool = false) -> Hiring.HireResult {
        var r = Hiring.HireResult.refused
        update { s, data, _ in
            r = Hiring.hire(personID, into: companyID, monthlyWage: monthlyWage, state: &s, data: data)
            if r == .ok && ownCar { PersonalEquipment.toggleOwnCar(&s, companyID: companyID, staffID: personID, set: true) }
        }
        return r
    }

    @discardableResult
    mutating func fire(personID: Int, companyID: Int) -> Double {
        var sev = 0.0
        update { s, data, _ in sev = Hiring.fire(personID, from: companyID, state: &s, data: data) }
        return sev
    }

    /// Mark a paperwork item as done for a team member. It is free; missing items can be fined in an inspection.
    mutating func completePaperwork(companyID: Int, personID: Int, key: String? = nil) {
        update { s, _, _ in
            guard let i = s.companyIndex(companyID), let k = s.companies[i].staff.firstIndex(where: { $0.id == personID }) else { return }
            var staff = s.companies[i].staff
            for it in StaffExtras.items(role: staff[k].role) where key == nil || it.key == key { StaffExtras.tick(&staff[k], key: it.key) }
            s.companies[i].staff = staff
        }
    }

    mutating func raise(personID: Int, companyID: Int, percent: Double) {
        update { s, data, _ in
            guard let i = s.companyIndex(companyID) else { return }
            StaffTalks.raise(&s, companyIndex: i, staffID: personID, percent: percent, data: data)
        }
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

    mutating func setOwnerSalary(companyID: Int, monthly: Double) {
        update { s, data, ctx in
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

    /// Who runs payroll at a company: the owner (approves each month), the accountant, or the manager.
    mutating func setPayrollMode(companyID: Int, mode: Payday.Mode?) {
        update { s, _, _ in
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
        return bd.standardStaff.map { $0.role }
    }

    /// The trade definition behind a company.
    func tradeInfo(companyID: Int) -> Trade? { state.company(companyID).flatMap { data.catalog[$0.type] } }
}
