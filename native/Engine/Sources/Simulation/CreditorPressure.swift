import Foundation
import GameCore
import Businesses
import Events

/// Lenders grow wary of a very large group that keeps all its cash: above twice the group threshold the credit score drifts down, slowly
/// and never below a floor, until some company pays out. Every few weeks, while confidence is low, the dividend policy of the most
/// cash-rich limited company is raised one step, so the quarter's existing dividend decision (`Shareholders`) puts money back in owners'
/// hands. Pressure, not punishment: the drift is small, floored, and stops as soon as a dividend policy is in force.
public enum CreditorPressure {
    /// Net-worth weight (`Threat.wealth`) from which the drift starts: twice the group threshold.
    static let startWealth = 0.34
    static let floor = 50.0
    /// Credit score below which the lenders ask for cash back.
    static let askBelow = 56.0
    static let askEveryWeeks = 26

    /// True when a limited company pays a dividend policy, so the lenders see cash going to the owners.
    static func paysOut(_ s: GameState) -> Bool {
        s.companies.contains { $0.status == .open && $0.type != "hold" && Shareholders.policy($0) != "none" }
    }

    static func weekly(_ s: inout GameState, data: GameData) {
        let d = Difficulty.of(s)
        let wealth = Threat.wealth(s)
        guard wealth >= startWealth, !paysOut(s) else { return }
        if s.credit > floor { s.credit = max(floor, s.credit - 0.08 * wealth * d.threatScale) }
        guard d != .sandbox, s.week % 4 == 0, s.credit < askBelow, s.week - (s.rest["credAt"]?.int ?? -askEveryWeeks) >= askEveryWeeks else { return }
        let rich = s.companies.indices.filter { s.companies[$0].status == .open && s.companies[$0].type != "hold" && s.companies[$0].cash > 0 }
            .max { s.companies[$0].cash < s.companies[$1].cash }
        guard let i = rich else { return }
        let co = s.companies[i]
        Shareholders.setPolicy(&s, companyID: co.id, policy: "low")
        s.rest["credAt"] = .number(Double(s.week))
        s.addMessage(from: "Your lenders", title: "Lenders want cash back from \(co.name)",
                     body: "Your group has grown large and your banks are uneasy that so much stays inside the companies. \(co.name) now pays out 25% of its profit as dividends: you will be asked to approve each quarter's dividend. Change the policy under Shareholders if you prefer.",
                     companyID: co.id, tone: "n")
    }
}
