import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

/// A property as the screen shows it.
public struct PropertyRow: Identifiable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var kind: String
    public var units: Double
    public var leasedUnits: Double
    public var rentPerUnit: Double
    public var vacancy: Double
    public var condition: Double
    public var value: Double
    public var cost: Double
    public var mortgage: Double
    public var weeklyRent: Double
    public var leases: [LeaseRow]
}

public struct LeaseRow: Equatable, Sendable {
    public var tenant: String
    public var squareMetres: Double
    public var weeklyRent: Double
    public var weeksLeft: Int
}

/// The whole portfolio of a rental company.
public struct PropertyPortfolio: Equatable, Sendable {
    public var rows: [PropertyRow]
    public var unitWord: String
    public var totalValue: Double { rows.reduce(0) { $0 + $1.value } }
    public var totalUnits: Double { rows.reduce(0) { $0 + $1.units } }
    public var mortgages: Double { rows.reduce(0) { $0 + $1.mortgage } }
    public var weeklyRent: Double
    public var grossYield: Double { totalValue > 0 ? weeklyRent * 52 / totalValue : 0 }
    public var occupancy: Double
    /// How much of the property work the staff can do, 0...1.4 (below 1 vacancy and repairs suffer).
    public var staffCover: Double
    public var gainOnCost: Double { rows.reduce(0) { $0 + $1.value - $1.cost } }
}

/// One insurance product as the screen shows it.
public struct ProductRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var isOffered: Bool
    public var status: String
    public var approvalFee: Double
    public var verifiedSellers: Double
}

/// An insurance salesperson and the weeks (as game weeks) at which each product verification is done.
public struct SalespersonRow: Identifiable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var verified: [String: Int]
}

public extension GameEngine {
    // MARK: Reading

    func propertyPortfolio(companyID: Int) -> PropertyPortfolio? {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], bd.family == "rent" else { return nil }
        let rows = co.properties.map { p -> PropertyRow in
            let mortgage = state.loans.first { $0.id == p.loanID }?.balance ?? 0
            let leases = p.leases.map { LeaseRow(tenant: $0.name.isEmpty ? "Your company" : $0.name, squareMetres: $0.squareMetres,
                                                 weeklyRent: $0.squareMetres * $0.weeklyRentPerM2, weeksLeft: max(0, $0.untilWeek - state.week)) }
            let lu = min(p.leasedUnits, p.units)
            let rent = leases.reduce(0) { $0 + $1.weeklyRent } + (p.units - lu) * (1 - p.vacancy) * p.rentPerUnit
            return PropertyRow(id: p.id, name: p.name, kind: p.kind, units: p.units, leasedUnits: p.leasedUnits, rentPerUnit: p.rentPerUnit, vacancy: p.vacancy,
                               condition: p.condition, value: p.value, cost: p.cost, mortgage: mortgage, weeklyRent: rent, leases: leases)
        }
        let kind = bd.traitText["kind"] ?? "res"
        let units = rows.reduce(0) { $0 + $1.units }
        let occ = units > 0 ? rows.reduce(0) { $0 + $1.units * (1 - $1.vacancy) } / units : 0
        return PropertyPortfolio(rows: rows, unitWord: kind == "res" ? "flats" : kind == "com" ? "m2" : "spaces",
                                 weeklyRent: co.lastWeekRevenue, occupancy: occ, staffCover: co.value("fm")["cover"].isNull ? 1 : co.value("fm")["cover"].double)
    }

    func propertyListings(companyID: Int) -> [PropertyListing] {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], bd.family == "rent" else { return [] }
        return RentalModel.listings(co, bd, World(state: state, data: data))
    }

    func tenantOffers(companyID: Int, propertyID: Int) -> [TenantOffer] {
        guard let co = state.company(companyID), let p = co.properties.first(where: { $0.id == propertyID }), p.kind == "com" else { return [] }
        return RentalModel.tenants(co, property: p, World(state: state, data: data))
    }

    func financeBook(companyID: Int) -> FinanceBook? {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return nil }
        return FinanceModel.book(co, bd, state: state)
    }

    func insuranceProducts(companyID: Int) -> [ProductRow] {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], bd.hasTrait("ins") else { return [] }
        let tables = data.catalog.tables
        let w = World(state: state, data: data)
        return FinanceModel.products(tables).map { p in
            let on = FinanceModel.isOffered(co, p.id)
            let doc = co.value("docs")[p.documentID]
            let status: String
            if !on { status = "Not offered" }
            else if doc["st"].string == "ok" { status = "Live" }
            else if doc["st"].string == "applied" { status = "Approval in \(max(0, doc["done"].int - state.week)) weeks" }
            else { status = "Needs approval" }
            let fee = Documents.cost(p.documentID, company: co, bd, w)
            return ProductRow(id: p.id, name: p.name, isOffered: on, status: status, approvalFee: fee,
                              verifiedSellers: on ? FinanceModel.verifiedAgents(co, product: p.id, week: state.week, people: state.people, salesRoles: tables.salesRoles) : 0)
        }
    }

    /// Salespeople of an insurer and for which products each is verified (or waiting).
    func salespeople(companyID: Int) -> [SalespersonRow] {
        guard let co = state.company(companyID) else { return [] }
        return co.staff.filter { $0.role == "agent" }.map { m in
            var v: [String: Int] = [:]
            for (k, x) in m.value("ver").object { v[k] = x["done"].int }
            return SalespersonRow(id: m.id, name: state.people[m.id]?.name ?? "Salesperson", verified: v)
        }
    }

    // MARK: Property actions

    /// Buy a listed property with a mortgage of `loanToValue` (0 ... 0.8) of the price.
    mutating func buyProperty(companyID: Int, listingIndex: Int, loanToValue: Double) -> RentalModel.BuyResult {
        var r = RentalModel.BuyResult.unknown
        update { s, data, _ in
            guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return }
            let ls = RentalModel.listings(co, bd, World(state: s, data: data))
            guard ls.indices.contains(listingIndex) else { return }
            r = RentalModel.buy(&s, companyID: companyID, listing: ls[listingIndex], loanToValue: loanToValue, data: data)
        }
        return r
    }

    @discardableResult
    mutating func sellProperty(companyID: Int, propertyID: Int) -> Double {
        var net = 0.0
        update { s, _, _ in net = RentalModel.sell(&s, companyID: companyID, propertyID: propertyID) }
        return net
    }

    @discardableResult
    mutating func renovateProperty(companyID: Int, propertyID: Int) -> RentalModel.BuyResult {
        var r = RentalModel.BuyResult.unknown
        update { s, data, _ in r = RentalModel.renovate(&s, companyID: companyID, propertyID: propertyID, data: data) }
        return r
    }

    mutating func leaseSpace(companyID: Int, propertyID: Int, offerIndex: Int) -> Bool {
        var ok = false
        update { s, data, _ in
            guard let co = s.company(companyID), let p = co.properties.first(where: { $0.id == propertyID }) else { return }
            let offers = RentalModel.tenants(co, property: p, World(state: s, data: data))
            guard offers.indices.contains(offerIndex) else { return }
            ok = RentalModel.lease(&s, companyID: companyID, propertyID: propertyID, offer: offers[offerIndex])
        }
        return ok
    }

    /// Sell a whole commercial building to one of the interested buyers. Returns the cash received, -1 if one of your companies rents in it.
    mutating func sellBuilding(companyID: Int, propertyID: Int, offerIndex: Int) -> Double {
        var net = 0.0
        update { s, data, _ in
            guard let co = s.company(companyID), let p = co.properties.first(where: { $0.id == propertyID }) else { return }
            let offers = RentalModel.tenants(co, property: p, World(state: s, data: data))
            guard offers.indices.contains(offerIndex) else { return }
            net = RentalModel.sell(&s, companyID: companyID, propertyID: propertyID, to: offers[offerIndex])
        }
        return net
    }

    // MARK: Insurance actions

    @discardableResult
    mutating func setInsuranceProduct(companyID: Int, product: String, offered: Bool) -> FinanceModel.ProductResult {
        var r = FinanceModel.ProductResult.unknown
        update { s, data, _ in r = FinanceModel.setProduct(&s, companyID: companyID, product: product, on: offered, data: data) }
        return r
    }

    @discardableResult
    mutating func verifySalesperson(companyID: Int, personID: Int, product: String) -> FinanceModel.ProductResult {
        var r = FinanceModel.ProductResult.unknown
        update { s, data, _ in r = FinanceModel.verifyAgent(&s, companyID: companyID, staffID: personID, product: product, data: data) }
        return r
    }

    // MARK: Insights

    /// Findings specific to property and finance companies, for the company screen.
    func rentalFinanceInsights(for co: Company) -> [Insight] {
        guard co.status == .open, let bd = data.catalog[co.type] else { return [] }
        var out: [Insight] = []
        let cur = currency(for: co)
        if bd.family == "rent", let pf = propertyPortfolio(companyID: co.id) {
            if pf.rows.isEmpty { out.append(Insight(id: "prop", symbol: "building.2", text: "No property owned. Buy one under Properties to earn rent.", tone: .bad)) }
            else {
                if pf.occupancy < 0.8 { out.append(Insight(id: "vacancy", symbol: "door.left.hand.open", text: "\(Int(jsRound((1 - pf.occupancy) * 100)))% of your space is empty. Lower rents, keep the place in good condition and market it.", tone: .warn)) }
                if pf.staffCover < 0.8 { out.append(Insight(id: "cover", symbol: "person.badge.clock", text: "Too few caretakers and property managers for the portfolio: vacancy and wear rise, and part of the rent goes to an outside firm.", tone: .warn)) }
                if let worn = pf.rows.filter({ $0.condition < 0.5 }).first { out.append(Insight(id: "worn", symbol: "wrench.and.screwdriver", text: "\(worn.name) is worn. Renovating restores condition and adds to its value.", tone: .warn)) }
                if pf.mortgages > 0, pf.grossYield < (state.economy.policyRate + 0.012) * pf.mortgages / max(1, pf.totalValue) {
                    out.append(Insight(id: "carry", symbol: "percent", text: "Rent covers less than the mortgage costs. Value growth has to make up the difference.", tone: .warn))
                }
            }
        }
        if let b = financeBook(companyID: co.id) {
            if b.underRegulator {
                out.append(Insight(id: "regulator", symbol: "exclamationmark.shield", text: b.kind == .insurer ? "The regulator restricts you: solvency is too low. Put capital into the company." : "The regulator warns about your capital ratio. Add equity or shrink the loan book.", tone: .bad))
            }
            switch b.kind {
            case .insurer:
                if b.policies > 0, b.solvency >= 0.8, b.solvency < 1.2 { out.append(Insight(id: "solvency", symbol: "gauge.with.dots.needle.33percent", text: "Solvency is \(String(format: "%.2f", b.solvency)); you need 1.0 and the regulator steps in at 0.8.", tone: .warn)) }
                if b.lossRatio > 0.9 { out.append(Insight(id: "claims", symbol: "doc.text.magnifyingglass", text: "Claims take \(Int(jsRound(b.lossRatio * 100)))% of premiums. Raise prices, tighten underwriting or hire claims staff.", tone: .warn)) }
                let any = insuranceProducts(companyID: co.id).contains { $0.isOffered }
                if !any { out.append(Insight(id: "products", symbol: "shield", text: "No insurance products on sale. Choose products under Insurance.", tone: .bad)) }
            case .bank:
                out.append(Insight(id: "capital", symbol: "building.columns", text: "Capital ratio \(Currency.percent(b.capitalRatio, decimals: 1)) against a minimum of \(Currency.percent(b.requiredRatio, decimals: 0)); \(cur.short(b.loans)) lent against \(cur.short(b.deposits)) of deposits.", tone: b.capitalRatio < b.requiredRatio * 0.7 ? .warn : .neutral))
                if b.centralBankLoan > 0 { out.append(Insight(id: "cbfacility", symbol: "arrow.down.to.line", text: "Borrowing \(cur.short(b.centralBankLoan)) from the central bank after withdrawals. It is repaid as deposits return.", tone: .warn)) }
            case .fund:
                if b.unitValue < b.highWaterMark * 0.97 { out.append(Insight(id: "hwm", symbol: "chart.line.downtrend.xyaxis", text: "The fund is below its high-water mark: no performance fee until it recovers.", tone: .neutral)) }
            }
        }
        return out
    }
}
