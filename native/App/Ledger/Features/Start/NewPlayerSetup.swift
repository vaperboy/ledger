import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

/// The new-player setup: three steps, one screen each. Country (largest first), trade (the in-game picker's table: twelve starters, or
/// all of them), company name.
/// Nothing is created until `begin` is called from the last step; the start screen decides whether replacing a saved game needs asking first.
struct NewPlayerSetup: View {
    enum Step { case country, trade, name }

    var onClose: () -> Void
    var begin: (_ countryCode: String, _ tradeID: String, _ companyName: String, _ playerName: String) -> Void

    @State private var step: Step = .country
    @State private var countryCode = ""
    @State private var tradeID = ""
    @State private var companyName = ""
    /// The owner's own name (stored as the player name); empty keeps the engine's default.
    @State private var playerName = ""
    @State private var suggested = ""
    @State private var allTrades: [StarterTrade] = []
    @State private var loading = false
    @State private var showAll = false
    @State private var picked: StarterTrade?
    @State private var startCash: Double?
    /// Narrows the long country list by name.
    @State private var countryQuery = ""
    @FocusState private var nameFocused: Bool
    private static let sizeOrder: [Country] = GameEngine.countriesBySize()
    private var countries: [Country] { Self.sizeOrder }

    private var country: Country? { countries.first { $0.code == countryCode } }
    private var currency: Currency? { country.map { Currency(country: $0, rates: ExchangeRates()) } }
    private var starters: [StarterTrade] { GameEngine.starterTradeIDs.compactMap { id in allTrades.first { $0.id == id } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch step {
            case .country: countryStep
            case .trade: tradeStep
            case .name: nameStep
            }
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .centerSheet(item: $picked, category: .medium, tone: .investment) { (t: StarterTrade) in tradeSheet(t) }
    }

    private var header: some View {
        let title: String = step == .country ? "Where do you live?" : step == .trade ? "What do you open?" : "Name your company"
        let number: Int = step == .country ? 1 : step == .trade ? 2 : 3
        return AppHeader(title: title, subtitle: "Step \(number) of 3", onBack: { goBack() })
            .padding(.top, 24)
    }

    private func goBack() {
        switch step {
        case .country: onClose()
        case .trade: showAll = false; step = .country
        case .name: step = .trade
        }
    }

    // MARK: Step 1, country

    private var countryStep: some View {
        let q: String = countryQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let shown: [Country] = q.isEmpty ? countries : countries.filter { (c: Country) -> Bool in c.name.lowercased().contains(q) }
        return VStack(spacing: Theme.Space.s) {
            LedgerField(placeholder: "Search countries", text: $countryQuery, identifier: "country-search")
            ScrollView {
                LazyVStack(spacing: 0) {
                    if shown.isEmpty { EmptyState(glyph: Glyph.world, title: "No country matches \u{201C}\(countryQuery)\u{201D}") }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { (i: Int, c: Country) in
                        if i > 0 { Hairline().padding(.leading, 44) }
                        Button { chooseCountry(c) } label: {
                            HStack(spacing: Theme.Space.m) {
                                Text(c.flag).font(.title2).frame(width: 32)
                                Text(c.name).textStyle(.headline)
                                Spacer(minLength: Theme.Space.s)
                                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
                            }
                            .frame(minHeight: 56).contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("country-" + c.code)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func chooseCountry(_ c: Country) {
        Haptics.choose()
        countryCode = c.code
        allTrades = []
        showAll = false
        step = .trade
    }

    // MARK: Step 2, trade

    private var tradeStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if loading && allTrades.isEmpty { LoadingState(text: "Pricing the trades", rows: 6) }
                if !allTrades.isEmpty { tradeTable }
                if allTrades.count > starters.count {
                    Button(showAll ? "Show fewer" : "All \(allTrades.count) trades") { Haptics.tap(); showAll.toggle() }
                        .buttonStyle(TertiaryButtonStyle(fullWidth: true))
                }
            }
        }
        .scrollIndicators(.hidden)
        .task(id: countryCode) { await loadTrades() }
    }

    private func loadTrades() async {
        guard !countryCode.isEmpty, allTrades.isEmpty else { return }
        loading = true
        let code: String = countryCode
        let list: [StarterTrade] = await Task.detached { GameEngine.startableTrades(countryCode: code, all: true) }.value
        if code == countryCode { allTrades = list }
        loading = false
    }

    /// One row per trade (name, one line about it, start-up cost on the right): the twelve starters first, all trades on request.
    private var tradeTable: some View {
        let rest: [StarterTrade] = allTrades.filter { !GameEngine.starterTradeIDs.contains($0.id) }
        let shown: [StarterTrade] = showAll ? starters + rest : starters
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Trade").textStyle(.label, tint: Theme.inkFaint)
                Spacer()
                Text("Start-up").textStyle(.label, tint: Theme.inkFaint)
            }
            .padding(.bottom, Theme.Space.xs)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { (i: Int, t: StarterTrade) in
                    if i > 0 { Hairline() }
                    tradeRow(t)
                }
            }
        }
    }

    private func tradeRow(_ t: StarterTrade) -> some View {
        Button { pick(t) } label: {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(t.name).textStyle(.headline).lineLimit(1)
                    Text(t.line.tidyMoney).textStyle(.caption).lineLimit(2).multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(costText(t)).textStyle(.headline, tint: t.startUpCost == nil ? Theme.inkFaint : Theme.ink, numeric: true).lineLimit(1)
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
            }
            .padding(.vertical, Theme.Space.m).frame(minHeight: 60).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("trade-" + t.id)
    }

    private func costText(_ t: StarterTrade) -> String {
        guard let cost = t.startUpCost, let cur = currency else { return "n/a" }
        return cur.tidyShort(cost)
    }

    private func pick(_ t: StarterTrade) {
        Haptics.choose()
        startCash = nil
        picked = t
    }

    /// The popup: what the business costs to open, the money you start with, one button.
    private func tradeSheet(_ t: StarterTrade) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t.line.tidyMoney).popupText(.body)
            if let cost = t.startUpCost, let cur = currency {
                PopupRow(label: "Start-up cost", value: cur.tidyShort(cost))
            }
            if let cash = startCash, let cur = currency {
                Text("You start with \(cur.tidyShort(cash)).").popupText(.caption)
            }
            Button("Open \(t.name)") { Haptics.tap(); open(t) }
                .buttonStyle(PopupPrimaryCapsuleStyle(tone: .investment))
                .accessibilityIdentifier("trade-open")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle(t.name)
        .task(id: t.id) {
            let code: String = countryCode
            let id: String = t.id
            let cash: Double? = await Task.detached { GameEngine.startingCash(countryCode: code, tradeID: id) }.value
            startCash = cash
        }
    }

    private func open(_ t: StarterTrade) {
        tradeID = t.id
        suggested = GameEngine.suggestedCompanyName(countryCode: countryCode, tradeID: t.id)
        companyName = suggested
        picked = nil
        step = .name
    }

    // MARK: Step 3, name

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Company name", text: $companyName)
                .textInputAutocapitalization(.words)
                .focused($nameFocused)
                .submitLabel(.go)
                .onSubmit { start() }
                .textStyle(.figure)
                .padding(.vertical, Theme.Space.s)
                .overlay(alignment: .bottom) { Hairline() }
            TextField("Your name (optional)", text: $playerName)
                .textInputAutocapitalization(.words)
                .submitLabel(.go)
                .onSubmit { start() }
                .textStyle(.figure)
                .padding(.vertical, Theme.Space.s)
                .overlay(alignment: .bottom) { Hairline() }
            Spacer(minLength: 0)
            Button("Start") { Haptics.tap(); start() }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("setup-start")
        }
        .onAppear { nameFocused = true }
    }

    private func start() {
        let n: String = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        begin(countryCode, tradeID, n.isEmpty ? suggested : n, playerName.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
