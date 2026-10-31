import SwiftUI
import Employees
import GameCore
import Businesses
import Simulation

/// The Team tab, built like native/design/new-look-2026-10/TeamA, TeamB and TeamC: a round icon, the serif title and a subtitle, then
/// underline tabs.
/// - Overview: Need you / Run by managers / Posts to fill, the cards that need the owner (payroll approval, paperwork, decisions...),
///   and who runs each company. Trouble inside companies a manager runs is folded away under "Handled by your managers".
/// - People: one directory of everyone (store staff, managers, department heads, assistant, regional, chain and group people), each person once,
///   with a role badge and a scope badge. A row opens the Team section of the company that employs them (group people open Group).
///   "Hire" opens hiring at a company's Team section.
/// - Delegation: per company who runs it, who approves payroll, the spending limit and hiring authority, with a banner when nobody approves
///   payroll. Manager scorecards sit under it.
/// - Vacancies: the open posts the engine knows about, each with a "Fill" cue. Executive posts (group level) open Group.
/// Every row opens the record on this tab's own navigation stack, so Back returns here. Pay, promotion and letting go stay in the company's
/// Team section (one home); chain and group posts stay in Group and the chain's section.
struct TeamView: View {
    enum Tab: String, CaseIterable, Identifiable { case overview = "Overview", people = "People", delegation = "Delegation", vacancies = "Vacancies"; var id: String { rawValue } }
    enum PeopleFilter: String, CaseIterable, Identifiable { case all = "All", managers = "Managers", staff = "Staff", attention = "Needs attention"; var id: String { rawValue } }

    @EnvironmentObject var store: GameStore
    /// Pushes go through the store, which owns this tab's stack (a record already on it is gone back to, not stacked twice).
    private var path: TabPath { TabPath(store: store, tab: .team) }
    @State private var tab: Tab = .overview
    @State private var query = ""
    @State private var filter: PeopleFilter = .all
    @State private var showAllScores = false
    /// The "Need you" tile was tapped: the Overview shows only the owner's list (the one the tile counts), in full.
    @State private var needYouOnly = false

    var body: some View {
        NavigationStack(path: Binding(get: { store.path(for: .team) }, set: { store.setPath($0, for: .team) })) {
            Group {
                if let e = store.engine {
                    let o = e.teamOverview()
                    let alerts = e.payrollAlertInfos()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            header(o, e)
                            tabBar
                            switch tab {
                            case .overview: overview(o, e, alerts)
                            case .people: people(o, e)
                            case .delegation: delegation(o, e, alerts)
                            case .vacancies: vacancies(o)
                            }
                        }
                        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 40)
                        .frame(maxWidth: 900).frame(maxWidth: .infinity)
                    }
                    .id(store.rootToken(.team))
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .ledgerBackground()
            .toolbar(.hidden, for: .navigationBar)
            .companyRouteDestinations()
            .returnBar(for: .team)
            // Choosing Team again: back to the Overview, search and filter cleared.
            .onChange(of: store.rootToken(.team)) { _, _ in tab = .overview; query = ""; filter = .all; needYouOnly = false; showAllScores = false }
        }
    }

    // MARK: Header and tabs

    private func header(_ o: TeamOverview, _ e: GameEngine) -> some View {
        let staff = o.companies.reduce(0) { $0 + $1.staff }
        let wages = o.companies.reduce(0) { $0 + $1.monthlyWages }
        let subtitle: String
        switch tab {
        case .overview:
            subtitle = o.companies.isEmpty ? "No companies yet." : "\(staff.peopleText) in \(o.companies.count) \(o.companies.count == 1 ? "company" : "companies") · \(store.short(wages)) a month in wages"
        case .people: subtitle = "Everyone who works for you"
        case .delegation: subtitle = "Who decides what"
        case .vacancies: subtitle = o.vacancies.isEmpty ? "No open posts" : "\(o.vacancies.count) open \(o.vacancies.count == 1 ? "post" : "posts")"
        }
        return HStack(spacing: 12) {
            IconCircle(glyph: Glyph.team, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text("Team").font(.serifTitle(28)).foregroundStyle(Theme.ivory)
                Text(subtitle.tidyMoney).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).lineLimit(2)
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if tab == .people { hireButton(o) }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                let on = t == tab
                Button { Haptics.tap(); needYouOnly = false; withAnimation(.easeOut(duration: 0.15)) { tab = t } } label: {
                    Text(t.rawValue).font(.system(size: 13.5)).foregroundStyle(on ? Theme.ivory : Theme.ivoryFaint)
                        .padding(.bottom, 9).padding(.horizontal, 2)
                        .overlay(alignment: .bottom) { Rectangle().fill(on ? Theme.gold : Color.clear).frame(height: 2) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("team-tab-\(t.rawValue)")
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
                if t != Tab.allCases.last { Spacer(minLength: 0) }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func sectionLabel(_ text: String, trailing: String = "") -> some View {
        HStack {
            Text(text.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(1.4).foregroundStyle(Theme.gold)
            Spacer()
            if !trailing.isEmpty { Text(trailing).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
        }
    }

    private func smallOutline(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gold)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: 1))
            .frame(minHeight: 30).contentShape(Rectangle())
    }

    /// "Hire" opens hiring, which lives in a company's Team section: straight there with one company, a short choice with several.
    @ViewBuilder private func hireButton(_ o: TeamOverview) -> some View {
        let hirable = o.companies.filter { !$0.isHolding }
        if hirable.count > 1 {
            Menu {
                ForEach(hirable) { l in Button(l.name) { Haptics.tap(); path.append(.companyAt(l.id, .staff)) } }
            } label: { smallOutline("Hire") }
        } else {
            Button {
                Haptics.tap()
                if let l = hirable.first { path.append(.companyAt(l.id, .staff)) }
                else { store.show("Open a company first, then hire from its Team section.", tone: "warn") }
            } label: { smallOutline("Hire") }
            .buttonStyle(.plain).accessibilityLabel("Hire")
        }
    }

    // MARK: Overview (TeamA)

    /// The payroll warning, who decides what in the companies that need you most, the count tiles and the latest activity.
    @ViewBuilder private func overview(_ o: TeamOverview, _ e: GameEngine, _ alerts: [PayrollAlertInfo]) -> some View {
        if needYouOnly {
            needYouList(o, e, alerts)
        } else {
            payrollNotes(alerts)
            decidesTables(o, e, alerts, limit: 3)
            peopleTiles(o, e, alerts)
            activityList(o, e, alerts)
        }
    }

    /// The full "Need you" list: exactly what the tile counts, from the same function the activity list starts with.
    @ViewBuilder private func needYouList(_ o: TeamOverview, _ e: GameEngine, _ alerts: [PayrollAlertInfo]) -> some View {
        let items: [ActivityItem] = needYouItems(o, e, alerts)
        sectionLabel("Need you", trailing: "\(items.count)")
        ActivityList(items: items, emptyText: "Nothing needs you. Your managers have the rest in hand.")
        Button { Haptics.tap(); needYouOnly = false } label: {
            Text("Back to overview ›").font(.system(size: 12.5)).foregroundStyle(Theme.gold).frame(maxWidth: .infinity, alignment: .trailing).frame(minHeight: 32)
        }.buttonStyle(.plain)
    }

    /// One amber note per company where nobody approves payroll, with the way to appoint someone.
    @ViewBuilder private func payrollNotes(_ alerts: [PayrollAlertInfo]) -> some View {
        ForEach(alerts, id: \.companyID) { a in
            OverviewNote(text: "Nobody approves payroll at \(a.companyName), so it comes to you every month.", actionTitle: "Appoint",
                         accessibilityLabel: "Appoint someone at \(a.companyName)") {
                path.append(.companyAt(a.companyID, .staff))
            }
        }
    }

    private func peopleTiles(_ o: TeamOverview, _ e: GameEngine, _ alerts: [PayrollAlertInfo]) -> some View {
        let need = needYouItems(o, e, alerts).count
        let needed = o.vacancies.filter { $0.needed }.count
        let list: [CountTileData] = [
            CountTileData(glyph: Glyph.person, count: e.teamPeople().count, label: "People", action: { filter = .all; tab = .people }),
            CountTileData(glyph: Glyph.warning, count: need, label: "Need you", tint: need > 0 ? Theme.caution : Theme.ivory,
                          action: { needYouOnly = true; tab = .overview }),
            CountTileData(glyph: Glyph.ovCalendar, count: o.vacancies.count, label: "Posts to fill", tint: needed > 0 ? Theme.loss : Theme.ivory,
                          action: { tab = .vacancies }),
        ]
        return CountTiles(title: "People", link: "View all ›", linkAction: { filter = .all; tab = .people }, tiles: list)
    }

    /// What waits for the owner first (payroll to approve, then people trouble above a manager's authority), then what managers handle.
    /// What waits for the owner: payroll nobody approves, then people trouble above a manager's authority. The "Need you" tile counts
    /// and opens exactly these items.
    private func needYouItems(_ o: TeamOverview, _ e: GameEngine, _ alerts: [PayrollAlertInfo]) -> [ActivityItem] {
        var items: [ActivityItem] = []
        for a in alerts {
            let money = e.state.company(a.companyID).map { store.money(a.amount, in: $0) } ?? store.money(a.amount)
            let cid = a.companyID
            items.append(ActivityItem(id: "pay\(cid)", glyph: Glyph.ovCoin, title: "Payroll \(money) needs your approval",
                                      subtitle: "\(a.companyName) · \(a.dateText) · no manager or accountant",
                                      action: { path.append(.companyAt(cid, .finances)) }))
        }
        for i in peopleIssues(o, e).filter({ $0.needsOwner }) {
            items.append(ActivityItem(id: "own\(i.id)", glyph: Glyph.person, title: i.title,
                                      subtitle: i.beyondAuthority ? "Above their authority · \(i.detail)" : i.detail, action: { open(i, e) }))
        }
        return items
    }

    /// What waits for the owner first, then what managers handle.
    private func activityList(_ o: TeamOverview, _ e: GameEngine, _ alerts: [PayrollAlertInfo]) -> some View {
        let people = peopleIssues(o, e)
        var items: [ActivityItem] = needYouItems(o, e, alerts)
        for i in people.filter({ !$0.needsOwner }) {
            items.append(ActivityItem(id: "mgr\(i.id)", glyph: Glyph.person, title: i.title, subtitle: "\(i.handledBy) · \(i.detail)", action: { open(i, e) }))
        }
        return ActivityList(items: Array(items.prefix(8)), emptyText: o.companies.isEmpty
                            ? "No one works for you yet. Open a company, then hire from its Team section."
                            : "Nothing needs you. Your managers have the rest in hand.")
    }

    /// Inbox-type decisions (equipment breakdown, press interview, an offer...) stay in the Inbox; only decisions about people
    /// (a raise, a poached manager, a proposal for staff) are listed here.
    private static func isPeopleDecision(_ m: Message) -> Bool {
        ["staffx", "mgrraise", "mgrpoach", "prop", "mprop", "mfind11"].contains(m.actionID) || m.actionID.hasPrefix("tg58")
    }
    private func peopleIssues(_ o: TeamOverview, _ e: GameEngine) -> [TeamOverview.Issue] {
        o.issues.filter { i in
            guard i.kind == .decision else { return true }
            guard let id = i.messageID, let m = e.state.inbox.first(where: { $0.id == id }) else { return false }
            return Self.isPeopleDecision(m)
        }
    }
    /// What a company line says needs the owner, without the Inbox-type decisions the engine counts in `issues`.
    private func forYou(_ l: TeamOverview.CompanyLine, _ e: GameEngine) -> Int {
        let hidden = e.state.inbox.filter { $0.status == "open" && $0.companyID == l.id && !Self.isPeopleDecision($0) }.count
        return max(0, l.issues - hidden)
    }

    /// Opens the exact record an issue is about: the decision in the Inbox, or the company on the section where it is dealt with.
    private func open(_ i: TeamOverview.Issue, _ e: GameEngine) {
        Haptics.tap()
        if i.kind == .decision, let m = i.messageID { store.openMessage(m); return }  // people decisions are answered in the Inbox
        guard let id = i.companyID else { return }
        let section: CompanySection
        switch i.kind {
        case .payroll, .cash: section = .finances
        case .chainVacancy: section = .chain
        default: section = .staff
        }
        path.append(.companyAt(id, section))
    }

    private func authorityWord(_ lvl: Int) -> String {
        switch lvl { case 0: return " · asks you"; case 1: return " · within limits"; case 2: return " · full control"; default: return "" }
    }

    // MARK: People (TeamB)

    @ViewBuilder private func people(_ o: TeamOverview, _ e: GameEngine) -> some View {
        let everyone = e.teamPeople()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matching = q.isEmpty ? everyone : everyone.filter { $0.name.lowercased().contains(q) || $0.role.lowercased().contains(q) || $0.employer.lowercased().contains(q) || $0.scope.lowercased().contains(q) }
        let counts: [PeopleFilter: Int] = [
            .all: matching.count,
            .managers: matching.filter { $0.isManagement }.count,
            .staff: matching.filter { !$0.isManagement }.count,
            .attention: matching.filter { $0.needsAttention }.count,
        ]
        let shown: [TeamSearchResult] = matching.filter { p in
            switch filter {
            case .all: return true
            case .managers: return p.isManagement
            case .staff: return !p.isManagement
            case .attention: return p.needsAttention
            }
        }

        HStack(spacing: 8) {
            GlyphView(glyph: "M16 16 L21 21 M11 4.5 A6.5 6.5 0 1 0 11 17.5 A6.5 6.5 0 1 0 11 4.5", size: 15, weight: 1.8, tint: Theme.ivoryDim)
            TextField("", text: $query, prompt: Text("Search name, role or company").foregroundStyle(Theme.ivoryDim))
                .font(.system(size: 13.5)).foregroundStyle(Theme.ivory).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("team-search")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(Theme.ivoryDim) }.buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9).teamCard(radius: Theme.Radius.row)

        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(PeopleFilter.allCases) { f in
                    let on = f == filter
                    Button { Haptics.tap(); filter = f } label: {
                        Text("\(f.rawValue) \(counts[f] ?? 0)").font(.system(size: 12)).lineLimit(1)
                            .foregroundStyle(on ? Theme.ivory : (f == .attention && (counts[f] ?? 0) > 0 ? Theme.caution : Theme.ivoryMuted))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(on ? Theme.goldWash : Color.clear))
                            .overlay(Capsule().strokeBorder(on ? Theme.gold : Theme.border, lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }.scrollIndicators(.hidden)

        if shown.isEmpty {
            Text(everyone.isEmpty ? "No one works for you yet. Open a company, then hire from its Team section." : "No one matches.")
                .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).padding(.vertical, 8)
        }
        VStack(spacing: 8) {
            ForEach(shown.prefix(200)) { p in
                Button { Haptics.tap(); openPerson(p) } label: { personCard(p, e) }.buttonStyle(.plain)
            }
        }
        if shown.count > 200 { Text("Showing the first 200 of \(shown.count). Search to narrow it down.").font(.caption2).foregroundStyle(Theme.ivoryFaint) }
    }

    /// The portrait key of a listed person, when the row points at a person record.
    private func personFace(_ p: TeamSearchResult, _ e: GameEngine) -> String? {
        p.personID.flatMap { e.state.people[$0]?.faceKey }
    }

    private func personCard(_ p: TeamSearchResult, _ e: GameEngine) -> some View {
        let wage: String = p.monthlyWage > 0 ? ((p.companyID.flatMap { e.state.company($0) }.map { store.short(p.monthlyWage, in: $0) } ?? store.short(p.monthlyWage)) + "/mo") : "no wage"
        return HStack(spacing: 12) {
            ThumbnailView(kind: .person, key: p.role, size: 38, initials: p.name, face: personFace(p, e))
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                HStack(spacing: 6) {
                    badge(p.role)
                    badge(p.scope)
                    Text(p.employer).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(wage.tidyMoney).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivory).lineLimit(1)
                Text(p.note.isEmpty ? "steady" : p.note).font(.system(size: 11)).foregroundStyle(p.needsAttention ? Theme.caution : Theme.ivoryFaint).lineLimit(1)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10).teamCard().contentShape(Rectangle())
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: 1))
    }

    /// A person opens the Team section of the company that employs them; chain and regional people open the chain's section;
    /// group people open Group.
    private func openPerson(_ p: TeamSearchResult) {
        if let id = p.companyID {
            path.append(.companyAt(id, (p.scope == "chain" || p.scope == "region") && p.chainID != nil ? .chain : .staff))
        } else {
            store.jump(to: .group)
        }
    }

    // MARK: Delegation (TeamC)

    @ViewBuilder private func delegation(_ o: TeamOverview, _ e: GameEngine, _ alerts: [PayrollAlertInfo]) -> some View {
        payrollNotes(alerts)
        if o.companies.isEmpty {
            Text("No companies yet.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
        }
        decidesTables(o, e, alerts, limit: nil)
        if !o.companies.isEmpty {
            Text("A manager or accountant approves routine payroll and spending up to the limit you set. Anything bigger always comes to you.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryDim).fixedSize(horizontal: false, vertical: true)
        }
        performance(o, e)
    }

    /// One "Who decides what" table per company, the ones that need you most first. On Overview only `limit` of them show, with a link to all.
    @ViewBuilder private func decidesTables(_ o: TeamOverview, _ e: GameEngine, _ alerts: [PayrollAlertInfo], limit: Int?) -> some View {
        let lines = o.companies.filter { !$0.isHolding }.sorted { (forYou($0, e), $1.name) > (forYou($1, e), $0.name) }
        let shown: [TeamOverview.CompanyLine] = limit.map { Array(lines.prefix($0)) } ?? lines
        ForEach(shown) { l in
            OverviewTable(title: "Who decides what", rows: decidesRows(l, e, alerts)) {
                Text(l.name).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
            }
        }
        if let limit, lines.count > limit {
            Button { Haptics.tap(); tab = .delegation } label: {
                Text("All \(lines.count) companies ›").font(.system(size: 12.5)).foregroundStyle(Theme.gold).frame(maxWidth: .infinity, alignment: .trailing).frame(minHeight: 32)
            }.buttonStyle(.plain)
        }
    }

    /// Runs it, Payroll, Spending and Hiring for one company: who decides now and what to do about it. Pages open the company's Team or
    /// Finances section; Spending opens a small menu that sets the manager's authority (the engine's own action).
    private func decidesRows(_ l: TeamOverview.CompanyLine, _ e: GameEngine, _ alerts: [PayrollAlertInfo]) -> [OverviewRowData] {
        let co = e.state.company(l.id)
        let hasMgr = l.authority >= 0
        let lvl = max(0, l.authority)
        let nobodyPays = alerts.contains { $0.companyID == l.id }
        let buy = co?.value("auth")["buy"].double ?? 0
        let limitText = "up to " + (co.map { store.short(buy, in: $0) } ?? store.short(buy))
        let spend: String = !hasMgr || lvl == 0 ? "Ask me always" : lvl == 1 ? "Manager, \(limitText)" : "Manager decides alone"
        let hire: String = !hasMgr || lvl == 0 ? "You" : lvl == 1 ? "Manager, \(limitText)" : "Manager decides alone"
        let byRule = hasMgr && lvl >= 1
        let id = l.id

        let runs = OverviewRowData(
            id: "run\(id)", glyph: Glyph.ovKey, title: "Runs it",
            value: l.delegated ? "\(l.managedBy)\(l.managerLeaving ? " (leaving)" : "")" : "You",
            note: l.delegated ? (l.managerTitle ?? "manager").lowercased() : "appoint a manager",
            noteTint: l.delegated ? Theme.ivoryFaint : Theme.caution,
            action: { path.append(.companyAt(id, .staff)) })
        let payroll = OverviewRowData(
            id: "pay\(id)", glyph: Glyph.ovCoin, title: "Payroll",
            value: byRule ? "\(l.managedBy), by their rule" : "You, every month",
            note: nobodyPays ? "no accountant" : byRule ? "rule set" : "your call",
            noteTint: nobodyPays ? Theme.caution : Theme.ivoryFaint,
            action: { path.append(.companyAt(id, .finances)) })
        var spending = OverviewRowData(
            id: "spend\(id)", glyph: Glyph.ovShield, title: "Spending", value: spend, note: "set limit", noteTint: Theme.gold,
            action: { path.append(.companyAt(id, .staff)) })
        if hasMgr {
            let words = ["Asks you first", "Decides within your limits", "Decides on their own"]
            spending.menu = words.enumerated().map { v, word in OverviewMenuItem(title: word, action: { setAuthority(l, v) }) }
        }
        let hiring = OverviewRowData(
            id: "hire\(id)", glyph: Glyph.person, title: "Hiring", value: hire, note: hasMgr ? "change" : "delegate", noteTint: Theme.gold,
            action: { path.append(.companyAt(id, .staff)) })
        return [runs, payroll, hiring, spending]
    }

    /// The manager's authority level, reported with the engine's own answer. Reversible, so no confirmation.
    private func setAuthority(_ l: TeamOverview.CompanyLine, _ level: Int) {
        let name = l.delegated ? l.managedBy : "The manager"
        _ = store.settle(store.act { $0.setManagerAuthority(companyID: l.id, level: level) },
                         "\(name) now \(GameEngine.authorityText(level: level)).", same: "\(name) already works that way.")
    }

    // MARK: Manager performance

    @ViewBuilder private func performance(_ o: TeamOverview, _ e: GameEngine) -> some View {
        if !o.scorecards.isEmpty {
            let lines = Dictionary(o.companies.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let limit = 5
            let shown = showAllScores ? o.scorecards : Array(o.scorecards.prefix(limit))
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Manager performance", trailing: o.scorecards.count > 1 ? "weakest first" : "1 manager")
                ForEach(shown, id: \.id) { c in
                    Button { Haptics.tap(); path.append(.companyAt(c.id, .staff)) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.managerName).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                                Text("\(c.companyName)\(lines[c.id].map { authorityWord($0.authority) } ?? "")\((lines[c.id]?.managerLeaving ?? false) ? " · leaving" : "")")
                                    .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(c.score)").font(.system(size: 14).monospacedDigit()).foregroundStyle(c.score < 35 ? Theme.loss : c.score < 50 ? Theme.caution : c.score >= 65 ? Theme.gain : Theme.ivory)
                                Text(CompanyManagement.scoreWord(c.score)).font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
                            }
                            GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10).teamCard().contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if o.scorecards.count > limit {
                    Button(showAllScores ? "Show fewer" : "Show all \(o.scorecards.count)") { withAnimation { showAllScores.toggle() } }
                        .buttonStyle(QuietButtonStyle()).padding(.top, 4)
                }
                Text("Scorecard 0 to 100 from margin, reputation, quality, mistakes, paperwork and targets. Open a manager to coach, limit or replace them.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.ivoryDim).padding(.top, 2)
            }.padding(.top, 4)
        }
    }

    // MARK: Vacancies

    @ViewBuilder private func vacancies(_ o: TeamOverview) -> some View {
        if o.vacancies.isEmpty {
            Text(o.companies.isEmpty ? "No companies yet." : "No open posts. Every post the engine has room for is filled.")
                .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).padding(.vertical, 8)
        } else {
            let urgent = o.vacancies.filter { $0.needed }.count
            sectionLabel("Open posts", trailing: urgent > 0 ? "\(urgent) needed now" : "none urgent")
            ForEach(o.vacancies) { v in
                Button { openVacancy(v) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(v.place).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                            HStack(spacing: 6) { badge(v.title); badge(v.scope) }
                            Text((v.employer.isEmpty ? "" : "Employer: \(v.employer). ") + v.detail).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 6)
                        Text(v.needed ? "Fill now  ›" : "Fill  ›").font(.system(size: 12.5, weight: .medium)).foregroundStyle(v.needed ? Theme.loss : Theme.gold).padding(.top, 2)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).teamCard().contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    /// A store or company post opens that company's Team section (hiring happens there); a chain post opens its Chain section; a group
    /// (executive) post opens Group.
    private func openVacancy(_ v: TeamOverview.Vacancy) {
        Haptics.tap()
        if v.scope == "chain", let id = v.companyID { path.append(.companyAt(id, .chain)) }
        else if let id = v.companyID { path.append(.companyAt(id, .staff)) }
        else { store.jump(to: .group) }
    }
}

private extension View {
    /// The Team tab's card: the surface colour with a hairline outline.
    func teamCard(radius: CGFloat = Theme.Radius.card) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}
