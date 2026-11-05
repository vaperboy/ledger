import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

/// The new-player setup: three steps, one screen each. Country (largest first), trade (twelve starters, or all of them), company name.
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
        .centerSheet(item: $picked) { (t: StarterTrade) in tradeSheet(t) }
    }

    private var header: some View {
        let title: String = step == .country ? "Where do you live?" : step == .trade ? "What do you open?" : "Name your company"
        return AppHeader(title: title, onBack: { goBack() })
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
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(countries) { (c: Country) in
                    Button { chooseCountry(c) } label: {
                        HStack(spacing: 12) {
                            Text(c.flag).font(.system(size: 26))
                            Text(c.name).font(.system(size: 16)).foregroundStyle(Theme.ivory)
                            Spacer(minLength: 8)
                        }
                        .padding(.vertical, 10).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    Hairline()
                }
            }
        }
        .scrollIndicators(.hidden)
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
            VStack(alignment: .leading, spacing: 12) {
                if loading && allTrades.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(.top, 40) }
                if showAll { allList } else { grid }
                if !allTrades.isEmpty {
                    Button { Haptics.tap(); showAll.toggle() } label: {
                        Text(showAll ? "Show fewer" : "All \(allTrades.count) trades").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.gold)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(PressableStyle())
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

    private var grid: some View {
        let columns: [GridItem] = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(starters) { (t: StarterTrade) in tile(t) }
        }
    }

    private func tile(_ t: StarterTrade) -> some View {
        Button { pick(t) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ThumbnailView(kind: .logo, key: "trade|" + t.id, size: 40)
                Text(t.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text(t.line.tidyMoney).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.leading)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private var allList: some View {
        VStack(spacing: 0) {
            ForEach(allTrades) { (t: StarterTrade) in
                Button { pick(t) } label: {
                    HStack(spacing: 10) {
                        Text(t.name).font(.system(size: 15)).foregroundStyle(Theme.ivory)
                        Spacer(minLength: 8)
                        if let cost = t.startUpCost, let cur = currency {
                            Text(cur.tidyShort(cost)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                        }
                    }
                    .padding(.vertical, 10).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                Hairline()
            }
        }
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
                Text("You start with \(cur.tidyShort(cash)), enough for the set-up and the first eight weeks.").popupText(.caption)
            }
            QuietButton(title: "Open \(t.name)", fullWidth: true) { open(t) }
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
                .font(.system(size: 20))
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Hairline() }
            TextField("Your name (optional)", text: $playerName)
                .textInputAutocapitalization(.words)
                .submitLabel(.go)
                .onSubmit { start() }
                .font(.system(size: 20))
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Hairline() }
            QuietButton(title: "Start", fullWidth: true) { start() }
            Spacer(minLength: 0)
        }
        .onAppear { nameFocused = true }
    }

    private func start() {
        let n: String = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        begin(countryCode, tradeID, n.isEmpty ? suggested : n, playerName.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
