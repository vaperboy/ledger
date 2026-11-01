import XCTest
import GameCore
import Countries
import Finance

/// Random numbers, calendar, money formatting, rounding and tax must match the original game exactly.
final class FoundationTests: XCTestCase {
    func testRandomSequenceMatchesOriginal() throws {
        let g = try Golden.load("currency_tax_rng")
        var r = DeterministicRandom(state: Int32(g["rng"]["seed"].int))
        for (i, z) in g["rng"]["z"].array.enumerated() { assertClose(r.next(), z.double, tol: 1e-15, "z[\(i)]") }
        for (i, z) in g["rng"]["rint"].array.enumerated() { XCTAssertEqual(r.int(3, 9), z.int, "rint[\(i)]") }
        for (i, z) in g["rng"]["gauss"].array.enumerated() { assertClose(r.gauss(), z.double, tol: 1e-12, "gauss[\(i)]") }
        for (i, z) in g["rng"]["pois"].array.enumerated() { XCTAssertEqual(r.poisson(Double(i) * 4.5), z.int, "pois[\(i)]") }
        XCTAssertEqual(Int(r.state), g["rng"]["after"].int, "state after sequence")

        var r2 = DeterministicRandom(state: Int32(g["rng2"]["seed"].int))
        for z in g["rng2"]["z"].array { assertClose(r2.next(), z.double, tol: 1e-15) }
        XCTAssertEqual(Int(r2.state), g["rng2"]["after"].int)

        var r3 = DeterministicRandom(state: 5)
        XCTAssertEqual(r3.shuffled([1, 2, 3, 4, 5, 6, 7, 8]), g["shuffle"].array.map { $0.int })
        XCTAssertEqual(Int(r3.state), g["shufAfter"].int)

        var r4 = DeterministicRandom(state: 9)
        let items = [("a", 1.0), ("b", 3.0), ("c", 0.0), ("d", 6.0)]
        let picked = (0..<10).map { _ in r4.weightedPick(items) { $0.1 }!.0 }
        XCTAssertEqual(picked, g["wpick"].array.map { $0.string })
    }

    func testCalendarMatchesOriginal() throws {
        let g = try Golden.load("currency_tax_rng")
        for e in g["cal"].array {
            let w = e["w"].int
            XCTAssertEqual(GameCalendar.dateString(week: w), e["d"].string, "date week \(w)")
            XCTAssertEqual(GameCalendar.monthString(week: w), e["m"].string)
            XCTAssertEqual(GameCalendar.monthIndex(week: w), e["mi"].int)
            XCTAssertEqual(GameCalendar.isMonthEnd(week: w), e["me"].bool, "month end week \(w)")
            XCTAssertEqual(GameCalendar.isYearEnd(week: w), e["ye"].bool, "year end week \(w)")
            XCTAssertEqual(GameCalendar.date(week: w).weekday, e["wd"].int)
        }
    }

    /// Tax figures deliberately corrected to the 2025/26 law (docs/TAX_SOURCES.md lists every change). The original's numbers are
    /// kept in Golden/countries_derived.json; for these (country, field) pairs the test checks the corrected values instead
    /// (`testCorrectedTaxFiguresArePinned`).
    static let correctedBrackets: Set<String> = ["SE", "LT", "DE", "FR", "NL", "US", "CA", "BR", "DK", "FI", "MX"]
    // MX: IMSS table + 3% state payroll tax; BR: employer FGTS 8% as payroll (owner-supplied 2026 rules, docs/TAX_SOURCES.md)
    static let correctedEmployerCost: Set<String> = ["DE", "MX", "BR"]

    func testCountryDerivedValuesMatchOriginal() throws {
        // The original game's city data: the real-life city overlay (docs/CITY_DATA.md) adds cities and fields on top of it.
        let book = try CountryBook.bundled(realCityMarket: false)
        XCTAssertEqual(book.countries.count, 23)
        let g = try Golden.load("countries_derived")
        for c in book.countries {
            let e = g[c.code]
            assertClose(c.priceLevel, e["pl"].double, tol: 1e-12, "\(c.code) pl")
            assertClose(c.marketStrength, e["mkt"].double, tol: 1e-12, "\(c.code) mkt")
            assertClose(c.rentLevel, e["rent"].double, tol: 1e-12, "\(c.code) rent")
            assertClose(c.wageLevel, e["wage"].double, tol: 1e-12, "\(c.code) wage")
            assertClose(c.startLoan, e["loan"].double, tol: 1e-12, "\(c.code) loan")
            XCTAssertEqual(c.startLoanTermMonths, e["loanTermM"].int)
            assertClose(c.shareCapitalMinimum, e["asCapital"].double, tol: 1e-12)
            assertClose(c.registrationFee, e["asFee"].double, tol: 1e-12)
            assertClose(c.conversionFee, e["asConvFee"].double, tol: 1e-12)
            assertClose(c.vatThreshold, e["vatThr"].double, tol: 1e-12)
            if !Self.correctedEmployerCost.contains(c.code) { assertClose(c.employerCostFactor, 1 + e["empNI"].double + e["otp"].double + e["injury"].double, tol: 1e-12) }
            assertClose(c.inheritanceFree, e["inhFree"].double, tol: 1e-12)
            XCTAssertEqual(c.cities.count, e["cities"].array.count)
            for (city, ec) in zip(c.cities, e["cities"].array) {
                XCTAssertEqual(city.id, ec["id"].string)
                assertClose(city.demand, ec["dem"].double, tol: 1e-12, "\(c.code) \(city.id) dem")
                assertClose(city.rent, ec["rent"].double, tol: 1e-12)
                assertClose(city.wage, ec["wage"].double, tol: 1e-12)
                assertClose(city.price, ec["price"].double, tol: 1e-12)
            }
            for (a, b) in zip(c.income.brackets, e["income"]["brackets"].array) where !Self.correctedBrackets.contains(c.code) {
                assertClose(a.from, b[0].double, tol: 1e-9, "\(c.code) bracket")
                assertClose(a.rate, b[1].double)
            }
        }
    }

    func testCorrectedTaxFiguresArePinned() throws {
        let book = try CountryBook.bundled()
        func c(_ code: String) -> Country { book.countries.first { $0.code == code }! }
        // Local-currency figures x the country's fx give accounting units
        func local(_ code: String, _ v: Double) -> Double { v * c(code).fx }
        XCTAssertEqual(c("UK").dividendTax, 0.3575, accuracy: 1e-12)          // upper dividend rate from April 2026
        XCTAssertEqual(c("FR").dividendTax, 0.314, accuracy: 1e-12)           // PFU 31.4% from 2026
        XCTAssertEqual(c("LT").corporateTax, 0.17, accuracy: 1e-12)           // 17% from 2026
        XCTAssertEqual(c("AE").corporateTax, 0.09, accuracy: 1e-12)           // federal 9%
        XCTAssertEqual(c("DE").employeeSocial, 0.2115, accuracy: 1e-12)
        XCTAssertEqual(c("DE").employerSocial, 0.2115, accuracy: 1e-12)
        XCTAssertEqual(c("US").income.brackets[1].from, local("US", 16100), accuracy: 1e-6)   // 2026 standard deduction
        XCTAssertEqual(c("DE").income.brackets[1].from, local("DE", 12348), accuracy: 1e-6)   // 2026 basic allowance
        XCTAssertEqual(c("FR").income.brackets[1].from, local("FR", 11600), accuracy: 1e-6)
        XCTAssertEqual(c("NL").income.brackets.map { $0.rate }, [0.3575, 0.3756, 0.495])
        XCTAssertEqual(c("LT").income.brackets.map { $0.rate }, [0.2, 0.25, 0.32])
        XCTAssertEqual(c("DK").income.brackets.map { $0.rate }, [0, 0.3706, 0.4456, 0.5206, 0.5706])
        // LT: 36 and 60 x the 2026 average wage (EUR 2,312.15 a month) = EUR 83,237.40 and 138,729 (VMI / KPMG LT, 2026)
        XCTAssertEqual(c("LT").income.brackets[1].from, local("LT", 83237), accuracy: 1e-6)
        XCTAssertEqual(c("LT").income.brackets[2].from, local("LT", 138729), accuracy: 1e-6)
        // MX: annual tariff of Anexo 8 RMF 2026 (DOF 28 Dec 2025): second step from MXN 10,135.12
        XCTAssertEqual(c("MX").income.brackets[1].from, local("MX", 10135), accuracy: 1e-6)
        XCTAssertEqual(c("MX").income.brackets.last!.from, local("MX", 5107704), accuracy: 1e-6)
        // Owner-supplied 2026 rules: MX ISR 30% on taxable profit, IVA 16%, dividend withholding 10%, state payroll tax 3% plus IMSS from the table
        XCTAssertEqual(c("MX").corporateTax, 0.30, accuracy: 1e-12)
        XCTAssertEqual(c("MX").vat.standard, 0.16, accuracy: 1e-12)
        XCTAssertEqual(c("MX").dividendTax, 0.10, accuracy: 1e-12)
        XCTAssertEqual(c("MX").statePayrollTax, 0.03, accuracy: 1e-12)
        XCTAssertFalse(c("MX").employerContributions.isEmpty)
        // IMSS is computed from pay: below the cap the effective rate is the table sum + 3%, far above the cap it falls
        let mx = c("MX"), tableSum = mx.employerContributions.reduce(0) { $0 + $1.rate }
        XCTAssertEqual(mx.employerSocialRate(monthlyWage: mx.contributionUnitMonthly * 5), tableSum + 0.03, accuracy: 1e-9)
        XCTAssertLessThan(mx.employerSocialRate(monthlyWage: mx.contributionUnitMonthly * 250), tableSum + 0.03)
        // LT: standard VAT 21%; the reduced category rate (old 9%) is 12% from 2026; the other reduced rate and the zero rate stay separate
        XCTAssertEqual(c("LT").vat.standard, 0.21, accuracy: 1e-12)
        XCTAssertEqual(c("LT").vat.food, 0.12, accuracy: 1e-12)
        XCTAssertEqual(c("LT").vat.low, 0.05, accuracy: 1e-12)
        XCTAssertEqual(c("LT").vat.zero, 0, accuracy: 1e-12)
        XCTAssertEqual(c("BR").employerPension, 0.08, accuracy: 1e-12)   // employer FGTS 8% is payroll cost
        // FI: combined state (12.64 / 19 / 30.25 / 33.25 / 37.5% , Vero 2026) + municipal scale, fitted to Veronmaksajat's 2026 table
        XCTAssertEqual(c("FI").income.brackets.map { $0.rate }, [0, 0.27, 0.33, 0.42, 0.44])
        XCTAssertEqual(c("NO").wealthThreshold, local("NO", 1_900_000), accuracy: 1e-6)
        XCTAssertEqual(c("BR").income.brackets[1].from, local("BR", 60000), accuracy: 1e-6)    // exempt up to BRL 5,000 a month
        // Every country says when and how its figures were checked
        for country in book.countries {
            XCTAssertEqual(country.pack["dataBasis"]["checked"].string, "2026-10", country.code)
            XCTAssertFalse(country.pack["dataBasis"]["note"].string.isEmpty, country.code)
        }
    }

    func testMoneyFormattingAndRoundingMatchOriginal() throws {
        let book = try CountryBook.bundled()
        let g = try Golden.load("currency_tax_rng")
        let vals = g["vals"].array.map { $0.double }
        let rates = ExchangeRates(drift: ["UK": 1.07, "US": 0.93, "JP": 1.2, "KR": 0.85, "SE": 1.01])
        for c in book.countries {
            let cur = Currency(country: c, rates: rates)
            let e = g["fmt"][c.code]
            assertClose(cur.rate, e["rate"].double, tol: 1e-12, "\(c.code) rate")
            for (i, v) in vals.enumerated() {
                XCTAssertEqual(cur.format(v), e["money"][i].string, "\(c.code) money(\(v))")
                XCTAssertEqual(cur.format(v, plain: true), e["plain"][i].string, "\(c.code) plain(\(v))")
                XCTAssertEqual(cur.short(v), e["mshort"][i].string, "\(c.code) mshort(\(v))")
                assertClose(cur.tidy(v), e["rl"][i].double, tol: 1e-9, "\(c.code) rl(\(v))")
                assertClose(cur.roundedStep(v, about: 100), e["rnl100"][i].double, tol: 1e-9, "\(c.code) rnl100(\(v))")
                assertClose(cur.roundedStep(v, about: 1000), e["rnl1000"][i].double, tol: 1e-9, "\(c.code) rnl1000(\(v))")
                assertClose(cur.roundedStep(v, about: 25), e["rnl25"][i].double, tol: 1e-9, "\(c.code) rnl25(\(v))")
                assertClose(cur.scaledPrice(v), e["KC"][i].double, tol: 1e-9, "\(c.code) KC(\(v))")
                assertClose(Currency.nicePrice(v), e["nice"][i].double, tol: 1e-9, "nice(\(v))")
            }
        }
    }

    func testTaxesMatchOriginal() throws {
        let book = try CountryBook.bundled()
        let g = try Golden.load("currency_tax_rng")
        // Deliberately corrected to the 2025/26 law (docs/TAX_SOURCES.md): income tax, dividend tax and wealth tax of these countries
        // no longer equal the original's numbers; `testCorrectedTaxFiguresArePinned` pins the new values.
        let incomeCorrected = Self.correctedBrackets.union(["NO"])
        let dividendCorrected: Set<String> = ["UK", "FR"]
        let wealthCorrected: Set<String> = ["NO"]
        for c in book.countries {
            let t = g["tax"][c.code]
            for (i, inc) in t["inc"].array.enumerated() {
                let v = inc.double
                if !incomeCorrected.contains(c.code) {
                    assertClose(Taxes.personalIncomeTax(v, kind: .selfEmployed, in: c), t["self"][i].double, tol: 1e-9, "\(c.code) self \(v)")
                    assertClose(Taxes.personalIncomeTax(v, kind: .wage, in: c), t["wage"][i].double, tol: 1e-9, "\(c.code) wage \(v)")
                    assertClose(Taxes.bracketTax(v, brackets: c.income.brackets), t["br"][i].double, tol: 1e-9)
                }
                if !dividendCorrected.contains(c.code) { assertClose(Taxes.dividendTax(v, shield: 50000, in: c), t["div"][i].double, tol: 1e-9) }
                if !wealthCorrected.contains(c.code) { assertClose(Taxes.wealthTax(netWorth: v * 10, in: c), t["wealth"][i].double, tol: 1e-9) }
            }
        }
    }

    func testAnnuityMatchesOriginal() throws {
        let g = try Golden.load("currency_tax_rng")
        for e in g["annuity"].array {
            let a = e[0]
            assertClose(Loans.annuity(principal: a[0].double, yearlyRate: a[1].double, months: a[2].double), e[1].double, tol: 1e-12)
        }
    }
}
