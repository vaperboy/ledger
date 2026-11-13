import SwiftUI
import GameCore
import Events
import Simulation

/// One answer to a decision: the app's normal secondary button, the same for every answer, so none looks preferred.
struct DecisionAnswerButton: View {
    var title: String
    var compact: Bool = false
    var identifier: String = ""
    /// Fills the row's height, so a pair stays the same size when one label wraps.
    var stretch: Bool = false
    var action: () -> Void

    var body: some View {
        Button { Haptics.tap(); action() } label: {
            Text(title).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
                .frame(maxHeight: stretch ? CGFloat.infinity : nil)
        }
        .buttonStyle(SecondaryButtonStyle(size: compact ? .compact : .regular, fullWidth: true))
        .accessibilityIdentifier(identifier)
    }
}

/// Every decision's answers, laid out the same way: No on the left and Yes on the right at equal size, any other answer
/// in rows below, equal paths stacked when there is no yes/no pair, and "Later" small and grey under them all.
struct DecisionChoices: View {
    @Environment(\.outsidePalette) private var P
    /// Answer labels in their original order; a tap sends the original index.
    var labels: [String]
    var compact: Bool = false
    var identifier: (Int) -> String = { (_: Int) -> String in "" }
    var later: (() -> Void)? = nil
    var laterIdentifier: String = "decision-later"
    var pick: (Int) -> Void

    private var gap: CGFloat { compact ? Theme.Space.s : Theme.Space.m }

    var body: some View {
        let l: DecisionLayout = DecisionOrder.layout(labels)
        VStack(spacing: gap) {
            if let no = l.no, let yes = l.yes {
                row([no, yes])
                ForEach(Self.rows(l.others), id: \.self) { (r: [Int]) in row(r) }
            } else {
                ForEach(l.others, id: \.self) { (i: Int) in button(i, stretch: false) }
            }
            if let later {
                Button(action: later) { Text("Later") }
                    .buttonStyle(TertiaryButtonStyle(size: .compact, tint: P.inkSoft))
                    .padding(.top, Theme.Space.l)
                    .accessibilityIdentifier(laterIdentifier)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ r: [Int]) -> some View {
        HStack(spacing: gap) {
            ForEach(r, id: \.self) { (i: Int) in button(i, stretch: true) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func button(_ i: Int, stretch: Bool) -> some View {
        DecisionAnswerButton(title: labels[i], compact: compact, identifier: identifier(i), stretch: stretch) { pick(i) }
    }

    /// Rows of two; an odd one out takes the full width.
    static func rows(_ ids: [Int]) -> [[Int]] {
        stride(from: 0, to: ids.count, by: 2).map { (k: Int) -> [Int] in Array(ids[k..<min(k + 2, ids.count)]) }
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
