import SwiftUI
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
    @State private var path: [CompanyRoute] = []
    @State private var tab: Tab = .overview
    @State private var query = ""
    @State private var filter: PeopleFilter = .all
    @State private var showDelegated = false
    @State private var showAllScores = false
    @State private var openGroups: Set<String> = []
    @State private var closedGroups: Set<String> = []

    var body: some View {
        NavigationStack(path: $path) {
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
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .ledgerBackground()
            .toolbar(.hidden, for: .navigationBar)
            .companyRouteDestinations()
            .routeRequests(for: .team, path: $path)
            .returnBar(for: .team)
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
                Button { Haptics.tap(); withAnimation(.easeOut(duration: 0.15)) { tab = t } } label: {
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

    @ViewBuilder private func overview(_ o: TeamOverview, _ e: GameEngine, _ alerts: [PayrollAlertInfo]) -> some View {
        let live = o.companies.filter { !$0.isHolding }
        let byManagers = live.filter { $0.delegated }.count
        let needed = o.vacancies.filter { $0.needed }.count
        let people = peopleIssues(o, e)
        let mine = people.filter { $0.needsOwner }
        let theirs = people.filter { !$0.needsOwner }
        let need = mine.count + alerts.count

        StatStrip(cells: [
            .init(label: "Need you", value: "\(need)", tint: need > 0 ? Theme.caution : Theme.ivory),
            .init(label: "Run by managers", value: "\(byManagers) of \(live.count)"),
            .init(label: "Posts to fill", value: "\(o.vacancies.count)", tint: needed > 0 ? Theme.loss : Theme.ivory),
        ], ruled: false)
        .padding(.vertical, 12).teamCard(radius: Theme.Radius.hero)

        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Needs you", trailing: need == 0 ? "nothing" : "")
            if need == 0 {
                Text(o.companies.isEmpty ? "No one works for you yet. Open a company, then hire from its Team section." : "Nothing needs you. Your managers have the rest in hand.")
                    .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).padding(.vertical, 4)
            }
            ForEach(alerts, id: \.companyID) { a in
                let money = e.state.company(a.companyID).map { store.money(a.amount, in: $0) } ?? store.money(a.amount)
                needCard(title: "Payroll \(money) needs your approval", note: "\(a.companyName) · \(a.dateText) · no manager or accountant", tint: Theme.caution, beyond: false) {
                    Haptics.tap(); path.append(.companyAt(a.companyID, .finances))
                }
            }
            ForEach(mine.prefix(12)) { i in
                needCard(title: i.title, note: i.beyondAuthority ? "Above their authority · \(i.detail)" : i.detail, tint: i.severity >= 3 ? Theme.loss : Theme.caution, beyond: i.beyondAuthority) { open(i, e) }
            }
            if mine.count > 12 { Text("And \(mine.count - 12) more in the companies below.").font(.caption2).foregroundStyle(Theme.ivoryFaint) }
            if !theirs.isEmpty { handledByManagers(theirs, e) }
        }

        if !o.companies.isEmpty { companies(o, e) }
    }

    private func needCard(title: String, note: String, tint: Color, beyond: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GlyphView(glyph: Glyph.warning, size: 16, weight: 1.8, tint: tint)
                    .frame(width: 34, height: 34).background(Circle().fill(tint.opacity(0.12)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.tidyMoney).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Text(note.tidyMoney).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
            .teamCard().contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func handledByManagers(_ theirs: [TeamOverview.Issue], _ e: GameEngine) -> some View {
        Button { withAnimation { showDelegated.toggle() } } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Handled by your managers · \(theirs.count)").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                    if !showDelegated { Text("Staff trouble in companies a manager runs. Their job; open one to look closer.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.leading) }
                }
                Spacer(minLength: 8)
                Image(systemName: showDelegated ? "chevron.up" : "chevron.down").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }.padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(.plain)
        if showDelegated {
            ForEach(theirs) { i in
                needCard(title: i.title, note: "\(i.handledBy) · \(i.detail)", tint: Theme.ivoryFaint, beyond: false) { open(i, e) }
            }
        }
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

    // MARK: Who runs each company

    @ViewBuilder private func companies(_ o: TeamOverview, _ e: GameEngine) -> some View {
        let lines = o.companies.sorted { (forYou($0, e), $1.name) > (forYou($1, e), $0.name) }
        let grouped = lines.count >= 10
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Who runs each company", trailing: grouped ? "\(lines.count)" : "")
            if !grouped {
                ForEach(lines) { l in
                    Button { Haptics.tap(); path.append(.companyAt(l.id, .staff)) } label: { companyRow(l, e).padding(.horizontal, 14).teamCard() }.buttonStyle(.plain)
                }
            } else {
                ForEach(groupLines(lines), id: \.key) { g in
                    VStack(spacing: 0) { companyGroup(g, e) }.padding(.horizontal, 14).teamCard()
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
                    Text(g.title.tidyMoney).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                    Text("\(g.lines.count) \(g.lines.count == 1 ? "company" : "companies") · \(byMgr) with a boss\(weak > 0 ? " · \(weak) weak" : "")")
                        .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                }
                Spacer(minLength: 8)
                if needs > 0 { Text("\(needs) for you").font(.system(size: 11)).foregroundStyle(Theme.caution) }
            }.padding(.vertical, 11).contentShape(Rectangle())
        }.buttonStyle(.plain)
        if open {
            ForEach(g.lines) { l in
                Hairline()
                Button { Haptics.tap(); path.append(.companyAt(l.id, .staff)) } label: { companyRow(l, e).padding(.leading, 26) }.buttonStyle(.plain)
            }
        }
    }

    private func companyRow(_ l: TeamOverview.CompanyLine, _ e: GameEngine) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(l.name).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text(l.delegated ? "\(l.managedBy) · \((l.managerTitle ?? "manager").lowercased())\(authorityWord(l.authority))\(l.managerLeaving ? " · leaving" : "")" : "You run it")
                    .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(l.isHolding ? "holding" : l.staff.peopleText).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
                if forYou(l, e) > 0 { Text("\(forYou(l, e)) for you").font(.system(size: 12)).foregroundStyle(Theme.gold) }
                else if let sc = l.score, sc < 35 { Text("score \(sc)").font(.system(size: 12)).foregroundStyle(Theme.loss) }
            }
            GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
        }
        .padding(.vertical, 11).contentShape(Rectangle())
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

    private func personCard(_ p: TeamSearchResult, _ e: GameEngine) -> some View {
        let initials = String(p.name.split(separator: " ").prefix(2).compactMap { $0.first })
        let wage: String = p.monthlyWage > 0 ? ((p.companyID.flatMap { e.state.company($0) }.map { store.short(p.monthlyWage, in: $0) } ?? store.short(p.monthlyWage)) + "/mo") : "no wage"
        return HStack(spacing: 12) {
            Text(initials).font(.system(size: 13)).foregroundStyle(Theme.gold).frame(width: 38, height: 38).background(Circle().fill(Color(hex: 0x1E1F21)))
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
        ForEach(alerts, id: \.companyID) { a in
            HStack(spacing: 10) {
                GlyphView(glyph: Glyph.warning, size: 16, weight: 1.9, tint: Theme.caution)
                Text("Nobody approves payroll at \(a.companyName), so it comes to you every month.").font(.system(size: 12.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Button { Haptics.tap(); path.append(.companyAt(a.companyID, .staff)) } label: {
                    Text("Appoint ›").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ivory)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.gold, lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("Appoint someone at \(a.companyName)")
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.caution.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Color(hex: 0x6A5630), lineWidth: 1))
        }
        if o.companies.isEmpty {
            Text("No companies yet.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
        }
        ForEach(o.companies.filter { !$0.isHolding }) { l in delegationCard(l, e, alerts) }
        if !o.companies.isEmpty {
            Text("A manager or accountant approves routine payroll and spending up to the limit you set. Anything bigger always comes to you.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryDim).fixedSize(horizontal: false, vertical: true)
        }
        performance(o, e)
    }

    private func delegationCard(_ l: TeamOverview.CompanyLine, _ e: GameEngine, _ alerts: [PayrollAlertInfo]) -> some View {
        let co = e.state.company(l.id)
        let auth = co?.value("auth")
        let hasMgr = l.authority >= 0
        let lvl = max(0, l.authority)
        let nobodyPays = alerts.contains { $0.companyID == l.id }
        func money(_ v: Double) -> String { co.map { store.short(v, in: $0) } ?? store.short(v) }
        let buy = auth?["buy"].double ?? 0
        let spend: String = !hasMgr || lvl == 0 ? "Ask me always" : lvl == 1 ? "Manager, up to \(money(buy))" : "Manager decides alone"
        let hire: String = !hasMgr || lvl == 0 ? "You" : lvl == 1 ? "Manager, up to \(money(buy))" : "Manager decides alone"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(l.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                Spacer()
                Text(l.staff.peopleText).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }
            Button { Haptics.tap(); path.append(.companyAt(l.id, .staff)) } label: {
                delegRow("Runs it", l.delegated ? "\(l.managedBy)\(l.managerLeaving ? " (leaving)" : "")" : "You",
                         l.delegated ? (l.managerTitle ?? "manager").lowercased() : "appoint manager", l.delegated ? Theme.ivoryFaint : Theme.gold)
            }.buttonStyle(.plain)
            Button { Haptics.tap(); path.append(.companyAt(l.id, .finances)) } label: {
                delegRow("Payroll", hasMgr && lvl >= 1 ? "\(l.managedBy), by their rule" : "You, every month",
                         nobodyPays ? "appoint" : hasMgr && lvl >= 1 ? "rule" : "your call", nobodyPays ? Theme.caution : hasMgr && lvl >= 1 ? Theme.ivoryFaint : Theme.gold)
            }.buttonStyle(.plain)
            if hasMgr {
                Menu {
                    ForEach([0, 1, 2], id: \.self) { v in
                        Button(["Asks you first", "Decides within your limits", "Decides on their own"][v]) { setAuthority(l, v) }
                    }
                } label: { delegRow("Spending", spend, "set limit", Theme.gold) }
            } else {
                Button { Haptics.tap(); path.append(.companyAt(l.id, .staff)) } label: { delegRow("Spending", spend, "set limit", Theme.gold) }.buttonStyle(.plain)
            }
            Button { Haptics.tap(); path.append(.companyAt(l.id, .staff)) } label: {
                delegRow("Hiring", hire, hasMgr ? "change" : "delegate", Theme.gold)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading).teamCard(radius: Theme.Radius.hero)
    }

    private func delegRow(_ what: String, _ who: String, _ note: String, _ tint: Color) -> some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 8) {
                Text(what).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).frame(width: 78, alignment: .leading)
                Text(who).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ivory).frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                Text("\(note) ›").font(.system(size: 11.5)).foregroundStyle(tint).lineLimit(1)
            }.padding(.top, 8)
        }.contentShape(Rectangle())
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
