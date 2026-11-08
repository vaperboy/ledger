import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Buying or selling in steps. Buy: what (funds and crypto with price, trend and risk), who pays and holds it (you or a holding), how
/// much (a large amount with quick picks), review, confirm. Sell: how much of the position, review, confirm. Every figure on the review
/// comes from the same quote the trade uses. Selling a large position whole is press-and-hold.
struct MarketTradeFlow: View {
    enum Side { case buy, sell }
    enum Step: Int { case what, who, amount, review, done }

    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @Environment(\.dismiss) private var dismiss
    var side: Side
    var positionID: String?
    @State private var step: Step
    @State private var assetID: String?
    @State private var owner: MarketUI.Owner?
    @State private var amountText = ""
    @State private var fraction = 1.0
    @State private var result: String?
    @State private var problem: String?
    @FocusState private var amountFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 44

    init(side: Side, assetID: String?, owner: MarketUI.Owner?, positionID: String?) {
        self.side = side
        self.positionID = positionID
        _assetID = State(initialValue: assetID)
        _owner = State(initialValue: owner)
        let first: Step = side == .sell ? .amount : (assetID == nil ? .what : (owner == nil ? .who : .amount))
        _step = State(initialValue: first)
    }

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(title: title, subtitle: subtitle, onBack: { back() }, backLabel: "Back")
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xs).padding(.bottom, Theme.Space.s)
            if let e = store.engine {
                ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) { content(e) }
                    .scrollDismissesKeyboard(.interactively)
            }
        }
        .ledgerBackground()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBackEnabled(canStep: { canStepBack }, step: { back() })
        .onAppear { skipLoneOwner() }
    }

    // MARK: Header and steps

    private var title: String { side == .buy ? "Buy" : "Sell" }

    private var subtitle: String {
        switch step {
        case .what: return "What to buy"
        case .who: return "Who pays and holds it"
        case .amount: return side == .buy ? "How much" : "How much to sell"
        case .review: return "Review"
        case .done: return side == .buy ? "Bought" : "Sold"
        }
    }

    private var firstStep: Step { side == .sell ? .amount : .what }
    private var canStepBack: Bool { step != firstStep && step != .done }

    private func back() {
        problem = nil
        switch step {
        case .done: dismiss()
        case .review: step = .amount
        case .amount:
            if side == .sell { dismiss() } else { step = ownerCount > 1 ? .who : .what }
        case .who: step = .what
        case .what: dismiss()
        }
    }

    private var ownerCount: Int { store.engine.map { (e: GameEngine) -> Int in MarketData.owners(e).count } ?? 1 }

    /// With no holding there is no one else to pay: the Who step is skipped.
    private func skipLoneOwner() {
        guard side == .buy, ownerCount <= 1 else { return }
        if owner == nil { owner = .player }
        if step == .who { step = .amount }
    }

    @ViewBuilder private func content(_ e: GameEngine) -> some View {
        let cur: Currency = e.homeCurrency
        switch step {
        case .what: what(e)
        case .who: who(e, cur)
        case .amount:
            if side == .buy { buyAmount(e, cur) } else { sellAmount(e, cur) }
        case .review: review(e, cur)
        case .done: done()
        }
    }

    // MARK: What

    private func what(_ e: GameEngine) -> some View {
        let list: [MarketUI.Asset] = MarketData.assets(e)
        let cur: Currency = e.homeCurrency
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { (pair: (offset: Int, element: MarketUI.Asset)) in
                if pair.offset > 0 { Hairline().padding(.leading, Theme.Icon.large + Theme.Space.m) }
                assetRow(pair.element, cur)
            }
        }
    }

    private func assetRow(_ a: MarketUI.Asset, _ cur: Currency) -> some View {
        let w: Double? = a.weekChange
        return Button {
            Haptics.choose()
            assetID = a.id
            if let o = owner, MarketData.refusal(a, for: o) != nil { owner = nil }
            step = owner == nil && ownerCount > 1 ? .who : .amount
            if owner == nil { owner = .player }
        } label: {
            HStack(spacing: Theme.Space.m) {
                LedgerGlyph(glyph: a.kind == .crypto ? Glyph.luxury : (a.kind == .managedFund ? Glyph.person : Glyph.invest), size: Theme.Icon.large, tint: P.inkSoft)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(a.name).textStyle(.headline).lineLimit(1)
                    Text(a.risk).textStyle(.caption).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s)
                if a.history.count >= 2 {
                    Sparkline(values: a.history, tint: (w ?? 0) >= 0 ? P.gain : P.loss, filled: false)
                        .frame(width: 52, height: 22)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    Text(cur.tidyDisplay(a.price)).textStyle(.headline, numeric: true).lineLimit(1).minimumScaleFactor(0.7)
                    Text(w.map { (x: Double) -> String in MarketFormat.percent(x) } ?? "per unit").textStyle(.caption, tint: w.map { (x: Double) -> Color in P.change(x) } ?? P.inkFaint, numeric: true)
                }
            }
            .padding(.vertical, Theme.Space.m)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(AcctPressStyle())
        .accessibilityIdentifier("trade-asset-\(a.id)")
    }

    // MARK: Who

    private func who(_ e: GameEngine, _ cur: Currency) -> some View {
        let asset: MarketUI.Asset? = assetID.flatMap { (id: String) -> MarketUI.Asset? in MarketData.asset(e, id: id) }
        return VStack(alignment: .leading, spacing: 0) {
            if let asset { Text("Buying \(asset.name)").textStyle(.caption, tint: P.inkFaint).padding(.bottom, Theme.Space.s) }
            ForEach(Array(MarketData.owners(e).enumerated()), id: \.element.id) { (pair: (offset: Int, element: MarketUI.OwnerInfo)) in
                if pair.offset > 0 { Hairline().padding(.leading, Theme.Icon.large + Theme.Space.m) }
                let o: MarketUI.OwnerInfo = pair.element
                let why: String? = asset.flatMap { (a: MarketUI.Asset) -> String? in MarketData.refusal(a, for: o.owner) }
                let pick: (() -> Void)? = why == nil ? { () -> Void in owner = o.owner; step = .amount } : nil
                LedgerRow(leading: .glyph(o.owner == .player ? Glyph.person : Glyph.group), leadingTint: P.inkSoft, title: o.name,
                          subtitle: why ?? "",
                          value: cur.tidyShort(o.cash), valueNote: "available", identifier: "trade-owner-\(o.id)", action: pick)
                    .opacity(why == nil ? 1 : 0.5)
            }
        }
    }

    // MARK: How much

    private func amountValue(_ cur: Currency) -> Double {
        let cleaned: String = amountText.replacingOccurrences(of: ",", with: ".").filter { (c: Character) -> Bool in c.isNumber || c == "." }
        return (Double(cleaned) ?? 0) * cur.rate
    }

    private func setAmount(_ accounting: Double, _ cur: Currency) {
        let local: Double = (accounting / cur.rate).rounded(.down)
        amountText = local > 0 ? String(format: "%.0f", local) : ""
    }

    @ViewBuilder private func buyAmount(_ e: GameEngine, _ cur: Currency) -> some View {
        if let a = assetID.flatMap({ (id: String) -> MarketUI.Asset? in MarketData.asset(e, id: id) }) {
            let payer: MarketUI.Owner = owner ?? .player
            let amount: Double = amountValue(cur)
            let q: MarketUI.TradePreview = MarketData.buyPreview(e, a, owner: payer, amount: amount)
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text("\(a.name) \u{00B7} paid by \(MarketData.ownerName(e, payer))").textStyle(.caption, tint: P.inkFaint)
                bigAmount(cur)
                HStack(spacing: Theme.Space.s) {
                    ForEach([0.1, 0.25, 0.5], id: \.self) { (f: Double) in
                        Button("\(Int(f * 100))%") { Haptics.choose(); setAmount(q.available * f, cur) }
                            .buttonStyle(SecondaryButtonStyle(size: .compact))
                    }
                    Button("Max") { Haptics.choose(); setAmount(max(0, q.available - (a.kind == .crypto ? q.available * 0.004 : cur.scaledPrice(29))), cur) }
                        .buttonStyle(SecondaryButtonStyle(size: .compact))
                        .accessibilityIdentifier("trade-max")
                }
                Text("Available \(cur.tidyShort(q.available))" + (q.minimum > 0 ? " \u{00B7} smallest order \(cur.tidyShort(q.minimum))" : ""))
                    .textStyle(.caption)
                PrimaryAction(title: "Review", blockedReason: q.refusal, identifier: "trade-review") { amountFocused = false; step = .review }
            }
        }
    }

    private func bigAmount(_ cur: Currency) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(cur.country.currencyCode).textStyle(.headline, tint: P.inkFaint)
            TextField("0", text: $amountText)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .font(.system(size: amountSize, weight: .medium, design: .serif)).monospacedDigit()
                .foregroundStyle(P.ink)
                .accessibilityIdentifier("trade-amount")
            if amountFocused {
                Button("Done") { Haptics.tap(); amountFocused = false }
                    .buttonStyle(TertiaryButtonStyle(size: .compact))
                    .accessibilityIdentifier("trade-amount-done")
            }
        }
        .padding(.vertical, Theme.Space.s)
        .overlay(alignment: .bottom) { Rectangle().fill(amountFocused ? P.focus : P.hairline).frame(height: amountFocused ? 1 : 0.5) }
    }

    @ViewBuilder private func sellAmount(_ e: GameEngine, _ cur: Currency) -> some View {
        if let id = positionID, let p = MarketData.position(e, id: id) {
            let q: MarketUI.TradePreview = MarketData.sellPreview(e, p, fraction: fraction)
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text("\(p.name) \u{00B7} held by \(p.ownerName)").textStyle(.caption, tint: P.inkFaint)
                Figure(label: "You sell", value: cur.tidyDisplay(q.amount), note: "\(cur.tidyDisplay(q.cashChange)) after costs", size: .display)
                if !p.wholeOnly {
                    SegmentedPill(items: [0.25, 0.5, 0.75, 1.0], title: { (f: Double) -> String in f >= 1 ? "All" : "\(Int(f * 100))%" }, selection: $fraction,
                                  identifier: { (f: Double) -> String in "trade-fraction-\(Int(f * 100))" })
                } else {
                    Text("Sells whole").textStyle(.caption)
                }
                PrimaryAction(title: "Review", blockedReason: q.refusal, identifier: "trade-review") { step = .review }
            }
        } else {
            EmptyState(glyph: Glyph.invest, title: "Nothing held here any more")
        }
    }

    // MARK: Review and confirm

    @ViewBuilder private func review(_ e: GameEngine, _ cur: Currency) -> some View {
        if side == .buy, let a = assetID.flatMap({ (id: String) -> MarketUI.Asset? in MarketData.asset(e, id: id) }) {
            let payer: MarketUI.Owner = owner ?? .player
            let q: MarketUI.TradePreview = MarketData.buyPreview(e, a, owner: payer, amount: amountValue(cur))
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Figure(label: "Leaves \(payer == .player ? "your accounts" : MarketData.ownerName(e, payer))", value: cur.tidyDisplay(q.cashChange), size: .display)
                VStack(spacing: 0) {
                    line("You buy", a.name)
                    line("Amount", cur.tidyDisplay(q.amount))
                    line("Price", cur.tidyDisplay(a.price))
                    line("Units", PositionRow.unitsText(q.units))
                    line(q.feeLabel, q.fee > 0 ? cur.tidyDisplay(q.fee) : "None", tint: q.fee > 0 ? P.loss : nil)
                    line("Held by", MarketData.ownerName(e, payer))
                    Hairline()
                    line("Cash after", cur.tidyDisplay(q.cashAfter), strong: true)
                }
                if let problem { Text(problem).textStyle(.caption, tint: P.warn).fixedSize(horizontal: false, vertical: true) }
                PrimaryAction(title: "Confirm purchase", blockedReason: q.refusal, identifier: "trade-confirm") {
                    finish(MarketData.buy(store, a, owner: payer, amount: q.amount))
                }
            }
        } else if side == .sell, let id = positionID, let p = MarketData.position(e, id: id) {
            let q: MarketUI.TradePreview = MarketData.sellPreview(e, p, fraction: fraction)
            let whole: Bool = p.wholeOnly || fraction >= 0.999
            let large: Bool = whole && q.amount >= cur.scaledPrice(10_000)
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Figure(label: "Reaches \(p.owner == .player ? "your account" : p.ownerName)", value: cur.tidyDisplay(q.cashChange), tint: P.gain, size: .display)
                VStack(spacing: 0) {
                    line("You sell", whole ? "All of \(p.name)" : "\(Int(saturating: (fraction * 100).rounded()))% of \(p.name)")
                    line("Value sold", cur.tidyDisplay(q.amount))
                    if q.units > 0 { line("Units", PositionRow.unitsText(q.units)) }
                    line(q.feeLabel, q.fee > 0 ? cur.tidyDisplay(q.fee) : "None", tint: q.fee > 0 ? P.loss : nil)
                    if p.costKnown { line("Result", MarketFormat.money(q.realizedGain, cur), tint: P.change(q.realizedGain)) }
                    Hairline()
                    line("Cash after", cur.tidyDisplay(q.cashAfter), strong: true)
                }
                if let problem { Text(problem).textStyle(.caption, tint: P.warn).fixedSize(horizontal: false, vertical: true) }
                if large && q.refusal == nil {
                    HoldToConfirmButton(title: "sell all", identifier: "trade-confirm") { finish(MarketData.sell(store, p, fraction: fraction)) }
                } else {
                    PrimaryAction(title: "Confirm sale", blockedReason: q.refusal, identifier: "trade-confirm") {
                        finish(MarketData.sell(store, p, fraction: fraction))
                    }
                }
            }
        }
    }

    private func line(_ label: String, _ value: String, tint: Color? = nil, strong: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(label).textStyle(.body, tint: strong ? P.ink : P.inkSoft)
            Spacer(minLength: Theme.Space.s)
            Text(value.tidyText).textStyle(strong ? .headline : .body, tint: tint ?? P.ink, numeric: true).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }

    private func finish(_ o: MarketUI.Outcome) {
        switch o {
        case .done(let text):
            Haptics.success()
            problem = nil
            result = text
            step = .done
        case .refused(let why):
            Haptics.warning()
            problem = why
        }
    }

    // MARK: Done

    private func done() -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            EmptyState(glyph: Glyph.check, title: result ?? (side == .buy ? "Bought" : "Sold"), tint: P.gain)
            Button("Done") { Haptics.tap(); dismiss() }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("trade-done")
        }
    }
}
