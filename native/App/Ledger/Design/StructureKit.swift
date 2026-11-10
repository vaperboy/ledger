import SwiftUI
import GameCore
import Businesses
import Simulation

enum StructureWords {
    static func percent(_ p: Double) -> String { "\(Int(saturating: p.rounded()))%" }

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

struct StructureRow: View {
    @Environment(\.outsidePalette) private var P
    var node: StructureNode
    var valueText: String
    var hasKids: Bool
    var expanded: Bool
    var actionID: String = ""
    var logoID: String = ""
    var tradeKey: String = ""
    var onToggle: () -> Void
    var onOpen: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.xxs) {
            Button { Haptics.tap(); onOpen() } label: {
                HStack(spacing: Theme.Space.s) {
                    mark
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Theme.Space.xs) {
                            Text(node.name).textStyle(.headline).lineLimit(1)
                            if case .decide(let n) = node.primaryAction { RedBubble(count: n, size: .small) }
                        }
                        StructureHealthPill(health: node.health).fixedSize()
                    }
                    Spacer(minLength: Theme.Space.xs)
                    Text(valueText).textStyle(.body, numeric: true).lineLimit(1).fixedSize()
                    LedgerGlyph(glyph: Glyph.chevron, size: 12, tint: P.accent)
                }
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(node.name + ", " + node.roleLabel + ", " + node.health.title + ", " + valueText)
            .accessibilityHint(StructureWords.actionTitle(node.primaryAction))
            .accessibilityIdentifier(actionID.isEmpty ? "structure-action-\(node.id)" : actionID)
            if hasKids {
                Button { Haptics.choose(); onToggle() } label: {
                    LedgerGlyph(glyph: expanded ? Glyph.chevronUp : Glyph.chevronDown, size: 12, tint: P.inkFaint)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(expanded ? "Hide what is under " + node.name : "Show what is under " + node.name)
                .accessibilityIdentifier("structure-node-\(node.id)")
            }
        }
        .padding(.leading, Theme.Space.m).padding(.trailing, hasKids ? Theme.Space.xxs : Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(P.accent.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder private var mark: some View {
        if !logoID.isEmpty {
            LogoBadge(logoID: logoID, size: 40)
        } else if !tradeKey.isEmpty {
            ThumbnailView(kind: .trade, key: tradeKey, size: 40)
        } else {
            LedgerGlyph(glyph: StructureWords.glyph(node.kind), size: Theme.Icon.medium, tint: P.accent).frame(width: 40, height: 40)
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
