import SwiftUI
import GameCore
import Businesses
import Simulation

/// Group > Structure > Authority: who manages whom. Every company with the person who runs it day to day and the authority they were given,
/// and the chain of bosses between them and you. Staff are not listed here; they report to their company's manager, and the Team tab and a
/// company's Team section show them. The group office (a group managing director and shared services) stays an optional action under More.
/// Read model: `GameEngine.groupManagement()`.
struct GroupAuthoritySection: View {
    var engine: GameEngine
    var openMore: (GroupMorePage) -> Void
    /// Rows shown per chain, holding or group before the rest are summarised.
    private let rowLimit = 6

    var body: some View {
        let g: GroupManagement = engine.groupManagement()
        let grouped: [String: [GroupManagement.Line]] = Dictionary(grouping: g.lines.filter { $0.groupName != nil }, by: { $0.groupName ?? "" })
        let names: [String] = grouped.keys.sorted()
        let alone: [GroupManagement.Line] = g.lines.filter { $0.groupName == nil }
        VStack(alignment: .leading, spacing: 12) {
            if g.lines.isEmpty {
                NoteCard(text: "Start a company to see who runs it.")
            } else {
                summary(g)
                ForEach(names, id: \.self) { name in
                    section(title: name, lines: grouped[name] ?? [])
                }
                if !alone.isEmpty { section(title: names.isEmpty ? "Companies" : "Stand-alone companies", lines: alone) }
                office(g)
            }
        }
    }

    private func summary(_ g: GroupManagement) -> some View {
        let byYou: Int = g.runByYou.count
        let delegated: Int = g.delegated.count
        return Card(padding: 14, radius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 18) {
                    figure("\(g.managerCount)", g.managerCount == 1 ? "manager" : "managers")
                    figure("\(delegated)", delegated == 1 ? "company delegated" : "companies delegated")
                    figure("\(byYou)", byYou == 1 ? "company you run" : "companies you run")
                }
                Text("Each manager runs the staff of their own company and decides within the authority you gave. You decide what is above that. Staff do not report to you directly unless nobody runs their company.")
                    .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 19, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(title: String, lines: [GroupManagement.Line]) -> some View {
        let sorted: [GroupManagement.Line] = lines.sorted { $0.name < $1.name }
        let shown: [GroupManagement.Line] = Array(sorted.prefix(rowLimit))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(1.4).foregroundStyle(Theme.gold)
                Spacer()
                Text("\(lines.count)").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
            }
            ForEach(shown) { line in
                NavigationLink(value: CompanyRoute.companyAt(line.id, .staff)) { row(line) }.buttonStyle(.plain)
            }
            if sorted.count > rowLimit {
                Text("And \(sorted.count - rowLimit) more. Open the Team tab for every manager.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    /// One company: who runs it and with what authority, and the line of bosses up to you. Opens the company's Team.
    private func row(_ line: GroupManagement.Line) -> some View {
        HStack(spacing: 12) {
            IconCircle(glyph: line.runner == nil && line.above.isEmpty ? Glyph.person : Glyph.team)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.isHolding ? "\(line.name) (holding)" : line.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2)
                Text(runnerLine(line)).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                if let up = reportsLine(line) { Text(up).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: Theme.ivoryDim)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Anna Reed, Store manager, decides within your limits", "You run it yourself", or the next in line.
    private func runnerLine(_ line: GroupManagement.Line) -> String {
        if let r = line.runner { return "\(r.name), \(r.title), \(r.authorityText)" }
        if let first = line.above.first { return "No manager at the company; \(first.name) (\(first.title)) decides first" }
        return "You run it yourself"
    }

    /// "Reports to Regional manager Ben Cole, then Group managing director Dee Lane, then you", or nil without a boss.
    private func reportsLine(_ line: GroupManagement.Line) -> String? {
        guard line.runner != nil || !line.above.isEmpty else { return nil }
        if line.above.isEmpty { return "Reports to you" }
        let rest: [GroupManagement.Rung] = line.runner == nil ? Array(line.above.dropFirst()) : line.above
        if rest.isEmpty { return "Reports to you" }
        return "Reports to " + rest.map { "\($0.title) \($0.name)" }.joined(separator: ", then ") + ", then you"
    }

    private func office(_ g: GroupManagement) -> some View {
        Button { Haptics.tap(); openMore(.office) } label: {
            CardRow(glyph: Glyph.team, title: "Group office",
                    subtitle: g.groupOfficeEstablished ? "Group managing director, reviews and shared services." : "Optional. Set it up only if you want posts above the companies.")
        }.buttonStyle(.plain)
    }
}
