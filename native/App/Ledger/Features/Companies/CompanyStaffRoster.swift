import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

private func roleLabel(_ id: String) -> String { id.prefix(1).uppercased() + id.dropFirst() }

/// What is wrong with one team member, from fields the engine keeps on them. Empty means nothing to act on.
enum StaffIssue {
    static func list(_ m: StaffMember) -> [String] {
        var out: [String] = []
        if m.noticeWeeks > 0 { out.append("on notice") }
        if let f = m.value("flag").isNull ? nil : m.str("flag"), let t = StaffProfile.problemText[f] { out.append(t) }
        if m.sickUntilWeek != nil { out.append("off sick") }
        if m.tiredness > 60 { out.append("tired") }
        let papers = StaffExtras.missing(m).count
        if papers > 0 { out.append("\(papers) papers missing") }
        if m.int("warn") > 0 { out.append("\(m.int("warn")) warning\(m.int("warn") == 1 ? "" : "s")") }
        return out
    }
    /// Only the ones that need the owner (a warning on file alone does not).
    static func needsAttention(_ m: StaffMember) -> Bool { list(m).contains { !$0.hasSuffix("warning") && !$0.hasSuffix("warnings") } }
}

/// The company's own staff: paperwork first, then people who need attention, then everyone else, grouped by role once the team is big.
/// A tap pushes the person's profile, where every action on them lives. The head count and the wage total are shown by the Team tab.
struct CompanyStaffRoster: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var company: Company
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var pending: PendingAction?
    /// The worker whose profile page is pushed; the Team tab owns the push so it outlives this list.
    @Binding var profile: WorkerRef?

    var body: some View {
        let cur = engine.currency(for: company)
        let staff = company.staff
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = staff.filter { q.isEmpty || name($0).lowercased().contains(q) || roleLabel($0.role).lowercased().contains(q) }
        let attention = shown.filter(StaffIssue.needsAttention)
        let rest = shown.filter { !StaffIssue.needsAttention($0) }
        let big = staff.count > 8
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if staff.count > 12 { LedgerField(placeholder: "Search by name or role", text: $query) }
            paperwork
            if !attention.isEmpty {
                Text("Needs attention \u{00B7} \(attention.count)").textStyle(.label, tint: P.warn)
                ForEach(attention) { m in row(m, cur) }
            }
            if big {
                let groups = Dictionary(grouping: rest, by: { $0.role }).sorted { $0.value.count > $1.value.count }
                ForEach(groups, id: \.key) { role, members in
                    let open = expanded.contains(role) || !q.isEmpty
                    let pay: String = cur.tidyShort(members.reduce(0) { $0 + $1.monthlyWage }) + " a month"
                    Button {
                        Haptics.choose()
                        Motion.animate(Motion.quickAnimation) { if open { expanded.remove(role) } else { expanded.insert(role) } }
                    } label: {
                        CardRowLabel(title: roleLabel(role), subtitle: "\(members.count) \(members.count == 1 ? "person" : "people")", value: pay, open: open)
                    }.buttonStyle(PressableStyle())
                    if open { ForEach(members) { m in row(m, cur) } }
                }
            } else {
                ForEach(rest) { m in row(m, cur) }
            }
            if !q.isEmpty && shown.isEmpty { EmptyState(glyph: Glyph.search, title: "No one matches \"\(query)\"", centered: false) }
            layOffRow(cur)
        }
        .confirmAction($pending)
    }

    private func name(_ m: StaffMember) -> String { engine.state.people[m.id]?.name ?? roleLabel(m.role) }

    private func row(_ m: StaffMember, _ cur: Currency) -> some View {
        let issues: [String] = StaffIssue.list(m)
        let attention: Bool = StaffIssue.needsAttention(m)
        let note: String = issues.isEmpty ? "" : issues.joined(separator: " \u{00B7} ")
        let wage: String = cur.tidyShort(m.monthlyWage)
        let id: Int = m.id
        return Button { Haptics.tap(); profile = WorkerRef(id: id) } label: {
            ThinPersonRow(name: name(m), title: roleLabel(m.role), note: note, noteTint: attention ? P.warn : P.inkFaint, wage: wage, roleKey: m.role,
                          face: engine.state.people[m.id]?.faceKey)
        }.buttonStyle(PressableStyle())
    }

    /// Missing paperwork across the team, with one action that ticks it all. Nothing when every file is complete.
    @ViewBuilder private var paperwork: some View {
        let staff = company.staff
        let papers = staff.reduce(0) { $0 + StaffExtras.missing($1).count }
        if papers > 0 {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                LedgerGlyph(glyph: Glyph.warning, size: Theme.Icon.medium, tint: P.warn)
                Text("\(papers) paperwork \(papers == 1 ? "item" : "items") missing. An inspection can fine you.").textStyle(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Space.s)
                TeamAction(title: "Do all") {
                    var done = 0
                    for m in staff { done += store.act({ $0.completePaperwork(companyID: company.id, personID: m.id) }) ?? 0 }
                    let left = store.engine?.state.company(company.id).map { $0.staff.reduce(0) { $0 + StaffExtras.missing($1).count } } ?? papers
                    if done > 0 && left == 0 { Haptics.success(); store.show("Paperwork done: \(done) \(done == 1 ? "item" : "items") ticked.", tone: "good") }
                    else if done > 0 { Haptics.warning(); store.show("\(done) \(done == 1 ? "item" : "items") ticked; \(left) still missing.", tone: "warn") }
                    else { Haptics.warning(); store.show("Nothing could be ticked.", tone: "warn") }
                }
            }
            .padding(.vertical, Theme.Space.xs)
        }
    }

    /// Cutting costs: a quiet row at the end of the list whose menu picks how many of the weakest go; each choice asks first.
    @ViewBuilder private func layOffRow(_ cur: Currency) -> some View {
        let staff = company.staff
        if staff.count > 1 {
            Menu {
                ForEach([1, 2, 3, 5].filter { $0 < staff.count }, id: \.self) { n in
                    let p = engine.layoffPreview(companyID: company.id, count: n)
                    Button("\(n) \u{00B7} saves \(cur.tidyShort(p.savesPerMonth)) a month") { confirmLayOff(n, p, cur) }
                }
            } label: {
                LedgerRow(leading: .symbol("person.fill.badge.minus"), leadingTint: P.loss, title: "Lay off the weakest",
                          subtitle: "Cuts the wage bill; severance is paid now", chevron: true)
            }
            .overlay(alignment: .top) { Hairline() }
            .padding(.top, Theme.Space.s)
        }
    }

    private func confirmLayOff(_ n: Int, _ p: (names: [String], savesPerMonth: Double, severance: Double), _ cur: Currency) {
        pending = PendingAction(title: "Lay off \(n) \(n == 1 ? "person" : "people")?", message: "\(p.names.joined(separator: ", ")). Saves \(cur.tidyDisplay(p.savesPerMonth)) a month; severance of \(cur.tidyDisplay(p.severance)) is paid now and the mood of the rest drops.", button: "Lay off", destructive: true) {
            let ids = store.act { $0.layOffStaff(companyID: company.id, count: n) } ?? []
            Haptics.warning()
            store.show(ids.isEmpty ? "No one was let go." : "\(ids.count) \(ids.count == 1 ? "person" : "people") let go: \(cur.tidyDisplay(p.savesPerMonth)) a month saved, severance \(cur.tidyDisplay(p.severance)) paid. The rest are shaken.", tone: ids.isEmpty ? "warn" : "n")
        }
    }
}

// MARK: Profile

/// One person: how they feel and why, their record, and everything the owner can do about them. Uses the engine's `staffProfile`.
struct StaffProfileView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    var staffID: Int
    @State private var pending: PendingAction?
    @State private var discussing = false

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let m = co.staff.first(where: { $0.id == staffID }), let p = e.staffProfile(companyID: companyID, staffID: staffID) {
            let cur = e.currency(for: co)
            let sub: String = "\(p.roleName) \u{00B7} age \(p.age)"
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    header(p, co, cur)
                    mood(p)
                    performance(p)
                    contractSection(p, cur)
                    promisesSection(e)
                    record(p, m, cur)
                    actions(e, co, m, p, cur)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .appScreen(title: p.name, subtitle: sub, tab: .company)
            .confirmAction($pending)
            .centerSheet(isPresented: $discussing) { ContractDiscussionView(companyID: companyID, personID: staffID).environmentObject(store) }
        } else {
            Text("This person no longer works here.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    private func header(_ p: StaffProfile.Profile, _ co: Company, _ cur: Currency) -> some View {
        let basis: String = p.payBasis == "fix" ? "fixed, a month" : "by the hour, a month"
        let tenure: String = p.weeksWithYou >= 52 ? String(format: "%.1f yr", Double(p.weeksWithYou) / 52) : "\(p.weeksWithYou) wk"
        let items: [KeyFigures.Item] = [
            .init(label: "Pay", value: cur.tidyShort(p.monthlyWage), sub: basis),
            .init(label: "Contract", value: p.contract?.typeLabel ?? "Permanent", sub: p.contract.map { HireWords.percentText($0.workingPercent) } ?? ""),
            .init(label: "With you", value: tenure, sub: p.skillGainedSinceStart ? "has learned new things here" : ""),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ThumbnailView(kind: .person, key: p.role, size: 48, initials: p.name, face: store.engine?.state.people[staffID]?.faceKey)
                VStack(alignment: .leading, spacing: 4) {
                    Text(co.name).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    HStack(spacing: 5) {
                        TeamBadge(text: p.roleName, tint: Theme.gold)
                        TeamBadge(text: "company")
                    }
                }
                Spacer(minLength: 0)
            }
            Card(padding: 14, radius: Theme.Radius.hero) { KeyFigures(items: items) }
        }
    }

    /// What the work log says, in sentences built from what happened. No rating and no figure.
    private func performance(_ p: StaffProfile.Profile) -> some View {
        TeamGroup("How the work goes") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(alignment: .leading, spacing: 6) {
                    if p.feedback.enoughToJudge {
                        ForEach(p.feedback.observations) { o in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(o.aspect).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                Text(o.text).font(.system(size: 13)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        Text(p.feedback.summary).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    }
                    if p.disengaged { Label("Seems to have lost interest in the work.", systemImage: "moon.zzz").font(.system(size: 12.5)).foregroundStyle(Theme.caution) }
                }
            }
        }
    }

    /// The employment contract: type, percentage, real dates, notice and the history of every change.
    @ViewBuilder private func contractSection(_ p: StaffProfile.Profile, _ cur: Currency) -> some View {
        if let c = p.contract {
            TeamGroup(title: "Contract", trailing: { TeamAction(title: "Discuss") { discussing = true } }) {
                Card(padding: 14, radius: Theme.Radius.row) {
                    VStack(spacing: 0) {
                        FlatRow(label: "Type", value: c.typeLabel, sub: c.payBasisLabel, rule: false)
                        FlatRow(label: "Working", value: HireWords.percentText(c.workingPercent), sub: HireWords.hours(c.contractedHoursPerWeek))
                        FlatRow(label: "Started", value: GameCalendar.dateString(week: c.startWeek))
                        if let end = c.endWeek { FlatRow(label: "Ends", value: GameCalendar.dateString(week: end)) }
                        if !c.seasonText.isEmpty { FlatRow(label: "Season", value: c.seasonText, sub: c.onSeason ? "On season now" : "Off season now") }
                        FlatRow(label: "Notice", value: "\(HireWords.weeksText(c.resignationNoticeWeeks)) from them", sub: "From you: \(String(format: "%g", c.employerNoticeWeeks)) weeks without cause")
                        historyRows(c)
                    }
                }
            }
        }
    }

    @ViewBuilder private func historyRows(_ c: EmploymentContract.Summary) -> some View {
        let recent: [ContractHistory.Entry] = Array(c.history.suffix(4).reversed())
        ForEach(recent) { h in FlatRow(label: h.text, value: GameCalendar.dateString(week: h.week)) }
    }

    /// Promises made to this person (the whole list is Company > Team > Promises).
    @ViewBuilder private func promisesSection(_ e: GameEngine) -> some View {
        let list: [StaffPromises.Promise] = e.promises(personID: staffID).filter { $0.isOpen || $0.status == .broken }
        if !list.isEmpty {
            TeamGroup("Promises") {
                Card(padding: 14, radius: Theme.Radius.row) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, pr in
                            FlatRow(label: pr.text, value: pr.status.rawValue, sub: pr.consequence, tint: pr.status == .broken ? Theme.loss : pr.status == .due ? Theme.caution : Theme.ivory, rule: i > 0)
                        }
                    }
                }
            }
        }
    }

    private func mood(_ p: StaffProfile.Profile) -> some View {
        let tint: Color = ["Leaving", "Unhappy"].contains(p.mood.word) ? Theme.loss : p.mood.word == "Happy" ? Theme.gain : p.mood.word == "Mixed" ? Theme.caution : Theme.ivoryMuted
        return TeamGroup(title: "Mood", trailing: { Chip(text: p.mood.word, tint: tint) }) {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(alignment: .leading, spacing: 5) {
                    if let pr = p.problem, let t = StaffProfile.problemText[pr] { Text("Problem: this person \(t).").font(.system(size: 13)).foregroundStyle(Theme.caution) }
                    if p.noticeWeeks > 0 { Text("Working their notice: \(p.noticeWeeks) week\(p.noticeWeeks == 1 ? "" : "s") left.").font(.system(size: 13)).foregroundStyle(Theme.loss) }
                    ForEach(p.mood.bad, id: \.self) { Label(String($0.prefix(1).uppercased() + $0.dropFirst()), systemImage: "minus.circle").font(.system(size: 13)).foregroundStyle(Theme.ivory) }
                    ForEach(p.mood.good, id: \.self) { Label(String($0.prefix(1).uppercased() + $0.dropFirst()), systemImage: "plus.circle").font(.system(size: 13)).foregroundStyle(Theme.ivory) }
                    if p.mood.good.isEmpty && p.mood.bad.isEmpty && p.problem == nil { Text("Nothing stands out.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint) }
                }
            }
        }
    }

    private func record(_ p: StaffProfile.Profile, _ m: StaffMember, _ cur: Currency) -> some View {
        let week: Int = store.engine?.state.week ?? 0
        let raise: String = p.lastRaiseWeek.map { "\(max(0, week - $0)) weeks ago" } ?? "never"
        return TeamGroup("Record") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Hours a week", value: "\(Int(p.hoursPerWeek.rounded()))", rule: false)
                    FlatRow(label: "Last raise", value: raise, sub: p.underpaid ? "Paid less than the job usually pays" : "")
                    if let plan = p.bonusPlan { FlatRow(label: "Bonus plan", value: plan, sub: p.bonusPaidThisYear > 0 ? "\(cur.tidyShort(p.bonusPaidThisYear)) paid this year" : "Nothing paid yet this year") }
                    if !p.perks.isEmpty { FlatRow(label: "Perks", value: p.perks.joined(separator: ", "), sub: "Worth about \(cur.tidyShort(p.perksWorth)) a month to them, counted as pay") }
                    if !p.expenses.isEmpty { FlatRow(label: "Expenses paid", value: p.expenses.joined(separator: ", ")) }
                    FlatRow(label: "Written warnings", value: "\(p.warnings)", sub: p.dismissalDocumented ? "Enough on file to let them go for cause" : "")
                }
            }
        }
    }

    @ViewBuilder private func actions(_ e: GameEngine, _ co: Company, _ m: StaffMember, _ p: StaffProfile.Profile, _ cur: Currency) -> some View {
        let missing: Int = StaffExtras.missing(m).count
        TeamGroup("What you can do") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if let talk = e.contractTalk(personID: staffID), talk.isRequest {
                        Label("\(p.name) has asked about \(talk.proposal.topic.title.lowercased()).", systemImage: "bubble.left.fill").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.gold)
                    }
                    WrapRow {
                        TeamAction(title: "Contract discussion") { discussing = true }
                        if p.problem != nil { TeamAction(title: "Talk to them") { talk(p) } }
                        TeamAction(title: "Written warning") { warn(p) }
                        if missing > 0 {
                            TeamAction(title: "Paperwork done (\(missing))") {
                                let done = store.act { $0.completePaperwork(companyID: companyID, personID: staffID) } ?? 0
                                if done > 0 { Haptics.success(); store.show("Paperwork done: \(done) \(done == 1 ? "item" : "items") ticked.", tone: "good") } else { Haptics.warning(); store.show("Nothing could be ticked.", tone: "warn") }
                            }
                        }
                        if !p.courses.isEmpty {
                            Menu {
                                ForEach(p.courses, id: \.id) { c in
                                    Button("\(c.name) \u{00B7} \(cur.tidyShort(c.cost))") { confirmCourse(c, p, cur) }
                                }
                            } label: {
                                Text("Send on a course").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.gold.opacity(0.7), lineWidth: 1))
                                    .frame(minHeight: 32)
                            }
                        }
                        TeamAction(title: "Let go", tint: Theme.loss) { confirmDismiss(p, cur) }
                    }
                    if !p.courses.isEmpty {
                        Text("Results vary: a course can change nothing, and a good result may tempt a competitor to poach them.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            }
        }
    }

    private func talk(_ p: StaffProfile.Profile) {
        let ok = store.act { $0.talkToStaff(companyID: companyID, staffID: staffID) } ?? nil
        Haptics.tap()
        store.show(ok == true ? "The talk helped: the problem is gone." : "The talk did not help. A warning is noted.", tone: ok == true ? "good" : "warn")
    }

    private func warn(_ p: StaffProfile.Profile) {
        let worked = store.act { $0.warnStaff(companyID: companyID, staffID: staffID) } ?? nil
        if worked == nil { Haptics.warning(); store.show("The warning could not be given now.", tone: "warn"); return }
        Haptics.tap()
        store.show(worked == true ? "The warning worked. \(p.name) has improved." : "Warning on file for \(p.name).", tone: worked == true ? "good" : "n")
    }

    private func confirmCourse(_ c: StaffProfile.Course, _ p: StaffProfile.Profile, _ cur: Currency) {
        pending = PendingAction(title: "Send \(p.name) on \(c.name)?", message: "Costs \(cur.tidyDisplay(c.cost)) from company cash. \(c.benefit) It may also change nothing, and a good result may tempt a competitor to poach them.", button: "Send for \(cur.tidyShort(c.cost))", amount: c.cost, currency: cur) { course(c, p) }
    }

    private func course(_ c: StaffProfile.Course, _ p: StaffProfile.Profile) {
        let r: StaffProfile.CourseResult? = store.act { $0.sendOnCourse(companyID: companyID, staffID: staffID, courseID: c.id) }
        switch r {
        case .done(let msg)?: Haptics.success(); store.show("\(c.name): \(msg).", tone: "good")
        case .cash?: Haptics.warning(); store.show("Not enough cash for \(c.name).", tone: "warn")
        case nil: break
        default: Haptics.warning(); store.show("That course is not available.", tone: "warn")
        }
    }

    private func confirmDismiss(_ p: StaffProfile.Profile, _ cur: Currency) {
        let risk = p.dismissalDocumented ? "Two warnings or theft are on file, so this is easy to defend." : "Nothing documented: they may claim unfair dismissal and win \(cur.tidyShort(p.compensationRange.lowerBound)) to \(cur.tidyShort(p.compensationRange.upperBound))."
        pending = PendingAction(title: "Let \(p.name) go?", message: "Notice and severance of \(cur.tidyDisplay(p.severance)) is paid. \(risk)", button: "Let go", destructive: true) {
            guard let r = store.act({ $0.dismissStaff(companyID: companyID, staffID: staffID) }) ?? nil else { store.show("They no longer work here.", tone: "warn"); dismiss(); return }
            Haptics.warning()
            store.show(r.claimedUnfairDismissal ? "\(p.name) is gone, and claimed unfair dismissal: \(cur.tidyDisplay(r.compensation)) paid on top of \(cur.tidyDisplay(r.severance)) severance." : (r.severance > 0 ? "Severance paid: \(cur.tidyDisplay(r.severance))." : "\(p.name) has left."), tone: r.claimedUnfairDismissal ? "bad" : "n")
            dismiss()
        }
    }
}

/// A group header of a long list (a role with its head count and pay): a row on the inset tone that opens or closes the people under it.
struct CardRowLabel: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var subtitle: String
    var value: String
    var open: Bool

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.accent).rotationEffect(.degrees(open ? 90 : 0))
            VStack(alignment: .leading, spacing: 0) {
                Text(title.tidyText).textStyle(.headline)
                Text(subtitle.tidyText).textStyle(.caption)
            }
            Spacer(minLength: Theme.Space.s)
            Text(value).textStyle(.body, tint: P.inkSoft, numeric: true).lineLimit(1)
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(P.inset))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
