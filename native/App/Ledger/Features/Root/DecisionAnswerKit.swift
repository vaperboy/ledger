import SwiftUI
import GameCore
import Events
import Simulation

/// One answer to a decision: the app's normal secondary button, the same for every answer, so none looks preferred.
struct DecisionAnswerButton: View {
    var title: String
    var compact: Bool = false
    var identifier: String = ""
    var action: () -> Void

    var body: some View {
        Button { Haptics.tap(); action() } label: {
            Text(title).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
        }
        .buttonStyle(SecondaryButtonStyle(size: compact ? .compact : .regular, fullWidth: true))
        .accessibilityIdentifier(identifier)
    }
}

extension GameStore {
    /// Shows what an answer actually did, with at most one link to the screen it is about.
    func announceDecision(label: String, answer: DecisionAnswer?) {
        guard let a = answer, a.applied else {
            announceAnswer(label: label, effects: [], ok: false)
            return
        }
        Haptics.success()
        outcome(chosen: label, result: a.lines.joined(separator: "\n"), link: a.link)
    }

    /// Opens the one screen an answered decision is about.
    func openDecisionLink(_ l: DecisionLink) {
        if l.app == PhoneApp.bank.rawValue {
            openBank(.personal, tab: .loans)
        } else if !l.app.isEmpty, let app = PhoneApp(rawValue: l.app) {
            openApp(app)
        } else {
            openCompany(l.companyID, section: CompanySection(key: l.section))
        }
    }
}
