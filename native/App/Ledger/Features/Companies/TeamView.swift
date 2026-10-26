import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Team tab: the management hierarchy and what needs the owner, not a roster of every worker in every store.
/// - "Needs you": decisions, wages at risk, companies nobody runs, managers leaving or failing, staff trouble where you run the company.
///   Under it, folded away: the same kind of trouble inside companies a manager runs (their job, for information).
/// - "Management": the people in management posts (department heads, chain, regional and group people), each with a role + scope badge and
///   the entity that employs them, then the posts still open, each with a clear "Fill" cue. Group posts exist only once the owner has set up
///   a group office (Group tab); until then this lists each company's own posts only.
/// - "Who runs each company": one line per company with who runs it, staff and wages; it opens that company's own Team section.
/// Searching lists matching employees across all companies; a result opens the company the person belongs to.
/// Every row opens the record on this tab's own navigation stack, so Back returns here. Hiring, pay, promotion and letting go
/// stay in Company > Team (one home); chain and group posts stay in Group and the chain's section.
struct TeamView: View {
    @EnvironmentObject var store: GameStore
    @State private var path: [CompanyRoute] = []
    @State private var query = ""
    @State private var showDelegated = false
    @State private var showAllVacancies = false
    @State private var showAllMembers = false
    @State private var showAllScores = false
    @State private var openGroups: Set<String> = []
    @State private var closedGroups: Set<String> = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let e = store.engine {
                    let o = e.teamOverview()
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Theme.Space.l) {
                            header(o, e)
                            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                                searchResults(e)
                            } else {
                                needsYou(o, e)
                                management(o, e)
                                performance(o, e)
                                companies(o, e)
                            }
                        }
                        .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                        .frame(maxWidth: 900).frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .ledgerBackground()
            .navigationTitle("Team")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Find anyone who works for you")
            .companyRouteDestinations()
            .routeRequests(for: .team, path: $path)
            .returnBar(for: .team)
        }
    }

    // MARK: Header

    private func header(_ o: TeamOverview, _ e: GameEngine) -> some View {
        let live = o.companies.filter { !$0.isHolding }
        let byManagers = live.filter { $0.delegated }.count
        let staff = o.companies.reduce(0) { $0 + $1.staff }
        let wages = o.companies.reduce(0) { $0 + $1.monthlyWages }
        let needed = o.vacancies.filter { $0.needed }.count
        let mine = peopleIssues(o, e).filter { $0.needsOwner }.count
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Team").font(.serifTitle(28))
            if o.companies.isEmpty {
                Text("No companies yet.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
            } else {
                KeyFigures(items: [
                    .init(label: "Need you", value: "\(mine)", tint: mine > 0 ? Theme.caution : Theme.ivory, sub: mine == 0 ? "all in hand" : "people matters"),
                    .init(label: "Run by managers", value: "\(byManagers) of \(live.count)", sub: "\(live.count - byManagers) by you"),
                    .init(label: "Posts to fill", value: "\(o.vacancies.count)", tint: needed > 0 ? Theme.loss : Theme.ivory, sub: needed > 0 ? "\(needed) needed now" : "none urgent"),
                ])
                Text("\(staff.peopleText) in \(o.companies.count) \(o.companies.count == 1 ? "company" : "companies") · \(store.short(wages)) a month in wages")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    // MARK: Needs you / handled by managers

    /// The Team tab is about people. Inbox-type decisions (equipment breakdown, press interview, an offer...) stay in the Inbox; only decisions
    /// that are themselves about people (a raise, a poached manager, a proposal for staff) are listed here.
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

    @ViewBuilder private func needsYou(_ o: TeamOverview, _ e: GameEngine) -> some View {
        let people = peopleIssues(o, e)
        let mine = people.filter { $0.needsOwner }
        let theirs = people.filter { !$0.needsOwner }
        LedgerSection(title: "Needs you", trailing: { Text(mine.isEmpty ? "nothing" : "\(mine.count)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(spacing: 0) {
                if mine.isEmpty {
                    Text(o.companies.isEmpty ? "No one works for you yet. Open a company, then hire from its Team section." : "Nothing needs you. Your managers have the rest in hand.")
                        .font(.bodyText).foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(mine.prefix(12).enumerated()), id: \.element.id) { n, i in
                        if n > 0 { Hairline() }
                        Button { open(i, e) } label: { issueRow(i, e) }.buttonStyle(.plain)
                    }
                    if mine.count > 12 { Text("And \(mine.count - 12) more in the companies below.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6) }
                }
                if !theirs.isEmpty {
                    Hairline().padding(.top, 4)
                    Button { withAnimation { showDelegated.toggle() } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Handled by your managers · \(theirs.count)").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                                if !showDelegated { Text("Staff trouble in companies a manager runs. Their job; open one to look closer.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: showDelegated ? "chevron.up" : "chevron.down").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }.padding(.vertical, 9).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if showDelegated {
                        ForEach(Array(theirs.enumerated()), id: \.element.id) { n, i in
                            Hairline()
                            Button { open(i, e) } label: { issueRow(i, e) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func issueRow(_ i: TeamOverview.Issue, _ e: GameEngine) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Circle().fill(i.severity >= 3 ? Theme.loss : i.severity == 2 ? Theme.caution : Theme.ivoryFaint).frame(width: 7, height: 7).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(i.title.tidyMoney).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                Text(i.beyondAuthority ? "Above their authority · \(i.detail)" : i.needsOwner ? i.detail : "\(i.handledBy) · \(i.detail)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).padding(.top, 4)
        }
        .padding(.vertical, 8).contentShape(Rectangle())
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

    // MARK: Management: people in post, then the posts still open

    @ViewBuilder private func management(_ o: TeamOverview, _ e: GameEngine) -> some View {
        if !o.members.isEmpty || !o.vacancies.isEmpty {
            let limit = 5
            let people = showAllMembers ? o.members : Array(o.members.prefix(8))
            let shown = showAllVacancies ? o.vacancies : Array(o.vacancies.prefix(limit))
            LedgerSection(title: "Management", trailing: { Text("\(o.members.count) in post · \(o.vacancies.count) open").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(spacing: 0) {
                    ForEach(Array(people.enumerated()), id: \.element.id) { n, m in
                        if n > 0 { Hairline() }
                        Button { openMember(m) } label: {
                            ManagementRow(name: m.name, role: m.role, scope: m.scope, line: "Employed by \(m.employer)", wage: store.short(m.monthlyWage))
                        }.buttonStyle(.plain)
                    }
                    if o.members.count > 8 {
                        Button(showAllMembers ? "Show fewer people" : "Show all \(o.members.count) people") { withAnimation { showAllMembers.toggle() } }
                            .buttonStyle(QuietButtonStyle()).padding(.vertical, 8)
                    }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { n, v in
                        if n > 0 || !people.isEmpty { Hairline() }
                        Button { openVacancy(v) } label: {
                            HStack(alignment: .top, spacing: Theme.Space.m) {
                                Circle().fill(v.needed ? Theme.loss : Theme.ivoryFaint).frame(width: 7, height: 7).padding(.top, 6)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(v.place).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                                    RoleScopeBadge(role: v.title, scope: v.scope)
                                    Text((v.employer.isEmpty ? "" : "Employer: \(v.employer). ") + v.detail).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 6)
                                Text(v.needed ? "Fill now  ›" : "Fill  ›").font(.system(size: 12.5, weight: .medium)).foregroundStyle(v.needed ? Theme.loss : Theme.gold).padding(.top, 2)
                            }.padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if o.vacancies.count > limit {
                        Button(showAllVacancies ? "Show fewer open posts" : "Show all \(o.vacancies.count) open posts") { withAnimation { showAllVacancies.toggle() } }
                            .buttonStyle(QuietButtonStyle()).padding(.top, 8)
                    }
                }
            }
        }
    }

    /// A store or company post opens that company's Team section (hiring happens there); a chain post opens its Chain section; a group post opens Group.
    private func openVacancy(_ v: TeamOverview.Vacancy) {
        Haptics.tap()
        if v.scope == "chain", let id = v.companyID { path.append(.companyAt(id, .chain)) }
        else if let id = v.companyID { path.append(.companyAt(id, .staff)) }
        else { store.jump(to: .group) }
    }

    /// A chain or regional person opens the chain's own section; a company person opens that company's Team section; a group person opens Group.
    private func openMember(_ m: TeamOverview.Member) {
        Haptics.tap()
        if m.chainID != nil, let id = m.companyID, m.scope == "chain" || m.scope == "region" { path.append(.companyAt(id, .chain)) }
        else if let id = m.companyID { path.append(.companyAt(id, .staff)) }
        else { store.jump(to: .group) }
    }

    // MARK: Manager performance

    @ViewBuilder private func performance(_ o: TeamOverview, _ e: GameEngine) -> some View {
        if !o.scorecards.isEmpty {
            let lines = Dictionary(o.companies.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let limit = 5
            let shown = showAllScores ? o.scorecards : Array(o.scorecards.prefix(limit))
            LedgerSection(title: "Manager performance", trailing: { Text(o.scorecards.count > 1 ? "weakest first" : "1 manager").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { n, c in
                        if n > 0 { Hairline() }
                        Button { Haptics.tap(); path.append(.companyAt(c.id, .staff)) } label: {
                            HStack(spacing: Theme.Space.m) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(c.managerName).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                                    Text("\(c.companyName)\(lines[c.id].map { authorityWord($0.authority) } ?? "")\((lines[c.id]?.managerLeaving ?? false) ? " · leaving" : "")")
                                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(c.score)").font(.system(size: 14).monospacedDigit()).foregroundStyle(c.score < 35 ? Theme.loss : c.score < 50 ? Theme.caution : c.score >= 65 ? Theme.gain : Theme.ivory)
                                    Text(CompanyManagement.scoreWord(c.score)).font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
                                }
                                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            }.padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if o.scorecards.count > limit {
                        Button(showAllScores ? "Show fewer" : "Show all \(o.scorecards.count)") { withAnimation { showAllScores.toggle() } }
                            .buttonStyle(QuietButtonStyle()).padding(.top, 8)
                    }
                    Text("Scorecard 0 to 100 from margin, reputation, quality, mistakes, paperwork and targets. Open a manager to coach, limit or replace them.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint).padding(.top, 8)
                }
            }
        }
    }

    // MARK: Companies

    @ViewBuilder private func companies(_ o: TeamOverview, _ e: GameEngine) -> some View {
        if !o.companies.isEmpty {
            let lines = o.companies.sorted { (forYou($0, e), $1.name) > (forYou($1, e), $0.name) }
            let grouped = lines.count >= 10
            LedgerSection(title: "Who runs each company", trailing: { Text("\(lines.count)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                if !grouped {
                    VStack(spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { n, l in
                            if n > 0 { Hairline() }
                            Button { Haptics.tap(); path.append(.companyAt(l.id, .staff)) } label: { companyRow(l, e) }.buttonStyle(.plain)
                        }
                    }
                } else {
                    let groups = groupLines(lines)
                    VStack(spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.element.key) { n, g in
                            if n > 0 { Hairline() }
                            companyGroup(g, e)
                        }
                    }
                }
            }
        }
    }

    private struct LineGroup { var key: String; var title: String; var kind: String; var lines: [TeamOverview.CompanyLine] }

    /// Chains first, then holdings, then everything else, each with its companies.
    private func groupLines(_ lines: [TeamOverview.CompanyLine]) -> [LineGroup] {
        var order: [String] = []
        var map: [String: LineGroup] = [:]
        for l in lines {
            var k = "solo", t = "Single companies", kind = "single"
            if let c = l.chainID { k = "c\(c)"; t = l.chainName ?? "Chain"; kind = "chain" }
            else if let h = l.holdingID { k = "h\(h)"; t = l.holdingName ?? "Holding"; kind = "holding" }
            else if l.isHolding { k = "h\(l.id)"; t = l.name; kind = "holding" }
            if map[k] == nil { map[k] = LineGroup(key: k, title: t, kind: kind, lines: []); order.append(k) }
            map[k]?.lines.append(l)
        }
        let rank = ["chain": 0, "holding": 1, "single": 2]
        return order.compactMap { map[$0] }.sorted { (rank[$0.kind] ?? 3, $0.title) < (rank[$1.kind] ?? 3, $1.title) }
    }

    private func isOpen(_ g: LineGroup) -> Bool {
        if openGroups.contains(g.key) { return true }
        if closedGroups.contains(g.key) { return false }
        return g.lines.contains { $0.issues > 0 } || g.lines.count <= 3
    }

    @ViewBuilder private func companyGroup(_ g: LineGroup, _ e: GameEngine) -> some View {
        let open = isOpen(g)
        let needs = g.lines.reduce(0) { $0 + forYou($1, e) }
        let byMgr = g.lines.filter { $0.delegated }.count
        let weak = g.lines.filter { ($0.score ?? 100) < 35 }.count
        Button {
            withAnimation {
                if open { openGroups.remove(g.key); closedGroups.insert(g.key) } else { closedGroups.remove(g.key); openGroups.insert(g.key) }
            }
        } label: {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.title.tidyMoney).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                    Text("\(g.lines.count) \(g.lines.count == 1 ? "company" : "companies") · \(byMgr) with a boss\(weak > 0 ? " · \(weak) weak" : "")")
                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer(minLength: 8)
                if needs > 0 { Text("\(needs) for you").font(.system(size: 11)).foregroundStyle(Theme.caution) }
            }.padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(.plain)
        if open {
            ForEach(g.lines) { l in
                Hairline()
                Button { Haptics.tap(); path.append(.companyAt(l.id, .staff)) } label: { companyRow(l, e).padding(.leading, 26) }.buttonStyle(.plain)
            }
        }
    }

    private func companyRow(_ l: TeamOverview.CompanyLine, _ e: GameEngine) -> some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(l.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text(l.delegated ? "\(l.managedBy) · \((l.managerTitle ?? "manager").lowercased())\(authorityWord(l.authority))\(l.managerLeaving ? " · leaving" : "")" : "You run it")
                    .font(.system(size: 11)).foregroundStyle(l.delegated ? Theme.ivoryFaint : Theme.ivoryMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(l.isHolding ? "holding" : l.staff.peopleText).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivory)
                if let sc = l.score { Text("score \(sc)").font(.system(size: 11)).foregroundStyle(sc < 35 ? Theme.loss : Theme.ivoryFaint) }
                if forYou(l, e) > 0 { Text("\(forYou(l, e)) for you").font(.system(size: 11)).foregroundStyle(Theme.caution) }
            }
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }
        .padding(.vertical, 8).contentShape(Rectangle())
    }

    private func authorityWord(_ lvl: Int) -> String {
        switch lvl { case 0: return " · asks you"; case 1: return " · within limits"; case 2: return " · full control"; default: return "" }
    }

    // MARK: Search across everyone

    @ViewBuilder private func searchResults(_ e: GameEngine) -> some View {
        let found = e.teamPeopleSearch(query: query)
        LedgerSection(title: "Search", trailing: { Text("\(found.count)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            if found.isEmpty { Text("No one matches.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
            VStack(spacing: 0) {
                ForEach(Array(found.prefix(100).enumerated()), id: \.element.id) { n, f in
                    if n > 0 { Hairline() }
                    if let companyID = f.companyID {
                        Button { Haptics.tap(); path.append(.companyAt(companyID, .staff)) } label: { searchRow(f, opens: true) }.buttonStyle(.plain)
                    } else {
                        searchRow(f, opens: false)
                    }
                }
            }
        }
    }

    /// One search hit: name, job and who employs them (a company, a chain, a holding or the group office).
    private func searchRow(_ f: TeamSearchResult, opens: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(f.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text("\(f.role) · \(f.employer)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
            }
            Spacer()
            if opens { Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
        }.padding(.vertical, 8).contentShape(Rectangle())
    }
}
