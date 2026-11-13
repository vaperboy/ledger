import SwiftUI
import GameCore
import Simulation

struct GovernmentNewsSection: View {
    var engine: GameEngine
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let read: WorldRead? = store.cachedWorldRead ?? engine.worldRead()
        let list: [GovNews] = read.map { (r: WorldRead) -> [GovNews] in Array(r.gov.news.prefix(40)) } ?? []
        VStack(alignment: .leading, spacing: 0) {
            Text("Source: the government. Rates, inflation, elections, terms of office and the courts, as it announces them.")
                .textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true).padding(.bottom, 12)
            if let lead = list.first {
                leadStory(lead)
                ForEach(Array(list.dropFirst().enumerated()), id: \.element.id) { (_: Int, n: GovNews) in
                    Rectangle().fill(P.hairline).frame(height: 1)
                    item(n)
                }
            } else {
                Text("No announcements yet.").textStyle(.body, tint: P.inkSoft)
                    .frame(maxWidth: .infinity).padding(.vertical, 36)
            }
            Button { store.openApp(.world) } label: {
                HStack(spacing: 6) {
                    Text("Open the World app").textStyle(.caption, tint: P.accent, weight: .semibold)
                    GlyphView(glyph: Glyph.chevron, size: 11, weight: 2, tint: P.accent)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 8)
        }
        .accessibilityIdentifier("news-government")
    }

    private func toneWord(_ tone: String) -> String { tone == "good" ? "Good news" : tone == "bad" ? "Warning" : "Notice" }
    private func toneColor(_ tone: String) -> Color { tone == "good" ? P.gain : tone == "bad" ? P.loss : P.inkFaint }

    private func leadStory(_ n: GovNews) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(toneWord(n.tone).uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(1.4).foregroundStyle(toneColor(n.tone))
            Text(n.text).font(.system(size: 26, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(GameCalendar.dateString(week: n.week)).textStyle(.caption, tint: P.inkFaint)
        }
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
    }

    private func item(_ n: GovNews) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(GameCalendar.dateString(week: n.week)).font(.system(size: 11, weight: .semibold)).foregroundStyle(P.inkFaint).frame(width: 74, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(n.text).font(.system(size: 15, weight: .medium, design: .serif)).foregroundStyle(P.ink).fixedSize(horizontal: false, vertical: true)
                if n.tone != "n" { Text(toneWord(n.tone)).textStyle(.caption, tint: toneColor(n.tone), weight: .semibold) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
