import SwiftUI

/// Home's important-events timeline: the last few notable things (big payments, loan repayments, good news, milestones), newest first,
/// at most 6 rows. New rows slide in over 250 ms and the newest has a brief gold edge; the first appearance never animates. Hidden when empty.
struct HomeTimeline: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlight: UUID?
    @Environment(\.scenePhase) private var scenePhase
    @State private var seen: Bool = false
    /// The events as they were before the day that is still behind a report: new rows slide in only after Continue.
    @State private var held: [HomeEvent]?
    /// How many rows the space left under the companies can take (0 hides the section); at most 6.
    var maxRows: Int = 6

    /// Height of one row and of the "Recent" title, used by Home to count what fits.
    static let rowHeight: CGFloat = 38
    static let titleHeight: CGFloat = 28

    var body: some View {
        let blocked: Bool = store.holdsHomeFigures
        let source: [HomeEvent] = blocked ? (held ?? store.homeEvents) : store.homeEvents
        let rows: [HomeEvent] = Array(source.prefix(max(0, min(6, maxRows))))
        Group {
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
                    .padding(.horizontal, 6).frame(height: HomeTimeline.rowHeight)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.gold.opacity(highlight == r.id ? 0.7 : 0), lineWidth: 1))
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 6)
            .animation(seen && !reduceMotion ? .easeOut(duration: 0.25) : nil, value: rows.map { $0.id })
            .onAppear { DispatchQueue.main.async { seen = true } }
            .onChange(of: rows.first?.id) { _, new in
                guard seen, !reduceMotion, let new else { return }
                highlight = new
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    if highlight == new { withAnimation(.easeOut(duration: 0.4)) { highlight = nil } }
                }
            }
          }
        }
        .onAppear { if held == nil { held = store.homeEvents } }
        .onChange(of: store.homeEvents) { _, new in if !store.holdsHomeFigures { held = new } }
        .onChange(of: blocked) { _, now in if !now { held = store.homeEvents } }
        .onChange(of: scenePhase) { _, phase in if phase == .active && !store.holdsHomeFigures { held = store.homeEvents } }
    }
}
