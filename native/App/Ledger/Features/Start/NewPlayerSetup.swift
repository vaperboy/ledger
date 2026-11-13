import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

struct NewPlayerSetup: View {
    enum Step { case country, trade, detail, name, options }
    enum Field { case company }

    var onClose: () -> Void
    var begin: (_ countryCode: String, _ tradeID: String, _ companyName: String, _ playerName: String, _ channel: SalesChannel) -> Void

    @State private var step: Step = .country
    @State private var avatarDone = false
    @State private var countryCode = ""
    @State private var tradeID = ""
    @State private var companyName = ""
    @State private var suggested = ""
    @State private var channel: SalesChannel = .consumers
    @State private var allTrades: [StarterTrade] = []
    @State private var loading = false
    @State private var picked: StarterTrade?
    @State private var startCash: Double?
    @State private var countryQuery = ""
    @State private var countryPage = 0
    @State private var tradePage = 0
    @FocusState private var field: Field?
    private static let countryRows = 6
    private static let tradeRows = 5
    /// Biggest countries first, with the country of the phone's region on top.
    private static let sizeOrder: [Country] = {
        let all: [Country] = GameEngine.countriesBySize()
        let region: String = Locale.current.region?.identifier ?? ""
        guard let home = all.first(where: { (c: Country) -> Bool in c.code == region }) else { return all }
        return [home] + all.filter { (c: Country) -> Bool in c.code != home.code }
    }()
    private var countries: [Country] { Self.sizeOrder }
    private var deviceRegion: String { Locale.current.region?.identifier ?? "" }
    /// Only one way to sell: the last step is skipped.
    private var asksChannel: Bool { SalesChannel.options(tradeID: tradeID).count > 1 }

    private var country: Country? { countries.first { $0.code == countryCode } }
    private var currency: Currency? { country.map { Currency(country: $0, rates: ExchangeRates()) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch step {
            case .country: countryStep
            case .trade: tradeStep
            case .detail: detailStep
            case .name: nameStep
            case .options: optionsStep
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .keyboardDismissable()
        .overlay { if !avatarDone && !ProfileLocal.shared.hasAvatar { AvatarSetupStep(onDone: { avatarDone = true }, onBack: onClose) } }
    }

    private var header: some View {
        let title: String
        let number: Int
        let total: Int = tradeID.isEmpty || asksChannel ? 5 : 4
        switch step {
        case .country: title = "Where do you live?"; number = 1
        case .trade: title = "What do you open?"; number = 2
        case .detail: title = picked?.name ?? "Your trade"; number = 3
        case .name: title = "Name your company"; number = 4
        case .options: title = "How you play"; number = 5
        }
        return AppHeader(title: title, subtitle: "Step \(number) of \(total)", onBack: { goBack() })
            .padding(.top, 24)
    }

    private func goBack() {
        switch step {
        case .country: onClose()
        case .trade: step = .country
        case .detail: picked = nil; step = .trade
        case .name: field = nil; step = .detail
        case .options: step = .name
        }
    }

    private var countryStep: some View {
        let q: String = countryQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let shown: [Country] = q.isEmpty ? countries : countries.filter { (c: Country) -> Bool in c.name.lowercased().contains(q) }
        let pages: Int = max(1, (shown.count + Self.countryRows - 1) / Self.countryRows)
        let page: Int = min(countryPage, pages - 1)
        let slice: [Country] = Array(shown.dropFirst(page * Self.countryRows).prefix(Self.countryRows))
        return VStack(spacing: Theme.Space.s) {
            LedgerField(placeholder: "Search countries", text: $countryQuery, identifier: "country-search")
                .onChange(of: countryQuery) { _, _ in countryPage = 0 }
            VStack(spacing: 0) {
                if shown.isEmpty { EmptyState(glyph: Glyph.world, title: "No country matches \u{201C}\(countryQuery)\u{201D}") }
                ForEach(Array(slice.enumerated()), id: \.element.id) { (i: Int, c: Country) in
                    if i > 0 { Hairline().padding(.leading, 44) }
                    Button { chooseCountry(c) } label: {
                        HStack(spacing: Theme.Space.m) {
                            Text(c.flag).font(.title2).frame(width: 32)
                            Text(c.name).textStyle(.headline)
                            if c.code == deviceRegion { Text("Your region").textStyle(.caption, tint: Theme.inkFaint) }
                            Spacer(minLength: Theme.Space.s)
                            LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
                        }
                        .frame(height: 52).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("country-" + c.code)
                }
            }
            pager(page: $countryPage, pages: pages)
        }
    }

    private func pager(page: Binding<Int>, pages: Int) -> some View {
        let cur: Int = min(page.wrappedValue, pages - 1)
        return HStack {
            Button("Previous") { Haptics.tap(); page.wrappedValue = max(0, cur - 1) }
                .buttonStyle(TertiaryButtonStyle(size: .compact)).disabled(cur == 0)
            Spacer()
            Text("\(cur + 1) of \(pages)").textStyle(.caption, tint: Theme.inkFaint)
            Spacer()
            Button("Next") { Haptics.tap(); page.wrappedValue = min(pages - 1, cur + 1) }
                .buttonStyle(TertiaryButtonStyle(size: .compact)).disabled(cur >= pages - 1)
        }
        .opacity(pages > 1 ? 1 : 0)
    }

    private func chooseCountry(_ c: Country) {
        Haptics.choose()
        countryCode = c.code
        allTrades = []
        tradePage = 0
        step = .trade
    }

    private var tradeStep: some View {
        let pages: Int = max(1, (allTrades.count + Self.tradeRows - 1) / Self.tradeRows)
        let page: Int = min(tradePage, pages - 1)
        let slice: [StarterTrade] = Array(allTrades.dropFirst(page * Self.tradeRows).prefix(Self.tradeRows))
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            if loading && allTrades.isEmpty { LoadingState(text: "Pricing the trades", rows: 5) }
            if !allTrades.isEmpty {
                HStack {
                    Text("Trade").textStyle(.label, tint: Theme.inkFaint)
                    Spacer()
                    Text("Start-up").textStyle(.label, tint: Theme.inkFaint)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(slice.enumerated()), id: \.element.id) { (i: Int, t: StarterTrade) in
                        if i > 0 { Hairline() }
                        tradeRow(t)
                    }
                }
                pager(page: $tradePage, pages: pages)
            }
            if !allTrades.isEmpty {
                Text("Bigger trades open as you level up.").textStyle(.caption, tint: Theme.inkFaint)
            }
        }
        .task(id: countryCode) { await loadTrades() }
    }

    private func loadTrades() async {
        guard !countryCode.isEmpty, allTrades.isEmpty else { return }
        loading = true
        let code: String = countryCode
        let list: [StarterTrade] = await Task.detached { GameEngine.startableTrades(countryCode: code) }.value
        if code == countryCode { allTrades = list }
        loading = false
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
            .padding(.vertical, Theme.Space.xs).frame(height: 56).contentShape(Rectangle())
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
        step = .detail
    }

    private var detailStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let t = picked {
                Text(t.line.tidyMoney).textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                if let cost = t.startUpCost, let cur = currency {
                    PopupRow(label: "Start-up cost", value: cur.tidyShort(cost))
                }
                if let cash = startCash, let cur = currency {
                    Text("You start with \(cur.tidyShort(cash)).").textStyle(.caption)
                }
                Button("Open \(t.name)") { Haptics.tap(); open(t) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(startCash == nil)
                    .accessibilityIdentifier("trade-open")
                    .task(id: t.id) {
                        let code: String = countryCode
                        let id: String = t.id
                        let cash: Double? = await Task.detached { GameEngine.startingCash(countryCode: code, tradeID: id) }.value
                        startCash = cash
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func open(_ t: StarterTrade) {
        tradeID = t.id
        suggested = GameEngine.suggestedCompanyName(countryCode: countryCode, tradeID: t.id)
        companyName = suggested
        channel = .consumers
        step = .name
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Company name", text: $companyName)
                .textInputAutocapitalization(.words)
                .focused($field, equals: .company)
                .submitLabel(.done)
                .onSubmit { field = nil }
                .textStyle(.figure)
                .padding(.vertical, Theme.Space.s)
                .overlay(alignment: .bottom) { Hairline() }
            Button(asksChannel ? "Next" : "Start") { Haptics.tap(); field = nil; if asksChannel { step = .options } else { start() } }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("setup-next")
        }
        .onAppear { field = .company }
    }

    private var optionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            SalesChannelPicker(tradeID: tradeID, channel: $channel)
            Button("Start") { Haptics.tap(); start() }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("setup-start")
        }
    }

    private func start() {
        let n: String = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let player: String = ProfileLocal.shared.name
        let way: SalesChannel = SalesChannel.options(tradeID: tradeID).first ?? .consumers
        begin(countryCode, tradeID, n.isEmpty ? suggested : n, player, asksChannel ? channel : way)
    }
}
