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

/// The worker's profile as a popup (from a banner or the inbox): the same `WorkerProfileBody` as the pushed page. The contract discussion
/// replaces the profile inside this popup (its close steps back to the profile) instead of opening a second popup on top.
struct WorkerProfileSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    var employeeID: Int
    @State private var discussing = false

    var body: some View {
        if discussing {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Button { Haptics.tap(); discussing = false } label: { Text("\u{2039} Profile") }
                    .buttonStyle(TertiaryButtonStyle(size: .compact))
                    .accessibilityLabel("Back to the profile")
                ContractDiscussionView(companyID: companyID, personID: employeeID)
                    .environment(\.popupClose, { discussing = false })
            }
        } else {
            WorkerProfileBody(companyID: companyID, employeeID: employeeID, showsName: true, onDiscuss: { discussing = true }, onGone: { dismiss() })
        }
    }
}

/// The worker's profile as a pushed page (from the Team roster): the same body, with the contract discussion as its one popup.
struct StaffProfileView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    var staffID: Int
    @State private var discussing = false

    var body: some View {
        let p: WorkerProfile? = store.engine?.workerProfile(companyID: companyID, employeeID: staffID)
        let age: String = store.engine?.staffProfile(companyID: companyID, staffID: staffID).map { " \u{00B7} age \($0.age)" } ?? ""
        ScrollView {
            WorkerProfileBody(companyID: companyID, employeeID: staffID, showsName: false, onDiscuss: { discussing = true }, onGone: { dismiss() })
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .appScreen(title: p?.name ?? "Profile", subtitle: (p?.roleName ?? "") + age, tab: .company)
        .centerSheet(isPresented: $discussing) { ContractDiscussionView(companyID: companyID, personID: staffID).environmentObject(store) }
    }
}

/// THE profile of one worker, wherever it is shown: who they are and how they feel, one action bar (discuss the contract, warn, and a More
/// menu with talk, paperwork, course, duty and letting go), then pay, what the pay lets you expect, growth, promises, mood, the work,
/// the contract and the record. Figures and outcomes are the engine's (`workerProfile`, `staffProfile`).
struct WorkerProfileBody: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var employeeID: Int
    /// The popup shows the name itself; the pushed page has it in its title.
    var showsName: Bool
    var onDiscuss: () -> Void
    /// Called after the person has left, so the container closes.
    var onGone: () -> Void
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(companyID), let p = e.workerProfile(companyID: companyID, employeeID: employeeID) {
                content(e, co, p, e.staffProfile(companyID: companyID, staffID: employeeID))
            } else {
                EmptyState(glyph: Glyph.person, title: "This person no longer works here.")
            }
        }
        .confirmAction($pending)
    }

    private func content(_ e: GameEngine, _ co: Company, _ p: WorkerProfile, _ s: StaffProfile.Profile?) -> some View {
        let cur: Currency = e.currency(for: co)
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            header(e, p, s)
            actionBar(e, co, p, s, cur)
            figures(p, cur)
            expectation(p)
            WorkerGrowthSection(engine: e, companyID: companyID, employeeID: employeeID)
            promisesSection(e)
            if let s { moodSection(s) } else { moodLines(p.moodBad, p.moodGood) }
            if let s { workSection(s) }
            contractSection(p, s)
            if let s { recordSection(s, cur) }
        }
    }

    // MARK: Header and actions

    private func moodTone(_ word: String) -> AcctPill.Tone {
        ["Leaving", "Unhappy"].contains(word) ? .bad : word == "Happy" ? .good : word == "Mixed" ? .warn : .neutral
    }

    private func tenure(_ weeks: Int) -> String {
        weeks >= 52 ? String(format: "%.1f years here", Double(weeks) / 52) : "\(weeks) weeks here"
    }

    private func header(_ e: GameEngine, _ p: WorkerProfile, _ s: StaffProfile.Profile?) -> some View {
        let dutyID: String = p.duty ?? ""
        let duty: String = dutyID.isEmpty ? "" : " \u{00B7} duty: " + dutyName(e, dutyID)
        let mood: String = s?.mood.word ?? p.mood
        return HStack(alignment: .center, spacing: Theme.Space.m) {
            ThumbnailView(kind: .person, key: p.role, size: 48, initials: p.name, face: e.state.people[employeeID]?.faceKey)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                if showsName { Text(p.name.tidyText).textStyle(.title).lineLimit(1).minimumScaleFactor(0.7) }
                Text((p.roleName + " \u{00B7} " + tenure(p.weeksEmployed) + duty).tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s)
            AcctPill(text: mood, tone: moodTone(mood))
        }
    }

    private func dutyName(_ e: GameEngine, _ id: String) -> String {
        e.recommendedRoles(companyID: companyID).first { (r: RoleOption) -> Bool in r.id == id }?.name ?? id
    }

    /// The one row of actions: discussing the contract is the main one; the rest sit in More, letting go last and marked destructive.
    private func actionBar(_ e: GameEngine, _ co: Company, _ p: WorkerProfile, _ s: StaffProfile.Profile?, _ cur: Currency) -> some View {
        let extras: [RoleOption] = e.recommendedRoles(companyID: companyID).filter { (r: RoleOption) -> Bool in !r.isCore }
        let missing: Int = co.staff.first(where: { $0.id == employeeID }).map { StaffExtras.missing($0).count } ?? 0
        let courses: [StaffProfile.Course] = s?.courses ?? []
        let problem: Bool = s?.problem != nil
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let talk = e.contractTalk(personID: employeeID), talk.isRequest {
                Label("\(p.name) has asked about \(talk.proposal.topic.title.lowercased()).", systemImage: "bubble.left.fill")
                    .textStyle(.body, tint: P.accent, weight: .medium)
            }
            HStack(spacing: Theme.Space.s) {
                Button { Haptics.tap(); onDiscuss() } label: { Text("Discuss contract") }
                    .buttonStyle(PrimaryButtonStyle(size: .compact, fullWidth: true))
                TeamAction(title: "Warn") { warn(p.name) }
                Menu {
                    if problem { Button("Talk to them") { talk() } }
                    if missing > 0 { Button("Paperwork done (\(missing))") { paperwork() } }
                    if let s, !courses.isEmpty {
                        Menu("Send on a course") {
                            ForEach(courses, id: \.id) { (c: StaffProfile.Course) in
                                Button("\(c.name) \u{00B7} \(cur.tidyShort(c.cost))") { confirmCourse(c, s, cur) }
                            }
                        }
                    }
                    if !extras.isEmpty {
                        Menu("Set duty") {
                            Button("No extra duty") { setDuty(nil) }
                            ForEach(extras) { (r: RoleOption) in
                                Button { setDuty(r.id) } label: {
                                    Text(r.name)
                                    if !r.effect.isEmpty { Text(r.effect) }
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Let go\u{2026}", role: .destructive) { confirmDismiss(p, s, cur) }
                } label: {
                    Text("More")
                }
                .menuStyle(.button)
                .buttonStyle(SecondaryButtonStyle(size: .compact))
                .accessibilityLabel("More actions")
            }
        }
    }

    // MARK: Figures and expectation

    private func figures(_ p: WorkerProfile, _ cur: Currency) -> some View {
        let basis: String = p.payBasis == "fix" ? "fixed salary" : "paid by the hour"
        let items: [KeyFigures.Item] = [
            .init(label: "Pay a month", value: cur.tidyShort(p.monthlyWage), sub: basis),
            .init(label: "Hours a week", value: String(Int(p.hoursPerWeek.rounded())), sub: "\(Int(p.hoursWorked.rounded())) worked in all"),
            .init(label: "Contract", value: p.contract?.typeLabel ?? "Permanent", sub: p.contract.map { HireWords.percentText($0.workingPercent) } ?? ""),
        ]
        return FigureRow(items: items, columns: 3, combineCells: true)
            .padding(.vertical, Theme.Space.m)
            .overlay(alignment: .top) { Hairline() }
    }

    /// What the pay lets you expect, against what the work is worth now.
    private func expectation(_ p: WorkerProfile) -> some View {
        let tint: Color = p.meetsExpectation ? P.gain : P.warn
        return LedgerSection(title: "What to expect", trailing: {
            AcctPill(text: p.meetsExpectation ? "Meets it" : "Falls short", tone: p.meetsExpectation ? .good : .warn)
        }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ProgressLine(fraction: p.expectedPerformance / 100, tint: P.inkSoft, label: "Expected for this pay", value: String(Int(p.expectedPerformance.rounded())))
                ProgressLine(fraction: p.performance / 100, tint: tint, label: "Delivers now", value: String(Int(p.performance.rounded())))
                if !p.performanceNote.isEmpty { Text(p.performanceNote.tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    // MARK: Promises

    /// Open promises with what you can do about each; broken ones stay listed with what they cost.
    @ViewBuilder private func promisesSection(_ e: GameEngine) -> some View {
        let open: [WorkerPromise] = e.promises(of: employeeID, companyID: companyID).filter { (x: WorkerPromise) -> Bool in x.isOpen }
        let broken: [StaffPromises.Promise] = e.promises(personID: employeeID).filter { (x: StaffPromises.Promise) -> Bool in x.status == .broken }
        if !open.isEmpty || !broken.isEmpty {
            LedgerSection("Promises") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(open) { (x: WorkerPromise) in promiseRow(x) }
                    ForEach(broken, id: \.id) { (b: StaffPromises.Promise) in
                        LedgerRow(title: b.text, subtitle: b.consequence, value: b.status.rawValue, valueTint: P.loss, density: .compact)
                    }
                }
            }
        }
    }

    private func promiseRow(_ x: WorkerPromise) -> some View {
        let due: Bool = x.status == "Due"
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(x.text.tidyText).textStyle(.body, tint: due ? P.warn : P.ink).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Space.s)
                Text(due ? "Due now" : GameCalendar.dateString(week: x.dueWeek)).textStyle(.caption)
            }
            WrapRow {
                TeamAction(title: "Keep it now") { keep(x) }
                if x.patienceLeft > 0 { TeamAction(title: "Ask to wait", tint: P.inkSoft) { wait(x) } }
                if atRisk(x) { TeamAction(title: "Ask for 4 more weeks", tint: P.inkSoft) { moreTime(x) } }
            }
        }
    }

    // MARK: Mood, work, contract, record

    private func cap(_ t: String) -> String { String(t.prefix(1).uppercased() + t.dropFirst()) }

    private func moodLines(_ bad: [String], _ good: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ForEach(bad, id: \.self) { (t: String) in Label(cap(t), systemImage: "minus.circle").textStyle(.body) }
            ForEach(good, id: \.self) { (t: String) in Label(cap(t), systemImage: "plus.circle").textStyle(.body) }
        }
    }

    private func moodSection(_ s: StaffProfile.Profile) -> some View {
        LedgerSection("Mood") {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                if let pr = s.problem, let t = StaffProfile.problemText[pr] { Text("Problem: this person \(t).").textStyle(.body, tint: P.warn) }
                if s.noticeWeeks > 0 { Text("Working their notice: \(s.noticeWeeks) week\(s.noticeWeeks == 1 ? "" : "s") left.").textStyle(.body, tint: P.loss) }
                moodLines(s.mood.bad, s.mood.good)
                if s.mood.good.isEmpty && s.mood.bad.isEmpty && s.problem == nil { Text("Nothing stands out.").textStyle(.caption) }
            }
        }
    }

    /// What the work log says, in sentences built from what happened. No rating and no figure.
    private func workSection(_ s: StaffProfile.Profile) -> some View {
        LedgerSection("How the work goes") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if s.feedback.enoughToJudge {
                    ForEach(s.feedback.observations) { o in
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(o.aspect).textStyle(.caption, tint: P.inkFaint)
                            Text(o.text).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text(s.feedback.summary).textStyle(.body, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
                if s.disengaged { Label("Seems to have lost interest in the work.", systemImage: "moon.zzz").textStyle(.body, tint: P.warn) }
                if s.skillGainedSinceStart { Text("Has learned new things here.").textStyle(.caption) }
            }
        }
    }

    /// The employment contract: type, percentage, real dates, notice and the latest changes.
    @ViewBuilder private func contractSection(_ p: WorkerProfile, _ s: StaffProfile.Profile?) -> some View {
        if let c = s?.contract {
            let recent: [ContractHistory.Entry] = Array(c.history.suffix(4).reversed())
            LedgerSection("Contract") {
                VStack(spacing: 0) {
                    FlatRow(label: "Type", value: c.typeLabel, sub: c.payBasisLabel, rule: false)
                    FlatRow(label: "Working", value: HireWords.percentText(c.workingPercent), sub: HireWords.hours(c.contractedHoursPerWeek))
                    FlatRow(label: "Started", value: GameCalendar.dateString(week: c.startWeek))
                    if let end = c.endWeek { FlatRow(label: "Ends", value: GameCalendar.dateString(week: end)) }
                    if !c.seasonText.isEmpty { FlatRow(label: "Season", value: c.seasonText, sub: c.onSeason ? "On season now" : "Off season now") }
                    FlatRow(label: "Notice", value: "\(HireWords.weeksText(c.resignationNoticeWeeks)) from them", sub: "From you: \(String(format: "%g", c.employerNoticeWeeks)) weeks without cause")
                    ForEach(recent) { h in FlatRow(label: h.text, value: GameCalendar.dateString(week: h.week)) }
                }
            }
        } else if let c = p.contract {
            LedgerSection("Contract") {
                FlatRow(label: c.typeLabel, value: HireWords.percentText(c.workingPercent),
                        sub: c.endWeek.map { (w: Int) -> String in "Ends " + GameCalendar.dateString(week: w) } ?? "", rule: false)
            }
        }
    }

    private func recordSection(_ s: StaffProfile.Profile, _ cur: Currency) -> some View {
        let week: Int = store.engine?.state.week ?? 0
        let raise: String = s.lastRaiseWeek.map { "\(max(0, week - $0)) weeks ago" } ?? "never"
        return LedgerSection("Record") {
            VStack(spacing: 0) {
                FlatRow(label: "Last raise", value: raise, sub: s.underpaid ? "Paid less than the job usually pays" : "", rule: false)
                if let plan = s.bonusPlan { FlatRow(label: "Bonus plan", value: plan, sub: s.bonusPaidThisYear > 0 ? "\(cur.tidyShort(s.bonusPaidThisYear)) paid this year" : "Nothing paid yet this year") }
                if !s.perks.isEmpty { FlatRow(label: "Perks", value: s.perks.joined(separator: ", "), sub: "Worth about \(cur.tidyShort(s.perksWorth)) a month to them, counted as pay") }
                if !s.expenses.isEmpty { FlatRow(label: "Expenses paid", value: s.expenses.joined(separator: ", ")) }
                FlatRow(label: "Written warnings", value: "\(s.warnings)", sub: s.dismissalDocumented ? "Enough on file to let them go for cause" : "")
            }
        }
    }

    // MARK: What the actions do

    private func talk() {
        let cid = companyID, eid = employeeID
        let ok = store.act { $0.talkToStaff(companyID: cid, staffID: eid) } ?? nil
        Haptics.tap()
        store.show(ok == true ? "The talk helped: the problem is gone." : "The talk did not help. A warning is noted.", tone: ok == true ? "good" : "warn")
    }

    private func warn(_ name: String) {
        let cid = companyID, eid = employeeID
        let worked = store.act { $0.warnStaff(companyID: cid, staffID: eid) } ?? nil
        if worked == nil { Haptics.warning(); store.show("The warning could not be given now.", tone: "warn"); return }
        Haptics.tap()
        store.show(worked == true ? "The warning worked. \(name) has improved." : "Warning on file for \(name).", tone: worked == true ? "good" : "n")
    }

    private func paperwork() {
        let cid = companyID, eid = employeeID
        let done = store.act { $0.completePaperwork(companyID: cid, personID: eid) } ?? 0
        if done > 0 { Haptics.success(); store.show("Paperwork done: \(done) \(done == 1 ? "item" : "items") ticked.", tone: "good") } else { Haptics.warning(); store.show("Nothing could be ticked.", tone: "warn") }
    }

    private func confirmCourse(_ c: StaffProfile.Course, _ s: StaffProfile.Profile, _ cur: Currency) {
        pending = PendingAction(title: "Send \(s.name) on \(c.name)?", message: "Costs \(cur.tidyDisplay(c.cost)) from company cash. \(c.benefit) It may also change nothing, and a good result may tempt a competitor to poach them.", button: "Send for \(cur.tidyShort(c.cost))", amount: c.cost, currency: cur) { course(c) }
    }

    private func course(_ c: StaffProfile.Course) {
        let cid = companyID, eid = employeeID
        let r: StaffProfile.CourseResult? = store.act { $0.sendOnCourse(companyID: cid, staffID: eid, courseID: c.id) }
        switch r {
        case .done(let msg)?: Haptics.success(); store.show("\(c.name): \(msg).", tone: "good")
        case .cash?: Haptics.warning(); store.show("Not enough cash for \(c.name).", tone: "warn")
        case nil: break
        default: Haptics.warning(); store.show("That course is not available.", tone: "warn")
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

    private func confirmDismiss(_ p: WorkerProfile, _ s: StaffProfile.Profile?, _ cur: Currency) {
        let documented: Bool = s?.dismissalDocumented ?? false
        let range: String = s.map { (x: StaffProfile.Profile) -> String in " and win \(cur.tidyShort(x.compensationRange.lowerBound)) to \(cur.tidyShort(x.compensationRange.upperBound))" } ?? ""
        let risk: String = documented ? "Two warnings or theft are on file, so this is easy to defend." : "Nothing documented: they may claim unfair dismissal\(range)."
        let sev: String = cur.tidyDisplay(s?.severance ?? 0)
        let cid = companyID, eid = employeeID, name = p.name
        let gone: () -> Void = onGone
        pending = PendingAction(title: "Let \(name) go?", message: "Notice and severance of \(sev) is paid. \(risk)", button: "Let go", destructive: true) {
            guard let r = store.act({ $0.dismissStaff(companyID: cid, staffID: eid) }) ?? nil else { store.show("They no longer work here.", tone: "warn"); gone(); return }
            Haptics.warning()
            store.show(r.claimedUnfairDismissal ? "\(name) is gone, and claimed unfair dismissal: \(cur.tidyDisplay(r.compensation)) paid on top of \(cur.tidyDisplay(r.severance)) severance." : (r.severance > 0 ? "\(name) has left. Severance paid: \(cur.tidyDisplay(r.severance))." : "\(name) has left."), tone: r.claimedUnfairDismissal ? "bad" : "n")
            gone()
        }
    }
}
