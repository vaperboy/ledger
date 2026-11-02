import SwiftUI

/// Home's important-events timeline: the last few notable things (big payments, loan repayments, good news, milestones), newest first,
/// at most 6 rows. New rows slide in over 250 ms and the newest has a brief gold edge; the first appearance never animates. Hidden when empty.
struct HomeTimeline: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlight: UUID?
    @State private var seen: Bool = false

    var body: some View {
        let rows: [HomeEvent] = Array(store.homeEvents.prefix(6))
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent").capsLabel().padding(.bottom, 8)
                ForEach(rows) { (r: HomeEvent) in
                    HStack(spacing: 10) {
                        GlyphView(glyph: r.glyph, size: 14, weight: 1.5, tint: Theme.gold)
                            .frame(width: 26, height: 26).background(Circle().fill(Theme.gold.opacity(0.12)))
                        Text(r.text).font(.system(size: 13)).foregroundStyle(Theme.ivory).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(r.day).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 6)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.gold.opacity(highlight == r.id ? 0.7 : 0), lineWidth: 1))
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 6)
            .animation(seen && !reduceMotion ? .easeOut(duration: 0.25) : nil, value: rows.map { $0.id })
            .onAppear { DispatchQueue.main.async { seen = true } }
            .onChange(of: store.homeEvents.first?.id) { _, new in
                guard seen, !reduceMotion, let new else { return }
                highlight = new
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    if highlight == new { withAnimation(.easeOut(duration: 0.4)) { highlight = nil } }
                }
            }
        }
    }
}
