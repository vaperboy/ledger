import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Company > Team > Promises: every promise made to this company's people (at hiring, in a contract discussion), open ones first. Each shows the
/// employee, the promise, the date it was made and falls due, its status (Pending, Due, Fulfilled, Broken, Renegotiated) and what that means for the
/// person and for you, in words. The engine checks each promise against the real action that keeps it (a raise, a course, a perk ...); this screen only
/// reads them and asks to move a date (`renegotiatePromise`: once per promise, and they may refuse).
struct CompanyPromises: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        let rows: [PromiseRow] = engine.promises(companyID: company.id)
        let group: [PromiseRow] = engine.promises(companyID: 0)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            summary(rows)
            if rows.isEmpty {
                Card(padding: 14, radius: Theme.Radius.row) {
                    Text("No promises yet. You can promise something when you hire (the terms page) or in a contract discussion.")
                        .font(.bodyText).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(rows) { r in PromiseCard(row: r, engine: engine, company: company) }
            if !group.isEmpty {
                TeamGroup("Group staff") {
                    VStack(spacing: 8) { ForEach(group) { r in PromiseCard(row: r, engine: engine, company: nil) } }
                }
            }
        }
    }

    private func summary(_ rows: [PromiseRow]) -> some View {
        let open: Int = rows.filter { $0.status == .pending }.count
        let due: Int = rows.filter { $0.status == .due }.count
        let kept: Int = rows.filter { $0.status == .fulfilled }.count
        let broken: Int = rows.filter { $0.status == .broken }.count
        let cells: [StatStrip.Cell] = [
            .init(label: "Pending", value: String(open)),
            .init(label: "Due", value: String(due), tint: due > 0 ? Theme.caution : Theme.ivory),
            .init(label: "Fulfilled", value: String(kept), tint: kept > 0 ? Theme.gain : Theme.ivory),
            .init(label: "Broken", value: String(broken), tint: broken > 0 ? Theme.loss : Theme.ivory),
        ]
        return Card(padding: 14, radius: Theme.Radius.hero) { StatStrip(cells: cells, ruled: false) }
    }
}

/// One promise as a card.
struct PromiseCard: View {
    @EnvironmentObject var store: GameStore
    var row: PromiseRow
    var engine: GameEngine
    /// The company whose staff list can open the person's profile; nil for group staff.
    var company: Company?
    @State private var pending: PendingAction?

    private func tint(_ s: StaffPromises.Status) -> Color {
        switch s {
        case .pending: return Theme.ivoryMuted
        case .due: return Theme.caution
        case .fulfilled: return Theme.gain
        case .broken: return Theme.loss
        case .renegotiated: return Theme.ivoryFaint
        }
    }

    private var isGroupOpen: Bool { company == nil && (row.status == .pending || row.status == .due) }
    private var hasProfile: Bool { company?.staff.contains { $0.id == row.personID } ?? false }

    var body: some View {
        Card(padding: 14, radius: Theme.Radius.row) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.employee).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory)
                    Spacer(minLength: 8)
                    Chip(text: row.status.rawValue, tint: tint(row.status))
                }
                Text(row.promise).font(.system(size: 13)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                Text("Made \(GameCalendar.dateString(week: row.madeWeek)) \u{00B7} due \(GameCalendar.dateString(week: row.dueWeek))")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                Text(row.consequence).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                actions
            }
        }
        .confirmAction($pending)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("promise-row")
    }

    @ViewBuilder private var actions: some View {
        if row.canRenegotiate || hasProfile || isGroupOpen {
            WrapRow {
                if isGroupOpen { TeamAction(title: "Keep it now") { confirmKeep() } }
                if row.canRenegotiate { renegotiate }
                if hasProfile, let c = company {
                    NavigationLink { StaffProfileView(companyID: c.id, staffID: row.personID) } label: {
                        Text("Open profile").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ivoryMuted)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: 1))
                            .frame(minHeight: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var renegotiate: some View {
        Menu {
            ForEach([4, 8, 13, 26], id: \.self) { w in
                Button("Move it to \(HireWords.weeksText(w)) from now") { ask(w) }
            }
        } label: {
            Text("Renegotiate").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.gold.opacity(0.7), lineWidth: 1))
                .frame(minHeight: 32)
        }
        .accessibilityIdentifier("promise-renegotiate")
    }

    // MARK: Group staff: the real action that keeps the promise

    private func detail() -> String { engine.promises(personID: row.personID).first { $0.id == row.id }?.detail ?? "" }

    private func confirmKeep() {
        pending = PendingAction(title: "Keep this promise now?", message: row.kind.fulfilledByForGroup + " It is done at once.", button: "Do it now") { keepNow() }
    }

    private func keepNow() {
        let pid = row.personID
        let current: Int = GroupPeople.level(engine.state, personID: pid)
        let target: Double = Double(detail()) ?? 100
        let expense: String = StaffExpenses.item(String(detail().dropFirst(4)))?.id ?? (StaffExpenses.all.first?.id ?? "")
        let ok: Bool?
        switch row.kind {
        case .salaryReview: ok = store.act { $0.groupRaise(personID: pid, percent: 0.05) }
        case .promotion: ok = store.act { $0.groupPromote(personID: pid) }
        case .responsibility: ok = store.act { $0.groupSetLevel(personID: pid, level: min(2, current + 1)) }
        case .training: ok = store.act { $0.groupTrain(personID: pid) }
        case .betterConditions, .futureBenefits: ok = store.act { $0.groupSetExpense(personID: pid, item: expense, on: true) }
        case .percentageChange: ok = store.act { $0.groupSetPercent(personID: pid, percent: target) }
        }
        if ok == true { Haptics.success(); store.show("Done: \(row.kind.title.lowercased()).", tone: "good") }
        else { Haptics.warning(); store.show("That could not be done now: it may already be the case, or the cash is short.", tone: "warn") }
    }

    private func ask(_ weeks: Int) {
        let pid = row.personID, prid = row.id
        let r: StaffPromises.RenegotiateResult? = store.act { $0.renegotiatePromise(personID: pid, promiseID: prid, newDueInWeeks: weeks) }
        switch r {
        case .agreed(let text)?: Haptics.success(); store.show(text, tone: "good")
        case .refused(let text)?: Haptics.warning(); store.show(text, tone: "warn")
        case .notPossible(let text)?: Haptics.warning(); store.show(text, tone: "warn")
        case nil: store.show("No game is loaded.", tone: "warn")
        }
    }
}
