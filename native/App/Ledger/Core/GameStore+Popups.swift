import SwiftUI
import GameCore
import Simulation

/// The Home popup queue: one open decision at a time on Home, and each serious alert once.
extension GameStore {
    /// Popups wait while the tutorial runs, a day is being played, or the daily brief or weekly report is still open.
    var homePopupsOn: Bool { !tutorialActive && !isAdvancing && dailySheet == nil && reportSheet == nil }

    /// The Home tab at its root, where decisions pop up.
    var onHomeRoot: Bool { tab == .company && depth(.company) == 0 }

    /// The decision to show now, oldest first; nil while another decision popup is open.
    var homeDecision: Message? {
        guard homePopupsOn, onHomeRoot, decisionPopup == nil, let e = engine else { return nil }
        return e.popupDecisions.first
    }

    /// The next serious alert that has not popped up yet.
    var homeAlert: Message? {
        guard homePopupsOn, let e = engine else { return nil }
        return e.popupAlerts.first { (m: Message) -> Bool in !m.isAlert }
    }

    /// "Later": the decision leaves Home and waits in the inbox.
    func laterDecision(_ m: Message) {
        Haptics.tap()
        act { (e: inout GameEngine) -> Void in e.deferDecision(messageID: m.id) }
    }

    func dismissHomeAlert(_ m: Message) {
        act { (e: inout GameEngine) -> Void in e.markAlertShown(messageID: m.id) }
    }

    /// The inbox lists a decision only while it is not showing somewhere else.
    func showsInInbox(_ m: Message) -> Bool {
        guard m.status == "open", m.isOwnerAddressed, !m.options.isEmpty, let e = engine else { return true }
        switch e.decisionChannel(m) {
        case .inbox: return true
        case .desk: return false
        case .home: return tutorialActive
        }
    }
}

extension View {
    /// Presents the Home decision popup and one-time alerts.
    func homePopups(_ store: GameStore) -> some View {
        let decision: Message? = store.homeDecision
        let alert: Message? = store.homeAlert
        return self
            .hostedPopup(key: "home-decision-\(decision?.id ?? 0)", priority: .decision, active: decision != nil, onClose: {
                if let m = decision { store.laterDecision(m) }
            }) {
                if let m = decision { HomeDecisionPopup(messageID: m.id).environmentObject(store) }
            }
            .hostedPopup(key: "home-alert-\(alert?.id ?? 0)", priority: .alert, active: alert != nil, onClose: {
                if let m = alert { store.dismissHomeAlert(m) }
            }) {
                if let m = alert { HomeAlertPopup(message: m).environmentObject(store) }
            }
    }
}

struct HomeAlertPopup: View {
    @EnvironmentObject var store: GameStore
    var message: Message

    var body: some View {
        let title: String = store.engine?.displayText(message.title, companyID: message.companyID) ?? message.title
        let text: String = store.engine?.displayText(message.body, companyID: message.companyID) ?? message.body
        GamePopup(title: title, showsClose: false, category: .compact, tone: message.tone == "bad" ? .danger : .warning, icon: "exclamationmark.triangle",
                  onClose: { store.dismissHomeAlert(message) }) {
            PopupBody {
                Text(text.tidyMoney).popupText(.body).fixedSize(horizontal: false, vertical: true)
                if message.companyID != 0 {
                    PopupOptionButton(title: "Open the company", identifier: "home-alert-open") {
                        store.dismissHomeAlert(message)
                        store.openCompany(message.companyID, section: nil)
                    }
                }
                PopupOptionButton(title: "OK", highlighted: true, identifier: "home-alert-ok") { store.dismissHomeAlert(message) }
            }
        }
    }
}
