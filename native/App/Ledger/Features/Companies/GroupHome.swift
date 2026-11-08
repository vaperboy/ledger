import SwiftUI
import GameCore
import Businesses
import Simulation

/// The four tabs of the Group tab.
enum GroupHomeTab: String, CaseIterable, Hashable {
    case overview = "Overview", structure = "Structure", people = "People", suppliers = "Suppliers"
}

/// The Group tab under its title: the tab strip and the chosen tab. Overview is the dashboard (with the way to add to the group),
/// Structure what owns and manages what (each card opens its page), People everyone who works for the group, Suppliers the group's supplier directory.
struct GroupHome: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @Binding var tab: GroupHomeTab
    var onAdd: () -> Void
    var onPick: (GroupEntity, GroupSection) -> Void

    var body: some View {
        let list: [GroupEntity] = GroupEntities.cached(store) ?? GroupEntities.build(engine)
        let waiting: Int = list.reduce(0) { (a: Int, g: GroupEntity) -> Int in a + GroupWaiting.count(engine, g) }
        let badges: [GroupHomeTab: Int] = waiting > 0 ? [GroupHomeTab.overview: waiting] : [:]
        VStack(spacing: 0) {
            GroupSectionBar(tab: $tab, badges: badges, sections: GroupHomeTab.allCases, idPrefix: "group-home-tab-",
                            anchors: [GroupHomeTab.structure: CoachStop.groupStructure, GroupHomeTab.people: CoachStop.groupPeople])
                .padding(.top, Theme.Space.s)
            SegmentPager(items: GroupHomeTab.allCases, selection: $tab) { (t: GroupHomeTab) in
                ScrollScreen(spacing: Theme.Space.xxl, top: Theme.Space.l) { content(t) }
            }
        }
    }

    @ViewBuilder private func content(_ t: GroupHomeTab) -> some View {
        switch t {
        case .overview: GroupOverviewTab(engine: engine, onAdd: onAdd, onPick: onPick, onStructure: { tab = .structure })
        case .structure: GroupStructureTab(engine: engine, onPick: onPick)
        case .people: GroupPeopleTab(engine: engine, onPick: onPick)
        case .suppliers: GroupSupplierDirectory(embedded: true)
        }
    }
}

/// Board decisions waiting for you on one entity (none on a company inside a holding: its board is the holding's page).
@MainActor
enum GroupWaiting {
    static func count(_ e: GameEngine, _ g: GroupEntity) -> Int {
        guard !g.indent, let key = e.boardKey(companyID: g.companyID) else { return 0 }
        return e.boardOpenDecisions(key: key)
    }
}

// MARK: - Overview

/// The group's value with its 30-day change and trend, the way to add to the group, what waits for you, the key figures and who runs what.
struct GroupOverviewTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var onAdd: () -> Void
    var onPick: (GroupEntity, GroupSection) -> Void
    var onStructure: () -> Void
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let list: [GroupEntity] = GroupEntities.cached(store) ?? GroupEntities.build(engine)
        let ov: TeamOverview = store.teamOverviewNow ?? engine.teamOverview()
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                hero
                LedgerRow(leading: .symbol("plus"), title: "Add to group", identifier: "group-add", action: onAdd)
                    .coachAnchor(.groupAdd)
            }
            needsYou(list)
            keyFigures(list, ov)
            whoRunsWhat(ov)
        }
    }

    // MARK: Hero

    /// The group's value is the one big number; its 30-day change, the cash inside the companies and the trend line sit under it.
    private var hero: some View {
        let value: Double = (store.netWorthNow ?? engine.netWorth).companies
        let hist: DayHistory = store.dayHistoryNow ?? engine.dayHistory
        let vc = DayHistory.change(hist.companies, days: 30)
        let vt = GroupFmt.change(vc?.amount ?? 0, vc?.share, has: vc != nil, store)
        var amount: String = ""
        if let c = vc { amount = (c.amount >= 0 ? "+" : "\u{2212}") + store.short(abs(c.amount)) }
        let trend: [Double] = Array(hist.companies.suffix(90))
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Group value").textStyle(.label, tint: P.inkFaint)
            LiveFigure(value: value, text: store.short(value)).textStyle(.display)
                .lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityLabel("Group value " + store.short(value))
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(vc == nil ? vt.text : vt.text + "  " + amount).textStyle(.caption, tint: vt.tint, numeric: true).lineLimit(1)
                Text("in 30 days").textStyle(.caption, tint: P.inkFaint).lineLimit(1)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            if trend.count >= 2 {
                Sparkline(values: trend, tint: (trend.last ?? 0) >= (trend.first ?? 0) ? Theme.accent : Theme.loss)
                    .frame(height: 44)
                    .padding(.top, Theme.Space.xs)
                    .accessibilityHidden(true)
            }
            GroupBrandLine(engine: engine)
        }
    }

    // MARK: Needs you

    /// Board decisions that wait for you, one tappable tile per entity; nothing when the boards are quiet.
    @ViewBuilder private func needsYou(_ list: [GroupEntity]) -> some View {
        let waiting: [Waiting] = list.compactMap { (g: GroupEntity) -> Waiting? in
            let n: Int = GroupWaiting.count(engine, g)
            return n > 0 ? Waiting(entity: g, count: n) : nil
        }
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Needs you").textStyle(.label, tint: P.inkFaint)
                ForEach(waiting) { (w: Waiting) in tile(w) }
            }
        }
    }

    private func tile(_ w: Waiting) -> some View {
        let g: GroupEntity = w.entity
        let n: Int = w.count
        return Button { Haptics.tap(); onPick(g, .board) } label: {
            HStack(spacing: Theme.Space.m) {
                LedgerGlyph(glyph: Glyph.achievements, size: Theme.Icon.large, tint: P.accent)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("\(n) board \(n == 1 ? "decision" : "decisions") waiting").textStyle(.headline).lineLimit(2)
                    Text(g.name).textStyle(.caption).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s)
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("group-needs-\(g.id)")
    }

    private struct Waiting: Identifiable {
        var entity: GroupEntity
        var count: Int
        var id: String { entity.id }
    }

    // MARK: Key figures

    /// Cash in the companies, this month's profit of the whole group, and the headcount.
    private func keyFigures(_ list: [GroupEntity], _ ov: TeamOverview) -> some View {
        let profit: Double = list.filter { (g: GroupEntity) -> Bool in !g.indent }.reduce(0) { (a: Double, g: GroupEntity) -> Double in a + g.profit }
        let staff: Int = ov.companies.reduce(0) { (a: Int, l: TeamOverview.CompanyLine) -> Int in a + l.staff }
        let sign: String = profit > 0.5 ? "+" : (profit < -0.5 ? "\u{2212}" : "")
        return KeyFigures(items: [
            KeyFigures.Item(label: "Cash", value: store.short(engine.groupCash), live: engine.groupCash),
            KeyFigures.Item(label: "Profit this month", value: sign + store.short(abs(profit)), tint: Theme.change(profit)),
            KeyFigures.Item(label: "Staff", value: "\(staff)"),
        ])
    }

    // MARK: Who runs what

    /// One row that opens Structure: how many companies have a manager, how many you run yourself, requests passed up to you.
    private func whoRunsWhat(_ ov: TeamOverview) -> some View {
        let lines: [TeamOverview.CompanyLine] = ov.companies.filter { (l: TeamOverview.CompanyLine) -> Bool in !l.isHolding }
        let managed: Int = lines.filter { (l: TeamOverview.CompanyLine) -> Bool in l.managerTitle != nil }.count
        let passed: Int = ov.issues.filter { (i: TeamOverview.Issue) -> Bool in i.beyondAuthority }.count
        var parts: [String] = ["\(managed) with a manager", "you run \(lines.count - managed)"]
        if passed > 0 { parts.append("\(passed) passed up to you") }
        return LedgerRow(leading: .glyph(Glyph.group), title: "Who runs what", subtitle: parts.joined(separator: " \u{00B7} "),
                         badge: passed, identifier: "group-who-runs-what", action: onStructure)
    }
}

// MARK: - People

/// The People tab: everyone who works for the group in one place: the totals, the group's own management, then per company, holding and chain who runs
/// each company (with its headcount and wages), its executives and its board seats. A person opens their profile.
struct GroupPeopleTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var onPick: (GroupEntity, GroupSection) -> Void
    @Environment(\.outsidePalette) private var P
    @State private var sheet: StaffSheet?
    // Shortlists live here, not in the sheets, so a paid search survives closing a sheet.
    @State private var candidates: [String: [Int]] = [:]

    enum StaffSheet: Identifiable, Hashable {
        case manager(Int), slot(Int, String)
        var id: String {
            switch self {
            case .manager(let c): return "m\(c)"
            case .slot(let c, let s): return "s\(c):\(s)"
            }
        }
    }

    var body: some View {
        let ov: TeamOverview = store.teamOverviewNow ?? engine.teamOverview()
        let list: [GroupEntity] = GroupEntities.cached(store) ?? GroupEntities.build(engine)
        let staff: Int = ov.companies.reduce(0) { (a: Int, l: TeamOverview.CompanyLine) -> Int in a + l.staff }
        let managers: Int = ov.companies.filter { (l: TeamOverview.CompanyLine) -> Bool in l.managerTitle != nil }.count + ov.members.count
        let wages: Double = ov.companies.reduce(0) { (a: Double, l: TeamOverview.CompanyLine) -> Double in a + l.monthlyWages }
            + ov.members.reduce(0) { (a: Double, m: TeamOverview.Member) -> Double in a + m.monthlyWage }
        let office: [TeamOverview.Member] = ov.members.filter { (m: TeamOverview.Member) -> Bool in m.companyID == nil && m.chainID == nil && m.id != "md" }
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            KeyFigures(items: [
                KeyFigures.Item(label: "Staff", value: "\(staff)"),
                KeyFigures.Item(label: "Managers", value: "\(managers)"),
                KeyFigures.Item(label: "Wages a month", value: store.short(wages)),
            ])
            if ov.groupOffice.established || !engine.groupManagingDirector.isNull {
                ExecutivePosts(engine: engine, chainID: nil)
            }
            if !office.isEmpty {
                block("Group office", trailing: "") {
                    ForEach(Array(office.enumerated()), id: \.element.id) { (n: Int, m: TeamOverview.Member) in
                        if n > 0 { rule }
                        memberRow(m, action: nil)
                    }
                }
            }
            ForEach(list) { (g: GroupEntity) in entityBlock(g, ov) }
        }
        .centerSheet(item: $sheet, category: .detail, tone: .info) { (s: StaffSheet) in
            Group {
                switch s {
                case .manager(let c):
                    ManagerSheet(companyID: c, candidates: binding(s.id))
                case .slot(let c, let slot):
                    TeamSlotSheet(companyID: c, slotID: slot, candidates: binding(s.id))
                }
            }
            .environmentObject(store)
        }
    }

    private func binding(_ key: String) -> Binding<[Int]> {
        Binding(get: { candidates[key] ?? [] }, set: { candidates[key] = $0 })
    }

    private var rule: some View { Hairline().padding(.leading, 40 + Theme.Space.m) }

    /// A titled list: the entity's name with its headcount and wages at the right, then its rows.
    private func block<Rows: View>(_ title: String, trailing: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).textStyle(.label, tint: P.inkFaint).lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                if !trailing.isEmpty { Text(trailing).textStyle(.caption, tint: P.inkFaint, numeric: true).lineLimit(1) }
            }
            VStack(spacing: 0) { rows() }
        }
    }

    // MARK: One entity

    /// A chain covers its stores and its chain-level people; a company or holding covers itself (a holding's companies have their own block).
    @ViewBuilder private func entityBlock(_ g: GroupEntity, _ ov: TeamOverview) -> some View {
        let ids: [Int] = g.isChain ? g.members : [g.companyID]
        let lines: [TeamOverview.CompanyLine] = ov.companies.filter { (l: TeamOverview.CompanyLine) -> Bool in ids.contains(l.id) }
        let execs: [TeamOverview.Member] = ov.members.filter { (m: TeamOverview.Member) -> Bool in
            if m.id.hasPrefix("slot-") { return m.companyID.map { (c: Int) -> Bool in ids.contains(c) } ?? false }
            return g.chainID != nil && m.chainID == g.chainID
        }
        let seats: [ManagerModel.Seat] = engine.boardKey(companyID: g.companyID).map { (k: String) -> [ManagerModel.Seat] in engine.boardSeats(key: k) } ?? []
        let staff: Int = lines.reduce(0) { (a: Int, l: TeamOverview.CompanyLine) -> Int in a + l.staff }
        let wages: Double = lines.reduce(0) { (a: Double, l: TeamOverview.CompanyLine) -> Double in a + l.monthlyWages }
            + execs.reduce(0) { (a: Double, m: TeamOverview.Member) -> Double in a + m.monthlyWage }
        if !lines.isEmpty || !execs.isEmpty || !seats.isEmpty {
            block(g.name, trailing: "\(staff) staff \u{00B7} " + store.short(wages) + " a month") {
                ForEach(Array(execs.enumerated()), id: \.element.id) { (n: Int, m: TeamOverview.Member) in
                    if n > 0 { rule }
                    memberRow(m, action: { open(m, g) })
                }
                ForEach(Array(lines.enumerated()), id: \.element.id) { (n: Int, l: TeamOverview.CompanyLine) in
                    if n > 0 || !execs.isEmpty { rule }
                    companyRow(l, passedUp: ov.issues.filter { (i: TeamOverview.Issue) -> Bool in i.companyID == l.id && i.beyondAuthority }.count)
                }
                ForEach(Array(seats.enumerated()), id: \.element.id) { (n: Int, s: ManagerModel.Seat) in
                    if n > 0 || !execs.isEmpty || !lines.isEmpty { rule }
                    seatRow(s, g)
                }
            }
        }
    }

    /// A company's own executive opens its post; a chain-level one opens the chain's Management.
    private func open(_ m: TeamOverview.Member, _ g: GroupEntity) {
        if let c = m.companyID, m.id.hasPrefix("slot-\(c)-") {
            sheet = .slot(c, String(m.id.dropFirst("slot-\(c)-".count)))
        } else {
            onPick(g, .management)
        }
    }

    private func face(_ personID: Int?) -> String? { personID.flatMap { (id: Int) -> String? in engine.state.people[id]?.faceKey } }

    private func memberRow(_ m: TeamOverview.Member, action: (() -> Void)?) -> some View {
        LedgerRow(leading: .thumb(ThumbSpec(kind: .person, key: "executive", initials: m.name, face: face(m.personID))),
                  title: m.name, subtitle: m.role, value: m.monthlyWage > 0 ? store.short(m.monthlyWage) : "",
                  lineLimit: 1, identifier: "group-staff-\(m.id)", action: action)
    }

    /// "Asks you first" / "Within your limits" / "Full control" for a manager.
    private func authority(_ l: TeamOverview.CompanyLine) -> String? {
        switch l.authority {
        case 0: return "Asks you first"
        case 1: return "Within your limits"
        case 2: return "Full control"
        default: return nil
        }
    }

    /// One company: who runs it and how far they may decide, its headcount and wages. Opens the manager's profile; a company you run yourself has no manager to open.
    private func companyRow(_ l: TeamOverview.CompanyLine, passedUp: Int) -> some View {
        let managerID: Int? = engine.state.company(l.id)?.managerID
        let who: String = l.managerTitle.map { (t: String) -> String in l.managedBy + ", " + t.lowercased() } ?? "You run it"
        var parts: [String] = [who]
        if passedUp > 0 { parts.append("\(passedUp) passed up to you") } else if l.managerTitle != nil, let a = authority(l) { parts.append(a) }
        let id: Int = l.id
        return LedgerRow(leading: .thumb(ThumbSpec(kind: .person, key: l.managerTitle ?? "owner", initials: l.managedBy, face: face(managerID))),
                         title: l.name, subtitle: parts.joined(separator: " \u{00B7} "),
                         value: "\(l.staff) staff", valueNote: l.monthlyWages > 0 ? store.short(l.monthlyWages) : "", lineLimit: 2,
                         identifier: "group-who-\(l.id)", action: managerID == nil ? nil : { sheet = .manager(id) })
    }

    /// A board seat: the person, the seat and its fee. Opens the entity's Boardroom.
    private func seatRow(_ s: ManagerModel.Seat, _ g: GroupEntity) -> some View {
        let p = engine.state.people[s.id]
        let name: String = p?.name ?? s.title
        return LedgerRow(leading: .thumb(ThumbSpec(kind: .person, key: p?.role ?? "executive", initials: name, face: p?.faceKey)),
                         title: name, subtitle: s.title + " \u{00B7} board", lineLimit: 1,
                         identifier: "group-seat-\(g.id)-\(s.id)", action: { onPick(g, .board) })
    }
}
