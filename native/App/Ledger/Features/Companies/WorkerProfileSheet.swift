import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

/// Which worker a list row opens. The engine's types are never made Identifiable: this wraps the id for `.centerSheet(item:)`.
struct WorkerRef: Identifiable, Hashable {
    var id: Int
}

/// The worker's profile as a popup (medium and large detents): pay, contract, hours, mood, what the pay lets you expect, the promises made to
/// them (keep now / ask to wait) and the actions: pay rise or contract talk, a duty, letting go. The full record is one tap away.
struct WorkerProfileSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    var employeeID: Int
    @State private var pending: PendingAction?
    @State private var discussing = false

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(companyID), let p = e.workerProfile(companyID: companyID, employeeID: employeeID) {
                content(e, co, p)
            } else {
                Text("This person no longer works here.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheet(isPresented: $discussing) {
            ContractDiscussionView(companyID: companyID, personID: employeeID).environmentObject(store)
        }
    }

    private func content(_ e: GameEngine, _ co: Company, _ p: WorkerProfile) -> some View {
        let cur: Currency = e.currency(for: co)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
                header(e, p)
                figures(p, cur)
                contractLine(p)
                expectation(p)
                WorkerGrowthSection(engine: e, companyID: companyID, employeeID: employeeID)
                promisesBlock(e, cur)
                moodBlock(p)
                actions(e, co, p, cur)
        }
    }

    // MARK: Parts

    private func header(_ e: GameEngine, _ p: WorkerProfile) -> some View {
        HStack(spacing: 12) {
            ThumbnailView(kind: .person, key: p.role, size: 44, initials: p.name, face: e.state.people[employeeID]?.faceKey)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).popupText(.figure).lineLimit(1)
                HStack(spacing: 5) {
                    TeamBadge(text: p.roleName, tint: Theme.gold)
                    if let d = p.duty, !d.isEmpty { TeamBadge(text: "Duty: " + dutyName(e, d)) }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func dutyName(_ e: GameEngine, _ id: String) -> String {
        e.recommendedRoles(companyID: companyID).first { (r: RoleOption) -> Bool in r.id == id }?.name ?? id
    }

    private func moodTint(_ word: String) -> Color {
        ["Leaving", "Unhappy"].contains(word) ? Theme.loss : word == "Happy" ? Theme.gain : word == "Mixed" ? Theme.caution : Theme.ivory
    }

    private func figures(_ p: WorkerProfile, _ cur: Currency) -> some View {
        let cells: [StatStrip.Cell] = [
            .init(label: "Salary / month", value: cur.tidyShort(p.monthlyWage)),
            .init(label: "Hours / week", value: String(Int(p.hoursPerWeek.rounded()))),
            .init(label: "Hours worked", value: String(Int(p.hoursWorked.rounded()))),
            .init(label: "Mood", value: p.mood, tint: moodTint(p.mood)),
        ]
        return Card(padding: 12, radius: Theme.Radius.row) { StatStrip(cells: cells, ruled: false) }
    }

    @ViewBuilder private func contractLine(_ p: WorkerProfile) -> some View {
        if let c = p.contract {
            let basis: String = p.payBasis == "fix" ? "fixed salary" : "paid by the hour"
            let line: String = c.typeLabel + " \u{00B7} " + HireWords.percentText(c.workingPercent) + " \u{00B7} " + basis
            let weeks: String = p.weeksEmployed >= 52 ? String(format: "%.1f years here", Double(p.weeksEmployed) / 52) : "\(p.weeksEmployed) weeks here"
            VStack(alignment: .leading, spacing: 2) {
                Text("Contract").capsLabel()
                Text(line).popupText(.body)
                Text(weeks + (c.endWeek.map { (w: Int) -> String in " \u{00B7} ends " + GameCalendar.dateString(week: w) } ?? "")).popupText(.caption)
            }
        }
    }

    /// What the pay lets you expect, against what the work is worth now.
    private func expectation(_ p: WorkerProfile) -> some View {
        let tint: Color = p.meetsExpectation ? Theme.gain : Theme.caution
        return Card(padding: 12, radius: Theme.Radius.row, stroke: tint.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("What to expect").capsLabel()
                    Spacer(minLength: 6)
                    Text(p.meetsExpectation ? "Meets it" : "Falls short").popupText(p.meetsExpectation ? .effect : .risk)
                }
                bar("Expected for this pay", p.expectedPerformance, Theme.ivoryMuted)
                bar("Delivers now", p.performance, tint)
                if !p.performanceNote.isEmpty {
                    Text(p.performanceNote).popupText(.caption)
                }
            }
        }
    }

    private func bar(_ label: String, _ value: Double, _ tint: Color) -> some View {
        let f: Double = min(1, max(0, value / 100))
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).popupText(.caption)
                Spacer(minLength: 6)
                Text(String(Int(value.rounded()))).popupText(.rowValue)
            }
            GeometryReader { (g: GeometryProxy) -> AnyView in
                AnyView(ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(tint).frame(width: g.size.width * f)
                })
            }
            .frame(height: 4)
        }
    }

    @ViewBuilder private func promisesBlock(_ e: GameEngine, _ cur: Currency) -> some View {
        let list: [WorkerPromise] = e.promises(of: employeeID, companyID: companyID).filter { (x: WorkerPromise) -> Bool in x.isOpen }
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Promises").capsLabel()
                ForEach(list) { (x: WorkerPromise) -> AnyView in AnyView(promiseRow(x)) }
            }
        }
    }

    private func promiseRow(_ x: WorkerPromise) -> some View {
        return Card(padding: 12, radius: Theme.Radius.row) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(x.text).popupText(x.status == "Due" ? .risk : .body)
                    Spacer(minLength: 6)
                    Text(x.status == "Due" ? "Due now" : GameCalendar.dateString(week: x.dueWeek)).popupText(.caption)
                }
                WrapRow {
                    TeamAction(title: "Keep it now") { keep(x) }
                    if x.patienceLeft > 0 { TeamAction(title: "Ask to wait", tint: Theme.ivoryMuted) { wait(x) } }
                    if atRisk(x) { TeamAction(title: "Ask for 4 more weeks", tint: Theme.ivoryMuted) { moreTime(x) } }
                }
            }
        }
    }

    private func moodBlock(_ p: WorkerProfile) -> some View {
        let bad: [String] = Array(p.moodBad.prefix(2))
        let good: [String] = Array(p.moodGood.prefix(2))
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(bad, id: \.self) { (t: String) -> AnyView in AnyView(Label(String(t.prefix(1).uppercased() + t.dropFirst()), systemImage: "minus.circle").popupText(.caption)) }
            ForEach(good, id: \.self) { (t: String) -> AnyView in AnyView(Label(String(t.prefix(1).uppercased() + t.dropFirst()), systemImage: "plus.circle").popupText(.caption)) }
        }
    }

    // MARK: Actions

    private func actions(_ e: GameEngine, _ co: Company, _ p: WorkerProfile, _ cur: Currency) -> some View {
        let extras: [RoleOption] = e.recommendedRoles(companyID: companyID).filter { (r: RoleOption) -> Bool in !r.isCore }
        return VStack(alignment: .leading, spacing: 8) {
            Text("What you can do").capsLabel()
            WrapRow {
                TeamAction(title: "Raise or change contract") { discussing = true }
                if !extras.isEmpty { dutyMenu(extras, p) }
                TeamAction(title: "Let go", tint: Theme.loss) { confirmDismiss(e, p, cur) }
            }
            NavigationLink { StaffProfileView(companyID: companyID, staffID: employeeID) } label: {
                Text("Full record \u{203A}").popupText(.effect).frame(minHeight: 32)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func dutyMenu(_ extras: [RoleOption], _ p: WorkerProfile) -> some View {
        Menu {
            Button("No extra duty") { setDuty(nil) }
            ForEach(extras) { (r: RoleOption) -> AnyView in
                AnyView(Button(r.name + (r.effect.isEmpty ? "" : ": " + r.effect)) { setDuty(r.id) })
            }
        } label: {
            Text("Set duty").popupText(.effect)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.gold.opacity(0.7), lineWidth: 1))
                .frame(minHeight: 32)
        }
    }

    private func setDuty(_ id: String?) {
        let cid = companyID, eid = employeeID
        let ok: Bool = store.act { $0.setDuty(companyID: cid, employeeID: eid, duty: id) } ?? false
        if ok { Haptics.success(); store.show(id == nil ? "No extra duty now." : "Duty set. They work it from your office where needed.", tone: "good") }
        else { Haptics.warning(); store.show("That duty cannot be given now: there may be no free place.", tone: "warn") }
    }

    private func keep(_ x: WorkerPromise) {
        let eid = employeeID, pid = x.id
        let r: PromiseReminders.Outcome? = store.act { $0.keepPromise(employeeID: eid, promiseID: pid) }
        if case .notPossible(let why)? = r { Haptics.warning(); store.show(why.isEmpty ? "That cannot be done now." : why, tone: "warn") }
        else { Haptics.success(); store.show("Promise kept.", tone: "good") }
    }

    /// A promise that is due or falls due within four weeks and has not been moved yet (the engine moves a date once).
    private func atRisk(_ x: WorkerPromise) -> Bool {
        guard x.waits == 0, let week = store.engine?.state.week else { return false }
        return x.status == "Due" || x.dueWeek - week <= 4
    }

    /// Asks for a new date. They may say no; the message is the engine's own answer.
    private func moreTime(_ x: WorkerPromise) {
        let eid = employeeID, pid = x.id
        let r: StaffPromises.RenegotiateResult? = store.act { $0.renegotiatePromise(personID: eid, promiseID: pid, newDueInWeeks: 4) }
        switch r {
        case .agreed(let said)?: Haptics.tap(); store.show(said, tone: "n")
        case .refused(let said)?: Haptics.warning(); store.show(said, tone: "warn")
        case .notPossible(let why)?: Haptics.warning(); store.show(why.isEmpty ? "That cannot be moved." : why, tone: "warn")
        case nil: Haptics.warning(); store.show("That cannot be moved.", tone: "warn")
        }
    }

    private func wait(_ x: WorkerPromise) {
        let eid = employeeID, pid = x.id
        let r: PromiseReminders.Outcome? = store.act { $0.askToWait(employeeID: eid, promiseID: pid) }
        if case .notPossible(let why)? = r { Haptics.warning(); store.show(why.isEmpty ? "They will not wait longer." : why, tone: "warn") }
        else { Haptics.tap(); store.show("They agree to wait a little.", tone: "n") }
    }

    private func confirmDismiss(_ e: GameEngine, _ p: WorkerProfile, _ cur: Currency) {
        let prof: StaffProfile.Profile? = e.staffProfile(companyID: companyID, staffID: employeeID)
        let risk: String = (prof?.dismissalDocumented ?? false) ? "Two warnings or theft are on file, so this is easy to defend." : "Nothing documented: they may claim unfair dismissal."
        let sev: String = cur.tidyDisplay(prof?.severance ?? 0)
        let cid = companyID, eid = employeeID, name = p.name
        pending = PendingAction(title: "Let \(name) go?", message: "Notice and severance of \(sev) is paid. \(risk)", button: "Let go", destructive: true) {
            guard let r = store.act({ $0.dismissStaff(companyID: cid, staffID: eid) }) ?? nil else { store.show("They no longer work here.", tone: "warn"); dismiss(); return }
            Haptics.warning()
            store.show(r.claimedUnfairDismissal ? "\(name) is gone, and claimed unfair dismissal: \(cur.tidyDisplay(r.compensation)) paid on top." : "\(name) has left.", tone: r.claimedUnfairDismissal ? "bad" : "n")
            dismiss()
        }
    }
}
