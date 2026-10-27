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

/// The company's own staff: a summary, issues first, then people grouped by role once the team is big enough to need it.
/// A tap opens the person's profile, where every action on them lives.
struct CompanyStaffRoster: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.currency(for: company)
        let staff = company.staff
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = staff.filter { q.isEmpty || name($0).lowercased().contains(q) || roleLabel($0.role).lowercased().contains(q) }
        let attention = shown.filter(StaffIssue.needsAttention)
        let rest = shown.filter { !StaffIssue.needsAttention($0) }
        let big = staff.count > 8
        let total: String = cur.tidyShort(staff.reduce(0) { $0 + $1.monthlyWage })
        TeamGroup(title: "People", trailing: {
            Text("\(staff.count) \(staff.count == 1 ? "person" : "people") · \(total) a month").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
        }) {
            if staff.isEmpty {
                Card(padding: 14, radius: Theme.Radius.row) {
                    Text(company.ownerHours > 0 ? "No one works here but you." : "No one works here.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                }
            }
            if staff.count > 12 { search }
            if !attention.isEmpty {
                Text("Needs attention · \(attention.count)").font(.system(size: 10.5, weight: .semibold)).tracking(0.8).textCase(.uppercase).foregroundStyle(Theme.caution).padding(.top, 2)
                ForEach(attention) { m in row(m, cur, showIssues: true) }
            }
            if big {
                let groups = Dictionary(grouping: rest, by: { $0.role }).sorted { $0.value.count > $1.value.count }
                ForEach(groups, id: \.key) { role, members in
                    let open = expanded.contains(role) || !q.isEmpty
                    let pay: String = cur.tidyShort(members.reduce(0) { $0 + $1.monthlyWage }) + " a month"
                    Button {
                        Haptics.choose()
                        withAnimation(.snappy(duration: 0.2)) { if open { expanded.remove(role) } else { expanded.insert(role) } }
                    } label: {
                        CardRowLabel(title: roleLabel(role), subtitle: "\(members.count) \(members.count == 1 ? "person" : "people")", value: pay, open: open)
                    }.buttonStyle(.plain)
                    if open { ForEach(members) { m in row(m, cur, showIssues: false) } }
                }
            } else {
                ForEach(rest) { m in row(m, cur, showIssues: false) }
            }
            if !q.isEmpty && shown.isEmpty { Text("No one matches \"\(query)\".").font(.bodyText).foregroundStyle(Theme.ivoryMuted).padding(.vertical, 8) }
            footer(cur)
        }
        .confirmAction($pending)
    }

    private var search: some View {
        HStack(spacing: 8) {
            GlyphView(glyph: Glyph.person, size: 14, weight: 1.5, tint: Theme.ivoryFaint)
            TextField("Name or role", text: $query).font(.system(size: 14)).foregroundStyle(Theme.ivory).textInputAutocapitalization(.never).autocorrectionDisabled()
            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.ivoryFaint) }.buttonStyle(.plain).accessibilityLabel("Clear search") }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).fill(Theme.surfaceTable))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func name(_ m: StaffMember) -> String { engine.state.people[m.id]?.name ?? roleLabel(m.role) }

    private func row(_ m: StaffMember, _ cur: Currency, showIssues: Bool) -> some View {
        let issues: [String] = StaffIssue.list(m)
        let attention: Bool = StaffIssue.needsAttention(m)
        let note: String = issues.isEmpty ? "" : issues.joined(separator: " · ")
        let wage: String = cur.tidyShort(m.monthlyWage)
        return NavigationLink { StaffProfileView(companyID: company.id, staffID: m.id) } label: {
            PersonCard(name: name(m), role: roleLabel(m.role), scope: "company", note: note, noteTint: attention ? Theme.caution : Theme.ivoryFaint, wage: wage, roleKey: m.role,
                       face: engine.state.people[m.id].map { FaceTraits.of($0, countryCode: company.countryCode) }, faceGroup: "\(company.id)")
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func footer(_ cur: Currency) -> some View {
        let staff = company.staff
        let papers = staff.reduce(0) { $0 + StaffExtras.missing($1).count }
        if papers > 0 {
            Card(padding: 12, radius: Theme.Radius.row, stroke: Theme.caution.opacity(0.5)) {
                HStack(spacing: 10) {
                    GlyphView(glyph: Glyph.warning, size: 18, weight: 1.6, tint: Theme.caution)
                    Text("\(papers) paperwork \(papers == 1 ? "item" : "items") missing. An inspection can fine you.").font(.system(size: 12.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    TeamAction(title: "Do all") {
                        var done = 0
                        for m in staff { done += store.act({ $0.completePaperwork(companyID: company.id, personID: m.id) }) ?? 0 }
                        let left = store.engine?.state.company(company.id).map { $0.staff.reduce(0) { $0 + StaffExtras.missing($1).count } } ?? papers
                        if done > 0 && left == 0 { Haptics.success(); store.show("Paperwork done: \(done) \(done == 1 ? "item" : "items") ticked.", tone: "good") }
                        else if done > 0 { Haptics.warning(); store.show("\(done) \(done == 1 ? "item" : "items") ticked; \(left) still missing.", tone: "warn") }
                        else { Haptics.warning(); store.show("Nothing could be ticked.", tone: "warn") }
                    }
                }
            }
        }
        if staff.count > 1 {
            Card(padding: 12, radius: Theme.Radius.row) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Cutting costs").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                        Text("Lets the weakest go; severance is paid now.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                    }
                    Spacer(minLength: 8)
                    Menu {
                        ForEach([1, 2, 3, 5].filter { $0 < staff.count }, id: \.self) { n in
                            let p = engine.layoffPreview(companyID: company.id, count: n)
                            Button("\(n) · saves \(cur.tidyShort(p.savesPerMonth)) a month, severance \(cur.tidyShort(p.severance))") { confirmLayOff(n, p, cur) }
                        }
                    } label: {
                        Text("Lay off the weakest").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.loss)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.loss.opacity(0.7), lineWidth: 1))
                    }
                }
            }
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
    @Environment(\.dismiss) private var dismiss
    var companyID: Int
    var staffID: Int
    @State private var pending: PendingAction?
    @State private var discussing = false

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let m = co.staff.first(where: { $0.id == staffID }), let p = e.staffProfile(companyID: companyID, staffID: staffID) {
            let cur = e.currency(for: co)
            let sub: String = "\(p.roleName) · age \(p.age) · \(p.skillBand.lowercased())"
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    header(p, co, cur)
                    mood(p)
                    record(p, m, cur)
                    actions(e, co, m, p, cur)
                    if let t = p.personality.flatMap({ StaffProfile.personalityText[$0] }) {
                        TeamGroup("Character") { Card(padding: 14, radius: Theme.Radius.row) { Text(t).font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted) } }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .appScreen(title: p.name, subtitle: sub, tab: .team)
            .confirmAction($pending)
            .sheet(isPresented: $discussing) { ContractDiscussionView(companyID: companyID, personID: staffID).environmentObject(store) }
        } else {
            Text("This person no longer works here.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    private func header(_ p: StaffProfile.Profile, _ co: Company, _ cur: Currency) -> some View {
        let basis: String = p.payBasis == "fix" ? "fixed, a month" : "by the hour, a month"
        let tenure: String = p.weeksWithYou >= 52 ? String(format: "%.1f yr", Double(p.weeksWithYou) / 52) : "\(p.weeksWithYou) wk"
        let items: [KeyFigures.Item] = [
            .init(label: "Pay", value: cur.tidyShort(p.monthlyWage), sub: basis),
            .init(label: "Skill", value: "\(Int(p.skill.rounded()))", sub: p.skillGainedSinceStart ? "has grown here" : ""),
            .init(label: "With you", value: tenure),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ThumbnailView(kind: .person, key: p.role, size: 48, initials: p.name, face: store.engine?.state.people[staffID].map { FaceTraits.of($0, countryCode: co.countryCode) }, faceGroup: "\(co.id)")
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
        let term: String = FixedTerm.endWeek(m).map { "Fixed term to week \($0)" } ?? "Permanent"
        let left: String = FixedTerm.endWeek(m).map { "\(max(0, $0 - week)) weeks left" } ?? ""
        return TeamGroup("Record") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Hours a week", value: "\(Int(p.hoursPerWeek.rounded()))", rule: false)
                    FlatRow(label: "Last raise", value: raise, sub: p.underpaid ? "Paid less than the job usually pays" : "")
                    if let plan = p.bonusPlan { FlatRow(label: "Bonus plan", value: plan, sub: p.bonusPaidThisYear > 0 ? "\(cur.tidyShort(p.bonusPaidThisYear)) paid this year" : "Nothing paid yet this year") }
                    if !p.perks.isEmpty { FlatRow(label: "Perks", value: p.perks.joined(separator: ", "), sub: "Worth about \(cur.tidyShort(p.perksWorth)) a month to them, counted as pay") }
                    if !p.expenses.isEmpty { FlatRow(label: "Expenses paid", value: p.expenses.joined(separator: ", ")) }
                    FlatRow(label: "Contract", value: term, sub: left)
                    FlatRow(label: "Late this quarter", value: "\(p.lateThisQuarter)")
                    FlatRow(label: "Complaints this quarter", value: "\(p.complaintsThisQuarter)")
                    FlatRow(label: "Written warnings", value: "\(p.warnings)", sub: p.dismissalDocumented ? "Enough on file to let them go for cause" : "")
                    FlatRow(label: "Energy", value: p.tiredness > 60 ? "tired" : "fine", sub: "\(p.stamina). \(p.learns)", tint: p.tiredness > 60 ? Theme.caution : Theme.ivory)
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
                                    Button("\(c.name) · \(cur.tidyShort(c.cost)) · up to +\(Int(c.maxGain.rounded())) skill") { confirmCourse(c, p, cur) }
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
        pending = PendingAction(title: "Send \(p.name) on \(c.name)?", message: "Costs \(cur.tidyDisplay(c.cost)) from company cash. Skill may rise by up to \(Int(c.maxGain.rounded())) points, or not at all; a good result may tempt a competitor to poach them.", button: "Send for \(cur.tidyShort(c.cost))", amount: c.cost, currency: cur) { course(c, p) }
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

/// A group header of a long list (a role with its head count and pay): a compact card that opens or closes the people under it.
struct CardRowLabel: View {
    var title: String
    var subtitle: String
    var value: String
    var open: Bool

    var body: some View {
        HStack(spacing: 10) {
            GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.gold).rotationEffect(.degrees(open ? 90 : 0))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }
            Spacer(minLength: 8)
            Text(value).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.surfaceTable))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
