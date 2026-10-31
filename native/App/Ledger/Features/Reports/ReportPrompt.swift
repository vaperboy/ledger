import SwiftUI
import Simulation

/// On Home after a period closes: one line with the result, "Read" opens the Reports app on that report, x dismisses it.
struct ReportPromptSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        if let r = engine.pendingReportPrompt() {
            let net = r.group.pnl.netProfit
            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    _ = store.act { $0.dismissReportPrompt(r) }
                    store.openReport(ReportRef(kind: r.kind, id: r.id))
                } label: {
                    HStack(spacing: 8) {
                        GlyphView(glyph: Glyph.reports, size: 14, weight: 1.7)
                        (Text("\(r.title) report ready · ").foregroundColor(Theme.ivory)
                            + Text(signed(net)).foregroundColor(Theme.change(net))
                            + Text(" profit").foregroundColor(Theme.ivory))
                            .font(.system(size: 12)).lineLimit(1).minimumScaleFactor(0.85)
                        Spacer(minLength: 4)
                        Text("Read ›").font(.system(size: 11.5)).foregroundStyle(Theme.gold)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-report-read")
                Button { Haptics.tap(); _ = store.act { $0.dismissReportPrompt(r) } } label: {
                    Image(systemName: "xmark").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.ivoryFaint)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Dismiss the report")
            }
            .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
    }

    private func signed(_ v: Double) -> String { abs(v) < 0.5 ? store.short(0) : (v > 0 ? "+" : "−") + store.short(abs(v)) }
}
