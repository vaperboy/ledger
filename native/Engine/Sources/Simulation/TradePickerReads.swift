import Foundation
import GameCore
import Countries
import Finance
import Businesses

public typealias DemandLevel = CityMarket.DemandLevel

public struct TradePickerRow: Identifiable, Equatable, Sendable {
    public var id: String { tradeID }
    public var tradeID: String
    public var name: String
    public var sector: String
    public var startUpCost: Double?
    public var minimumCost: Double? = nil
    public var demand: DemandLevel
    public var staffMin: Int
    public var staffMax: Int
    public var blocked: String?
    public var isFunded: Bool
}

public struct StartUpCostBreakdown: Equatable, Sendable {
    public var tradeID: String
    public var cityID: String
    public var lines: [FinanceLine]
    public var total: Double
    public var shareCapital: Double
    public var premisesKind: NewCompanyPlan.PremisesKind
    public var premisesName: String?
    public var buying: Bool
}

public struct MonthlyFixedCostEstimate: Equatable, Sendable {
    public var lines: [FinanceLine]
    public var total: Double
    public var staffCount: Int
}

public extension GameEngine {
    func tradePickerRows(cityID: String? = nil, countryCode: String? = nil) -> [TradePickerRow] {
        readMemo.value(stateStamp, "tradePickerRows|\(cityID ?? "-")|\(countryCode ?? "-")") { tradePickerRowsFresh(cityID: cityID, countryCode: countryCode) }
    }

    func tradePickerRowsFresh(cityID: String? = nil, countryCode: String? = nil) -> [TradePickerRow] {
        let code = countryCode ?? state.homeCountryCode
        let country = data.countries.resolve(code, orHome: state.homeCountryCode)
        let city = country.city(cityID ?? state.player.cityID) ?? country.cities[0]
        let tables = data.balance.cityMarket
        return TradeAffordability.rows(state: state, data: data, cityID: city.id, countryCode: country.code).compactMap { a in
            guard let bd = data.catalog[a.tradeID] else { return nil }
            let low = Self.employees(bd, size: bd.minSize), high = Self.employees(bd, size: a.size)
            return TradePickerRow(tradeID: bd.id, name: bd.name, sector: bd.category, startUpCost: a.cost, minimumCost: a.minimum,
                                  demand: CityMarket.demandLevel(trade: bd.id, country: country, city: city, tables: tables),
                                  staffMin: min(low, high), staffMax: max(low, high), blocked: a.blocked, isFunded: a.isFunded)
        }
    }

    func startUpCostBreakdown(tradeID: String, cityID: String, premises: NewCompanyPlan.Pick? = nil, countryCode: String? = nil) -> StartUpCostBreakdown? {
        guard let bd = data.catalog[tradeID],
              let plan = newCompanyPlan(tradeID: tradeID, cityID: cityID, size: startSize(bd, cityID: cityID, countryCode: countryCode), pick: premises, countryCode: countryCode)
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
        return StartUpCostBreakdown(tradeID: tradeID, cityID: cityID, lines: lines, total: lines.reduce(0) { $0 + $1.amount }, shareCapital: e.shareCapital,
                                    premisesKind: plan.premisesKind, premisesName: option?.name, buying: buying)
    }

    func monthlyFixedCostEstimate(tradeID: String, cityID: String, premises: NewCompanyPlan.Pick? = nil, countryCode: String? = nil) -> MonthlyFixedCostEstimate? {
        guard let bd = data.catalog[tradeID] else { return nil }
        let size = startSize(bd, cityID: cityID, countryCode: countryCode)
        guard let plan = newCompanyPlan(tradeID: tradeID, cityID: cityID, size: size, pick: premises, countryCode: countryCode),
              let (tmp, id) = previewCompany(tradeID: tradeID, cityID: cityID, size: size, countryCode: countryCode), let co = tmp.company(id) else { return nil }
        let w = World(state: tmp, data: data)
        let perMonth = 52.0 / 12
        let option = plan.pick.flatMap { p in plan.options.first { $0.index == p.listingIndex } }
        var lines: [FinanceLine] = []
        if let o = option, plan.pick?.buy ?? false {
            let margin = max(0.012, Banking.creditMargin(tmp.credit) * 0.45) + 0.004
            lines.append(FinanceLine(id: "mortgage", label: "Mortgage payment",
                                     amount: Loans.annuity(principal: o.purchasePrice - o.downPayment, yearlyRate: tmp.economy.policyRate + margin, months: 180)))
        } else {
            lines.append(FinanceLine(id: "rent", label: "Rent", amount: option?.monthlyRent ?? plan.estimate.monthlyRent))
        }
        lines.append(FinanceLine(id: "running", label: "Running costs", amount: CompanyCosts.fixedOverhead(co, bd, w) * perMonth))
        lines.append(FinanceLine(id: "wages", label: "Wages", amount: plan.estimate.firstPayroll))
        lines = lines.filter { $0.amount > 0 }
        let staff = bd.standardStaff.enumerated().reduce(0.0) { $0 + ($1.offset == 0 && bd.ownerFTE >= 1 ? max(0, $1.element.count - 1) : $1.element.count) }
        return MonthlyFixedCostEstimate(lines: lines, total: lines.reduce(0) { $0 + $1.amount }, staffCount: Int(saturating: staff.rounded()))
    }

    func affordableStartSize(tradeID: String, cityID: String) -> Double? {
        tradeAffordability(cityID: cityID).first { $0.tradeID == tradeID }?.size
    }

    private func startSize(_ bd: Trade, cityID: String, countryCode: String?) -> Double {
        if countryCode == nil, let r = tradeAffordability(cityID: cityID).first(where: { $0.tradeID == bd.id }) { return r.size }
        let country = data.countries.resolve(countryCode ?? state.homeCountryCode, orHome: state.homeCountryCode)
        return CompanySetup.recommendedSize(bd, city: country.city(cityID) ?? country.cities[0])
    }

    private static func employees(_ bd: Trade, size: Double) -> Int {
        CompanySetup.standardStaff(bd, size: size).enumerated().reduce(0) { $0 + ($1.offset == 0 && bd.ownerFTE >= 1 ? max(0, $1.element.count - 1) : $1.element.count) }
    }
}
