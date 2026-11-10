import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

func holdingPct(_ p: Double) -> String {
    p == p.rounded() ? "\(Int(p))%" : String(format: "%.1f%%", p)
}

@MainActor
func holdingInjectAction(store: GameStore, holdingID: Int, holdingName: String, amount: Double, cur: Currency) -> PendingAction {
    PendingAction(title: "Put \(cur.tidyShort(amount)) into \(holdingName)?", message: "The money moves from your personal account into the holding's own account. It stays there until the holding spends it.",
                  button: "Put in", amount: amount, currency: cur) {
        let ok: Bool = store.act { (e: inout GameEngine) -> Bool in e.putMoneyInto(companyID: holdingID, amount: amount) } ?? false
        if ok { Haptics.success() } else { Haptics.warning() }
        store.show(ok ? "\(cur.tidyShort(amount)) is now in \(holdingName)." : "You don't have that much available.", tone: ok ? "good" : "warn")
    }
}

struct HoldingTierNote: View {
    var tier: HoldingStakes.Tier
    var percent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(tier.title) at \(holdingPct(percent))").popupText(.rowLabel)
            Text(tier.summary).popupText(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct HoldingTierLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Under 20%: passive. Dividends only, no board seat.").popupText(.caption)
            Text("20% to 50%: influence. May take a board seat.").popupText(.caption)
            Text("Over 50%: control. Consolidated, votes at the board.").popupText(.caption)
            Text("90% or more: may buy out the rest and merge the company in.").popupText(.caption)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct HoldingCashNeed: View {
    var holdingCash: Double
    var needed: Double
    var cur: Currency
    var onInject: (Double) -> Void

    var body: some View {
        let short: Double = max(0, (needed - holdingCash).rounded(.up))
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            PopupRow(label: "Cash in the holding", value: cur.tidyShort(holdingCash))
            if short > 0 {
                Text("The holding is \(cur.tidyShort(short)) short for this. It pays from its own account.").popupText(.risk)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Put \(cur.tidyShort(short)) into the holding") { onInject(short) }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("holding-inject")
            }
        }
    }
}

enum HoldingStakeGroup: Int, CaseIterable, Identifiable {
    case controlled, big, small

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .controlled: return "Controlled"
        case .big: return "Big stakes"
        case .small: return "Small stakes"
        }
    }

    var word: String {
        switch self {
        case .controlled: return "Controlled"
        case .big: return "Big stake"
        case .small: return "Small stake"
        }
    }

    var range: String {
        switch self {
        case .controlled: return "over 50%"
        case .big: return "20% to 50%"
        case .small: return "under 20%"
        }
    }

    static func of(percent: Double) -> HoldingStakeGroup {
        switch HoldingStakes.tier(forPercent: percent) {
        case .control, .squeezeOut, .whole: return .controlled
        case .influence: return .big
        case .passive, .none: return .small
        }
    }
}

struct HoldingStakeRow<More: View>: View {
    var tradeKey: String
    var title: String
    var subtitle: String
    var value: String
    var valueNote: String
    var showRunner: Bool
    var runnerName: String?
    var runnerRole: String?
    var runnerFace: String?
    var health: StructureNode.Health?
    var primary: String
    var key: String
    var onPrimary: () -> Void
    @ViewBuilder var more: () -> More

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                ThumbnailView(kind: .trade, key: tradeKey, size: 40, glyph: Glyph.home)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title).textStyle(.body, weight: .medium).lineLimit(1)
                    Text(subtitle).textStyle(.caption, tint: Theme.inkFaint).lineLimit(2)
                }
                Spacer(minLength: Theme.Space.s)
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    Text(value).textStyle(.body, numeric: true, weight: .medium).lineLimit(1)
                    Text(valueNote).textStyle(.caption, tint: Theme.inkFaint, numeric: true).lineLimit(1)
                }
            }
            if showRunner || health != nil {
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    runner
                    Spacer(minLength: Theme.Space.s)
                    if let health { StructureHealthPill(health: health) }
                }
            }
            HStack(spacing: Theme.Space.s) {
                Button { Haptics.tap(); onPrimary() } label: {
                    Text(primary).textStyle(.caption, tint: Theme.accent, weight: .semibold)
                        .lineLimit(2).multilineTextAlignment(.leading)
                        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(Theme.accent.opacity(0.14)))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(primary + ", " + title)
                .accessibilityIdentifier("holding-\(key)")
                Spacer(minLength: Theme.Space.s)
                Menu {
                    more()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More for " + title)
                .accessibilityIdentifier("holding-more-\(key)")
            }
        }
        .padding(.vertical, Theme.Space.m)
    }

    @ViewBuilder private var runner: some View {
        if !showRunner {
            EmptyView()
        } else if let name = runnerName {
            HStack(spacing: Theme.Space.s) {
                StructureAvatar(name: name, role: runnerRole, face: runnerFace, size: 28)
                Text(name).textStyle(.caption).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: Theme.Space.s) {
                LedgerGlyph(glyph: Glyph.person, size: Theme.Icon.small, tint: Theme.inkFaint)
                Text("You run it").textStyle(.caption)
            }
        }
    }
}
