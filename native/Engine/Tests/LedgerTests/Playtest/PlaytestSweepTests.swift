import XCTest
import Foundation
import GameCore
import Countries
import Businesses
import Simulation

/// The sweep: bot policies x countries x trades x seeds x scenarios, 3 in-game years each, invariants checked daily/weekly.
/// Enabled only with LEDGER_PLAYTEST=1. Narrow with LEDGER_PT_COUNTRIES, LEDGER_PT_TRADES, LEDGER_PT_SEEDS, LEDGER_PT_POLICIES, LEDGER_PT_SCENARIOS, LEDGER_PT_YEARS.
final class PlaytestSweepTests: XCTestCase {
    static var allTrades: [String] {
        guard let e = try? GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1) else { return [] }
        return e.data.catalog.all.filter { SpecialFamilies.isStartable($0) }.map { $0.id }.sorted()
    }

    func runJobs(_ jobs: [Job]) {
        let (si, sn) = PT.shard
        let skip = Progress.skip
        var n = 0
        for (i, job) in jobs.enumerated() where i % sn == si {
            if skip.contains(job.name) { continue }
            Progress.start(job.name)
            do {
                do { _ = try PlayBot(job).run() } catch { Findings.shared.add(1, "newgame-throws:\(job.country)", "newGame threw \(error)", repro: job.repro, file: "GameEngine.newGame") }
            }
            Progress.done(job.name)
            n += 1
            if n % 5 == 0 { Findings.shared.flush() }
        }
        Findings.shared.flush()
    }

    func jobs(_ scenarios: [Scenario], trades: [String], countries: [String], policies: [Policy], seeds: [Int]) -> [Job] {
        var out: [Job] = []
        for sc in scenarios { for t in trades { for c in countries { for p in policies { for s in seeds {
            out.append(Job(country: c, trade: t, seed: s, policy: p, scenario: sc))
        } } } } }
        return out
    }

    /// Every startable trade as the first company, per country and policy.
    func testSweepTrades() throws {
        try XCTSkipUnless(PT.enabled, "set LEDGER_PLAYTEST=1")
        let trades = PT.list("LEDGER_PT_TRADES", Self.allTrades)
        let countries = PT.list("LEDGER_PT_COUNTRIES", ["UK", "US", "NO", "SE", "DE", "JP"])
        let policies = PT.list("LEDGER_PT_POLICIES", ["competent"]).compactMap { Policy(rawValue: $0) }
        let seeds = PT.ints("LEDGER_PT_SEEDS", [1])
        XCTAssertFalse(trades.isEmpty)
        runJobs(jobs([.single], trades: trades, countries: countries, policies: policies, seeds: seeds))
    }

    /// Multi-company, chain/franchise, holding, startup and football scenarios.
    func testSweepScenarios() throws {
        try XCTSkipUnless(PT.enabled, "set LEDGER_PLAYTEST=1")
        let scenarios = PT.list("LEDGER_PT_SCENARIOS", ["multi", "chain", "holding", "startup", "football"]).compactMap { Scenario(rawValue: $0) }
        let trades = PT.list("LEDGER_PT_TRADES", ["cafe", "bakery", "hardware", "cleaning", "tutor", "barber"])
        let countries = PT.list("LEDGER_PT_COUNTRIES", ["UK", "US", "NO", "DE", "JP"])
        let policies = PT.list("LEDGER_PT_POLICIES", ["competent", "reckless"]).compactMap { Policy(rawValue: $0) }
        let seeds = PT.ints("LEDGER_PT_SEEDS", [1, 2])
        var js: [Job] = []
        for sc in scenarios {
            // football and startup do not depend on the first trade: one trade is enough
            let ts = (sc == .football || sc == .startup) ? [trades[0]] : trades
            js += jobs([sc], trades: ts, countries: countries, policies: policies, seeds: seeds)
        }
        runJobs(js)
    }

    /// Passive and reckless policies over every trade in two countries.
    func testSweepPolicies() throws {
        try XCTSkipUnless(PT.enabled, "set LEDGER_PLAYTEST=1")
        let trades = PT.list("LEDGER_PT_TRADES", Self.allTrades)
        let countries = PT.list("LEDGER_PT_COUNTRIES", ["UK", "JP"])
        runJobs(jobs([.single], trades: trades, countries: countries, policies: [.reckless, .passive], seeds: PT.ints("LEDGER_PT_SEEDS", [2])))
    }

    /// Same seed twice must give an identical state hash.
    func testDeterminism() throws {
        try XCTSkipUnless(PT.enabled, "set LEDGER_PLAYTEST=1")
        let trades = PT.list("LEDGER_PT_TRADES", ["cafe", "bakery", "hardware", "cleaning", "taxi", "barber"])
        let countries = PT.list("LEDGER_PT_COUNTRIES", ["UK", "NO", "JP"])
        var js: [Job] = []
        for t in trades { for c in countries { js.append(Job(country: c, trade: t, seed: 7, policy: .competent, scenario: .single, years: 1)) } }
        let (si, sn) = PT.shard
        for (i, job) in js.enumerated() where i % sn == si {
            Progress.start("det/" + job.name)
            guard let a = try? PlayBot(job).run(), let b = try? PlayBot(job).run() else { continue }
            if a.hash != b.hash { Findings.shared.add(1, "nondeterministic:\(job.trade)", "Same seed twice gives different state hash (\(a.hash) vs \(b.hash))", repro: job.repro, file: "something reads Date()/random/unordered Dictionary iteration") }
            Progress.done("det/" + job.name)
        }
        Findings.shared.flush(tag: PT.tag + "-det")
    }

    /// Re-run one job: LEDGER_PT_COUNTRY/TRADE/SEED/POLICY/SCENARIO. Prints findings.
    func testRepro() throws {
        try XCTSkipUnless(PT.enabled && PT.env["LEDGER_PT_TRADE"] != nil, "set LEDGER_PLAYTEST=1 and LEDGER_PT_TRADE")
        let job = Job(country: PT.env["LEDGER_PT_COUNTRY"] ?? "UK", trade: PT.env["LEDGER_PT_TRADE"]!, seed: Int(PT.env["LEDGER_PT_SEED"] ?? "1") ?? 1,
                      policy: Policy(rawValue: PT.env["LEDGER_PT_POLICY"] ?? "competent") ?? .competent, scenario: Scenario(rawValue: PT.env["LEDGER_PT_SCENARIO"] ?? "single") ?? .single)
        let r = try PlayBot(job).run()
        for f in Findings.shared.all { print("FINDING sev\(f.sev) x\(f.count) \(f.title) :: \(f.repro)") }
        print("RESULT", r)
    }
}
