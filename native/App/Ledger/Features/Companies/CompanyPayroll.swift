import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Pay day and what falls due: the one home for the company's pay day. A change made while this month's payroll is unpaid waits for it.
struct CompanyPayroll: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.currency(for: company)
        let o = engine.financeOverview(companyID: company.id)
        let due = o.upcoming.filter { $0.id == "pay\(company.id)" || $0.id == "bills\(company.id)" }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            CompanyPayrollRun(engine: engine, company: company)
            if let info = engine.paydayInfo(companyID: company.id) {
                paydaySection(info)
            }
            LedgerSection("What falls due") {
                VStack(alignment: .leading, spacing: 6) {
                    if due.isEmpty {
                        Text("Nothing is waiting: no wages are owed and no rent or supplier bills have built up this month.")
                            .font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(due) { u in
                                ListRow(symbol: "calendar", tint: Theme.ivoryMuted, title: u.title, subtitle: u.detail, trailing: cur.tidyShort(u.amount), trailingSub: u.dateText)
                            }
                        }
                    }
                    Text("Wages build up week by week and leave on pay day. Rent and supplier bills leave on the last day of the month. Both come from company cash; if it runs short, wages are late and the bills carry interest.")
                        .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .confirmAction($pending)
    }

    @ViewBuilder private func paydaySection(_ info: PaydayInfo) -> some View {
        LedgerSection(title: "Pay day", trailing: {
            Text(info.dayLabel).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
        }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if !info.hasPayroll {
                    Text("No one is on the payroll yet, so there is nothing to pay. Pay day matters once you hire someone.")
                        .font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Staff are next paid on \(info.nextPayText). Rent and supplier bills follow on \(info.billText).")
                        .font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                    if let q = info.pendingLabel {
                        Text("Changing to the \(q.lowercased()) after this month's payroll is paid. Staff need notice.")
                            .font(.system(size: 12)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
                    }
                    if info.isLate {
                        Text("Wages are late, so a change waits until they are paid.").font(.system(size: 12)).foregroundStyle(Theme.loss)
                    }
                    VStack(spacing: 0) {
                        ForEach(info.choices) { c in
                            Button { choose(c, info) } label: {
                                ListRow(symbol: c.isCurrent ? "checkmark.circle.fill" : (c.isQueued ? "clock" : "circle"),
                                        tint: c.isCurrent ? Theme.gold : Theme.ivoryMuted, title: c.label, subtitle: timing(c, info))
                            }.buttonStyle(.plain)
                        }
                    }
                    Text("A weekend pay day is paid the Friday before. Early in the month last month's takings are in; the last day stacks wages and rent on one day.")
                        .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
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
            case .queueCleared?: store.show("The waiting change was dropped. Pay day stays the \(current).", tone: "n")
            case .unchanged?: store.show("That is already the pay day.", tone: "n")
            default: Haptics.warning(); store.show("The pay day could not be changed.", tone: "warn")
            }
        }
        if info.changesImmediately {
            pending = PendingAction(title: "Move pay day to the \(name)?",
                                    message: "This month is already paid. From next month staff are paid on \(first) instead of the \(current): \(gap(c)). Staff need notice, and wages then fall due at a different time of the month from your takings.",
                                    button: "Move pay day", run: run)
        } else {
            pending = PendingAction(title: "Move pay day to the \(name)?",
                                    message: "This month's payroll still goes out on \(nextPay). After it staff are paid on the \(name), first on \(first). Nothing is paid twice or skipped.",
                                    button: "Queue the change", run: run)
        }
    }
}
