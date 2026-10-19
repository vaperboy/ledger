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

    func testCountryDerivedValuesMatchOriginal() throws {
        let book = try CountryBook.bundled()
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
            assertClose(c.employerCostFactor, 1 + e["empNI"].double + e["otp"].double + e["injury"].double, tol: 1e-12)
            assertClose(c.inheritanceFree, e["inhFree"].double, tol: 1e-12)
            XCTAssertEqual(c.cities.count, e["cities"].array.count)
            for (city, ec) in zip(c.cities, e["cities"].array) {
                XCTAssertEqual(city.id, ec["id"].string)
                assertClose(city.demand, ec["dem"].double, tol: 1e-12, "\(c.code) \(city.id) dem")
                assertClose(city.rent, ec["rent"].double, tol: 1e-12)
                assertClose(city.wage, ec["wage"].double, tol: 1e-12)
                assertClose(city.price, ec["price"].double, tol: 1e-12)
            }
            for (a, b) in zip(c.income.brackets, e["income"]["brackets"].array) {
                assertClose(a.from, b[0].double, tol: 1e-9, "\(c.code) bracket")
                assertClose(a.rate, b[1].double)
            }
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
        for c in book.countries {
            let t = g["tax"][c.code]
            for (i, inc) in t["inc"].array.enumerated() {
                let v = inc.double
                assertClose(Taxes.personalIncomeTax(v, kind: .selfEmployed, in: c), t["self"][i].double, tol: 1e-9, "\(c.code) self \(v)")
                assertClose(Taxes.personalIncomeTax(v, kind: .wage, in: c), t["wage"][i].double, tol: 1e-9, "\(c.code) wage \(v)")
                assertClose(Taxes.dividendTax(v, shield: 50000, in: c), t["div"][i].double, tol: 1e-9)
                assertClose(Taxes.wealthTax(netWorth: v * 10, in: c), t["wealth"][i].double, tol: 1e-9)
                assertClose(Taxes.bracketTax(v, brackets: c.income.brackets), t["br"][i].double, tol: 1e-9)
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
