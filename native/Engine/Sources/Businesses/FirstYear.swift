import Foundation
import GameCore
import Countries
import Finance

/// First-year economics. Kinder numbers while the player learns; the behaviours themselves
/// (demand, supplier cut-off, competition authority, bankruptcy) are unchanged and only ask this table whether they apply yet.
public struct FirstYear: Sendable, Equatable {
    /// Demand multiplier by quarter of the first game year (weeks 0 to 51), applied to all companies.
    public var demandMult: [Double] = [1.25, 1.15, 1.05, 1.0]
    /// False: suppliers do not cut a buyer off until `supplierCutoffWeek`.
    public var supplierCutoffEnabled = false
    public var supplierCutoffWeek = 27
    /// False: the competition authority stays away until the player owns `competitionAuthorityCompanies` companies.
    public var competitionAuthorityEnabled = false
    public var competitionAuthorityCompanies = 3
    /// False: no company goes bankrupt before `bankruptcyWeek`; after `frozenAfterWeeks` weeks below zero the bank freezes the account instead.
    public var bankruptcyEnabled = false
    public var bankruptcyWeek = 27
    public var frozenAfterWeeks = 4
    /// New-player start: until this week no account goes into overdraft; a bill the cash cannot cover waits for the next day.
    public var noOverdraftWeeks = 12
    /// New-player start: weeks of fixed costs and payroll added to the start-up cost to make the starting cash.
    public var startRunwayWeeks = 8

    public init() {}

    public init(json j: JSONValue) {
        if j.isNull { return }
        if !j["demandMult"].array.isEmpty { demandMult = j["demandMult"].array.map { $0.double } }
        if !j["supplierCutoffEnabled"].isNull { supplierCutoffEnabled = j["supplierCutoffEnabled"].bool }
        if !j["supplierCutoffWeek"].isNull { supplierCutoffWeek = j["supplierCutoffWeek"].int }
        if !j["competitionAuthorityEnabled"].isNull { competitionAuthorityEnabled = j["competitionAuthorityEnabled"].bool }
        if !j["competitionAuthorityCompanies"].isNull { competitionAuthorityCompanies = j["competitionAuthorityCompanies"].int }
        if !j["bankruptcyEnabled"].isNull { bankruptcyEnabled = j["bankruptcyEnabled"].bool }
        if !j["bankruptcyWeek"].isNull { bankruptcyWeek = j["bankruptcyWeek"].int }
        if !j["frozenAfterWeeks"].isNull { frozenAfterWeeks = j["frozenAfterWeeks"].int }
        if !j["noOverdraftWeeks"].isNull { noOverdraftWeeks = j["noOverdraftWeeks"].int }
        if !j["startRunwayWeeks"].isNull { startRunwayWeeks = j["startRunwayWeeks"].int }
    }

    /// The bundled table (for code that has no `GameData` at hand).
    public static let bundled: FirstYear = (try? Balance.bundled().firstYear) ?? FirstYear()

    /// Multiplier on demand in a game week: by quarter of the first year, 1 afterwards.
    public func demandMultiplier(week: Int) -> Double {
        guard week >= 0, week < 52, !demandMult.isEmpty else { return 1 }
        return demandMult[min(demandMult.count - 1, week / 13)]
    }
    /// The no-overdraft protection of a new-player game (ladder games only) is on.
    public func noOverdraftActive(_ s: GameState) -> Bool { Gates.ladderOn(s) && s.week < noOverdraftWeeks }
    public func supplierCutoffActive(week: Int) -> Bool { supplierCutoffEnabled || week >= supplierCutoffWeek }
    public func bankruptcyActive(week: Int) -> Bool { bankruptcyEnabled || week >= bankruptcyWeek }
    public func competitionAuthorityActive(_ s: GameState) -> Bool {
        competitionAuthorityEnabled || Gates.companiesOwned(s) >= competitionAuthorityCompanies
    }

    public static let frozenAction = "bankfrz"
    public static let frozenText = "The bank has frozen the account until the balance is back above zero."

    /// Weekly, before the bankruptcy checks: a company below zero for `frozenAfterWeeks` weeks before the cut-off week gets one Inbox item
    /// (once per spell below zero). The engine skips bankruptcy while `bankruptcyActive` is false.
    public static func freezeSweep(_ s: inout GameState, balance: Balance) {
        let f = balance.firstYear
        guard !f.bankruptcyActive(week: s.week) else { return }
        for i in s.companies.indices where s.companies[i].status == .open && s.companies[i].type != "hold" {
            let c = s.companies[i]
            if c.cash >= 0 { if c.raw["frz"] != nil { s.companies[i].raw.removeValue(forKey: "frz") }; continue }
            guard c.weeksNegative >= f.frozenAfterWeeks, c.raw["frz"] == nil else { continue }
            s.companies[i].set("frz", 1)
            s.addMessage(kind: "ask", from: "Your bank", title: "Account frozen at \(c.name)", body: frozenText, companyID: c.id, tone: "bad", status: "open",
                         options: [.option("Understood", "")], action: frozenAction)
        }
    }
}
