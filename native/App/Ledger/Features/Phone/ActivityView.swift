import SwiftUI
import GameCore
import Simulation

struct ActivityView: View {
    @EnvironmentObject var store: GameStore
    @State private var scope: Scope = .all
    @State private var kind: Kind? = nil
    @State private var query: String = ""
    private let shown = 300

    private enum Scope: Hashable {
        case all, you, company(Int)
    }

    private enum Kind: String, CaseIterable, Hashable, Identifiable {
        case income, wages, tax, loans, investments, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .income: return "Income"
            case .wages: return "Wages"
            case .tax: return "Tax"
            case .loans: return "Loans"
            case .investments: return "Investments"
            case .other: return "Bills and costs"
            }
        }
        var why: String {
            switch self {
            case .income: return "Money earned or received"
            case .wages: return "Paid to the people who work for you"
            case .tax: return "Paid to or refunded by the tax office"
            case .loans: return "A loan instalment, interest or overdraft cost"
            case .investments: return "Shares, funds and savings"
            case .other: return "A running cost of the business"
            }
        }
    }

    private struct Row: Identifiable {
        var id: String
        var week: Int
        var day: Int?
        var label: String
        var amount: Double
        var who: String
        var scope: Scope
        var kind: Kind
        var balance: Double?
        var company: Company?
    }

    private func classify(_ label: String, amount: Double) -> Kind {
        let l: String = label.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { l.contains($0) } }
        if has(["tax", "vat"]) { return .tax }
        if has(["payroll", "back pay", "wage"]) { return .wages }
        if has(["loan", "overdraft", "interest", "mortgage", "instalment"]) { return .loans }
        if has(["bought", "sold ", "dividend", "fund manager", "savings", "deposit", "showcase funds"]) { return .investments }
        return amount > 0 ? .income : .other
    }

    private func rows(_ e: GameEngine) -> [Row] {
        var out: [Row] = []
        for (n, line) in e.state.statement.prefix(shown).enumerated() {
            let place: Company? = line.companyID != 0 ? e.state.company(line.companyID) : nil
            out.append(Row(id: "me-\(n)", week: line.week, day: line.day, label: line.label, amount: line.amount, who: place.map { "You, for " + $0.name } ?? "You",
                           scope: .you, kind: classify(line.label, amount: line.amount), balance: line.balanceAfter, company: nil))
        }
        for m in e.companyMovements() {
            out.append(Row(id: "co-" + m.id, week: m.week, day: nil, label: m.label, amount: m.amount, who: m.companyName,
                           scope: .company(m.companyID), kind: classify(m.label, amount: m.amount), balance: nil, company: e.state.company(m.companyID)))
        }
        return out.enumerated().sorted { (a, b) -> Bool in
            if a.element.week != b.element.week { return a.element.week > b.element.week }
            if (a.element.day ?? -1) != (b.element.day ?? -1) { return (a.element.day ?? -1) > (b.element.day ?? -1) }
            return a.offset < b.offset
        }.map { $0.element }
    }

    private func visible(_ all: [Row]) -> [Row] {
        let q: String = query.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { (r: Row) -> Bool in
            if scope != .all && r.scope != scope { return false }
            if let kind, r.kind != kind { return false }
            if !q.isEmpty && !(r.label.lowercased().contains(q) || r.who.lowercased().contains(q) || r.kind.title.lowercased().contains(q)) { return false }
            return true
        }
    }

    var body: some View {
        if let e = store.engine {
            let all: [Row] = rows(e)
            let list: [Row] = visible(all)
            PhonePageScroll(spacing: 14) {
                if all.isEmpty {
                    EmptyState(glyph: Glyph.list, title: "Nothing has moved yet", message: "Sales, tax, wages, loans and purchases from you and every company are listed here as they happen.")
                } else {
                    filters(e)
                    summary(list)
                    if list.isEmpty {
                        EmptyState(glyph: Glyph.list, title: "No movement matches", message: "Clear the search or choose another account or kind.", centered: false)
                    } else {
                        feed(Array(list.prefix(shown)))
                    }
                    Text("Your own account keeps the latest \(shown) lines; each company keeps its latest \(GameEngine.movementsKept).")
                        .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func filters(_ e: GameEngine) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                GlyphView(glyph: Glyph.list, size: 14, weight: 1.6, tint: Theme.inkFaint)
                TextField("Search what, who or why", text: $query)
                    .textFieldStyle(.plain).textStyle(.body).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier("activity-search")
            }
            .padding(.horizontal, Theme.Space.m).frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.inset))
            chips(scopeChips(e), selected: scope, identifier: "activity-account") { (s: Scope) in scope = s }
            chips(kindChips, selected: kind, identifier: "activity-kind") { (k: Kind?) in kind = k }
        }
    }

    private func scopeChips(_ e: GameEngine) -> [(String, Scope)] {
        var out: [(String, Scope)] = [("All accounts", .all), ("You", .you)]
        for co in e.state.companies where co.isOpenOrClosed { out.append((co.name, .company(co.id))) }
        return out
    }

    private var kindChips: [(String, Kind?)] {
        var out: [(String, Kind?)] = [("Everything", nil)]
        for k in Kind.allCases { out.append((k.title, k)) }
        return out
    }

    private func chips<T: Hashable>(_ items: [(String, T)], selected: T, identifier: String, pick: @escaping (T) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s) {
                ForEach(Array(items.enumerated()), id: \.offset) { (i: Int, item: (String, T)) in
                    let on: Bool = item.1 == selected
                    Button { Haptics.choose(); pick(item.1) } label: {
                        Text(item.0).textStyle(.caption, tint: on ? Theme.page : Theme.ink, weight: .medium).lineLimit(1)
                            .padding(.horizontal, Theme.Space.m).frame(minHeight: 36)
                            .background(Capsule().fill(on ? Theme.ink : Theme.inset))
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("\(identifier)-\(item.0)")
                }
            }
        }
    }

    private func summary(_ list: [Row]) -> some View {
        let moneyIn: Double = list.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
        let moneyOut: Double = list.filter { $0.amount < 0 }.reduce(0) { $0 + abs($1.amount) }
        let co: Company? = { if case .company = scope { return list.first?.company }; return nil }()
        let fmt: (Double) -> String = { (v: Double) -> String in co.map { store.short(v, in: $0) } ?? store.short(v) }
        return Card(padding: 14, radius: Theme.Radius.hero) {
            StatStrip(cells: [
                .init(label: "Came in", value: "+" + fmt(moneyIn), tint: Theme.gain),
                .init(label: "Went out", value: "\u{2212}" + fmt(moneyOut)),
                .init(label: "Lines", value: "\(list.count)")
            ], ruled: false)
        }
    }

    private struct DayGroup: Identifiable {
        var id: Int
        var week: Int
        var day: Int?
        var rows: [Row]
    }

    private func groups(_ list: [Row]) -> [DayGroup] {
        var out: [DayGroup] = []
        for r in list {
            if let last = out.last, last.week == r.week, last.day == r.day {
                out[out.count - 1].rows.append(r)
            } else {
                out.append(DayGroup(id: out.count, week: r.week, day: r.day, rows: [r]))
            }
        }
        return out
    }

    private func feed(_ list: [Row]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(groups(list)) { (g: DayGroup) in
                header(g)
                ForEach(Array(g.rows.enumerated()), id: \.element.id) { (i: Int, r: Row) in
                    if i > 0 { Hairline() }
                    row(r)
                }
            }
        }
    }

    private func header(_ g: DayGroup) -> some View {
        let text: String = g.day.map { GameCalendar.dateString(week: g.week, dayOffset: $0) } ?? GameCalendar.dateString(week: g.week)
        return Text(g.day == nil ? "Week of " + text : text).textStyle(.figure)
            .padding(.top, 14).padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ r: Row) -> some View {
        let income: Bool = r.amount >= 0
        let sign: String = income ? "+" : "\u{2212}"
        let money: String = r.company.map { store.short(abs(r.amount), in: $0) } ?? store.short(abs(r.amount))
        var sub: String = r.who + " \u{00B7} " + r.kind.why
        if let b = r.balance { sub += " \u{00B7} balance " + store.short(b) }
        return LedgerRow(leading: .glyph(income ? Glyph.arrowIn : Glyph.arrowOut), leadingTint: income ? Theme.gain : Theme.inkSoft,
                         title: r.label.tidyText, subtitle: sub, value: sign + money, valueTint: Theme.change(r.amount), density: .compact, lineLimit: 3)
    }
}
