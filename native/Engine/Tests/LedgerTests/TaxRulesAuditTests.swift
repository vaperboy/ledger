import XCTest
import GameCore
import Countries
import Employees
import Finance
import Businesses
@testable import Investments
@testable import Simulation

/// Capital gains and savings interest rates, the corporate tax deadline, loss carry-forward limits, monotonic income brackets,
/// statutory sick pay and the scaled broker minimums (docs/TAX_SOURCES.md, "Second tax pass").
final class TaxRulesAuditTests: XCTestCase {
    private func book() throws -> CountryBook { try CountryBook.bundled() }

    func testIncomeBracketsNeverFallInAnyCountry() throws {
        for c in try book().countries {
            var last = -1.0, lastRate = -1.0
            for b in c.income.brackets {
                XCTAssertGreaterThan(b.from, last - 1e-9, "\(c.code) thresholds rise")
                XCTAssertGreaterThanOrEqual(b.rate, lastRate - 1e-12, "\(c.code) marginal rate falls at \(b.from)")
                last = b.from; lastRate = b.rate
            }
        }
        let br = try book().countries.first { $0.code == "BR" }!
        XCTAssertEqual(br.income.brackets.map { $0.rate }, [0, 0.075, 0.15, 0.225, 0.275])
        XCTAssertEqual(br.income.brackets[1].from, 60000 * br.fx, accuracy: 1e-6, "exempt up to BRL 5,000 a month")
    }

    func testCapitalGainsAndInterestHaveTheirOwnRates() throws {
        let b = try book()
        func c(_ code: String) -> Country { b.countries.first { $0.code == code }! }
        XCTAssertEqual(c("CH").capitalGainsTax, 0)               // no tax on private gains
        XCTAssertEqual(c("SG").capitalGainsTax, 0)
        XCTAssertEqual(c("DE").capitalGainsTax, 0.26375, accuracy: 1e-12)
        XCTAssertEqual(c("DE").savingsInterestTax, 0.26375, accuracy: 1e-12)
        XCTAssertEqual(c("UK").capitalGainsTax, 0.24, accuracy: 1e-12)
        XCTAssertEqual(c("UK").dividendTax, 0.3575, accuracy: 1e-12)
        XCTAssertEqual(c("FR").capitalGainsTax, 0.314, accuracy: 1e-12)
        XCTAssertEqual(c("US").capitalGainsTax, 0.15, accuracy: 1e-12)
        XCTAssertEqual(c("IE").capitalGainsTax, 0.33, accuracy: 1e-12)
        XCTAssertEqual(c("NO").savingsInterestTax, 0.22, accuracy: 1e-12)
        XCTAssertNotEqual(c("UK").capitalGainsTax, c("UK").dividendTax)
        // The reader uses them, and only them, at the year end.
        for code in ["CH", "UK", "US", "DE", "KR"] {
            var e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: 5)
            e.update { s, data, ctx in
                let k = data.countries.resolve(code, orHome: code)
                s.tax = PersonalTaxYear(raw: ["ytd": 0, "paid": 0, "enkIncome": 0, "wage": 0, "div": 0, "ytdDiv": 0, "withheld": 0, "gain": 0, "int": 0, "shield": 0])
                s.tax.gains = 2_000_000; s.tax.interest = 100_000
                let before = s.cash + s.savings
                PersonalFinance.yearEnd(&s, context: ctx, netWorth: 0, ownedCompanyValue: 0)
                XCTAssertEqual(before - (s.cash + s.savings), 2_000_000 * k.capitalGainsTax + 100_000 * k.savingsInterestTax, accuracy: 3, code)
            }
        }
    }

    func testCorporateTaxFallsDueAtTheCountrysLag() throws {
        let b = try book()
        func c(_ code: String) -> Country { b.countries.first { $0.code == code }! }
        XCTAssertEqual(c("UK").corporateTaxDueWeeks, 39, "9 months and a day")
        XCTAssertEqual(c("US").corporateTaxDueWeeks, 15, "15 April")
        XCTAssertEqual(c("PL").corporateTaxDueWeeks, 13)
        XCTAssertEqual(Set(b.countries.map { $0.corporateTaxDueWeeks }).count > 5, true, "not 26 weeks everywhere")
        for code in ["UK", "US", "JP"] {
            var e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: 3)
            e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
            guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 5_000_000) else { XCTFail(code); continue }
            e.update { s, data, ctx in
                let i = s.companyIndex(id)!
                s.companies[i].status = .open
                s.companies[i].payables["tax"] = 1000
                MonthEnd.closeYear(&s, data: data, context: ctx)
                XCTAssertEqual(s.companies[i].taxDueWeek, s.week + data.countries.resolve(code, orHome: code).corporateTaxDueWeeks, code)
            }
        }
    }

    func testLossLimitsAndExpiry() throws {
        let b = try book()
        func c(_ code: String) -> Country { b.countries.first { $0.code == code }! }
        let de = c("DE"), us = c("US"), fr = c("FR"), no = c("NO")
        let m = 1_000_000 * de.fx
        XCTAssertEqual(Taxes.lossOffsetLimit(profit: 10 * m, in: de), m + 0.6 * 9 * m, accuracy: 1e-6, "DE: 1M + 60% above")
        XCTAssertEqual(Taxes.lossOffsetLimit(profit: 0.5 * m, in: de), 0.5 * m, accuracy: 1e-6)
        XCTAssertEqual(Taxes.lossOffsetLimit(profit: 10 * m, in: fr), m + 0.5 * 9 * m, accuracy: 1e-6, "FR: 1M + 50% above")
        XCTAssertEqual(Taxes.lossOffsetLimit(profit: 10_000_000, in: us), 8_000_000, accuracy: 1e-6, "US: 80% of taxable income")
        XCTAssertEqual(Taxes.lossOffsetLimit(profit: 10_000_000, in: no), 10_000_000, "NO: no cap")
        XCTAssertEqual(c("JP").lossYears, 10); XCTAssertEqual(c("MX").lossYears, 10); XCTAssertEqual(c("CA").lossYears, 20)
        XCTAssertEqual(no.lossYears, 0)

        // End to end in the US: 100M of old losses, 20M profit: only 80% of the profit is covered, tax on the other 20%.
        var e = try GameEngine.newGame(countryCode: "US", playerName: "T", seed: 4)
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 5_000_000) else { return XCTFail("cafe") }
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            s.companies[i].status = .open
            s.companies[i].lossCarryForward = 100_000_000
            s.companies[i].payables["tax"] = 0
            for _ in 0..<12 {
                var bk = s.companies[i].books; bk.month = ["rev": 20_000_000.0 / 12]; s.companies[i].books = bk
                MonthEnd.closeMonth(&s, companyIndex: i, data: data, context: ctx)
            }
            let rate = data.countries.resolve("US", orHome: "US").corporateTax
            XCTAssertEqual(s.companies[i].taxAccrued, 20_000_000 * 0.2 * rate, accuracy: 1)
            XCTAssertEqual(s.companies[i].lossCarryForward, 100_000_000 - 16_000_000, accuracy: 1)
        }

        // Expiry: Japan's losses last 10 years. A lot from year 1 is gone when year 10 closes; a lot from year 5 is not.
        let jp = c("JP")
        var co = e.state.companies[e.state.companyIndex(id)!]
        co.lossCarryAtYearStart = 300; co.lossCarryForward = 300; co.yearProfitSoFar = 0
        co.set("lossLots", .array([.array([.number(1), .number(100)]), .array([.number(5), .number(200)])]))
        var early = co
        MonthEnd.rollLossLots(&early, country: jp, closingYear: 10)
        XCTAssertEqual(early.lossCarryForward, 300, accuracy: 1e-9, "the year-1 loss can still be used in year 11")
        MonthEnd.rollLossLots(&co, country: jp, closingYear: 11)
        XCTAssertEqual(co.lossCarryForward, 200, accuracy: 1e-9, "the year-1 loss lapsed after ten years")
        // No limit in Norway: nothing lapses
        var co2 = e.state.companies[e.state.companyIndex(id)!]
        co2.lossCarryAtYearStart = 300; co2.lossCarryForward = 300; co2.yearProfitSoFar = 0
        co2.set("lossLots", .array([.array([.number(1), .number(300)])]))
        MonthEnd.rollLossLots(&co2, country: no, closingYear: 40)
        XCTAssertEqual(co2.lossCarryForward, 300, accuracy: 1e-9)
        // A loss this year is added as a new lot; profit uses the oldest lot first
        var co3 = e.state.companies[e.state.companyIndex(id)!]
        co3.lossCarryAtYearStart = 300; co3.yearProfitSoFar = -50; co3.lossCarryForward = 350
        co3.set("lossLots", .array([.array([.number(1), .number(300)])]))
        MonthEnd.rollLossLots(&co3, country: no, closingYear: 3)
        XCTAssertEqual(co3.lossCarryForward, 350, accuracy: 1e-9)
        XCTAssertEqual(co3.value("lossLots").array.count, 2)
    }

    // MARK: Sick pay

    func testStatutorySickPayByCountry() throws {
        func rules(_ code: String) -> LabourRules { LabourRules(code: code) }
        let w = 10_000.0   // a weekly wage far above every flat cap, in the same units as the rate 1
        XCTAssertEqual(rules("DE").employerSickPay(weeklyWage: w), w, accuracy: 1e-9, "DE: six weeks at 100% by the employer")
        XCTAssertEqual(rules("US").employerSickPay(weeklyWage: w), 0, "US: no federal sick pay")
        XCTAssertEqual(rules("JP").employerSickPay(weeklyWage: w), 0, "JP: health insurance, not the employer")
        XCTAssertEqual(rules("FR").employerSickPay(weeklyWage: w), w * 0.4 * 2 / 5, accuracy: 1e-9, "FR: three waiting days, then the employer's top-up")
        XCTAssertEqual(rules("SE").employerSickPay(weeklyWage: w), w * 0.8 * 4 / 5, accuracy: 1e-9, "SE: 80% after the qualifying day")
        XCTAssertEqual(rules("ES").employerSickPay(weeklyWage: w), w * 0.6 * 2 / 5, accuracy: 1e-9, "ES: nothing for three days, then 60%")
        XCTAssertEqual(rules("LT").employerSickPay(weeklyWage: w), w * 0.6206 * 2 / 5, accuracy: 1e-9, "LT: the employer pays the first two days")
        XCTAssertEqual(rules("UK").employerSickPay(weeklyWage: w, rate: 1), 123.25, accuracy: 1e-9, "UK: SSP flat weekly rate from 6 April 2026")
        XCTAssertEqual(rules("UK").employerSickPay(weeklyWage: 100, rate: 1), 80, accuracy: 1e-9, "UK: 80% of earnings when that is lower")
        XCTAssertEqual(rules("IE").employerSickPay(weeklyWage: w, rate: 1), 550, accuracy: 1e-9, "IE: 70% up to EUR 110 a day")
        XCTAssertEqual(rules("NL").employerSickPay(weeklyWage: w), w * 0.7, accuracy: 1e-9)
    }

    func testSickWeekCostsWhatTheLawSaysInThePayroll() throws {
        for code in ["UK", "DE", "FR", "US", "JP", "SE"] {
            var e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: 6)
            e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
            guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 5_000_000) else { XCTFail(code); continue }
            e.update { s, data, _ in
                let i = s.companyIndex(id)!
                s.companies[i].status = .open
                s.companies[i].staff = [StaffMember(raw: ["id": 9001, "role": "waiter", "wage": 1_000_000, "w0": 0])]
                s.companies[i].managerID = nil
                let bd = data.catalog[s.companies[i].type]!
                let country = data.countries.resolve(code, orHome: code)
                let labour = LabourRules(country: country)
                let weekly = 1_000_000.0 * 12 / 52
                _ = CompanyCosts.wages(&s, companyIndex: i, bd, data: data)
                let healthy = s.companies[i].lastWages
                XCTAssertEqual(healthy, weekly * (1 + labour.leaveWeeks / 52 * 0.3) * country.employerCostFactor, accuracy: 1e-6, "\(code) healthy week")
                s.companies[i].staff[0].sickUntilWeek = s.week
                _ = CompanyCosts.wages(&s, companyIndex: i, bd, data: data)
                let sick = s.companies[i].lastWages
                let paid = labour.employerSickPay(weeklyWage: weekly, rate: country.fx, capScale: World(state: s, data: data).inflationIndex)
                XCTAssertEqual(sick, paid * country.employerCostFactor, accuracy: 1e-6, "\(code) sick week")
                switch code {
                case "DE": XCTAssertEqual(sick, weekly * country.employerCostFactor, accuracy: 1e-6)
                case "US", "JP": XCTAssertEqual(sick, 0)
                case "UK": XCTAssertEqual(paid, 123.25 * country.fx * World(state: s, data: data).inflationIndex, accuracy: 1e-6)
                default: XCTAssertLessThan(sick, healthy)
                }
            }
        }
    }

    // MARK: Broker minimums

    func testBrokerMinimumsScaleWithThePriceLevel() throws {
        let b = try book()
        let ch = b.countries.first { $0.code == "CH" }!, ke = b.countries.first { $0.code == "MX" }!
        for c in [ch, ke] {
            let cur = Currency(country: c, rates: ExchangeRates())
            XCTAssertEqual(Brokerage.minimumPurchase(cur), cur.scaledPrice(100))
            XCTAssertEqual(Brokerage.brokerFee(1, currency: cur), cur.scaledPrice(29))
        }
        XCTAssertNotEqual(Brokerage.minimumPurchase(Currency(country: ch, rates: ExchangeRates())), Brokerage.minimumPurchase(Currency(country: ke, rates: ExchangeRates())))
        XCTAssertEqual(Brokerage.minimumPurchase(nil), 100)
        XCTAssertEqual(Brokerage.brokerFee(1), 29)
        var e = try GameEngine.newGame(countryCode: "CH", playerName: "T", seed: 8)
        e.update { s, _, _ in
            let cur = Currency(country: ch, rates: ExchangeRates(drift: s.exchangeRates.values))
            let min = Brokerage.minimumPurchase(cur)
            XCTAssertEqual(Brokerage.buy(&s, .stock, "FOOD", amount: min - 1, currency: cur), .tooSmall)
        }
    }
}
