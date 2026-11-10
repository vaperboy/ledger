import SwiftUI
import GameCore
import Countries
import Employees
import Businesses

enum HireFeedback: Equatable {
    case hired(String)
    case declined(String)
    case unavailable(String)
    case countered(Double, String)

    var text: String { switch self { case .hired(let t), .declined(let t), .unavailable(let t), .countered(_, let t): return t } }
    var isHired: Bool { if case .hired = self { return true } else { return false } }
    var counterAmount: Double? { if case .countered(let a, _) = self { return a } else { return nil } }
    var tint: Color { switch self { case .hired: return Theme.gain; case .declined, .countered: return Theme.caution; case .unavailable: return Theme.loss } }

    static func counter(_ c: Negotiation.Counter, name: String) -> HireFeedback {
        .countered(c.amount, c.isFinal ? "\(name) says this is as low as they will go." : "\(name) would take the job for this much.")
    }
}

struct RoleScopeBadge: View {
    var role: String
    var scope: String
    var body: some View { Chip(text: "\(role) · \(scope)", tint: scope == "store" || scope == "company" ? Theme.gold : Theme.goldLight) }
}

struct ManagementRow: View {
    var name: String?
    var role: String
    var scope: String
    var line: String
    var lineTint: Color = Theme.ivoryFaint
    var wage: String?
    var face: String? = nil
    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name ?? "Vacant").textStyle(.headline, tint: name == nil ? Theme.inkSoft : Theme.ink).lineLimit(1).minimumScaleFactor(0.8)
                RoleScopeBadge(role: role, scope: scope)
                if !line.isEmpty { Text(line).textStyle(.caption, tint: lineTint).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: Theme.Space.s)
            if let wage { Text(wage).textStyle(.headline, numeric: true) }
            LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint).accessibilityHidden(true)
        }
        .padding(.vertical, Theme.Space.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this post")
    }
}

struct PeopleSheet<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) { content() }
            .centerSheetTitle(title)
    }
}
