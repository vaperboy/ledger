import SwiftUI
import GameCore
import Simulation

/// One thing on the Phone that asks for the player: the banner at the top of the Phone home shows the first one, and the app that
/// owns it carries a red bubble. Built from the engine by `PhoneAlerts`; no game rules here.
struct PhoneAlert: Identifiable, Equatable {
    var id: String
    /// The app that opens when the banner is tapped.
    var app: PhoneApp
    /// Small caps source line ("Bank").
    var source: String
    var title: String
    var detail: String
    /// A company the alert is about (0 = none).
    var companyID: Int = 0
    /// A message to open in the Inbox, for an inbox alert (0 = none).
    var messageID: Int = 0
}

/// A payroll that no manager or accountant approves. This is the app-side shape of the engine's `GameEngine.payrollAlerts()`
/// (companyID, companyName, amount, dateText), so the screens compile before and after that read exists.
struct PayrollAlertInfo: Equatable {
    var companyID: Int
    var companyName: String
    var amount: Double
    var dateText: String
}

/// Where the Phone reads payroll alerts from.
protocol PayrollAlertSource {
    func payrollAlertInfos() -> [PayrollAlertInfo]
}

extension GameEngine: PayrollAlertSource {
    /// WIRING POINT. Returns no alerts until the engine read `GameEngine.payrollAlerts() -> [PayrollAlert]` exists. When it does,
    /// replace the body with
    ///     payrollAlerts().map { PayrollAlertInfo(companyID: $0.companyID, companyName: $0.companyName, amount: $0.amount, dateText: $0.dateText) }
    /// and nothing else in the app changes: the Bank bubble, the Phone tab count and the banner all read through here.
    func payrollAlertInfos() -> [PayrollAlertInfo] { [] }
}

/// Reads the engine into Phone alerts and per-app bubble counts.
@MainActor
enum PhoneAlerts {
    static func payroll(engine: GameEngine) -> [PayrollAlertInfo] { engine.payrollAlertInfos() }

    /// Alerts, most urgent first: payroll (money stops), then open decisions (bad news before the rest).
    static func all(engine: GameEngine, formatter store: GameStore) -> [PhoneAlert] {
        var out: [PhoneAlert] = []
        for p in payroll(engine: engine) {
            var amountText = ""
            if let co = engine.state.company(p.companyID) { amountText = store.money(p.amount, in: co) } else { amountText = store.money(p.amount) }
            let detail: String = amountText + " on " + p.dateText + ". No manager or accountant approves it."
            let title: String = "Payroll needs you · " + p.companyName
            out.append(PhoneAlert(id: "payroll-\(p.companyID)", app: .bank, source: "Bank", title: title, detail: detail, companyID: p.companyID))
        }
        let open: [Message] = engine.state.inbox.filter { $0.status == "open" }
        let bad: [Message] = open.filter { $0.tone == "bad" }
        let rest: [Message] = open.filter { $0.tone != "bad" }
        let ordered: [Message] = bad + rest
        for m in ordered.prefix(3) {
            let title: String = engine.displayText(m.title, companyID: m.companyID)
            let detail: String = m.companyID != 0 ? (engine.state.company(m.companyID)?.name ?? "") : ""
            out.append(PhoneAlert(id: "message-\(m.id)", app: .inbox, source: "Inbox", title: title, detail: detail, companyID: m.companyID, messageID: m.id))
        }
        return out
    }

    /// Red bubble per app: Inbox = open decisions, Bank = payroll alerts.
    static func badges(engine: GameEngine) -> [PhoneApp: Int] {
        var out: [PhoneApp: Int] = [:]
        let decisions: Int = engine.state.inbox.filter { $0.status == "open" }.count
        let payrolls: Int = payroll(engine: engine).count
        if decisions > 0 { out[.inbox] = decisions }
        if payrolls > 0 { out[.bank] = payrolls }
        return out
    }
}
