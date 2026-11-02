import SwiftUI
import GameCore
import Countries
import Employees
import Businesses

// Shared pieces for people screens: one authority picker, one role + scope badge, one sheet frame. (The hiring flow and its candidate rows are in
// Features/Companies/HireFlowKit.swift.)

/// The engine's answer to a job offer in words, so every hiring screen reports it the same way.
enum HireFeedback: Equatable {
    case hired(String)
    /// An insult or a flat no this time; a better offer may work.
    case declined(String)
    /// Gone or not possible (took another job, lost patience, no premises, no cash).
    case unavailable(String)
    /// They name their own figure (a monthly wage in accounting units): accept it, counter, or walk away. The engine may make it a fair one or not;
    /// the going rate shown on the row is what to judge it against.
    case countered(Double, String)

    var text: String { switch self { case .hired(let t), .declined(let t), .unavailable(let t), .countered(_, let t): return t } }
    var isHired: Bool { if case .hired = self { return true } else { return false } }
    var counterAmount: Double? { if case .countered(let a, _) = self { return a } else { return nil } }
    var tint: Color { switch self { case .hired: return Theme.gain; case .declined, .countered: return Theme.caution; case .unavailable: return Theme.loss } }

    /// The words for a counter, the same on every screen.
    static func counter(_ c: Negotiation.Counter, name: String) -> HireFeedback {
        .countered(c.amount, c.isFinal ? "\(name) says this is as low as they will go." : "\(name) would take the job for this much.")
    }
}

/// The words for authority levels, the same on every screen: 0 asks you, 1 within limits, 2 full control.
enum AuthorityWords {
    static let labels = ["Asks you", "Within limits", "Full control"]
    static func label(_ level: Int) -> String { labels[min(2, max(0, level))] }
    static func consequence(_ level: Int) -> String {
        ["Every decision and spend comes to you as a message. Safe, but you will be asked a lot.",
         "Handles things up to the limits you set; anything bigger comes to you.",
         "Decides everything on their own. Fewer messages; you see results, not choices."][min(2, max(0, level))]
    }
}

/// Picks an authority level, with what it means under the picker. The same `AuthorityPicker` as the executive posts, without a spend limit.
struct AuthorityLevelPicker: View {
    var level: Int
    var set: (Int) -> Void
    var body: some View { AuthorityPicker(level: level, style: .full, setLevel: set) }
}

/// Role plus scope (store, company, chain, region, group) as one badge, as on every management list.
struct RoleScopeBadge: View {
    var role: String
    var scope: String
    var body: some View { Chip(text: "\(role) · \(scope)", tint: scope == "store" || scope == "company" ? Theme.gold : Theme.goldLight) }
}

/// One row of a management list: the person (or "Vacant"), their role + scope badge, one line on what matters now, and the pay.
/// The whole row is the button that opens the post's sheet.
struct ManagementRow: View {
    var name: String?
    var role: String
    var scope: String
    var line: String
    var lineTint: Color = Theme.ivoryFaint
    var wage: String?
    /// The portrait key of the person in the post (nil for a vacant post).
    var face: String? = nil
    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name ?? "Vacant").font(.system(size: 13.5, weight: .medium)).foregroundStyle(name == nil ? Theme.ivoryMuted : Theme.ivory).lineLimit(1)
                RoleScopeBadge(role: role, scope: scope)
                if !line.isEmpty { Text(line).font(.system(size: 11)).foregroundStyle(lineTint).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            if let wage { Text(wage).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory) }
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The frame of a people sheet: its own navigation bar with Done, a scroll view and the page background.
struct PeopleSheet<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) { content() }
                    .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .ledgerBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.foregroundStyle(Theme.gold) } }
        }
    }
}
