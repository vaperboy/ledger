import XCTest
import GameCore
import Countries
import Businesses
import Simulation

/// No country is built into the game. Every country comes from its own data file entry, and nothing in the code or in the
/// shared data may be taken from one particular country (the HTML game was written around Norway).
final class CountryNeutralityTests: XCTestCase {
    private var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
    }

    private func files(withExtension ext: String) throws -> [URL] {
        let e = try XCTUnwrap(FileManager.default.enumerator(at: sourcesDirectory, includingPropertiesForKeys: nil))
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == ext }
    }

    func testNoCountryCodeIsWrittenIntoTheCode() throws {
        let codes = try CountryBook.bundled().countries.map { $0.code }
        let quoted = try NSRegularExpression(pattern: "\"(\(codes.joined(separator: "|")))\"")
        var found: [String] = []
        for f in try files(withExtension: "swift") {
            if f.lastPathComponent == "Demo.swift" { continue }   // a showcase game for screenshots, not game logic
            for (n, line) in try String(contentsOf: f, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let text = String(line)
                if text.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                if text.contains("d[\"DK\"]") || text.contains("j[\"CH\"]") { continue }   // data keys that only look like country codes (demand design factor, marketing channels)
                if quoted.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { found.append("\(f.lastPathComponent):\(n + 1): \(text.trimmingCharacters(in: .whitespaces))") }
            }
        }
        XCTAssertTrue(found.isEmpty, "country codes in code (move them to data):\n" + found.joined(separator: "\n"))
    }

    func testSharedDataHasNoNorwegianIdentifiersOrBrands() throws {
        let banned = ["\"mva\"", "\"skjenk\"", "\"salg\"", "\"tobak\"", "\"mattil\"", "\"haccp\"", "\"ysk\"", "\"tgodk\"", "\"elvirk\"", "\"vvs\"", "\"bygg\"", "\"megler\"", "\"forsik\"",
                      "\"ENK\":", "\"AS\":", "\"ENKs\":", "\"ASs\":", "\"needAS\"", "\"NRDK\"", "\"FJSF\"", "\"HVBK\"", "\"NRC\"", "Nordtrans", "Brenner", "Sandmo", "Stalheim", "Maxell & Str"]
        var found: [String] = []
        for f in try files(withExtension: "json") {
            let text = try String(contentsOf: f, encoding: .utf8)
            for b in banned where text.contains(b) { found.append("\(f.lastPathComponent) contains \(b)") }
        }
        XCTAssertTrue(found.isEmpty, found.joined(separator: "\n"))
    }

    func testOnlyNorwaysOwnEntryMentionsNorway() throws {
        let book = try CountryBook.bundled()
        for c in book.countries where c.code != "NO" {
            let text = String(data: try JSONEncoder().encode(c.pack), encoding: .utf8) ?? ""
            XCTAssertFalse(text.contains("Norw") || text.contains("NOK"), "\(c.name)'s data mentions Norway")
        }
        for f in try files(withExtension: "json") where f.lastPathComponent != "countries.json" {
            let text = try String(contentsOf: f, encoding: .utf8)
            XCTAssertFalse(text.contains("Norw") || text.contains("NOK"), "\(f.lastPathComponent) mentions Norway")
        }
    }

    private func json(_ relative: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: sourcesDirectory.appendingPathComponent(relative)))
    }

    func testEveryCountryHasItsOwnCompleteData() throws {
        let book = try CountryBook.bundled()
        let weather = try json("Businesses/Resources/weather.json")
        let balance = try json("Businesses/Resources/balance.json")
        let tickers = ["ENRG", "FOOD", "BANK", "INDU", "TELE", "MATL", "RETL", "TECH", "TRAN", "PROP"]
        for c in book.countries {
            XCTAssertFalse(weather["CL"][c.code].isNull, "\(c.code): climate")
            XCTAssertEqual(weather["STORM"][c.code].array.count, 12, "\(c.code): storm chances")
            XCTAssertEqual(balance["tourism"]["seasonByCountry"][c.code].array.count, 12, "\(c.code): tourism seasons")
            XCTAssertFalse(c.pack["names"]["coinEnd"].array.isEmpty, "\(c.code): brand-name endings")
            XCTAssertTrue(c.pack["citiesFinal"].bool, "\(c.code): cities written out")
            XCTAssertFalse(c.cities.isEmpty, "\(c.code): cities")
            for t in tickers { XCTAssertFalse(c.pack["flavour"]["stocks"][t].string.isEmpty, "\(c.code): name of \(t)") }
            XCTAssertFalse(c.pack["authorities"]["tax"].string.isEmpty, "\(c.code): tax authority")
            XCTAssertFalse(c.companyForms["soleTrader"]?.isEmpty ?? true, "\(c.code): sole trader form")
            XCTAssertFalse(c.companyForms["limited"]?.isEmpty ?? true, "\(c.code): limited form")
        }
        // Companies and stocks are named from the country's own words.
        let uk = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 4)
        let de = try GameEngine.newGame(countryCode: "DE", playerName: "T", seed: 4)
        XCTAssertNotEqual(uk.quotes(.stock).map { $0.name }, de.quotes(.stock).map { $0.name })
    }

    func testNoCurrencyStandsStill() throws {
        // In the HTML game the Norwegian krone never moved. Here every currency except the player's own drifts.
        var rates = ExchangeRates()
        var random = DeterministicRandom(seed: 9)
        let book = try CountryBook.bundled()
        for _ in 0..<24 { rates.monthlyDrift(book: book, homeCode: "UK", random: &random) }
        for c in book.countries where c.code != "UK" { XCTAssertNotEqual(rates.drift[c.code], nil, "\(c.code) did not drift") }
        XCTAssertNil(rates.drift["UK"], "the player's home currency is the yardstick")
    }

    func testCompanyNamesUseTheCountrysOwnEndings() throws {
        for code in ["UK", "DE", "JP", "BR"] {
            var e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: 11)
            let endings = try XCTUnwrap(e.homeCountry.pack["names"]["coinEnd"].array.map { $0.string }) 
            e.update { s, _, _ in Ledger_noop(&s) }
            XCTAssertFalse(endings.isEmpty)
            XCTAssertFalse(endings.contains("vik") && code != "NO" && code != "SE", "\(code) must not use Nordic endings")
        }
    }
}

private func Ledger_noop(_ s: inout GameState) {}
