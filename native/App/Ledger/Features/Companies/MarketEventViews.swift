import SwiftUI
import GameCore
import Businesses
import Simulation

/// Compact rows for the latest market events (Market section and Market app). Gold = opportunity, green = gain, red = loss.
/// A row that appears while the screen is open slides in and gets a brief edge; the first render never animates.
struct MarketEventRows: View {
    var events: [MarketEvent]
    @State private var known: Set<Int>? = nil
    @State private var fresh: Set<Int> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Events of this company, plus the ones about the whole market, newest first.
    static func relevant(_ e: GameEngine, companyID: Int?) -> [MarketEvent] {
        let all: [MarketEvent] = e.marketEvents(limit: 30)
        let mine: [MarketEvent] = all.filter { (m: MarketEvent) -> Bool in
            guard let id = companyID else { return true }
            return m.companyID == nil || m.companyID == id
        }
        return Array(mine.prefix(4))
    }

    static func tint(_ m: MarketEvent) -> Color {
        if m.kind == .acquisitionOpportunity || m.kind == .majorContract { return Theme.gold }
        if m.tone == "good" { return Theme.gain }
        if m.tone == "bad" { return Theme.loss }
        return Theme.ivoryMuted
    }

    private var ids: [Int] { events.map { (m: MarketEvent) -> Int in m.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !events.isEmpty {
                Text("LATEST IN THE MARKET").capsLabel()
                ForEach(events) { (m: MarketEvent) in
                    row(m)
                        .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                }
            }
        }
        .animation(OrgMotion.hierarchy(reduceMotion), value: ids)
        .onAppear { if known == nil { known = Set(ids) } }
        .onChange(of: ids) { _, new in
            let old: Set<Int> = known ?? []
            let added: Set<Int> = Set(new).subtracting(old)
            known = old.union(new)
            guard !added.isEmpty else { return }
            fresh = added
            DispatchQueue.main.asyncAfter(deadline: .now() + OrgMotion.flashSeconds) { fresh = [] }
        }
    }

    private func row(_ m: MarketEvent) -> some View {
        let tint: Color = Self.tint(m)
        let flash: Color? = fresh.contains(m.id) ? tint : nil
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        return HStack(alignment: .top, spacing: 10) {
            Circle().fill(tint).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.title.tidyText).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2)
                if !m.detail.isEmpty {
                    Text(m.detail.tidyText).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(tint.opacity(0.08)))
        .overlay(shape.strokeBorder(tint.opacity(0.28), lineWidth: 1))
        .orgEdge(flash, radius: Theme.Radius.row)
    }
}

/// A slim header on the Sales tab: how the trade's prices moved this month, with a line that draws itself once.
struct MarketTrendCard: View {
    var trend: MarketTrend

    var body: some View {
        let change: Double = trend.priceIndexChangeThisMonth
        let pct: Double = abs(change) * 100
        let steady: Bool = pct < 0.05
        let tint: Color = steady ? Theme.ivoryMuted : (change > 0 ? Theme.gain : Theme.loss)
        let word: String = change > 0 ? "up" : "down"
        let figure: String = String(format: "%.1f%%", pct)
        let text: String = steady ? "Prices are steady this month" : "Prices are \(word) \(figure) this month"
        return Card(padding: 12, radius: Theme.Radius.hero) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MARKET TREND").capsLabel()
                    Text(text).font(.system(size: 13.5, weight: .medium)).foregroundStyle(tint).lineLimit(2)
                }
                Spacer(minLength: 6)
                Sparkline(values: trend.points, tint: tint, filled: false)
                    .frame(width: 96, height: 30)
                    .drawsItself()
            }
        }
    }
}
