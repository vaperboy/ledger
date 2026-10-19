import Foundation
import GameCore

/// One country's rules, derived from its data file (`Resources/countries.json`).
///
/// All money amounts here are in the game's **accounting unit** (an internal unit the player never sees; the
/// original game calls it "base units" and uses the Norwegian krone as the reference). A country's own currency
/// is worth `fx` accounting units per 1 local unit. To show a player a local amount, divide by the country's
/// current exchange rate (see `ExchangeRates`).
///
/// To change a country's economy, edit `countries.json`; no code needs to change (see docs/ADDING_CONTENT.md).
public struct Country: Equatable, Sendable, Identifiable {
    public struct City: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var population: Double   // thousands
        public var rent: Double          // rent level, 1 = national average
        public var wage: Double          // wage level
        public var demand: Double        // customer demand level
        public var price: Double         // price level
    }

    public struct IncomeTax: Equatable, Sendable {
        public var flat: Double
        public var allowance: Double
        /// [share, maximum] standard deduction for employees, if the country has one
        public var wageDeduction: (share: Double, maximum: Double)?
        /// (from income, marginal rate), ascending
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
    /// Accounting units per one unit of local currency (before monthly drift)
    public var fx: Double
    public var populationMillions: Double
    /// Price level versus the reference economy
    public var priceLevel: Double
    /// Real spending power (customers' purchasing strength)
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
    public var employerSocial: Double
    public var employerPension: Double
    public var employerInjury: Double
    public var employeeSocial: Double
    public var selfEmployedSocial: Double
    public var income: IncomeTax
    public var wealthRate: Double
    public var wealthThreshold: Double
    public var wealthCompanyShare: Double
    /// How well local people can afford things, relative to the reference country (1 = same). Original: `bp20`.
    public var buyingPower: Double
    public var inheritanceFree: Double
    public var inheritanceRate: Double
    public var inheritanceBusinessRelief: Double
    public var inheritanceBusinessFree: Double
    public var vat: VAT
    public var vatThreshold: Double
    public var vatFilingMonths: Int
    /// US-style sales tax: charged to consumers only
    public var usesSalesTax: Bool
    public var shareCapitalMinimum: Double
    public var registrationFee: Double
    public var conversionFee: Double
    public var companyForms: [String: String]
    public var leaveWeeks: Double
    public var firstNames: [String]
    public var lastNames: [String]
    public var companyNameStarts: [String]
    public var cities: [City]
    /// The original data file, kept whole for features that read extra fields (authorities, documents, tourism ...)
    public var pack: JSONValue

    public var id: String { code }

    /// Employer's total payroll multiplier: wages cost this much more than the gross pay. Original: `OC()`.
    public var employerCostFactor: Double { 1 + employerSocial + employerPension + employerInjury }

    /// Cost level used to scale fixed prices from the reference economy. Original: `costIdx`.
    public var costIndex: Double { 0.5 + 0.5 * priceLevel }

    public func city(_ id: String) -> City? { cities.first { $0.id == id } }
}

/// The reference economy every country is compared with. Original: `REF_ECONOMY`.
public enum ReferenceEconomy {
    public static let medianWage = 56000.0
    public static let priceIndex = 137.0
    public static let officeRent = 2500.0
    public static let spendPerPerson = 330000.0
    /// The reference country's row in the round-20 economy table (Norway: cost 110, wage 97, buying power 90).
    public static let round20Reference = (costIndex: 110.0, wageIndex: 97.0, buyingPowerIndex: 90.0)
}

extension Country {
    /// Build a country from its data-file entry. Original: `defineCountry(p)`.
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
        let priceIndexRatio = eco["priceIndex"].double / ReferenceEconomy.priceIndex
        priceLevel = r2(priceIndexRatio)
        marketStrength = r2((B(eco["spendPerPerson"].double) / ReferenceEconomy.spendPerPerson / priceIndexRatio).squareRoot())
        startingPolicyRate = eco["policyRate"].double
        bureaucracy = eco["bureaucracy"].double
        rentLevel = r2(B(eco["officeRent"].double) / ReferenceEconomy.officeRent)
        wageLevel = r2(B(eco["medianWage"].double) / ReferenceEconomy.medianWage)
        startLoan = B(p["start"]["loan"].double)
        startLoanTermMonths = Int(jsRound(p["start"]["loanYears"].double * 12))
        corporateTax = tax["corporate"].double
        specialTax = tax["special"].object.mapValues { $0.double }
        dividendTax = tax["dividend"].double
        dividendShield = tax["dividendShield"].double
        employerSocial = tax["employer"]["social"].double
        employerPension = tax["employer"]["pension"].double
        employerInjury = tax["employer"]["injury"].double
        employeeSocial = soc["employee"].double
        selfEmployedSocial = soc["selfEmployed"].double
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
        conversionFee = B(p["companies"]["conversionFee"].double)
        companyForms = p["companies"]["forms"].object.mapValues { $0.string }
        leaveWeeks = p["work"]["leaveWeeks"].double
        firstNames = p["names"]["first"].array.map { $0.string }
        lastNames = p["names"]["last"].array.map { $0.string }
        companyNameStarts = p["names"]["companyStart"].array.map { $0.string }
        self.pack = p

        // Cities. Original: MKCITY. Demand grows with the log of the city's population.
        let rentL = rentLevel, wageL = wageLevel, mkt = marketStrength, pl = priceLevel
        let derivedCities: [City] = p["cities"].array.map { x in
            // The reference country (NO) lists its cities fully worked out, as objects. All others use the compact list form.
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

        // "Round 20" economy table (original: features/world/country_economics.js). Real-world cost, wage and
        // buying-power indices (USD-based) replace the first-draft price, wage and demand levels. Applied once.
        let ei = p["economyIndex"]
        if ei.isNull {
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
    }
}
