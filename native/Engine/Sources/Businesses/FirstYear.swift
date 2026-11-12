import Foundation
import GameCore
import Countries
import Finance

public struct FirstYear: Sendable, Equatable {
    public var demandMult: [Double] = [1.25, 1.15, 1.05, 1.0]
    public var supplierCutoffEnabled = false
    public var supplierCutoffWeek = 27
    public var competitionAuthorityEnabled = false
    public var competitionAuthorityWeek = 52
    public var bankruptcyEnabled = false
    public var bankruptcyWeek = 27
    public var frozenAfterWeeks = 4
    public var noOverdraftWeeks = 12
    public var startRunwayWeeks = 12
    /// Own savings every new player brings, in the reference economy; a government grant covers the rest of the runway.
    public var startSavings = 100_000.0
    public var untendedDemand = 1.0
    public var untendedServe = 1.0

    public init() {}

    public init(json j: JSONValue) {
        if j.isNull { return }
        if !j["demandMult"].array.isEmpty { demandMult = j["demandMult"].array.map { $0.double } }
        if !j["supplierCutoffEnabled"].isNull { supplierCutoffEnabled = j["supplierCutoffEnabled"].bool }
        if !j["supplierCutoffWeek"].isNull { supplierCutoffWeek = j["supplierCutoffWeek"].int }
        if !j["competitionAuthorityEnabled"].isNull { competitionAuthorityEnabled = j["competitionAuthorityEnabled"].bool }
        if !j["competitionAuthorityWeek"].isNull { competitionAuthorityWeek = j["competitionAuthorityWeek"].int }
        if !j["bankruptcyEnabled"].isNull { bankruptcyEnabled = j["bankruptcyEnabled"].bool }
        if !j["bankruptcyWeek"].isNull { bankruptcyWeek = j["bankruptcyWeek"].int }
        if !j["frozenAfterWeeks"].isNull { frozenAfterWeeks = j["frozenAfterWeeks"].int }
        if !j["noOverdraftWeeks"].isNull { noOverdraftWeeks = j["noOverdraftWeeks"].int }
        if !j["startRunwayWeeks"].isNull { startRunwayWeeks = j["startRunwayWeeks"].int }
        if !j["startSavings"].isNull { startSavings = j["startSavings"].double }
        if !j["untendedDemand"].isNull { untendedDemand = j["untendedDemand"].double }
        if !j["untendedServe"].isNull { untendedServe = j["untendedServe"].double }
    }

    public static let bundled: FirstYear = (try? Balance.bundled().firstYear) ?? FirstYear()

    public func demandMultiplier(week: Int) -> Double {
        guard week >= 0, week < 52, !demandMult.isEmpty else { return 1 }
        return demandMult[min(demandMult.count - 1, week / 13)]
    }
    public func untended(_ s: GameState) -> Bool { (untendedDemand < 1 || untendedServe < 1) && Gates.ladderOn(s) && !Gates.goalDone(s, 2) && !Gates.goalDone(s, 5) }
    public func serveShare(_ s: GameState) -> Double { untended(s) ? min(1, max(0, untendedServe)) : 1 }
    public func noOverdraftActive(_ s: GameState) -> Bool { Gates.ladderOn(s) && s.week < noOverdraftWeeks }
    public func supplierCutoffActive(week: Int) -> Bool { supplierCutoffEnabled || week >= supplierCutoffWeek }
    public func bankruptcyActive(week: Int) -> Bool { bankruptcyEnabled || week >= bankruptcyWeek }
    public func competitionAuthorityActive(_ s: GameState) -> Bool {
        competitionAuthorityEnabled || s.week >= competitionAuthorityWeek
    }

    public static let frozenAction = "bankfrz"
    public static let frozenText = "The bank has frozen the account until the balance is back above zero."

    public static func freezeSweep(_ s: inout GameState, balance: Balance) {
        let f = balance.firstYear
        noticeSweep(&s, balance: balance)
        guard !f.bankruptcyActive(week: s.week) else { return }
        for i in s.companies.indices where s.companies[i].status == .open {
            let c = s.companies[i]
            if c.cash >= 0 { if c.raw["frz"] != nil { s.companies[i].raw.removeValue(forKey: "frz") }; continue }
            guard c.weeksNegative >= f.frozenAfterWeeks, c.raw["frz"] == nil else { continue }
            s.companies[i].set("frz", 1)
            s.addMessage(kind: "ask", from: "Your bank", title: "Account frozen at \(c.name)", body: frozenText, companyID: c.id, tone: "bad", status: "open",
                         options: [.option("Understood", "")], action: frozenAction)
        }
    }

    public static func companyAge(_ co: Company, week: Int) -> Int { week - (co.openedWeek ?? co.foundedWeek) }

    public static func noticeSweep(_ s: inout GameState, balance: Balance) {
        let f = balance.firstYear
        var done = s.rest["fyNotes"] ?? .object([:])
        func due(_ key: String, week: Int) -> Bool {
            guard s.week >= week, s.week < week + 2, done[key].isNull else { return false }
            done[key] = .number(1)
            return true
        }
        if Gates.ladderOn(s), due("overdraft", week: f.noOverdraftWeeks) {
            s.addMessage(from: "Your bank", title: "Overdraft protection has ended",
                         body: "Until now the bank held back any bill your cash could not cover. From now on an account can go into overdraft, and that costs interest. Keep some cash in reserve.",
                         tone: "n")
        }
        if !(f.bankruptcyEnabled && f.supplierCutoffEnabled), due("week27", week: min(f.bankruptcyWeek, f.supplierCutoffWeek)) {
            s.addMessage(from: "Your accountant", title: "The first-year safety nets are off",
                         body: "A company in the red can now go bankrupt instead of being frozen, and suppliers can stop selling to a buyer who keeps paying late. Pay bills on time and watch your cash.",
                         tone: "bad")
        }
        if !f.competitionAuthorityEnabled, done["authority"].isNull, s.week >= f.competitionAuthorityWeek {
            done["authority"] = .number(1)
            s.addMessage(from: "Your accountant", title: "The competition authority is watching you",
                         body: "After a year in business the competition authority can look into a company that holds a big share of its market.",
                         tone: "n")
        }
        s.rest["fyNotes"] = done
        guard let first = f.demandMult.first, first > 1 else { return }
        for i in s.companies.indices where s.companies[i].status == .open {
            let age = companyAge(s.companies[i], week: s.week)
            guard age >= 52, age < 54, s.companies[i].raw["fyEnd"] == nil else { continue }
            s.companies[i].set("fyEnd", 1)
            let c = s.companies[i]
            s.addMessage(from: "Your accountant", title: "\(c.name) has finished its first year",
                         body: "New businesses draw extra curiosity in their first year. That boost has now faded, so expect fewer customers unless you keep winning them with price, quality and marketing.",
                         companyID: c.id, tone: "n")
        }
    }
}
