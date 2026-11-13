import SwiftUI
import GameCore
import Businesses
import Simulation

enum GroupHomeTab: String, CaseIterable, Hashable {
    case overview = "Overview", people = "People", suppliers = "Suppliers"
}

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
                            anchors: [GroupHomeTab.people: CoachStop.groupPeople])
                .padding(.top, Theme.Space.s)
            SegmentPager(items: GroupHomeTab.allCases, selection: $tab) { (t: GroupHomeTab) in
                ScrollScreen(spacing: Theme.Space.xxl, top: Theme.Space.l) { content(t) }
            }
        }
    }

    @ViewBuilder private func content(_ t: GroupHomeTab) -> some View {
        switch t {
        case .overview: GroupOverviewTab(engine: engine, onAdd: onAdd, onPick: onPick)
        case .people: GroupPeopleTab(engine: engine, onPick: onPick)
        case .suppliers: GroupSupplierDirectory(embedded: true)
        }
    }
}

@MainActor
enum GroupWaiting {
    static func count(_ e: GameEngine, _ g: GroupEntity) -> Int {
        guard let key = e.boardKey(companyID: g.companyID) else { return 0 }
        return e.boardOpenDecisions(key: key)
    }
}

struct GroupOverviewTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var onAdd: () -> Void
    var onPick: (GroupEntity, GroupSection) -> Void
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let list: [GroupEntity] = GroupEntities.cached(store) ?? GroupEntities.build(engine)
        let ov: TeamOverview = store.teamOverviewNow ?? engine.teamOverview()
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            hero(keyFigures(list, ov))
            LedgerRow(leading: .symbol("plus"), title: "Add to group", identifier: "group-add", action: onAdd)
                .coachAnchor(.groupAdd)
            GroupStructureTab(engine: engine, onPick: onPick)
            needsYou(list)
        }
    }

    private func hero<Figures: View>(_ figures: Figures) -> some View {
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
            figures
            if trend.count >= 2 {
                Sparkline(values: trend, tint: (trend.last ?? 0) >= (trend.first ?? 0) ? Theme.accent : Theme.loss)
                    .frame(height: 44)
                    .padding(.top, Theme.Space.xs)
                    .accessibilityHidden(true)
            }
            GroupBrandLine(engine: engine)
        }
    }

    @ViewBuilder private func needsYou(_ list: [GroupEntity]) -> some View {
        let waiting: [Waiting] = list.compactMap { (g: GroupEntity) -> Waiting? in
            let n: Int = GroupWaiting.count(engine, g)
            return n > 0 ? Waiting(entity: g, count: n) : nil
        }
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Decisions waiting").textStyle(.label, tint: P.inkFaint)
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

    private func keyFigures(_ list: [GroupEntity], _ ov: TeamOverview) -> KeyFigures {
        let profit: Double = list.reduce(0) { (a: Double, g: GroupEntity) -> Double in a + g.profit }
        let staff: Int = ov.companies.reduce(0) { (a: Int, l: TeamOverview.CompanyLine) -> Int in a + l.staff }
        let sign: String = profit > 0.5 ? "+" : (profit < -0.5 ? "\u{2212}" : "")
        return KeyFigures(items: [
            KeyFigures.Item(label: "Cash", value: store.short(engine.state.cash), live: engine.state.cash),
            KeyFigures.Item(label: "Profit this month", value: sign + store.short(abs(profit)), tint: Theme.change(profit)),
            KeyFigures.Item(label: "Staff", value: "\(staff)"),
        ])
    }
}

struct GroupPeopleTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var onPick: (GroupEntity, GroupSection) -> Void
    @Environment(\.outsidePalette) private var P
    @State private var sheet: StaffSheet?
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

    private func open(_ m: TeamOverview.Member, _ g: GroupEntity) {
        if let c = m.companyID, m.id.hasPrefix("slot-\(c)-") {
            sheet = .slot(c, String(m.id.dropFirst("slot-\(c)-".count)))
        } else {
            onPick(g, .management)
        }
    }

    private func face(_ personID: Int?) -> String? { personID.flatMap { (id: Int) -> String? in engine.state.people[id]?.faceKey } }

    // People rows read like the company's own people list.
    @ViewBuilder private func personRow(_ row: ThinPersonRow, identifier: String, action: (() -> Void)?) -> some View {
        if let action {
            Button { Haptics.tap(); action() } label: { row }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier(identifier)
        } else {
            row.accessibilityIdentifier(identifier)
        }
    }

    private func memberRow(_ m: TeamOverview.Member, action: (() -> Void)?) -> some View {
        personRow(ThinPersonRow(name: m.name, title: m.role, wage: m.monthlyWage > 0 ? store.short(m.monthlyWage) : nil, chevron: action != nil,
                                roleKey: "executive", face: face(m.personID)),
                  identifier: "group-staff-\(m.id)", action: action)
    }

    private func authority(_ l: TeamOverview.CompanyLine) -> String? {
        switch l.authority {
        case 0: return "Asks you first"
        case 1: return "Within your limits"
        case 2: return "Full control"
        default: return nil
        }
    }

    private func companyRow(_ l: TeamOverview.CompanyLine, passedUp: Int) -> some View {
        let managerID: Int? = engine.state.company(l.id)?.managerID
        // The player's own avatar when they run it; a boss above the store is found by name when the store has no manager of its own.
        let boss: Person? = managerID == nil && l.managerTitle != nil ? engine.state.people.values.first { (p: Person) -> Bool in p.name == l.managedBy } : nil
        let who: String = l.managerTitle ?? "You run it"
        var parts: [String] = [who]
        if passedUp > 0 { parts.append("\(passedUp) passed up to you") } else if l.managerTitle != nil, let a = authority(l) { parts.append(a) }
        let id: Int = l.id
        parts.insert(l.name, at: 0)
        return personRow(ThinPersonRow(name: l.managerTitle == nil ? engine.state.player.name : l.managedBy, title: parts.joined(separator: " \u{00B7} "),
                                       wage: "\(l.staff) staff", chevron: managerID != nil, roleKey: l.managerTitle ?? "manager",
                                       face: face(managerID) ?? boss?.faceKey, isYou: l.managerTitle == nil),
                         identifier: "group-who-\(l.id)", action: managerID == nil ? nil : { sheet = .manager(id) })
    }

    private func seatRow(_ s: ManagerModel.Seat, _ g: GroupEntity) -> some View {
        let p = engine.state.people[s.id]
        let name: String = p?.name ?? s.title
        return personRow(ThinPersonRow(name: name, title: s.title + " \u{00B7} board", roleKey: p?.role ?? "executive", face: p?.faceKey),
                         identifier: "group-seat-\(g.id)-\(s.id)", action: { onPick(g, .board) })
    }
}
