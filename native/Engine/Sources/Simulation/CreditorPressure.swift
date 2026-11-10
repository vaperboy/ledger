import Foundation
import GameCore
import Businesses
import Events

public enum CreditorPressure {
    static let startWealth = 0.34
    static let floor = 50.0
    static let askBelow = 56.0
    static let askEveryWeeks = 26

    static func paysOut(_ s: GameState) -> Bool {
        s.companies.contains { $0.status == .open && Shareholders.policy($0) != "none" }
    }

    static func weekly(_ s: inout GameState, data: GameData) {
        let d = Difficulty.of(s)
        let wealth = Threat.wealth(s)
        guard wealth >= startWealth, !paysOut(s) else { return }
        if s.credit > floor { s.credit = max(floor, s.credit - 0.08 * wealth * d.threatScale) }
        guard d != .sandbox, s.week % 4 == 0, s.credit < askBelow, s.week - (s.rest["credAt"]?.int ?? -askEveryWeeks) >= askEveryWeeks else { return }
        let rich = s.companies.indices.filter { s.companies[$0].status == .open && s.companies[$0].cash > 0 }
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
