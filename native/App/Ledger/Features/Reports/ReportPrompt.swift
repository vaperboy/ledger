import SwiftUI
import Simulation

/// On Home after a period closes: the headline, one sentence, and a link to the full report. Dismissable.
struct ReportPromptSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    /// A finished week, month or year report is news, not a headline: one quiet row under the priorities with the result and a
    /// way to read it. The full report lives in Group > Money > Reports.
    var body: some View {
        if let r = engine.pendingReportPrompt() {
            let net = r.group.pnl.netProfit
            HStack(alignment: .center, spacing: 10) {
                Button {
                    store.reportRequest = ReportRef(kind: r.kind, id: r.id)
                    store.moneySection = .reports
                    store.jump(to: .group)
                    store.act { $0.dismissReportPrompt(r) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text").font(.system(size: 13)).foregroundStyle(Theme.gold).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(r.title) report is ready").font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                            HStack(spacing: 4) {
                                Text("Profit").foregroundStyle(Theme.ivoryFaint)
                                Text(signed(net)).foregroundStyle(Theme.change(net))
                                Text("· net worth").foregroundStyle(Theme.ivoryFaint)
                                Text(signed(r.netWorthChange)).foregroundStyle(Theme.change(r.netWorthChange))
                            }
                            .font(.system(size: 12).monospacedDigit())
                        }
                        Spacer(minLength: 6)
                        Text("Read").font(.system(size: 12)).foregroundStyle(Theme.gold)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ivoryFaint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { store.act { $0.dismissReportPrompt(r) } } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ivoryFaint).padding(6)
                }
                .buttonStyle(.plain).accessibilityLabel("Dismiss the report")
            }
            .padding(.vertical, 10)
            .overlay(alignment: .top) { Hairline() }
        }
    }

    private func signed(_ v: Double) -> String { abs(v) < 0.5 ? store.short(0) : (v > 0 ? "+" : "−") + store.short(abs(v)) }
}
