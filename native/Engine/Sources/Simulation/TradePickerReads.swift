import Foundation
import GameCore
import Countries
import Finance
import Businesses

// The new-company screens (new look, Oct 2026): the trade picker table (Trade, Start-up, Demand, Staff; no margin) and the set-up form's costs.
// Everything is reshaped from the existing new-company code: `TradeAffordability` (the exact start-up cost), `CompanySetup.estimate`,
// `NewCompanyPlan` (the premises the player picks), `CityMarket` (demand) and `CompanyCosts` (the monthly fixed costs). Nothing here changes the game.

public typealias DemandLevel = CityMarket.DemandLevel

/// One row of the trade picker.
public struct TradePickerRow: Identifiable, Equatable, Sendable {
    public var id: String { tradeID }
    public var tradeID: String
    public var name: String
    /// The group the picker's filter chips use (the trade's category).
    public var sector: String
    /// The exact start-up cost in this city at the recommended size; nil when the trade cannot be started here (`blocked` says why).
    public var startUpCost: Double?
    /// How many customers the trade can expect in this city against an average place: High, Medium or Low.
    public var demand: DemandLevel
    /// People a typical company of this trade employs besides the owner, at the smallest size and at the size this city carries.
    public var staffMin: Int
    public var staffMax: Int
    public var blocked: String?
    /// The player's account (current account plus savings) covers the start-up cost.
    public var isFunded: Bool
}

/// What the start-up cost is made of.
public struct StartUpCostBreakdown: Equatable, Sendable {
    public var tradeID: String
    public var cityID: String
    public var legalForm: LegalForm
    /// "Registration and licences", "Fit-out and equipment", "Deposit and first month", and (only when the trade has them) "Property purchase" and
    /// "Waiting for a licence". They add up to `total`.
    public var lines: [FinanceLine]
    public var total: Double
    /// Locked into a limited company on top of `total`, paid from the player's own account; 0 for a sole trader.
    public var shareCapital: Double
    public var premisesKind: NewCompanyPlan.PremisesKind
    /// The place the figures use when the player picked one (nil: the standard place, or no fixed place).
    public var premisesName: String?
    public var buying: Bool
}

/// What the company costs to keep each month once it is open (an estimate; what rent and wages really are depends on the place and the people).
public struct MonthlyFixedCostEstimate: Equatable, Sendable {
    /// Rent (or the mortgage payment when buying), running costs, accounting for a sole trader, and wages. Lines with nothing to pay are left out.
    public var lines: [FinanceLine]
    public var total: Double
    /// People on the payroll in the wages line (the owner is not counted).
    public var staffCount: Int
}

public extension GameEngine {
    /// The trade picker for a city (the player's home city and country unless given).
    func tradePickerRows(cityID: String? = nil, countryCode: String? = nil) -> [TradePickerRow] {
        let code = countryCode ?? state.homeCountryCode
        let country = data.countries.resolve(code, orHome: state.homeCountryCode)
        let city = country.city(cityID ?? state.player.cityID) ?? country.cities[0]
        let tables = data.balance.cityMarket
        return TradeAffordability.rows(state: state, data: data, cityID: city.id, countryCode: country.code).compactMap { a in
            guard let bd = data.catalog[a.tradeID] else { return nil }
            let low = Self.employees(bd, size: bd.minSize), high = Self.employees(bd, size: CompanySetup.recommendedSize(bd, city: city))
            return TradePickerRow(tradeID: bd.id, name: bd.name, sector: bd.category, startUpCost: a.cost,
                                  demand: CityMarket.demandLevel(trade: bd.id, country: country, city: city, tables: tables),
                                  staffMin: min(low, high), staffMax: max(low, high), blocked: a.blocked, isFunded: a.isFunded)
        }
    }

    /// The start-up cost split the way the set-up form shows it. With no `premises` it is the standard place the picker's figure prices, so
    /// the two agree to the penny; with a pick it is that rented or bought place (`newCompanyPlan`).
    func startUpCostBreakdown(tradeID: String, cityID: String, legalForm: LegalForm, premises: NewCompanyPlan.Pick? = nil, countryCode: String? = nil) -> StartUpCostBreakdown? {
        guard let bd = data.catalog[tradeID],
              let plan = newCompanyPlan(tradeID: tradeID, cityID: cityID, form: legalForm, size: startSize(bd, cityID: cityID, countryCode: countryCode), pick: premises, countryCode: countryCode)
        else { return nil }
        let e = plan.estimate
        let option = plan.pick.flatMap { p in plan.options.first { $0.index == p.listingIndex } }
        let buying = option != nil && (plan.pick?.buy ?? false)
        let fitOut = option?.fitOut ?? e.premisesFitOut
        let deposit = option.map { buying ? $0.downPayment : $0.deposit } ?? (e.premises - e.premisesFitOut)
        var lines = [
            FinanceLine(id: "licences", label: "Registration and licences", amount: e.documents + e.registration + e.abroad),
            FinanceLine(id: "fitout", label: "Fit-out and equipment", amount: e.equipment + e.vehicles + fitOut),
            FinanceLine(id: "deposit", label: "Deposit and first month", amount: deposit + e.stock + e.firstPayroll + e.buffer),
        ]
        if e.property > 0 { lines.append(FinanceLine(id: "property", label: "Property purchase", amount: e.property)) }
        if e.wait > 0 { lines.append(FinanceLine(id: "wait", label: "Waiting for a licence", amount: e.wait)) }
        return StartUpCostBreakdown(tradeID: tradeID, cityID: cityID, legalForm: legalForm, lines: lines, total: lines.reduce(0) { $0 + $1.amount }, shareCapital: e.shareCapital,
                                    premisesKind: plan.premisesKind, premisesName: option?.name, buying: buying)
    }

    /// What keeping the company costs a month after opening: the place (rent, or the mortgage when buying), the trade's fixed running costs, the
    /// accountant a sole trader pays, and the standard team's wages (the same one month of wages the start-up cost holds).
    func monthlyFixedCostEstimate(tradeID: String, cityID: String, legalForm: LegalForm, premises: NewCompanyPlan.Pick? = nil, countryCode: String? = nil) -> MonthlyFixedCostEstimate? {
        guard let bd = data.catalog[tradeID] else { return nil }
        let size = startSize(bd, cityID: cityID, countryCode: countryCode)
        guard let plan = newCompanyPlan(tradeID: tradeID, cityID: cityID, form: legalForm, size: size, pick: premises, countryCode: countryCode),
              let (tmp, id) = previewCompany(tradeID: tradeID, cityID: cityID, form: legalForm, size: size, countryCode: countryCode), let co = tmp.company(id) else { return nil }
        let w = World(state: tmp, data: data)
        let perMonth = 52.0 / 12
        let option = plan.pick.flatMap { p in plan.options.first { $0.index == p.listingIndex } }
        var lines: [FinanceLine] = []
        if let o = option, plan.pick?.buy ?? false {
            // The mortgage `CompanySetup.setPremises` opens: what is not paid down, over 15 years, at the policy rate plus the bank's margin.
            let margin = max(0.012, Banking.creditMargin(tmp.credit) * 0.45) + 0.004
            lines.append(FinanceLine(id: "mortgage", label: "Mortgage payment",
                                     amount: Loans.annuity(principal: o.purchasePrice - o.downPayment, yearlyRate: tmp.economy.policyRate + margin, months: 180)))
        } else {
            lines.append(FinanceLine(id: "rent", label: "Rent", amount: option?.monthlyRent ?? plan.estimate.monthlyRent))
        }
        lines.append(FinanceLine(id: "running", label: "Running costs", amount: CompanyCosts.fixedOverhead(co, bd, w) * perMonth))
        lines.append(FinanceLine(id: "accounting", label: "Accounting", amount: CompanyCosts.accountant(co, w) * perMonth))
        lines.append(FinanceLine(id: "wages", label: "Wages", amount: plan.estimate.firstPayroll))
        lines = lines.filter { $0.amount > 0 }
        let staff = bd.standardStaff.enumerated().reduce(0.0) { $0 + ($1.offset == 0 && bd.ownerFTE >= 1 ? max(0, $1.element.count - 1) : $1.element.count) }
        return MonthlyFixedCostEstimate(lines: lines, total: lines.reduce(0) { $0 + $1.amount }, staffCount: Int(staff.rounded()))
    }

    // MARK: Helpers

    /// The size the picker prices a trade at: the one the city carries (`CompanySetup.recommendedSize`), as `TradeAffordability` does.
    private func startSize(_ bd: Trade, cityID: String, countryCode: String?) -> Double {
        let country = data.countries.resolve(countryCode ?? state.homeCountryCode, orHome: state.homeCountryCode)
        return CompanySetup.recommendedSize(bd, city: country.city(cityID) ?? country.cities[0])
    }

    /// People on the payroll of a standard company of this size, not counting the owner where the owner fills the first post.
    private static func employees(_ bd: Trade, size: Double) -> Int {
        CompanySetup.standardStaff(bd, size: size).enumerated().reduce(0) { $0 + ($1.offset == 0 && bd.ownerFTE >= 1 ? max(0, $1.element.count - 1) : $1.element.count) }
    }
}
