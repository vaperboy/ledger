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

/// The worker's profile as a popup (from the inbox): the same `WorkerProfileBody` as the pushed page, with the actions inline.
/// The contract discussion replaces the profile inside this popup (its close steps back to the profile) instead of opening a second popup.
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
            WorkerProfileBody(companyID: companyID, employeeID: employeeID, showsName: true, inlineActions: true, onDiscuss: { discussing = true }, onGone: { dismiss() })
        }
    }
}

/// The worker's profile as a pushed page (from the Team roster): the same body, with Discuss contract pinned at the bottom.
struct StaffProfileView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
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
            WorkerProfileBody(companyID: companyID, employeeID: staffID, showsName: false, inlineActions: false, onDiscuss: { discussing = true }, onGone: { dismiss() })
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if p != nil {
                WorkerActionBar(companyID: companyID, employeeID: staffID, onDiscuss: { discussing = true }, onGone: { dismiss() })
                    .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.m)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
                    .background(P.page)
                    .overlay(alignment: .top) { Hairline() }
            }
        }
        .appScreen(title: p?.name ?? "Profile", subtitle: (p?.roleName ?? "") + age, tab: .company)
        .centerSheet(isPresented: $discussing, category: .detail, tone: .info) { ContractDiscussionView(companyID: companyID, personID: staffID).environmentObject(store) }
    }
}

/// The one action of a profile, Discuss contract, with every other action (warn, talk, course, duty, letting go last) in a "…" menu.
struct WorkerActionBar: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var employeeID: Int
    var onDiscuss: () -> Void
    /// Called after the person has left, so the container closes.
    var onGone: () -> Void
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(companyID), let p = e.workerProfile(companyID: companyID, employeeID: employeeID) {
                bar(e, co, p, e.staffProfile(companyID: companyID, staffID: employeeID), e.currency(for: co))
            }
        }
        .confirmAction($pending)
    }

    private func bar(_ e: GameEngine, _ co: Company, _ p: WorkerProfile, _ s: StaffProfile.Profile?, _ cur: Currency) -> some View {
        let extras: [RoleOption] = e.recommendedRoles(companyID: companyID).filter { (r: RoleOption) -> Bool in !r.isCore }
        let courses: [StaffProfile.Course] = s?.courses ?? []
        let problem: Bool = s?.problem != nil
        return HStack(spacing: Theme.Space.s) {
            Button { Haptics.tap(); onDiscuss() } label: { Text("Discuss contract") }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("worker-discuss")
            Menu {
                Button("Give a written warning") { warn(p.name) }
                if problem { Button("Talk to them") { talk() } }
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
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).frame(width: 22)
            }
            .menuStyle(.button)
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel("More actions")
            .accessibilityIdentifier("worker-more")
        }
    }

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

    private func confirmCourse(_ c: StaffProfile.Course, _ s: StaffProfile.Profile, _ cur: Currency) {
        pending = PendingAction(title: "Send \(s.name) on \(c.name)?", message: "Costs \(cur.tidyDisplay(c.cost)) from company cash. \(c.benefit) It may also change nothing, and a good result may tempt a competitor to poach them.", button: "Send for \(cur.tidyShort(c.cost))", amount: c.cost, currency: cur, tone: .info, icon: "graduationcap") { course(c) }
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

    private func confirmDismiss(_ p: WorkerProfile, _ s: StaffProfile.Profile?, _ cur: Currency) {
        let documented: Bool = s?.dismissalDocumented ?? false
        let range: String = s.map { (x: StaffProfile.Profile) -> String in " and win \(cur.tidyShort(x.compensationRange.lowerBound)) to \(cur.tidyShort(x.compensationRange.upperBound))" } ?? ""
        let risk: String = documented ? "Two warnings or theft are on file, so this is easy to defend." : "Nothing documented: they may claim unfair dismissal\(range)."
        let sev: String = cur.tidyDisplay(s?.severance ?? 0)
        let cid = companyID, eid = employeeID, name = p.name
        let gone: () -> Void = onGone
        pending = PendingAction(title: "Let \(name) go?", message: "Notice and severance of \(sev) is paid. \(risk)", button: "Let go", destructive: true, tone: .danger, icon: "person.fill.xmark") {
            guard let r = store.act({ $0.dismissStaff(companyID: cid, staffID: eid) }) ?? nil else { store.show("They no longer work here.", tone: "warn"); gone(); return }
            Haptics.warning()
            store.show(r.claimedUnfairDismissal ? "\(name) is gone, and claimed unfair dismissal: \(cur.tidyDisplay(r.compensation)) paid on top of \(cur.tidyDisplay(r.severance)) severance." : (r.severance > 0 ? "\(name) has left. Severance paid: \(cur.tidyDisplay(r.severance))." : "\(name) has left."), tone: r.claimedUnfairDismissal ? "bad" : "n")
            gone()
        }
    }
}

/// THE profile of one worker, wherever it is shown. A hero (portrait, role, mood, and the monthly pay as the one big figure), their request
/// when they have one, then what the pay lets you expect, growth, promises, why they feel as they do and how the work goes. The contract and
/// the record open under one row. Figures and outcomes are the engine's (`workerProfile`, `staffProfile`).
struct WorkerProfileBody: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var employeeID: Int
    /// The popup shows the name itself; the pushed page has it in its title.
    var showsName: Bool
    /// The popup has no pinned bar: the actions sit under the hero.
    var inlineActions: Bool = true
    var onDiscuss: () -> Void
    /// Called after the person has left, so the container closes.
    var onGone: () -> Void
    @State private var showDetails = false

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let p = e.workerProfile(companyID: companyID, employeeID: employeeID) {
            content(e, co, p, e.staffProfile(companyID: companyID, staffID: employeeID))
        } else {
            EmptyState(glyph: Glyph.person, title: "This person no longer works here.")
        }
    }

    private func content(_ e: GameEngine, _ co: Company, _ p: WorkerProfile, _ s: StaffProfile.Profile?) -> some View {
        let cur: Currency = e.currency(for: co)
        return VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                hero(e, p, s, cur)
                if let talk = e.contractTalk(personID: employeeID), talk.isRequest { requestCard(p, talk.proposal.topic.title) }
                if inlineActions { WorkerActionBar(companyID: companyID, employeeID: employeeID, onDiscuss: onDiscuss, onGone: onGone) }
            }
            expectation(p)
            WorkerGrowthSection(engine: e, companyID: companyID, employeeID: employeeID)
            promisesSection(e)
            if let s { moodSection(s) } else if !p.moodBad.isEmpty || !p.moodGood.isEmpty { TeamBlock("Why they feel this way") { moodLines(p.moodBad, p.moodGood) } }
            if let s { workSection(s) }
            details(p, s, cur, extras: e.staffTermsUnlocked(companyID: companyID))
        }
    }

    // MARK: Hero

    private func tenure(_ weeks: Int) -> String {
        weeks >= 52 ? String(format: "%.1f years here", Double(weeks) / 52) : "\(weeks) weeks here"
    }

    private func dutyName(_ e: GameEngine, _ id: String) -> String {
        e.recommendedRoles(companyID: companyID).first { (r: RoleOption) -> Bool in r.id == id }?.name ?? id
    }

    /// Who they are and how they feel, then the pay as the one big figure with hours and contract as its context line.
    private func hero(_ e: GameEngine, _ p: WorkerProfile, _ s: StaffProfile.Profile?, _ cur: Currency) -> some View {
        let dutyID: String = p.duty ?? ""
        let duty: String = dutyID.isEmpty ? "" : " \u{00B7} duty: " + dutyName(e, dutyID)
        let mood: String = s?.mood.word ?? p.mood
        let basis: String = p.payBasis == "fix" ? "fixed salary" : "paid by the hour"
        let contract: String = (p.contract?.typeLabel ?? "Permanent") + (p.contract.map { ", " + HireWords.percentText($0.workingPercent) } ?? "")
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                ThumbnailView(kind: .person, key: p.role, size: 56, initials: p.name, face: e.state.people[employeeID]?.faceKey)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    if showsName { Text(p.name.tidyText).textStyle(.title).lineLimit(1).minimumScaleFactor(0.7) }
                    Text((p.roleName + " \u{00B7} " + tenure(p.weeksEmployed) + duty).tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                    Text(mood).textStyle(.headline, tint: ThinPersonRow.moodTint(mood, P))
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            TeamHero(value: cur.tidyShort(p.monthlyWage), unit: "a month",
                     context: "\(basis.prefix(1).uppercased() + basis.dropFirst()) \u{00B7} \(Int(saturating: p.hoursPerWeek.rounded())) h a week \u{00B7} \(contract)")
        }
    }

    /// Their open request: the one card of the page (it needs you); Discuss contract answers it.
    private func requestCard(_ p: WorkerProfile, _ topic: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: "bubble.left.fill").foregroundStyle(P.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("\(HireWords.first(p.name)) has asked about \(topic.lowercased())").textStyle(.headline)
                Text("Discuss the contract to answer.").textStyle(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.surfaceRaised))
    }

    // MARK: Expectation

    /// What the pay lets you expect, against what the work is worth now.
    private func expectation(_ p: WorkerProfile) -> some View {
        let tint: Color = p.meetsExpectation ? P.gain : P.caution
        return TeamBlock(title: "What the pay buys", trailing: {
            Text(p.meetsExpectation ? "Meets it" : "Falls short").textStyle(.caption, tint: tint, weight: .medium)
        }) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                ProgressLine(fraction: p.expectedPerformance / 100, tint: P.inkSoft, label: "Expected for this pay", value: Words.level(p.expectedPerformance, scale: .quality))
                ProgressLine(fraction: p.performance / 100, tint: tint, label: "Delivers now", value: Words.level(p.performance, scale: .quality))
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
            TeamBlock("Promises") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(open.enumerated()), id: \.element.id) { (n: Int, x: WorkerPromise) in
                        if n > 0 { Hairline() }
                        promiseRow(x)
                    }
                    ForEach(broken, id: \.id) { (b: StaffPromises.Promise) in
                        Hairline()
                        LedgerRow(title: b.text, subtitle: b.consequence, value: b.status.rawValue, valueTint: P.loss, density: .compact)
                    }
                }
            }
        }
    }

    private func promiseRow(_ x: WorkerPromise) -> some View {
        let due: Bool = x.status == "Due"
        return VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(x.text.tidyText).textStyle(.headline, tint: due ? P.caution : P.ink).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Space.s)
                Text(due ? "Due now" : GameCalendar.dateString(week: x.dueWeek)).textStyle(.caption, tint: due ? P.caution : nil)
            }
            HStack(spacing: Theme.Space.xs) {
                Button("Keep it now") { keep(x) }.buttonStyle(TertiaryButtonStyle(size: .compact))
                if x.patienceLeft > 0 { Button("Ask to wait") { wait(x) }.buttonStyle(TertiaryButtonStyle(size: .compact, tint: P.inkSoft)) }
                if atRisk(x) { Button("Ask for 4 more weeks") { moreTime(x) }.buttonStyle(TertiaryButtonStyle(size: .compact, tint: P.inkSoft)) }
                Spacer(minLength: 0)
            }
            .padding(.leading, -Theme.Space.s)
        }
        .padding(.vertical, Theme.Space.s)
    }

    // MARK: Mood and work

    private func cap(_ t: String) -> String { String(t.prefix(1).uppercased() + t.dropFirst()) }

    private func moodLines(_ bad: [String], _ good: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(bad, id: \.self) { (t: String) in reason(cap(t), good: false) }
            ForEach(good, id: \.self) { (t: String) in reason(cap(t), good: true) }
        }
    }

    private func reason(_ text: String, good: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Image(systemName: good ? "plus" : "minus").font(.system(size: 11, weight: .bold)).foregroundStyle(good ? P.gain : P.caution).frame(width: 14)
                .accessibilityHidden(true)
            Text(text.tidyText).textStyle(.body).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func moodSection(_ s: StaffProfile.Profile) -> some View {
        TeamBlock("Why they feel this way") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if let pr = s.problem, let t = StaffProfile.problemText[pr] { Text("Problem: this person \(t).").textStyle(.body, tint: P.caution).fixedSize(horizontal: false, vertical: true) }
                if s.noticeWeeks > 0 { Text("Working their notice: \(s.noticeWeeks) week\(s.noticeWeeks == 1 ? "" : "s") left.").textStyle(.body, tint: P.loss) }
                moodLines(s.mood.bad, s.mood.good)
                if s.mood.good.isEmpty && s.mood.bad.isEmpty && s.problem == nil { Text("Nothing stands out.").textStyle(.caption) }
            }
        }
    }

    /// What the work log says, in sentences built from what happened. No rating and no figure.
    private func workSection(_ s: StaffProfile.Profile) -> some View {
        TeamBlock("How the work goes") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
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
                if s.disengaged { Text("Seems to have lost interest in the work.").textStyle(.body, tint: P.caution) }
                if s.skillGainedSinceStart { Text("Has learned new things here.").textStyle(.caption) }
            }
        }
    }

    // MARK: Contract and record (one row that opens them)

    /// `extras`: bonus, perks and paid expenses show only once the company has five staff or a manager.
    private func details(_ p: WorkerProfile, _ s: StaffProfile.Profile?, _ cur: Currency, extras: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            Button {
                Haptics.choose()
                Motion.animate(Motion.quickAnimation) { showDetails.toggle() }
            } label: {
                HStack(spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text("Contract and record").textStyle(.headline)
                        Text(extras ? "Dates, notice, raises, bonus, perks, warnings" : "Dates, notice, raises, warnings").textStyle(.caption)
                    }
                    Spacer(minLength: Theme.Space.s)
                    LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint).rotationEffect(.degrees(showDetails ? 90 : 0))
                }
                .padding(.vertical, Theme.Space.m)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("worker-details")
            if showDetails {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    contractSection(p, s)
                    if let s { recordSection(s, p, cur, extras: extras) }
                }
                .padding(.top, Theme.Space.s)
            }
            Hairline()
        }
    }

    /// The employment contract: type, percentage, real dates, notice and the latest changes.
    @ViewBuilder private func contractSection(_ p: WorkerProfile, _ s: StaffProfile.Profile?) -> some View {
        if let c = s?.contract {
            let recent: [ContractHistory.Entry] = Array(c.history.suffix(4).reversed())
            TeamBlock("Contract") {
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
            TeamBlock("Contract") {
                FlatRow(label: c.typeLabel, value: HireWords.percentText(c.workingPercent),
                        sub: c.endWeek.map { (w: Int) -> String in "Ends " + GameCalendar.dateString(week: w) } ?? "", rule: false)
            }
        }
    }

    private func recordSection(_ s: StaffProfile.Profile, _ p: WorkerProfile, _ cur: Currency, extras: Bool) -> some View {
        let week: Int = store.engine?.state.week ?? 0
        let raise: String = s.lastRaiseWeek.map { "\(max(0, week - $0)) weeks ago" } ?? "never"
        return TeamBlock("Record") {
            VStack(spacing: 0) {
                FlatRow(label: "Last raise", value: raise, sub: s.underpaid ? "Paid less than the job usually pays" : "", rule: false)
                FlatRow(label: "Hours worked", value: "\(Int(saturating: p.hoursWorked.rounded()))", sub: "In all, since they started")
                if extras, let plan = s.bonusPlan { FlatRow(label: "Bonus plan", value: plan, sub: s.bonusPaidThisYear > 0 ? "\(cur.tidyShort(s.bonusPaidThisYear)) paid this year" : "Nothing paid yet this year") }
                if extras, !s.perks.isEmpty { FlatRow(label: "Perks", value: s.perks.joined(separator: ", "), sub: "Worth about \(cur.tidyShort(s.perksWorth)) a month to them, counted as pay") }
                if extras, !s.expenses.isEmpty { FlatRow(label: "Expenses paid", value: s.expenses.joined(separator: ", ")) }
                FlatRow(label: "Written warnings", value: "\(s.warnings)", sub: s.dismissalDocumented ? "Enough on file to let them go for cause" : "")
            }
        }
    }

    // MARK: What the promise actions do

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
}
