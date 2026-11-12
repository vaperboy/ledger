import Foundation
import GameCore

public struct EmployerContribution: Equatable, Sendable {
    public var name: String
    public var rate: Double
    public var capUnits: Double
}

public struct Country: Equatable, Sendable, Identifiable {
    public struct City: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var population: Double
        public var rent: Double
        public var wage: Double
        public var demand: Double
        public var price: Double
        public var metro: Double = 0
        public var affluence: Double = 1
        public var inequality: Double = 0.33
        public var touristIndex: Double = 1
        public var isExtra: Bool = false
    }

    public var coreCities: [City] { cities.filter { !$0.isExtra } }

    public struct IncomeTax: Equatable, Sendable {
        public var flat: Double
        public var allowance: Double
        public var wageDeduction: (share: Double, maximum: Double)?
        public var brackets: [(from: Double, rate: Double)]
        public var socialFloor: Double
        public var socialCapShare: Double

        public static func == (a: IncomeTax, b: IncomeTax) -> Bool {
            a.flat == b.flat && a.allowance == b.allowance && a.socialFloor == b.socialFloor && a.socialCapShare == b.socialCapShare
                && a.wageDeduction?.share == b.wageDeduction?.share && a.wageDeduction?.maximum == b.wageDeduction?.maximum
                && a.brackets.count == b.brackets.count && zip(a.brackets, b.brackets).allSatisfy { $0.from == $1.from && $0.rate == $1.rate }
        }
    }

    public struct VAT: Equatable, Sendable {
        public var standard: Double, food: Double, low: Double, zero: Double
        public func rate(for category: String) -> Double {
            switch category {
            case "std": return standard
            case "food": return food
            case "low": return low
            case "zero": return zero
            default: return 0
            }
        }
    }

    public var code: String
    public var name: String
    public var flag: String
    public var region: String
    public var currencyCode: String
    public var currencySymbol: String
    public var fx: Double
    public var populationMillions: Double
    public var gini: Double
    public var priceLevel: Double
    public var marketStrength: Double
    public var startingPolicyRate: Double
    public var bureaucracy: Double
    public var rentLevel: Double
    public var wageLevel: Double
    public var startLoan: Double
    public var startLoanTermMonths: Int
    public var corporateTax: Double
    public var specialTax: [String: Double]
    public var dividendTax: Double
    public var dividendShield: Double
    public var capitalGainsTax: Double
    public var savingsInterestTax: Double
    public var lossFree: Double
    public var lossShare: Double
    public var lossYears: Int
    public var employerSocial: Double
    public var employerPension: Double
    public var employerInjury: Double
    public var employerContributions: [EmployerContribution] = []
    public var contributionUnitMonthly: Double = 0
    public var statePayrollTax: Double = 0
    public var employeeSocial: Double
    public var income: IncomeTax
    public var wealthRate: Double
    public var wealthThreshold: Double
    public var wealthCompanyShare: Double
    public var buyingPower: Double
    public var inheritanceFree: Double
    public var inheritanceRate: Double
    public var inheritanceBusinessRelief: Double
    public var inheritanceBusinessFree: Double
    public var vat: VAT
    public var vatThreshold: Double
    public var vatFilingMonths: Int
    public var usesSalesTax: Bool
    public var shareCapitalMinimum: Double
    public var registrationFee: Double
    public var companyForms: [String: String]
    public var overdraftMargin: Double
    public var vehicleRules: VehicleRules = .none
    public var firstNames: [String]
    public var lastNames: [String]
    public var companyNameStarts: [String]
    public var cities: [City]
    public var pack: JSONValue

    public var id: String { code }

    public var employerCostFactor: Double { 1 + employerSocial + employerPension + employerInjury }

    public func payrollFactor(monthlyWage: Double) -> Double { 1 + employerOnCost(monthlyWage: monthlyWage) }

    public func employerSocialRate(monthlyWage: Double) -> Double {
        guard !employerContributions.isEmpty, monthlyWage > 0 else { return employerSocial }
        let unit = contributionUnitMonthly
        let charged = employerContributions.reduce(0.0) { acc, c in
            let base = c.capUnits > 0 && unit > 0 ? min(monthlyWage, c.capUnits * unit) : monthlyWage
            return acc + c.rate * base
        }
        return charged / monthlyWage + statePayrollTax
    }

    public func employerOnCost(monthlyWage: Double) -> Double { employerSocialRate(monthlyWage: monthlyWage) + employerPension + employerInjury }

    public var medianMonthlyWage: Double { ReferenceEconomy.medianWage * wageLevel }

    public var costIndex: Double { 0.5 + 0.5 * priceLevel }

    public func city(_ id: String) -> City? { cities.first { $0.id == id } }
}

public enum ReferenceEconomy {
    public static let medianWage = 56000.0
    public static let priceIndex = 137.0
    public static let officeRent = 2500.0
    public static let spendPerPerson = 330000.0
    public static let round20Reference = (costIndex: 110.0, wageIndex: 97.0, buyingPowerIndex: 90.0)
}

extension Country {
    public init(pack p: JSONValue) {
        let fx = p["fx"].double
        func B(_ v: Double) -> Double { v * fx }
        let eco = p["economy"], tax = p["tax"], inc = tax["income"], soc = inc["social"]
        let r2 = { (v: Double) in jsRound(v * 100) / 100 }

        code = p["code"].string
        name = p["name"].string
        flag = p["flag"].string
        region = p["region"].isNull ? "Europe" : p["region"].string
        currencyCode = p["currency"].string
        currencySymbol = p["symbol"].isNull ? p["currency"].string : p["symbol"].string
        self.fx = fx
        populationMillions = p["population"].double
        let giniValue = p["gini"].isNull ? 0.33 : p["gini"].double
        gini = giniValue
        let priceIndexRatio = eco["priceIndex"].double / ReferenceEconomy.priceIndex
        priceLevel = r2(priceIndexRatio)
        marketStrength = r2((B(eco["spendPerPerson"].double) / ReferenceEconomy.spendPerPerson / priceIndexRatio).squareRoot())
        startingPolicyRate = eco["policyRate"].double
        bureaucracy = eco["bureaucracy"].double
        rentLevel = r2(B(eco["officeRent"].double) / ReferenceEconomy.officeRent)
        wageLevel = r2(B(eco["medianWage"].double) / ReferenceEconomy.medianWage)
        startLoan = B(p["start"]["loan"].double)
        startLoanTermMonths = Int(saturating: jsRound(p["start"]["loanYears"].double * 12))
        corporateTax = tax["corporate"].double
        specialTax = tax["special"].object.mapValues { $0.double }
        dividendTax = tax["dividend"].double
        dividendShield = tax["dividendShield"].double
        capitalGainsTax = tax["capitalGains"].isNull ? tax["dividend"].double : tax["capitalGains"].double
        savingsInterestTax = tax["savingsInterest"].isNull ? tax["dividend"].double : tax["savingsInterest"].double
        lossFree = B(tax["loss"]["free"].double)
        lossShare = tax["loss"]["share"].isNull ? 1 : tax["loss"]["share"].double
        lossYears = tax["loss"]["years"].int
        employerSocial = tax["employer"]["social"].double
        employerPension = tax["employer"]["pension"].double
        employerInjury = tax["employer"]["injury"].double
        employerContributions = tax["employer"]["contributions"].array.map { EmployerContribution(name: $0["name"].string, rate: $0["rate"].double, capUnits: $0["capUMA"].double) }
        statePayrollTax = tax["employer"]["statePayroll"].double
        let unitDaily = tax["employer"]["unit"]["daily"].double, unitDays = tax["employer"]["unit"]["monthDays"].double
        contributionUnitMonthly = B(unitDaily * unitDays)
        employeeSocial = soc["employee"].double
        let wd = inc["wageDeduction"].array
        income = IncomeTax(
            flat: inc["flat"].double,
            allowance: B(inc["allowance"].double),
            wageDeduction: wd.count == 2 ? (wd[0].double, B(wd[1].double)) : nil,
            brackets: inc["brackets"].array.map { (B($0[0].double), $0[1].double) },
            socialFloor: B(soc["floor"].double),
            socialCapShare: soc["capShare"].double
        )
        let wealth = tax["wealth"]
        wealthRate = wealth.isNull ? 0 : wealth["rate"].double
        wealthThreshold = wealth.isNull ? 0 : B(wealth["threshold"].double)
        wealthCompanyShare = wealth.isNull ? 0 : wealth["companyShareCounted"].double
        let inh = tax["inherit"]
        inheritanceFree = inh.isNull ? 0 : B(inh["free"].double)
        inheritanceRate = inh["rate"].double
        inheritanceBusinessRelief = inh["biz"].double
        inheritanceBusinessFree = inh.isNull ? 0 : B(inh["bizFree"].double)
        let rates = p["vat"]["rates"]
        vat = VAT(standard: rates["std"].double, food: rates["food"].double, low: rates["low"].double, zero: rates["zero"].double)
        vatThreshold = B(p["vat"]["threshold"].double)
        vatFilingMonths = p["vat"]["filingMonths"].int
        usesSalesTax = p["vat"]["salesTax"].bool
        shareCapitalMinimum = B(p["companies"]["capital"].double)
        registrationFee = jsRound(B(p["companies"]["registrationFee"].double))
        companyForms = p["companies"]["forms"].object.mapValues { $0.string }
        overdraftMargin = eco["overdraftMargin"].isNull ? 0.10 : eco["overdraftMargin"].double
        vehicleRules = VehicleRules(pack: p)
        firstNames = p["names"]["first"].array.map { $0.string }
        lastNames = p["names"]["last"].array.map { $0.string }
        companyNameStarts = p["names"]["companyStart"].array.map { $0.string }
        self.pack = p

        let rentL = rentLevel, wageL = wageLevel, mkt = marketStrength, pl = priceLevel
        let derivedCities: [City] = p["cities"].array.map { x in
            if !x["id"].isNull {
                return City(id: x["id"].string, name: x["name"].string, population: x["pop"].double,
                            rent: x["rent"].double, wage: x["wage"].double, demand: x["dem"].double, price: x["price"].double)
            }
            let pop = x[2].double
            let dem = min(2.4, max(0.35, 0.42 + 0.55 * log10(pop / 20))) * mkt
            return City(
                id: x[0].string, name: x[1].string, population: pop,
                rent: r2(rentL * x[3].double), wage: r2(wageL * x[4].double),
                demand: r2(dem), price: r2(pl * (0.9 + 0.1 * x[3].double))
            )
        }

        let ei = p["economyIndex"]
        if p["citiesFinal"].bool {
            cities = derivedCities
            if ei.isNull { buyingPower = 1 } else {
                let ref = ReferenceEconomy.round20Reference
                priceLevel = r2(ei["costIndex"].double / ref.costIndex)
                wageLevel = r2(ei["wageIndex"].double / ref.wageIndex)
                marketStrength = 1
                buyingPower = ei["buyingPowerIndex"].double / ref.buyingPowerIndex
            }
        } else if ei.isNull {
            cities = derivedCities
            buyingPower = 1
        } else {
            let ref = ReferenceEconomy.round20Reference
            let newPL = r2(ei["costIndex"].double / ref.costIndex)
            let newWage = r2(ei["wageIndex"].double / ref.wageIndex)
            let oldPL = priceLevel == 0 ? 1 : priceLevel, oldWage = wageLevel == 0 ? 1 : wageLevel, oldMkt = marketStrength == 0 ? 1 : marketStrength
            cities = derivedCities.map { ct in
                var c = ct
                c.wage = r2(ct.wage / oldWage * newWage)
                c.price = r2(ct.price / oldPL * newPL)
                c.demand = r2(ct.demand / oldMkt)
                return c
            }
            priceLevel = newPL
            wageLevel = newWage
            marketStrength = 1
            buyingPower = ei["buyingPowerIndex"].double / ref.buyingPowerIndex
        }

        var entries: [String: JSONValue] = [:]
        for x in p["cities"].array { entries[x["id"].isNull ? x[0].string : x["id"].string] = x }
        let finalWageLevel = wageLevel
        cities = cities.map { City.withPlaceData($0, entry: entries[$0.id] ?? .null, countryGini: giniValue, wageLevel: finalWageLevel) }
        if !employerContributions.isEmpty { employerSocial = employerSocialRate(monthlyWage: B(eco["medianWage"].double)) }
    }
}
