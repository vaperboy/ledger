import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Pay day and what falls due: the one home for the company's pay day. A change made while this month's payroll is unpaid waits for it.
struct CompanyPayroll: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.currency(for: company)
        let o = engine.financeOverview(companyID: company.id)
        let due = o.upcoming.filter { $0.id == "pay\(company.id)" || $0.id == "bills\(company.id)" }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            LedgerSection("What falls due") {
                VStack(alignment: .leading, spacing: 0) {
                    if due.isEmpty {
                        EmptyState(glyph: Glyph.check, title: "Nothing is waiting", message: "No wages are owed and no rent or supplier bills have built up this month.", centered: false)
                    } else {
                        ForEach(Array(due.enumerated()), id: \.element.id) { n, u in
                            if n > 0 { Hairline() }
                            LedgerRow(leading: .glyph(Glyph.reports), title: u.title, subtitle: u.detail, value: cur.tidyShort(u.amount), valueNote: u.dateText)
                        }
                    }
                    Text("Wages build up week by week and leave on pay day. Rent and supplier bills leave on the last day of the month. Both come from company cash; if it runs short, wages are late and the bills carry interest.")
                        .textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true).padding(.top, Theme.Space.s)
                }
            }
            if let info = engine.paydayInfo(companyID: company.id) {
                paydaySection(info, datesShown: due.contains { $0.id == "pay\(company.id)" && !$0.dateText.isEmpty })
            }
        }
        .confirmAction($pending)
    }

    /// The pay-day choice. The next dates are said here only when "What falls due" above does not already show them.
    @ViewBuilder private func paydaySection(_ info: PaydayInfo, datesShown: Bool) -> some View {
        LedgerSection("Pay day") {
            if !info.hasPayroll {
                EmptyState(glyph: Glyph.calendar, title: "No one is on the payroll yet", message: "Pay day matters once you hire someone.", centered: false)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    if !datesShown {
                        Text("Staff are next paid on \(info.nextPayText). Rent and supplier bills follow on \(info.billText).")
                            .textStyle(.body).fixedSize(horizontal: false, vertical: true)
                    }
                    if let q = info.pendingLabel {
                        Text("Changing to the \(q.lowercased()) after this month's payroll is paid. Staff need notice.")
                            .textStyle(.caption, tint: P.warn).fixedSize(horizontal: false, vertical: true)
                    }
                    if info.isLate {
                        Label("Wages are late, so a change waits until they are paid.", systemImage: "exclamationmark.triangle.fill").textStyle(.body, tint: P.loss, weight: .medium)
                    }
                    ForEach(info.choices) { c in
                        let tag: String = c.isCurrent ? "Current" : (c.isQueued ? "Queued" : "")
                        ChoiceCard(title: c.label, subtitle: timing(c, info), trailing: tag, selected: c.isCurrent || c.isQueued) { choose(c, info) }
                    }
                    Text("A weekend pay day is paid the Friday before. Early in the month last month's takings are in; the last day stacks wages and rent on one day.")
                        .textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func gap(_ c: PaydayChoice) -> String {
        c.daysBeforeBills <= 0 ? "the same day as rent and supplier bills" : "\(c.daysBeforeBills) days before rent and supplier bills"
    }

    private func timing(_ c: PaydayChoice, _ info: PaydayInfo) -> String {
        (info.changesImmediately ? "First paid " : "Then paid ") + c.firstPayText + ", " + gap(c)
    }

    private func choose(_ c: PaydayChoice, _ info: PaydayInfo) {
        guard !c.isCurrent || info.pendingDay != nil else { return }
        let name = c.label.lowercased()
        let day = c.day
        let current = info.dayLabel.lowercased()
        let nextPay = info.nextPayText
        let first = c.firstPayText
        let run: () -> Void = {
            switch store.act({ $0.setPayday(companyID: company.id, day: day) }) {
            case .changedNow?: Haptics.success(); store.show("Pay day is now the \(name). First paid \(first).", tone: "good")
            case .queued?: Haptics.success(); store.show("Pay day moves to the \(name) after this month's payroll (\(nextPay)).", tone: "good")
            case .queueCleared?: Haptics.tap(); store.show("The waiting change was dropped. Pay day stays the \(current).", tone: "n")
            case .unchanged?: store.show("That is already the pay day.", tone: "n")
            case nil: break
            default: Haptics.warning(); store.show("The pay day could not be changed.", tone: "warn")
            }
        }
        run()
    }
}
