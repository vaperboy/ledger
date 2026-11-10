import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

struct MarketListingPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var holdingID: Int
    @State private var pending: PendingAction?
    @State private var next: MarketRoute?
    @State private var dividendText = ""
    @FocusState private var dividendFocus: Bool

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(holdingID), co.type == "hold", co.status.isLive {
                let cur: Currency = e.homeCurrency
                let inst: ExchangeInstrument? = ExchangeBook(e.state).instruments["co:\(holdingID)"]
                ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                    if let i = inst, e.isListed(companyID: holdingID) {
                        listedHero(e, i, co, cur)
                        calendar(e, i, cur)
                        dividend(e, i, co, cur)
                        sell(i)
                    } else {
                        privateHero(e, co, cur)
                        check(e, co, cur)
                    }
                    rules(cur)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if inst == nil || !e.isListed(companyID: holdingID) { goPublicBar(e, co, cur) }
                }
                .confirmAction($pending)
                .appScreen(title: co.name, subtitle: "Market \u{00B7} Exchange")
                .navigationDestination(item: $next) { (r: MarketRoute) in MarketDestination(route: r) }
            } else {
                EmptyState(glyph: Glyph.group, title: "Not a holding company", message: "Only a holding company can go public.")
                    .appScreen(title: "Go public", subtitle: "Market \u{00B7} Exchange")
            }
        }
    }

    private func privateHero(_ e: GameEngine, _ co: Company, _ cur: Currency) -> some View {
        MarketHero(label: "Worth today", value: cur.tidyShort(e.holdingValue(companyID: holdingID)),
                   context: "Not listed. " + ExchangeListingWords.short(e.exchangeListingCheck(holdingID: holdingID), cur).capitalizedFirst, identifier: "listing-hero")
    }

    private func check(_ e: GameEngine, _ co: Company, _ cur: Currency) -> some View {
        let age: Int = e.state.week - co.foundedWeek
        let value: Double = e.holdingValue(companyID: holdingID)
        let minimum: Double = e.listingMinimumValue
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            MarketLabel(title: "Listing check")
            ExchangeCard {
                checkLine(age >= ExchangeRules.minimumAgeWeeks,
                          "Trading for \(ExchangeRules.minimumAgeWeeks) weeks",
                          age >= ExchangeRules.minimumAgeWeeks ? "It is \(age) weeks old." : "It is \(max(0, age)) weeks old: \((ExchangeRules.minimumAgeWeeks - age).weeksText) to go.")
                Hairline()
                checkLine(value >= minimum, "Worth at least " + cur.tidyShort(minimum),
                          value >= minimum ? "It is worth " + cur.tidyShort(value) + "." : "It is worth " + cur.tidyShort(value) + ": " + cur.tidyShort(minimum - value) + " short.")
                Hairline()
                checkLine(true, "Listing fee " + cur.tidyShort(e.listingFee), "Paid once, when the shares first trade.")
            }
        }
    }

    private func checkLine(_ ok: Bool, _ title: String, _ words: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            LedgerGlyph(glyph: ok ? Glyph.check : Glyph.close, size: Theme.Icon.medium, tint: ok ? P.gain : P.loss)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title.tidyText).textStyle(.headline).fixedSize(horizontal: false, vertical: true)
                Text(words.tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func goPublicBar(_ e: GameEngine, _ co: Company, _ cur: Currency) -> some View {
        let outcome: ExchangeListOutcome = e.exchangeListingCheck(holdingID: holdingID)
        let blocked: String? = outcome == .ok ? nil : blockWords(outcome, cur)
        return PrimaryAction(title: "Go public", blockedReason: blocked, identifier: "listing-go-public") {
            pending = PendingAction(title: "Take \(co.name) public?",
                                    message: "The listing fee is \(cur.tidyDisplay(e.listingFee)). Its shares then trade on the exchange at its value per share. You cannot undo this, and you cannot sell your own shares for \(ExchangeRules.lockUpDays) days.",
                                    button: "Go public", destructive: true, amount: e.listingFee, currency: cur) {
                let r: ExchangeListOutcome? = store.act { (g: inout GameEngine) -> ExchangeListOutcome in g.listOnExchange(holdingID: holdingID) }
                if case .ok? = r { Haptics.success(); store.show("\(co.name) is listed on the exchange.", tone: "good") }
                else if let r { Haptics.warning(); store.show(blockWords(r, cur), tone: "warn") }
            }
        }
        .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.s)
        .background(P.ground.opacity(0.96))
    }

    private func blockWords(_ r: ExchangeListOutcome, _ cur: Currency) -> String {
        switch r {
        case .ok: return ""
        case .notAHolding: return "Only a holding company can go public."
        case .alreadyListed: return "It is already listed."
        case .tooSmall(let n): return "It must be worth at least " + cur.tidyShort(n) + " first."
        case .tooYoung(let w): return "It must trade for \(ExchangeRules.minimumAgeWeeks) weeks first: \(w.weeksText) to go."
        case .notEnoughMoney(let fee): return "You need " + cur.tidyShort(fee) + " for the listing fee."
        }
    }

    private func listedHero(_ e: GameEngine, _ i: ExchangeInstrument, _ co: Company, _ cur: Currency) -> some View {
        let t: CapTable.Table = CapTable.table(co)
        let context: String = MarketFormat.percent(i.change, decimals: 2) + " on the day \u{00B7} you hold \(Int(t.youPct.rounded()))% (\(t.you.formatted()) of \(t.total.formatted()) shares)"
        return MarketHero(label: "Share price", value: ExchangeUI.price(i.close, cur), context: context, contextTint: P.change(i.change),
                          series: i.history, seriesTint: i.change >= 0 ? P.gain : P.loss, identifier: "listing-hero")
    }

    private func calendar(_ e: GameEngine, _ i: ExchangeInstrument, _ cur: Currency) -> some View {
        let today: Int = PublicExchange.today(e.state)
        let results: Int = ExchangeRules.nextResultsDay(listedDay: i.listedDay, today: today)
        let lockEnd: Int = i.listedDay + ExchangeRules.lockUpDays
        let blockNow: String? = ExchangeRules.insiderBlock(listedDay: i.listedDay, disclosureDay: i.dividendDay, today: today)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            MarketLabel(title: "Results and blackout calendar")
            ExchangeCard {
                Text(blockNow ?? "You can sell your own shares today.").textStyle(.body, tint: blockNow == nil ? P.gain : P.caution)
                    .fixedSize(horizontal: false, vertical: true)
                ExchangeQuarterStrip(today: today, results: results, lockEnd: lockEnd, dividendDay: i.dividendDay)
                Hairline()
                if lockEnd > today { dateLine("Lock-up ends", ExchangeUI.daysWord(lockEnd - today), "You cannot sell your own shares until then.") }
                dateLine("Results", ExchangeUI.daysWord(results - today), "Every \(ExchangeRules.quarterDays) days after the listing.")
                dateLine("Blackout", "from " + ExchangeUI.daysWord(max(0, results - ExchangeRules.blackoutBefore - today)),
                         "\(ExchangeRules.blackoutBefore) days before the results until \(ExchangeRules.blackoutAfter) day after. No selling.")
                if i.dividendDay >= 0 {
                    dateLine("Last dividend", "\(max(0, today - i.dividendDay)) days ago", "Paid " + ExchangeUI.price(i.dividendPerShare, cur) + " a share.")
                }
            }
        }
    }

    private func dateLine(_ title: String, _ when: String, _ words: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).textStyle(.headline)
                Spacer(minLength: Theme.Space.s)
                Text(when.tidyText).textStyle(.body, tint: P.accent, numeric: true)
            }
            Text(words.tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func parsedDividend(_ cur: Currency) -> Double {
        let cleaned: String = dividendText.replacingOccurrences(of: ",", with: ".").filter { (c: Character) -> Bool in c.isNumber || c == "." }
        return (Double(cleaned) ?? 0) * cur.rate
    }

    private func dividend(_ e: GameEngine, _ i: ExchangeInstrument, _ co: Company, _ cur: Currency) -> some View {
        let amount: Double = parsedDividend(cur)
        let most: Double = Payments.maximumDividend(co, state: e.state, context: e.context)
        var copy: GameEngine = e
        let result: ExchangeDividendResult = copy.declareExchangeDividend(holdingID: holdingID, amount: amount)
        let t: CapTable.Table = CapTable.table(co)
        let ok: Bool = Self.isOK(result)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            MarketLabel(title: "Dividend")
            ExchangeCard {
                Text("A dividend is paid to every shareholder by the shares they hold. You can declare one every \(ExchangeRules.dividendGapDays) days, and only out of retained profit.")
                    .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                ValueRow(label: "The most it can pay now", value: cur.tidyShort(most), tint: P.ink)
                HStack(spacing: Theme.Space.s) {
                    Text("Total to pay").textStyle(.body, tint: P.inkSoft)
                    Spacer(minLength: Theme.Space.s)
                    TextField("0", text: $dividendText).keyboardType(.decimalPad).focused($dividendFocus)
                        .textStyle(.headline, numeric: true).multilineTextAlignment(.trailing).frame(minWidth: 90)
                    Text(cur.country.currencySymbol).textStyle(.caption, tint: P.inkFaint)
                    if dividendFocus { Button("Done") { dividendFocus = false }.textStyle(.body, tint: P.accent, weight: .semibold).frame(minWidth: 44, minHeight: 44) }
                }
                .overlay(alignment: .bottom) { Rectangle().fill(dividendFocus ? P.focus : P.hairline).frame(height: dividendFocus ? 1 : 0.5) }
                Text("If you do this, this will happen").textStyle(.label, tint: P.inkFaint).padding(.top, Theme.Space.xs)
                Text(dividendWords(result, amount, t, i, cur).tidyText).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("listing-dividend-effect")
                PrimaryAction(title: "Declare dividend", identifier: "listing-declare-dividend") {
                    pending = PendingAction(title: "Declare a dividend?", message: dividendWords(result, amount, t, i, cur), button: "Declare", destructive: true) {
                        let r: ExchangeDividendResult? = store.act { (g: inout GameEngine) -> ExchangeDividendResult in g.declareExchangeDividend(holdingID: holdingID, amount: amount) }
                        if case .ok? = r { Haptics.success(); store.show("Dividend declared.", tone: "good"); dividendText = "" }
                        else if let r { Haptics.warning(); store.show(dividendWords(r, amount, t, i, cur), tone: "warn") }
                    }
                }
                .disabled(!ok)
            }
        }
    }

    private static func isOK(_ r: ExchangeDividendResult) -> Bool {
        if case .ok = r { return true }
        return false
    }

    private func dividendWords(_ r: ExchangeDividendResult, _ amount: Double, _ t: CapTable.Table, _ i: ExchangeInstrument, _ cur: Currency) -> String {
        switch r {
        case .ok(let dps):
            let yours: Double = dps * Double(t.you)
            return "Every share is paid " + ExchangeUI.price(dps, cur) + ". You receive " + cur.tidyShort(yours) + " for your \(t.you.formatted()) shares, the market the rest. "
                + "The price starts the next day lower by the same amount, and you cannot sell for \(ExchangeRules.disclosureDays) days while the market takes it in."
        case .notListed: return "The company is not on the exchange."
        case .tooSoon(let d): return "Too soon: the next dividend can be declared in \(d) days."
        case .nothingToPay: return "Enter the total to pay out."
        case .tooMuch(let m): return "That is more than the company can pay out of its retained profit and still keep two weeks of costs. The most is " + cur.tidyShort(m) + "."
        case .refused(let why): return why
        }
    }

    private func sell(_ i: ExchangeInstrument) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            MarketLabel(title: "Your shares")
            PrimaryAction(title: "Sell shares on the exchange", identifier: "listing-sell") { next = .stock(i.id) }
        }
    }

    private func rules(_ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            MarketLabel(title: "How it works")
            ExchangeCard {
                ruleLine("One closing auction every trading day, Monday to Friday. Orders wait for it.")
                ruleLine("The price moves at most \(Int(ExchangeRules.dayMoveShare * 100))% a day, and stays within \(Int(ExchangeRules.bandShare * 100))% of the value per share.")
                ruleLine("You keep at least \(ExchangeRules.ownerFloorPercent)% of your company. No outside holder may own more than \(ExchangeRules.holderCapPercent)%.")
                ruleLine("You cannot sell for \(ExchangeRules.lockUpDays) days after listing, for \(ExchangeRules.blackoutBefore) days before each results day, or for \(ExchangeRules.blackoutAfter) day after it.")
                ruleLine("Results come every \(ExchangeRules.quarterDays) days. A dividend can be declared once in that time.")
            }
        }
    }

    private func ruleLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Circle().fill(P.accent).frame(width: 5, height: 5).padding(.top, 6)
            Text(text.tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension String {
    fileprivate var capitalizedFirst: String { prefix(1).uppercased() + String(dropFirst()) }
}

struct ExchangeQuarterStrip: View {
    var today: Int
    var results: Int
    var lockEnd: Int
    var dividendDay: Int
    @Environment(\.outsidePalette) private var P

    private let span: Double = Double(ExchangeRules.quarterDays)

    private func band(_ from: Int, _ to: Int) -> (start: CGFloat, end: CGFloat)? {
        let a: Double = max(0, Double(from - today)) / span
        let b: Double = min(1, Double(to - today + 1) / span)
        return b > a ? (CGFloat(a), CGFloat(b)) : nil
    }

    var body: some View {
        var blocks: [(start: CGFloat, end: CGFloat)] = []
        if let b = band(today, lockEnd - 1) { blocks.append(b) }
        if let b = band(results - ExchangeRules.blackoutBefore, results + ExchangeRules.blackoutAfter) { blocks.append(b) }
        if dividendDay >= 0, let b = band(dividendDay, dividendDay + ExchangeRules.disclosureDays) { blocks.append(b) }
        let mark: CGFloat = CGFloat(min(1, max(0, Double(results - today) / span)))
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            GeometryReader { geo in
                let w: CGFloat = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(P.inset).frame(height: 10)
                    ForEach(Array(blocks.enumerated()), id: \.offset) { (pair: (offset: Int, element: (start: CGFloat, end: CGFloat))) in
                        Capsule().fill(P.loss.opacity(0.35)).frame(width: max(4, (pair.element.end - pair.element.start) * w), height: 10)
                            .offset(x: pair.element.start * w)
                    }
                    Rectangle().fill(P.accent).frame(width: 2, height: 18).offset(x: min(max(0, mark * w - 1), max(0, w - 2)))
                    Circle().fill(P.ink).frame(width: 8, height: 8).offset(x: 0)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 20)
            HStack {
                Text("Today").textStyle(.caption)
                Spacer()
                HStack(spacing: Theme.Space.xs) {
                    Capsule().fill(P.loss.opacity(0.35)).frame(width: 14, height: 6)
                    Text("cannot sell").textStyle(.caption)
                    Rectangle().fill(P.accent).frame(width: 2, height: 10)
                    Text("results").textStyle(.caption)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The next \(ExchangeRules.quarterDays) days: results in \(max(0, results - today)) days")
    }
}
