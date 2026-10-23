import SwiftUI
import Simulation

/// On Home after a period closes: the headline, one sentence, and a link to the full report. Dismissable.
struct ReportPromptSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        if let r = engine.pendingReportPrompt() {
            let net = r.group.pnl.netProfit
            LedgerSection(title: "Last " + r.kind.noun, trailing: {
                Button { store.act { $0.dismissReportPrompt(r) } } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ivoryFaint).padding(6)
                }
                .buttonStyle(.plain).accessibilityLabel("Dismiss the report")
            }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(store.short(net)).font(.hero(26)).foregroundStyle(net < 0 ? Theme.loss : Theme.ivory)
                        Text("profit · " + r.title).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                        Spacer(minLength: 8)
                        Text(signed(r.netWorthChange)).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.change(r.netWorthChange))
                        Text("net worth").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                    }
                    if let first = r.summary.first {
                        Text(first.tidyMoney).font(.system(size: 14)).foregroundStyle(Theme.ivoryMuted).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        store.reportRequest = ReportRef(kind: r.kind, id: r.id)
                        store.moneySection = .reports
                        store.tab = .group
                        store.act { $0.dismissReportPrompt(r) }
                    } label: {
                        Text("Read the full report  →").font(.system(size: 12)).foregroundStyle(Theme.gold)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func signed(_ v: Double) -> String { abs(v) < 0.5 ? store.short(0) : (v > 0 ? "+" : "−") + store.short(abs(v)) }
}
