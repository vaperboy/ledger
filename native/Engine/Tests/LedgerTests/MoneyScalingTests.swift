import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Money limits must make sense in every country's own currency (docs/MONEY_SCALING.md). A fixed number of accounting units
/// is a handful of coins in one country and a month's rent in another, so every limit that a player meets is derived from
/// the country's median wage (`medianMonthlyWage`) or price level (`Currency.scaledPrice`).
final class MoneyScalingTests: XCTestCase {
    func newGame(_ code: String) throws -> GameEngine { try GameEngine.newGame(countryCode: code, playerName: "T", seed: 7) }

    /// Loan offers, the overdraft, the start-up loan and the group threshold are a sensible number of months of an ordinary wage
    /// in each of the 23 countries (not tens of years in poor countries or a few days in rich ones).
    func testLimitsAreSensibleMultiplesOfTheLocalWageInEveryCountry() throws {
        let book = try CountryBook.bundled()
        XCTAssertEqual(book.countries.count, 23)
        for c in book.countries {
            var e = try newGame(c.code)
            let wage = c.medianMonthlyWage
            XCTAssertGreaterThan(wage, 0, c.code)
            // The start-up loan buys a similar business everywhere: it follows the price level (companies' costs do), not the wage level
            let loanPerPriceLevel = c.startLoan / c.costIndex
            XCTAssertTrue((100_000...260_000).contains(loanPerPriceLevel), "\(c.code): start-up loan is \(loanPerPriceLevel) at the reference price level")
            // The consumer-loan offer for a player without other debts (fair credit): a few months of wages, never absurd
            e.update { s, _, _ in s.loans.removeAll() }
            let offer = e.loanOffer(kind: "cons", amount: 0, companyID: nil)
            let months = offer.maximum / wage
            XCTAssertTrue((0.3...8).contains(months), "\(c.code): consumer loan offer is \(months) median wages (\(e.homeCurrency.display(offer.maximum)))")
            // The overdraft allowance: a fraction of a year's wage
            let od = e.state.overdraftLimit / wage
            XCTAssertTrue((0.2...6).contains(od), "\(c.code): overdraft limit is \(od) median wages")
            // The group-size threshold of the original (5 M at the reference economy) follows the price level
            let big = e.state.rest["group"]?["big"].double ?? 0
            let ref = 5_000_000.0
            XCTAssertEqual(big / ref, c.costIndex, accuracy: 0.05 * c.costIndex, "\(c.code): group threshold \(big)")
        }
    }

    /// The bank's assumed minimum income is derived from the country's median wage: 380 000 at the reference economy (a wage level
    /// of 1), so a country with half the wage level assumes half. (The original used one country's level for everybody.)
    func testLoanIncomeFloorFollowsTheMedianWage() throws {
        let book = try CountryBook.bundled()
        for c in book.countries {
            XCTAssertEqual(Banking.assumedIncomeMonths * c.medianMonthlyWage, 380_000 * c.wageLevel, accuracy: 1e-6, c.code)
            XCTAssertEqual(c.medianMonthlyWage, ReferenceEconomy.medianWage * c.wageLevel, accuracy: 1e-9)
        }
        // A new player with no income still gets a loan offer worth a few months of the local wage
        let poor = try newGame("PL"), rich = try newGame("CH")
        let a = poor.loanOffer(kind: "cons", amount: 0, companyID: nil).maximum / (try CountryBook.bundled()["PL"]!.medianMonthlyWage)
        let b = rich.loanOffer(kind: "cons", amount: 0, companyID: nil).maximum / (try CountryBook.bundled()["CH"]!.medianMonthlyWage)
        XCTAssertEqual(a, b, accuracy: 0.6 * max(a, b), "offers should be comparable in months of wages: PL \(a), CH \(b)")
    }

    /// Fines and thresholds written at the reference price level become the country's price level.
    func testFinesAndThresholdsScaleWithThePriceLevel() throws {
        let book = try CountryBook.bundled()
        let ch = book["CH"]!, br = book["BR"]!
        XCTAssertGreaterThan(ch.costIndex, br.costIndex)
        let curCH = Currency(country: ch, rates: ExchangeRates()), curBR = Currency(country: br, rates: ExchangeRates())
        XCTAssertGreaterThan(curCH.scaledPrice(6000), curBR.scaledPrice(6000))
        // In its own currency a Swiss fine is of the same order as a Brazilian one only after dividing by the exchange rate
        XCTAssertEqual(curCH.scaledPrice(6000) / ch.costIndex, 6000, accuracy: 6000 * 0.05)
    }
}

/// A lint that keeps new unscaled money constants out of the engine: every number of 1000 or more in the engine's sources must
/// either sit in a call that scales it (`scaledPrice`, `medianMonthlyWage`, a rounding step ...) or be listed below with the reason
/// it is a design constant rather than an amount the player sees.
final class MoneyLiteralLintTests: XCTestCase {
    /// file name -> literals that are allowed without scaling, with the reason
    static let allowed: [String: [String: String]] = [
        "Country.swift": ["56000": "ReferenceEconomy: the reference economy's own numbers", "2500": "ReferenceEconomy", "330000": "ReferenceEconomy"],
        "Currency.swift": ["1000": "rounding steps of nicePrice", "5000": "rounding steps", "10000": "rounding steps", "50000": "rounding steps", "100000": "rounding steps"],
        "Wages.swift": ["80000": "wage elasticity against the role table's reference wage"],
        "TradeCatalog.swift": ["3400": "calibration of a trade at the reference economy"],
        "TradeTuning.swift": ["250000": "documentation example", "150000000": "documentation example"],
        "Markets.swift": ["980000": "crypto price in accounting units (global asset)", "36000": "crypto price", "1700": "crypto price"],
        "Demo.swift": ["60_000_000": "showcase data", "4_000_000": "showcase data", "9_000_000": "showcase data"],
        "Banking.swift": ["80_000": "reference-economy base, divided by its median wage", "380_000": "reference-economy base, divided by its median wage", "1000": "rounding of the offer"],
        "StaffTalks.swift": ["70000": "compared with the role table's reference wage", "45000": "compared with the role table's reference wage", "50000": "fallback role wage at the reference level"],
        "StaffRoutine.swift": ["40000": "fallback role wage at the reference level"],
        "Hiring.swift": ["40000": "fallback role wage at the reference level (scaled by the city wage right after)"],
        "CompanySetup.swift": ["1000": "rounding step", "300000": "fallback vehicle price at the reference level", "40000": "fallback role wage at the reference level",
                               "220000": "inside scaledPrice", "50000": "inside scaledPrice", "25000": "inside scaledPrice", "8000": "inside scaledPrice", "3000": "inside scaledPrice"],
        "DailyTrade.swift": ["100000": "trade ticket class (reference level)", "20000": "trade ticket class", "1500": "trade ticket class"],
        "Marketing.swift": ["8000": "trade size at the reference level"],
        "Capacity.swift": ["50000": "times the wage level"],
        "EquipmentUnits.swift": ["600000": "kilometre wear"],
        "StaffExtras.swift": ["6000": "fine range, scaled in StaffRoutine.applyExtras", "20000": "fine range, scaled in applyExtras", "10000": "fine range, scaled in applyExtras", "40000": "fine range, scaled in applyExtras"],
        "EventEngine.swift": ["5_000_000": "fallback for imported saves; new games store a scaled value (GameEngine.newGame)"],
        "Providers.swift": ["1400": "number of reviews, not money"],
        "Currency.swift#unicode": ["2212": "the minus sign escape \\u{2212}"],
        "Balance.swift": ["1000": "rounding to three decimals"], "Demand.swift": ["1000": "rounding to three decimals"],
        "Satisfaction.swift": ["9999": "sentinel week number"], "GameEngine.swift": ["2147483647": "random seed range", "1000": "first id of the id counter"],
        "WorldWeek.swift": ["10000": "rounding of a rate to basis points"], "Demo.swift#seed": ["2026": "demo seed"],
        // Models ported from the original after the first scaling pass. Counts, physical quantities, ids and hashes are not money; the
        // amounts below are the original's reference-level design numbers (the differential tests against the original pass with
        // them) and are scaled per country now (bank/insurer capital, insurer premium base, developer land price, default rental unit price, rental loss
        // bookings, caretaker wage).
        "SalmonModel.swift": ["1000": "kilograms per tonne / price per tonne in the market's own unit", "3500": "tonnes of a farm (quantity)"],
        "EnergyModel.swift": ["1000": "barrels per thousand barrels; per-barrel prices follow the global oil price", "10000": "stake size in thousand barrels (quantity)", "5000": "stake size (quantity)", "2000": "stake size (quantity)"],
        "FootballModel.swift": ["4294967296": "hash arithmetic", "2654435761": "hash arithmetic", "100000": "rounding step", "2000": "club value threshold in USD millions (converted by rate)", "1000": "hash buckets (the caretaker wage is scaled by the wage level)"],
        "RentalModel.swift": ["2654435761": "hash arithmetic", "4000": "square metres per commercial building (quantity)"],
        "FinanceModel.swift": ["30000": "policies (count)", "1000": "policies per noise step (count)"],
        "ProjectModel.swift": ["1500": "hour value at the reference level, multiplied by the wage level in use (differential-tested)", "1650": "hour value (same)", "1700": "hour value (same)", "2000": "job size class / hour value (hours, same)", "5000": "job size class (hours)", "1000": "job size class (hours) / default hour value"],
        // Goals: reference-level rewards and milestone targets, scaled by the helper (cash, K, m) with the player's currency.
        "PlayerGoals.swift": ["25000": "reward, scaled by cash()", "6000": "reward, scaled by cash()", "3000": "reward, scaled by cash()", "2500": "reward, scaled by cash()",
                              "15000": "reward, scaled by cash()", "1500": "people (count)", "300000": "milestone target, scaled by K()/m()", "700000": "milestone target, scaled by K()/m()"],
        "MiscActions.swift": ["86400": "seconds in a day"],
        "Banking.swift#annuity": ["100000": "ratio: instalment per 100 000 borrowed, any currency"],
    ]
    /// Files with technical number tables only (calendar arithmetic, hashing, encoding)
    static let skipFiles: Set<String> = ["GameCalendar.swift", "LZString.swift", "JSONValue.swift", "HashedRandom.swift", "DeterministicRandom.swift"]
    static let scalingMarkers = ["scaledPrice(", "medianMonthlyWage", "roundedStep(", "step:", ".tidy(", "wageLevel", "costIndex", "ReferenceEconomy", "Balance"]

    func testNoUnscaledMoneyLiteralsInTheEngine() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else { throw XCTSkip("sources not available") }
        let re = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_.\"$])(\d{1,3}(?:_\d{3})+|\d{4,})(?:\.\d+)?(?![A-Za-z0-9_\"%])"#)
        var violations: [String] = []
        var scanned = 0
        for case let url as URL in walker where url.pathExtension == "swift" {
            scanned += 1
            let name = url.lastPathComponent
            if Self.skipFiles.contains(name) { continue }
            let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            for (n, raw) in lines.enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("//") { continue }
                let code = line.components(separatedBy: " // ").first ?? line
                for m in re.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                    let lit = String(code[Range(m.range(at: 1), in: code)!])
                    if Self.allowed[name]?[lit] != nil || Self.allowed[name + "#unicode"]?[lit] != nil || Self.allowed[name + "#seed"]?[lit] != nil || Self.allowed[name + "#annuity"]?[lit] != nil { continue }
                    if Self.scalingMarkers.contains(where: { code.contains($0) }) { continue }
                    violations.append("\(name):\(n + 1): \(lit)  \(line.prefix(110))")
                }
            }
        }
        if scanned == 0 { throw XCTSkip("sources not available") }
        XCTAssertTrue(violations.isEmpty, "Unscaled money-sized literal(s). Scale them with Currency.scaledPrice / Country.medianMonthlyWage, or list them in MoneyLiteralLintTests.allowed with the reason:\n" + violations.joined(separator: "\n"))
    }
}
