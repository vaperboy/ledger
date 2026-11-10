import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Simulation

struct GuidedStartView: View {
    @EnvironmentObject var store: GameStore
    @StateObject private var estimator = StartEstimator()

    var body: some View {
        if let e = store.engine {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Figure(label: "Cash available", value: store.money(Payments.liquid(e.state)), note: "", size: .display)
                    NavigationLink { StartChooseView() } label: {
                        entry("Help me choose", "Answer three questions and see three businesses that fit.", "start-help")
                    }.buttonStyle(AcctPressStyle())
                    NavigationLink { StartBrowseView() } label: {
                        entry("Browse every business", "Every trade with its cost, payback and risk. Search and filter.", "start-browse")
                    }.buttonStyle(AcctPressStyle())
                    Text("Nothing is guaranteed: a new business can lose money at first.")
                        .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .appScreen(title: "Start a company", subtitle: "", tab: .company)
            .environmentObject(estimator)
            .task { estimator.warm(e, cityID: e.state.player.cityID) }
        }
    }

    private func entry(_ title: String, _ line: String, _ id: String) -> some View {
        Card(padding: 16) {
            HStack(spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(title).textStyle(.headline)
                    Text(line).textStyle(.caption).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Space.s)
                LedgerGlyph(glyph: Glyph.chevron, size: 14, tint: Theme.inkFaint)
            }
        }
        .accessibilityIdentifier(id)
    }
}

struct StartBar<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: Theme.Space.xs, content: content)
            .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity)
            .background(P.page)
            .overlay(alignment: .top) { Hairline() }
    }
}

struct StartChip: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var on: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.choose()
            action()
        } label: {
            Text(title).textStyle(.caption, tint: on ? P.ink : P.inkSoft, weight: .medium)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(on ? P.accentWash : P.card))
                .overlay(Capsule().strokeBorder(on ? P.accent : Color.clear, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct StartChooseView: View {
    @EnvironmentObject var store: GameStore
    @State private var budget: StartBudget = .small
    @State private var time: StartTime = .handsOn
    @State private var interest: String?
    @State private var go = false

    var body: some View {
        if let e = store.engine {
            let tiers: StartCostTiers = e.startCostTiers()
            let interests: [String] = e.startInterests()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    question("1. How much do you want to spend?") {
                        SegmentedPill(items: StartBudget.allCases, title: { budgetTitle($0) }, selection: $budget)
                        Text(budgetRange(budget, tiers)).textStyle(.caption, tint: Theme.inkFaint)
                    }
                    question("2. How much time can you give it?") {
                        SegmentedPill(items: StartTime.allCases, title: { $0 == .handsOff ? "Hands-off" : "Hands-on" }, selection: $time)
                        Text(time == .handsOff ? "Mostly run by a team; you check in." : "You work in it yourself, at least at first.")
                            .textStyle(.caption, tint: Theme.inkFaint)
                    }
                    question("3. What interests you?") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                            StartChip(title: "Anything", on: interest == nil) { interest = nil }
                            ForEach(interests, id: \.self) { (name: String) in
                                StartChip(title: name, on: interest == name) { interest = name }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StartBar { PrimaryAction(title: "See my matches", identifier: "start-matches") { go = true } }
            }
            .appScreen(title: "Help me choose", subtitle: "Three questions", tab: .company)
            .navigationDestination(isPresented: $go) { StartMatchesView(budget: budget, time: time, interest: interest) }
        }
    }

    private func question<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).textStyle(.headline)
            content()
        }
    }

    private func budgetTitle(_ b: StartBudget) -> String { b == .small ? "Small" : b == .medium ? "Medium" : "Large" }

    private func budgetRange(_ b: StartBudget, _ t: StartCostTiers) -> String {
        switch b {
        case .small: return "Start costs up to \(store.money(t.lowTop))."
        case .medium: return "Start costs from \(store.money(t.lowTop)) to \(store.money(t.midTop))."
        case .large: return "Start costs above \(store.money(t.midTop))."
        }
    }
}

struct StartMatchesView: View {
    @EnvironmentObject var store: GameStore
    @EnvironmentObject var estimator: StartEstimator
    var budget: StartBudget
    var time: StartTime
    var interest: String?
    @State private var results: [StartEstimate] = []
    @State private var tried = 0
    @State private var total = 0
    @State private var finished = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if !finished {
                    ProgressLine(fraction: total == 0 ? 0 : Double(tried) / Double(total), label: "Trying businesses on a copy of your game", value: "\(tried) of \(total)")
                } else if results.isEmpty {
                    EmptyState(glyph: Glyph.market, title: "Nothing fits your cash right now.", message: "Browse every business to see what each one needs.")
                }
                ForEach(results, id: \.facts.tradeID) { (est: StartEstimate) in
                    NavigationLink { StartConfirmView(tradeID: est.facts.tradeID, cityID: est.facts.cityID) } label: { card(est) }
                        .buttonStyle(AcctPressStyle())
                }
                Text("Nothing is guaranteed: a new business can lose money at first. Ranges come from trial runs, not promises.")
                    .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .appScreen(title: "Your matches", subtitle: "", tab: .company)
        .task { await load() }
    }

    private func load() async {
        guard !finished, let e = store.engine else { return }
        let city: String = e.state.player.cityID
        let candidates = e.startCandidates(budget: budget, time: time, interest: interest, cityID: city)
        total = candidates.count
        var list: [StartEstimate] = []
        for r in candidates {
            if let est = await estimator.estimate(e, tradeID: r.tradeID, cityID: city) { list.append(est) }
            tried += 1
        }
        results = Array(StartEstimate.ranked(list).prefix(3))
        finished = true
    }

    private func card(_ est: StartEstimate) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(est.facts.name).textStyle(.headline)
                    Spacer(minLength: Theme.Space.s)
                    Chip(text: est.pill.rawValue, tint: pillTint(est.pill))
                }
                line("Start cost", store.money(est.facts.startCost))
                line("Usual payback", StartText.payback(est))
                line("First month", "\(store.money(est.firstMonthLow)) to \(store.money(est.firstMonthHigh))")
                Text("Risk: \(est.risk.rawValue). \(est.riskLine)").textStyle(.caption, tint: Theme.inkSoft)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(label).textStyle(.caption)
            Spacer(minLength: Theme.Space.m)
            Text(value).textStyle(.body, numeric: true).multilineTextAlignment(.trailing)
        }
    }

    private func pillTint(_ p: StartEstimate.Pill) -> Color {
        switch p {
        case .easier: return Theme.gain
        case .care: return Theme.caution
        case .lowCost: return Theme.accent
        }
    }
}

struct StartBrowseView: View {
    @EnvironmentObject var store: GameStore
    @EnvironmentObject var estimator: StartEstimator
    @State private var query = ""
    @State private var lowCost = false
    @State private var fastPayback = false
    @State private var handsOff = false
    @State private var skill = false

    var body: some View {
        if let e = store.engine {
            let city: String = e.state.player.cityID
            let rows: [TradePickerRow] = e.startableRows(cityID: city)
            let tiers: StartCostTiers = e.startCostTiers(cityID: city)
            let known: [Int] = rows.compactMap { estimator.cached(e, $0.tradeID, city)?.paybackHigh }.sorted()
            let fastCut: Int = known.isEmpty ? 0 : known[(known.count - 1) / 3]
            let shown: [TradePickerRow] = rows.filter { keep($0, e, city, tiers, fastCut) }
            let fundedCount: Int = rows.filter { $0.isFunded }.count
            let doneCount: Int = rows.filter { $0.isFunded && estimator.cached(e, $0.tradeID, city) != nil }.count
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    LedgerField(placeholder: "Search businesses", text: $query, identifier: "start-search")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            StartChip(title: "Low cost", on: lowCost) { lowCost.toggle() }
                            StartChip(title: "Fast payback", on: fastPayback) { fastPayback.toggle() }
                            StartChip(title: "Hands-off", on: handsOff) { handsOff.toggle() }
                            StartChip(title: "Skill", on: skill) { skill.toggle() }
                        }
                    }
                    if doneCount < fundedCount {
                        ProgressLine(fraction: fundedCount == 0 ? 0 : Double(doneCount) / Double(fundedCount), label: "Working out paybacks", value: "\(doneCount) of \(fundedCount)")
                    }
                    if shown.isEmpty {
                        EmptyState(glyph: Glyph.market, title: "No business matches.", message: "Clear a filter or change the search.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element.tradeID) { (n: Int, r: TradePickerRow) in
                                if n > 0 { Hairline() }
                                NavigationLink { StartConfirmView(tradeID: r.tradeID, cityID: city) } label: { row(e, r, city) }
                                    .buttonStyle(AcctPressStyle())
                                    .disabled(!r.isFunded)
                            }
                        }
                    }
                    Text("Nothing is guaranteed: a new business can lose money at first.")
                        .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .appScreen(title: "Every business", subtitle: "\(shown.count) shown", tab: .company)
            .task { estimator.warm(e, cityID: city) }
        }
    }

    private func keep(_ r: TradePickerRow, _ e: GameEngine, _ city: String, _ tiers: StartCostTiers, _ fastCut: Int) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty && !(r.name.lowercased().contains(q) || r.sector.lowercased().contains(q)) { return false }
        if lowCost, let c = r.startUpCost, tiers.budget(for: c) != .small { return false }
        if handsOff, !(e.data.catalog[r.tradeID]?.isHandsOff ?? false) { return false }
        if skill, !(e.data.catalog[r.tradeID]?.needsOwnerSkill ?? false) { return false }
        if fastPayback {
            guard let high = estimator.cached(e, r.tradeID, city)?.paybackHigh, high <= fastCut else { return false }
        }
        return true
    }

    private func row(_ e: GameEngine, _ r: TradePickerRow, _ city: String) -> some View {
        let est: StartEstimate? = estimator.cached(e, r.tradeID, city)
        let payback: String = !r.isFunded ? "Needs more cash" : est.map { "Payback " + StartText.weeks($0.paybackLow, $0.paybackHigh) } ?? "Working it out"
        let risk: String = est.map { "Risk \($0.risk.rawValue)" } ?? ""
        return HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).textStyle(.headline)
                Text(r.sector).textStyle(.caption, tint: Theme.inkFaint)
                Text(risk.isEmpty ? payback : payback + " · " + risk).textStyle(.caption).multilineTextAlignment(.leading)
            }
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: 2) {
                Text(store.money(r.startUpCost ?? 0)).textStyle(.headline, numeric: true)
                Text("start cost").textStyle(.caption, tint: Theme.inkFaint)
            }
        }
        .padding(.vertical, Theme.Space.s)
        .opacity(r.isFunded ? 1 : 0.55)
        .contentShape(Rectangle())
    }
}
