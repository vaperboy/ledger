import XCTest
import GameCore
import Finance
import Businesses
import Simulation

/// The executive-search fee: pinned at 15,000 (reference level, scaled by the country's price level) for every kind of search.
final class ManagerSearchFeeTests: XCTestCase {
    private func game(_ country: String = "UK") throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: country, playerName: "T", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 50_000_000) else { throw XCTSkip("no cafe") }
        return (e, id)
    }

    private func companyCash(_ e: GameEngine, _ id: Int) -> Double { e.state.company(id)!.cash }

    func testSearchChargesTheReferenceFeeToTheCompany() throws {
        for country in ["UK", "US", "JP"] {
            var (e, id) = try game(country)
            let fee = ManagerModel.searchFee(currency: e.homeCurrency)
            let before = companyCash(e, id)
            XCTAssertNotNil(e.searchManagers(companyID: id))
            XCTAssertEqual(before - companyCash(e, id), jsRound(fee), accuracy: 0.5, country)
            XCTAssertEqual(fee, e.homeCurrency.scaledPrice(15000), country)
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        }
    }

    func testSearchTeamChargesTheSameFee() throws {
        var (e, id) = try game()
        let before = companyCash(e, id)
        XCTAssertNotNil(e.searchTeam(companyID: id, key: "ceo"))
        XCTAssertEqual(before - companyCash(e, id), jsRound(ManagerModel.searchFee(currency: e.homeCurrency)), accuracy: 0.5)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testSearchExecutiveChargesThePlayerTheSameFee() throws {
        var (e, _) = try game()
        let before = e.state.cash
        XCTAssertNotNil(e.searchExecutive(.md))
        XCTAssertEqual(before - e.state.cash, jsRound(ManagerModel.searchFee(currency: e.homeCurrency)), accuracy: 0.5)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    /// A second copy of the fee must not reappear in the manager files or in the App's labels.
    func testNoSecondCopyOfTheFeeLiteral() throws {
        let native = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var hits: [String] = []
        for dir in ["Engine/Sources/Businesses", "App/Ledger/Features/Companies"] {
            guard let walker = FileManager.default.enumerator(at: native.appendingPathComponent(dir), includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let name = url.lastPathComponent
                let isManager = dir.hasPrefix("Engine") ? name.hasPrefix("Manager") : true
                guard isManager, let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for (n, line) in text.components(separatedBy: "\n").enumerated() where line.contains("scaledPrice(15000)") && !line.contains("static func searchFee") {
                    hits.append("\(name):\(n + 1)")
                }
            }
        }
        // Franchise termination's lawyer (CompanyFranchise.swift) is a different rule that happens to share the number.
        hits.removeAll { $0.hasPrefix("CompanyFranchise.swift") }
        XCTAssertTrue(hits.isEmpty, "Use ManagerModel.searchFee(currency:) instead: \(hits)")
    }

    func testFeeIsFifteenThousandAtTheReferenceLevel() throws {
        let (e, _) = try game()
        XCTAssertEqual(ManagerModel.searchFee(currency: e.homeCurrency), e.homeCurrency.scaledPrice(15000))
    }
}
