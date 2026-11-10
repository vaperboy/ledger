import SwiftUI
import GameCore
import Businesses
import Simulation

enum StructureWords {
    static func percent(_ p: Double) -> String { "\(Int(saturating: p.rounded()))%" }

    static func ownership(_ n: StructureNode) -> String {
        "You " + percent(n.ownerYouPercent)
    }

    static func actionTitle(_ a: StructureNode.Action) -> String {
        switch a {
        case .decide(let n): return "Decide (\(n))"
        case .appointManager: return "Appoint manager"
        case .fix(let why): return "Fix: " + why
        case .open: return "Open"
        }
    }

    static func tone(_ h: StructureNode.Health) -> AcctPill.Tone {
        switch h {
        case .thriving, .healthy: return .good
        case .tight: return .warn
        case .struggling: return .bad
        case .setup: return .neutral
        }
    }

    static func glyph(_ k: StructureNode.Kind) -> String {
        switch k {
        case .you: return Glyph.person
        case .chain, .headOffice, .branch: return Glyph.group
        case .company: return Glyph.home
        }
    }

    static func change(_ c: Double) -> String {
        let size: String = "\(Int(saturating: (abs(c) * 100).rounded()))%"
        return (c >= 0 ? "\u{25B2} " : "\u{25BC} ") + size
    }
}

struct StructureRung: Identifiable {
    var id: String
    var name: String
    var title: String
    var authority: String
    var role: String?
    var face: String?
}

struct StructureAvatar: View {
    var name: String
    var role: String?
    var face: String?
    var size: CGFloat = 28

    var body: some View {
        ThumbnailView(kind: .person, key: role ?? "manager", size: size, initials: name, face: face)
    }
}

struct StructureHealthPill: View {
    var health: StructureNode.Health

    var body: some View {
        AcctPill(text: health.title, tone: StructureWords.tone(health))
    }
}

struct StructureSplitBar: View {
    var control: Double
    var influence: Double
    var passive: Double

    var body: some View {
        GeometryReader { (g: GeometryProxy) in
            let total: Double = max(0.0001, control + influence + passive)
            let width: CGFloat = max(0, g.size.width - 4)
            HStack(spacing: 2) {
                segment(control, Theme.accent, width, total)
                segment(influence, Theme.warn, width, total)
                segment(passive, Theme.slateBlue, width, total)
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Control \(Int(saturating: (control * 100).rounded())) percent, influence \(Int(saturating: (influence * 100).rounded())) percent, passive \(Int(saturating: (passive * 100).rounded())) percent")
    }

    @ViewBuilder private func segment(_ part: Double, _ tint: Color, _ width: CGFloat, _ total: Double) -> some View {
        if part > 0 {
            Rectangle().fill(tint).frame(width: width * CGFloat(part / total))
        }
    }
}

struct StructureCard: View {
    @Environment(\.outsidePalette) private var P
    var node: StructureNode
    var valueText: String
    var runnerRole: String? = nil
    var runnerFace: String? = nil
    var rungs: [StructureRung] = []
    var canExpand: Bool
    var expanded: Bool
    var actionID: String = ""
    var onToggle: () -> Void
    var onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if canExpand {
                Button { Haptics.choose(); onToggle() } label: { head }
                    .buttonStyle(PressableStyle())
                    .accessibilityHint(expanded ? "Hides what is under it" : "Shows what is under it")
                    .accessibilityIdentifier("structure-node-\(node.id)")
            } else {
                head.accessibilityIdentifier("structure-node-\(node.id)")
            }
            if expanded && !rungs.isEmpty { chain }
            actionPill
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.card))
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                tile
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(node.name).textStyle(.headline).lineLimit(1)
                    Text(node.roleLabel).textStyle(.caption, tint: P.inkFaint).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s)
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    Text(valueText).textStyle(.headline, numeric: true).lineLimit(1).minimumScaleFactor(0.7)
                    if let c = node.change {
                        Text(StructureWords.change(c)).textStyle(.caption, tint: Theme.change(c), numeric: true).lineLimit(1)
                    }
                }
                if canExpand {
                    LedgerGlyph(glyph: expanded ? Glyph.chevronUp : Glyph.chevronDown, size: 12, tint: P.inkFaint)
                        .frame(width: 20, height: 28)
                        .accessibilityHidden(true)
                }
            }
            HStack(alignment: .center, spacing: Theme.Space.s) {
                Text(StructureWords.ownership(node)).textStyle(.caption, tint: P.inkSoft).lineLimit(2)
                Spacer(minLength: Theme.Space.s)
                StructureHealthPill(health: node.health)
            }
            runner
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var tile: some View {
        LedgerGlyph(glyph: StructureWords.glyph(node.kind), size: Theme.Icon.medium, tint: P.accent)
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.inset))
            .accessibilityHidden(true)
    }

    @ViewBuilder private var runner: some View {
        if let name = node.runnerName {
            HStack(spacing: Theme.Space.s) {
                StructureAvatar(name: name, role: runnerRole, face: runnerFace, size: 24)
                Text(name + (node.runnerTitle.map { (t: String) -> String in " \u{00B7} " + t } ?? "")).textStyle(.caption).lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                if let a = node.authority { AcctPill(text: a, tone: .neutral) }
            }
        } else {
            HStack(spacing: Theme.Space.s) {
                LedgerGlyph(glyph: Glyph.person, size: Theme.Icon.small, tint: P.inkFaint)
                Text("You run it").textStyle(.caption)
            }
        }
    }

    private var chain: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Hairline()
            Text("Chain of command, top first").textStyle(.label, tint: P.inkFaint)
            ForEach(rungs) { (r: StructureRung) in
                HStack(spacing: Theme.Space.m) {
                    StructureAvatar(name: r.name, role: r.role, face: r.face, size: 32)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(r.name).textStyle(.body, weight: .medium).lineLimit(1)
                        Text(r.title).textStyle(.caption, tint: P.inkFaint).lineLimit(1)
                    }
                    Spacer(minLength: Theme.Space.s)
                    AcctPill(text: r.authority, tone: .neutral)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var actionTint: Color {
        switch node.primaryAction {
        case .decide, .appointManager: return P.accent
        case .fix: return P.loss
        case .open: return P.inkSoft
        }
    }

    @ViewBuilder private var actionPill: some View {
        if node.kind != .you {
            let title: String = StructureWords.actionTitle(node.primaryAction)
            Button { Haptics.tap(); onAction() } label: {
                Text(title).textStyle(.caption, tint: actionTint, weight: .semibold)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(actionTint.opacity(0.14)))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(title + ", " + node.name + ", " + node.roleLabel)
            .accessibilityIdentifier(actionID.isEmpty ? "structure-action-\(node.id)" : actionID)
        }
    }
}

struct StructureCrumb: Identifiable {
    var id: String
    var title: String
    var action: (() -> Void)? = nil
}

struct StructureCrumbs: View {
    @Environment(\.outsidePalette) private var P
    var crumbs: [StructureCrumb]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.xs) {
                ForEach(Array(crumbs.enumerated()), id: \.element.id) { (n: Int, c: StructureCrumb) in
                    if n > 0 {
                        LedgerGlyph(glyph: Glyph.chevron, size: 10, tint: P.inkFaint)
                            .accessibilityHidden(true)
                    }
                    crumb(c)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(minHeight: 44)
    }

    @ViewBuilder private func crumb(_ c: StructureCrumb) -> some View {
        if let action = c.action {
            Button { Haptics.tap(); action() } label: {
                Text(c.title).textStyle(.body, tint: P.accent).lineLimit(1)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("entity-crumb-\(c.id)")
        } else {
            Text(c.title).textStyle(.body, weight: .semibold).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
        }
    }
}
