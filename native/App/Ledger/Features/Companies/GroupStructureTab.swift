import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Structure tab of the Group: what you own and who runs it. A hero with the group's value, how much of it you control, influence or
/// only hold, and one line on managers and waiting decisions; then the tree from `engine.structureTree()` collapsed to you and your
/// holdings, chains and companies. A card opens to show what sits under it (locations, subsidiaries, divisions, stakes) and its chain of
/// command. Anything struggling or waiting on a decision opens its parents on first sight.
struct GroupStructureTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var onPick: (GroupEntity, GroupSection) -> Void
    @Environment(\.outsidePalette) private var P
    @State private var expanded: Set<String> = []
    @State private var seeded = false

    /// One visible card and how deep it sits.
    private struct Row: Identifiable {
        var node: StructureNode
        var depth: Int
        var id: String { node.id }
    }

    var body: some View {
        let nodes: [StructureNode] = store.memo("structureTree") { (e: GameEngine) -> [StructureNode] in e.structureTree() } ?? []
        let mgmt: GroupManagement? = store.memo("groupMgmt") { (e: GameEngine) -> GroupManagement in e.groupManagement() }
        let list: [GroupEntity] = GroupEntities.cached(store) ?? GroupEntities.build(engine)
        let lines: [Int: GroupManagement.Line] = Dictionary((mgmt?.lines ?? []).map { (l: GroupManagement.Line) -> (Int, GroupManagement.Line) in (l.id, l) }, uniquingKeysWith: { (a: GroupManagement.Line, _: GroupManagement.Line) -> GroupManagement.Line in a })
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if nodes.count <= 1 {
                EmptyState(glyph: Glyph.group, title: "No companies yet", message: "Add one from Overview.")
            } else {
                hero(nodes, mgmt)
                VStack(spacing: Theme.Space.s) {
                    ForEach(rows(nodes)) { (r: Row) in
                        card(r, nodes, lines, list)
                    }
                }
            }
        }
        .onAppear { seed(nodes) }
    }

    // MARK: Tree

    /// The cards in display order: the children of you, then the children of every open card.
    private func rows(_ nodes: [StructureNode]) -> [Row] {
        var kids: [String: [StructureNode]] = [:]
        for n in nodes { if let p = n.parentID { kids[p, default: []].append(n) } }
        var out: [Row] = []
        func walk(_ id: String, _ depth: Int) {
            for c in kids[id] ?? [] {
                out.append(Row(node: c, depth: depth))
                if expanded.contains(c.id) { walk(c.id, depth + 1) }
            }
        }
        walk("you", 0)
        return out
    }

    /// The parents of every struggling node or node with a decision waiting, all the way up (you is always open).
    private func autoExpanded(_ nodes: [StructureNode]) -> Set<String> {
        var byID: [String: StructureNode] = [:]
        for n in nodes { byID[n.id] = n }
        var out = Set<String>()
        for n in nodes where n.health == .struggling || n.waitingDecisions > 0 {
            var p: String? = n.parentID
            while let id = p, id != "you" {
                out.insert(id)
                p = byID[id]?.parentID
            }
        }
        return out
    }

    private func seed(_ nodes: [StructureNode]) {
        guard !seeded, nodes.count > 1 else { return }
        seeded = true
        expanded.formUnion(autoExpanded(nodes))
    }

    private func toggle(_ id: String) {
        Motion.animate(Motion.quickAnimation) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }

    // MARK: Card

    private func card(_ r: Row, _ nodes: [StructureNode], _ lines: [Int: GroupManagement.Line], _ list: [GroupEntity]) -> some View {
        let n: StructureNode = r.node
        let rungs: [StructureRung] = chainOfCommand(n, nodes, lines)
        let hasKids: Bool = nodes.contains { (x: StructureNode) -> Bool in x.parentID == n.id }
        let person: Person? = n.runnerPersonID.flatMap { (id: Int) -> Person? in engine.state.people[id] }
        let own: Bool = n.kind == .holding || n.kind == .chain || n.kind == .company
        let target: GroupEntity? = entity(for: n, list)
        let actionID: String = own ? (target.map { (g: GroupEntity) -> String in "group-entity-\(g.id)" } ?? "") : ""
        return StructureCard(node: n, valueText: store.short(n.value), runnerRole: person?.role, runnerFace: person?.faceKey, rungs: rungs,
                             canExpand: hasKids || !rungs.isEmpty, expanded: expanded.contains(n.id), actionID: actionID,
                             onToggle: { toggle(n.id) }, onAction: { perform(n, own: own, target: target) })
            .padding(.leading, CGFloat(r.depth) * Theme.Space.l)
    }

    /// From the top of the chain down to the person who runs the company; a chain takes its head office's.
    private func chainOfCommand(_ n: StructureNode, _ nodes: [StructureNode], _ lines: [Int: GroupManagement.Line]) -> [StructureRung] {
        var cid: Int? = n.companyID
        if cid == nil, n.kind == .chain {
            cid = nodes.first(where: { (x: StructureNode) -> Bool in x.parentID == n.id && x.kind == .headOffice })?.companyID
        }
        guard let id = cid, let line = lines[id] else { return [] }
        var all: [GroupManagement.Rung] = Array(line.above.reversed())
        if let runner = line.runner { all.append(runner) }
        return all.map { (r: GroupManagement.Rung) -> StructureRung in
            let p: Person? = engine.state.people[r.personID]
            return StructureRung(id: r.id, name: r.name, title: r.title, authority: r.authorityText, role: p?.role, face: p?.faceKey)
        }
    }

    // MARK: Opening

    /// The Group page of a chain, holding or company; a location of a chain finds the chain's page.
    private func entity(for n: StructureNode, _ list: [GroupEntity]) -> GroupEntity? {
        if n.kind == .chain, let cid = Int(n.id.dropFirst("chain:".count)) {
            return list.first(where: { (g: GroupEntity) -> Bool in g.chainID == cid })
        }
        guard let c = n.companyID else { return nil }
        return GroupEntities.find(list, companyID: c)
    }

    /// Decide opens the board, Appoint manager the Management tab, Fix and Open the page itself; locations, divisions and stakes open their company.
    private func perform(_ n: StructureNode, own: Bool, target: GroupEntity?) {
        switch n.primaryAction {
        case .decide: go(target, .board, n)
        case .appointManager: go(target, .management, n)
        case .fix, .open: go(own ? target : nil, .overview, n)
        }
    }

    private func go(_ g: GroupEntity?, _ section: GroupSection, _ n: StructureNode) {
        if let g { onPick(g, section) } else if let c = n.companyID { store.openCompany(c) }
    }

    // MARK: Hero

    private func hero(_ nodes: [StructureNode], _ mgmt: GroupManagement?) -> some View {
        let value: Double = (store.netWorthNow ?? engine.netWorth).companies
        let hist: DayHistory = store.dayHistoryNow ?? engine.dayHistory
        let vc = DayHistory.change(hist.companies, days: 30)
        let vt = GroupFmt.change(vc?.amount ?? 0, vc?.share, has: vc != nil, store)
        let split: (control: Double, influence: Double, passive: Double) = tierShares(nodes)
        let managers: Int = mgmt?.managerCount ?? 0
        let byYou: Int = mgmt?.runByYou.count ?? 0
        let waiting: Int = engine.boardDecisionsWaiting
        let line: String = "\(managers) \(managers == 1 ? "manager" : "managers") \u{00B7} you run \(byYou) yourself \u{00B7} \(waiting) \(waiting == 1 ? "decision" : "decisions") waiting"
        return Card(padding: Theme.Space.l, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Group value").textStyle(.label, tint: P.inkFaint)
                LiveFigure(value: value, text: store.short(value)).textStyle(.display)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityLabel("Group value " + store.short(value))
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(vt.text).textStyle(.caption, tint: vt.tint, numeric: true).lineLimit(1)
                    if vc != nil { Text("in 30 days").textStyle(.caption, tint: P.inkFaint).lineLimit(1) }
                }
                if split.control + split.influence + split.passive > 0 {
                    StructureSplitBar(control: split.control, influence: split.influence, passive: split.passive)
                    WrapRow(spacing: Theme.Space.m) {
                        Chip(text: "Control " + pct(split.control), tint: Theme.accent)
                        Chip(text: "Influence " + pct(split.influence), tint: Theme.warn)
                        Chip(text: "Passive " + pct(split.passive), tint: Theme.slateBlue)
                    }
                }
                Text(line).textStyle(.caption, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("structure-summary")
            }
        }
    }

    private func pct(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

    /// How the value of what you own splits by how much of each company is yours: over 50% control, 20-50% influence, under 20% passive.
    /// Holdings and chains are left out because the companies under them are counted.
    private func tierShares(_ nodes: [StructureNode]) -> (control: Double, influence: Double, passive: Double) {
        var c: Double = 0
        var i: Double = 0
        var p: Double = 0
        for n in nodes where n.kind != .you && n.kind != .holding && n.kind != .chain {
            let w: Double = max(0, n.value)
            switch HoldingStakes.tier(forPercent: n.holdingPercent ?? n.ownerYouPercent) {
            case .control, .squeezeOut, .whole: c += w
            case .influence: i += w
            case .passive, .none: p += w
            }
        }
        let total: Double = c + i + p
        guard total > 0 else { return (0, 0, 0) }
        return (c / total, i / total, p / total)
    }
}
