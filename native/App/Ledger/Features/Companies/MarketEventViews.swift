import SwiftUI
import GameCore
import Businesses
import Simulation

/// Compact rows for the latest market events (Market app). A dot carries the tone: gold = opportunity, green = gain, red = loss.
/// A row that appears while the screen is open slides in and gets a brief edge; the first render never animates.
struct MarketEventRows: View {
    @EnvironmentObject var store: GameStore
    var events: [MarketEvent]
    /// The caps title above the rows; off when the screen labels the group itself.
    var showsTitle = true
    @State private var known: Set<Int>? = nil
    @State private var fresh: Set<Int> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Events of this company, plus the ones about the whole market, newest first.
    static func relevant(_ e: GameEngine, companyID: Int?, limit: Int = 4) -> [MarketEvent] {
        let all: [MarketEvent] = e.marketEvents(limit: 30)
        var seen: Set<String> = []
        // Newest first; the same headline again (a later week's copy) is left out.
        let mine: [MarketEvent] = all.filter { (m: MarketEvent) -> Bool in
            if let id = companyID, m.companyID != nil && m.companyID != id { return false }
            return seen.insert(m.title).inserted
        }
        return Array(mine.prefix(limit))
    }

    /// What the event does to you, in one line: the first sentence of its consequence (or of its detail when it has none).
    static func impact(_ m: MarketEvent) -> String {
        let text: String = (m.consequence.isEmpty ? m.detail : m.consequence).tidyText
        guard let end = text.range(of: ". ") else { return text }
        return String(text[..<end.lowerBound]) + "."
    }

    static func tint(_ m: MarketEvent) -> Color {
        if m.kind == .acquisitionOpportunity || m.kind == .majorContract { return Theme.gold }
        if m.tone == "good" { return Theme.gain }
        if m.tone == "bad" { return Theme.loss }
        return Theme.ivoryMuted
    }

    private var ids: [Int] { events.map { (m: MarketEvent) -> Int in m.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !events.isEmpty {
                if showsTitle { Text("LATEST IN THE MARKET").capsLabel().padding(.bottom, Theme.Space.s) }
                ForEach(Array(events.enumerated()), id: \.element.id) { (pair: (offset: Int, element: MarketEvent)) in
                    if pair.offset > 0 { Hairline().padding(.leading, 17) }
                    row(pair.element)
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

    private func thank(_ m: MarketEvent) {
        let eid: Int = m.id
        let r: SettingResult? = store.act { $0.acknowledgeRecognition(eventID: eid) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
        else if r != nil { Haptics.success(); store.show("Thanked. They will remember it.", tone: "good") }
    }

    private func row(_ m: MarketEvent) -> some View {
        let tint: Color = Self.tint(m)
        let flash: Color? = fresh.contains(m.id) ? tint : nil
        return HStack(alignment: .top, spacing: 10) {
            Circle().fill(tint).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.title.tidyText).textStyle(.body, weight: .medium).lineLimit(1)
                if !Self.impact(m).isEmpty {
                    Text(Self.impact(m)).textStyle(.caption).lineLimit(1)
                }
                if m.kind == .recognition && !m.acknowledged {
                    TeamAction(title: "Thank them") { thank(m) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .orgEdge(flash, radius: Theme.Radius.row)
        .newMarker(.market, "e\(m.id)", style: .capsule, important: m.tone == "bad", alignment: .topTrailing)
    }
}
