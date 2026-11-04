import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

/// "Hire <name>": two pages for a worker. Page 1: what they ask, the going rate, the start date and one button, `Offer the going rate`, with a
/// text link `Change the offer`. Page 2 (only via the link): the pay figure, counter options and hours, with every other term (contract type,
/// seasons, pay basis, commission, benefits, promises) collapsed under `More terms`. Every figure is the engine's: `termsSummary` for what is shown, `hireOffer` for the answer. Posts other than
/// workers (manager, assistant, team posts) take the same two pages, priced by `hireSalaryTalk` (their ask shows once they have named it).
/// `embedded`: shown inside the hiring popup (no screen frame, no scroll view of its own: the popup's `FitScroll` hugs each page).
struct HireOnePage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var request: HireRequest
    var embedded = false
    @StateObject private var model = HireFlowModel()
    @State private var pending: PendingAction?
    @State private var stage = 1

    /// The figures both pages show, whatever the post.
    private struct HirePay {
        var ask: Double?
        var market: Double
        var yours: Double
        var startWeek: Int
        var counters: [HireCounter]
    }
    private struct HireCounter: Identifiable { var id: String; var wage: Double }

    private var isWorker: Bool { if case .worker = request.post { return true }; return false }

    private var hourFactor: Double { StaffModel.fullWeekHours * 52 / 12 }
    private var first: String { HireWords.first(store.engine?.state.people[request.personID]?.name ?? "They") }

    var body: some View {
        Group {
            if model.hired || model.gone {
                ended
            } else if let e = store.engine, let person = e.state.people[request.personID], person.employerID == 0,
                      let opts = e.hireDraftOptions(post: request.post, companyID: request.companyID, personID: request.personID) {
                page(e, person, opts)
            } else {
                Text("\(first) is no longer on the market.").font(.bodyText).foregroundStyle(Theme.ivoryMuted).padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .modifier(HireFrame(embedded: embedded, title: "Hire \(HireWords.first(store.engine?.state.people[request.personID]?.name ?? "worker"))",
                            subtitle: request.roleTitle + (stage == 1 ? "" : " \u{00B7} offer")))
        .confirmAction($pending)
        .onChange(of: model.finished) { _, done in if done { dismiss() } }
    }

    /// Moves between the two pages with the app's move animation.
    private func go(_ to: Int) {
        Haptics.tap()
        withAnimation(Motion.move(reduceMotion)) { stage = to }
    }

    /// The page content in the app's scroll view, or bare inside the popup (whose `FitScroll` scrolls it).
    @ViewBuilder private func scrolled<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if embedded {
            content()
        } else {
            ScrollView {
                content()
                    .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.xs).padding(.bottom, Theme.Space.l)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func paySummary(_ e: GameEngine, _ terms: Hiring.Terms, _ offer: Double?) -> HirePay? {
        let cid: Int = request.companyID ?? 0
        if isWorker {
            guard let s = e.termsSummary(companyID: cid, candidateID: request.personID, terms: terms, offer: offer) else { return nil }
            let picks: [HireCounter] = s.counterOptions.map { (o: TermsCounterOption) -> HireCounter in HireCounter(id: o.id, wage: o.monthlyWage) }
            return HirePay(ask: s.salaryAsk, market: s.marketPay, yours: s.yourOffer, startWeek: s.startWeek, counters: picks)
        }
        guard let t = e.hireSalaryTalk(post: request.post, companyID: request.companyID, chainID: request.chainID, personID: request.personID, terms: terms, offer: offer) else { return nil }
        var picks: [HireCounter] = []
        if let ask = t.theirAsk {
            picks.append(HireCounter(id: "ask", wage: ask))
            picks.append(HireCounter(id: "market", wage: t.marketPay))
            picks.append(HireCounter(id: "middle", wage: ((ask + t.marketPay) / 2).rounded()))
        } else {
            picks.append(HireCounter(id: "market", wage: t.marketPay))
        }
        return HirePay(ask: t.theirAsk, market: t.marketPay, yours: t.yourOffer, startWeek: e.state.week, counters: picks)
    }

    // MARK: Helpers

    private func currency(_ e: GameEngine) -> Currency {
        if let id = request.companyID, let co = e.state.company(id) { return e.currency(for: co) }
        return e.homeCurrency
    }

    private func sells(_ e: GameEngine) -> Bool {
        guard isWorker, let id = request.companyID, let co = e.state.company(id), let role = e.state.people[request.personID]?.role else { return false }
        return PayPlans.eligible(role: role, trade: co.type, salesRoles: e.salesRoles)
    }

    private func termsOf(_ e: GameEngine, _ opts: HireDraftOptions) -> Hiring.Terms {
        model.draft.terms(worker: isWorker, sells: sells(e), busy: opts.busyMonths)
    }

    private func has(_ opts: HireDraftOptions, _ field: String) -> Bool { opts.fields.contains(field) }

    // MARK: The page

    private func page(_ e: GameEngine, _ person: Person, _ opts: HireDraftOptions) -> some View {
        let cur: Currency = currency(e)
        let terms: Hiring.Terms = termsOf(e, opts)
        let problem: String? = e.hireTermsProblem(post: request.post, companyID: request.companyID, personID: request.personID, terms: terms)
        let offerArg: Double? = model.offerSet ? model.offer : nil
        let summary: HirePay? = paySummary(e, terms, offerArg)
        return scrolled {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                header(e, person)
                if let s = summary {
                    if stage == 1 { quickStage(e, s, cur, terms, problem).transition(.opacity) } else { payStage(e, opts, s, cur, terms, problem).transition(.opacity) }
                }
            }
        }
    }

    /// One header for both pages: who they are and what they claim.
    private func header(_ e: GameEngine, _ person: Person) -> some View {
        return HStack(spacing: 10) {
            ThumbnailView(kind: .person, key: person.role, size: 36, initials: person.name, face: person.faceKey)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name).font(.serifTitle(17)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text(CandidateClaims.line(e, person)).font(.system(size: 11)).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func cardBox<C: View>(@ViewBuilder _ content: @escaping () -> C) -> some View {
        Card(padding: 12, radius: Theme.Radius.card) { content() }
    }

    private func block<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).capsLabel()
            content()
        }
    }

    private func chip(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(QuietButtonStyle(tint: on ? Theme.gold : Theme.ivoryMuted))
    }

    private func problemText(_ problem: String?) -> some View {
        Text(problem ?? "").font(.system(size: 12)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Page 1: the going rate

    private func quickStage(_ e: GameEngine, _ s: HirePay, _ cur: Currency, _ terms: Hiring.Terms, _ problem: String?) -> some View {
        let rate: Double = s.market
        let talk: HireSalaryTalk? = e.hireSalaryTalk(post: request.post, companyID: request.companyID, chainID: request.chainID, personID: request.personID, terms: terms, offer: rate)
        let annual: Double = talk?.annualEmployerCost ?? 0
        let startText: String = GameCalendar.dateString(week: s.startWeek)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            cardBox {
                VStack(alignment: .leading, spacing: 8) {
                    FlatRow(label: "Asks", value: s.ask.map { (a: Double) -> String in cur.tidyShort(a) + " a month" } ?? "Names it when you offer", rule: false)
                    FlatRow(label: "Going rate", value: cur.tidyShort(rate) + " a month", rule: false)
                    FlatRow(label: "Starts", value: startText, rule: false)
                }
            }
            if problem != nil { problemText(problem) }
            QuietButton(title: "Offer the going rate", fullWidth: true) { confirm(rate, annual, cur, terms) }
                .opacity(problem == nil ? 1 : 0.5).disabled(problem != nil)
                .accessibilityIdentifier("hire-quick-offer")
            Button { go(2) } label: {
                Text("Change the offer").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(PressableStyle()).accessibilityIdentifier("hire-next")
        }
    }

    private func contractBlock(_ opts: HireDraftOptions) -> some View {
        let kinds: [HireDraft.Kind] = opts.contractKinds.compactMap { (k: HireOption) -> HireDraft.Kind? in HireDraft.Kind(rawValue: k.id) }
        return block("Contract") {
            SegmentedChoice(items: kinds, title: { (k: HireDraft.Kind) -> String in opts.contractKinds.first { (o: HireOption) -> Bool in o.id == k.rawValue }?.title ?? k.rawValue }, selection: $model.draft.kind)
        }
    }

    private func hoursBlock(_ opts: HireDraftOptions) -> some View {
        let hours: Double = model.draft.percent / 100 * StaffModel.fullWeekHours
        let caption: String = HireWords.hours(hours)
        return block("Hours \u{00B7} " + caption) {
            SegmentedChoice(items: opts.percents, title: { (v: Double) -> String in "\(Int(v))%" }, selection: $model.draft.percent)
        }
    }

    private func weeksStepper(_ opts: HireDraftOptions) -> some View {
        Stepper("Ends after \(HireWords.weeksText(model.draft.weeks))", value: $model.draft.weeks, in: opts.temporaryWeekRange, step: 1)
            .font(.system(size: 13)).foregroundStyle(Theme.ivory)
    }

    private func seasonBlock(_ opts: HireDraftOptions) -> some View {
        let ids: Set<String> = model.draft.seasonIDs
        return block("Seasons") {
            WrapRow {
                ForEach(opts.seasons) { (s: HireOption) -> AnyView in
                    let on: Bool = ids.contains(s.id)
                    return AnyView(chip(s.title, on) { if on { model.draft.seasonIDs.remove(s.id) } else { model.draft.seasonIDs.insert(s.id) } })
                }
                chip("Every year", model.draft.seasonCount == 0) { model.draft.seasonCount = 0 }
                chip("This season", model.draft.seasonCount == 1) { model.draft.seasonCount = 1 }
            }
        }
    }

    @ViewBuilder private func promisesBlock(_ opts: HireDraftOptions) -> some View {
        if has(opts, "promises") && !opts.promiseKinds.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Promises you make").capsLabel()
                ForEach(Array(model.draft.promises.enumerated()), id: \.offset) { i, d -> AnyView in
                    AnyView(HStack {
                        Text(d.kind.title).font(.system(size: 13)).foregroundStyle(Theme.ivory)
                        Spacer(minLength: 6)
                        Text("in \(HireWords.weeksText(d.dueInWeeks))").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        Button { model.draft.promises.remove(at: i) } label: { Image(systemName: "xmark.circle").foregroundStyle(Theme.ivoryFaint) }
                            .buttonStyle(PressableStyle()).accessibilityLabel("Remove this promise")
                    })
                }
                PromiseMaker(options: opts, current: model.draft.percent) { (d: StaffPromises.Draft) -> Void in model.draft.promises.append(d) }
            }
        }
    }

    // MARK: Page 2: terms and pay

    private func shownOffer(_ s: HirePay) -> Double {
        if model.offerSet { return model.offer }
        return s.yours > 0 ? s.yours : s.market
    }

    private func payStage(_ e: GameEngine, _ opts: HireDraftOptions, _ s: HirePay, _ cur: Currency, _ terms: Hiring.Terms, _ problem: String?) -> some View {
        let shown: Double = shownOffer(s)
        let talk: HireSalaryTalk? = e.hireSalaryTalk(post: request.post, companyID: request.companyID, chainID: request.chainID, personID: request.personID, terms: terms, offer: shown)
        let comOnly: Bool = model.draft.isCommissionOnly(sells: sells(e))
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            figuresCard(s, cur, shown)
            if s.ask == nil { hearAskRow(e, cur, terms) }
            counterChips(s, shown)
            offerSlider(s, cur, shown)
            costLine(talk, cur, comOnly)
            if has(opts, "percent") { cardBox { hoursBlock(opts) } }
            if problem != nil { problemText(problem) }
            if let last = model.lines.last { SpeechBubble(text: last.text, mine: last.mine) }
            moreTerms(e, opts)
            actions(talk, cur, terms, shown, blocked: problem != nil)
        }
    }

    private func figuresCard(_ s: HirePay, _ cur: Currency, _ shown: Double) -> some View {
        cardBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(cur.tidyShort(shown)).font(.serifTitle(34)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.6)
                    Text("a month, yours").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    Spacer(minLength: 0)
                }
                HStack {
                    Text(s.ask.map { (a: Double) -> String in "They ask " + cur.tidyShort(a) } ?? "Ask not said yet").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.caution)
                    Spacer(minLength: 6)
                    Text("Market " + cur.tidyShort(s.market)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                }
            }
        }
    }

    private func chipTitle(_ id: String) -> String {
        switch id {
        case "ask": return "Ask"
        case "market": return "Market"
        case "middle": return "Middle"
        default: return "Yours"
        }
    }

    private func counterChips(_ s: HirePay, _ shown: Double) -> some View {
        let picks: [HireCounter] = s.counters.filter { (o: HireCounter) -> Bool in o.id == "ask" || o.id == "market" || o.id == "middle" }
        let anyOn: Bool = picks.contains { (o: HireCounter) -> Bool in abs(o.wage - shown) < 0.5 }
        return HStack(spacing: 6) {
            ForEach(picks) { (o: HireCounter) -> AnyView in
                let on: Bool = abs(o.wage - shown) < 0.5
                let id: String = o.id == "ask" ? "hire-offer-ask" : o.id == "market" ? "hire-offer-market" : "hire-offer-" + o.id
                return AnyView(chipButton(chipTitle(o.id), on, id) { model.offer = o.wage; model.offerSet = true })
            }
            chipButton("Yours", !anyOn, "hire-offer-yours") { model.offer = shown; model.offerSet = true }
        }
    }

    /// Posts other than workers: their ask stays unsaid until you ask for it (the engine's `hearTheirAsk`).
    private func hearAskRow(_ e: GameEngine, _ cur: Currency, _ terms: Hiring.Terms) -> some View {
        let post = request.post, cid = request.companyID, chain = request.chainID, pid = request.personID
        let factor: Double = hourFactor
        return Button {
            let amount: Double? = store.act { $0.hearTheirAsk(post: post, companyID: cid, chainID: chain, personID: pid, terms: terms) } ?? nil
            if let amount {
                Haptics.tap()
                model.lines.append(HireLine(mine: false, text: "I would want about \(HireWords.hourly(amount / factor, cur)) an hour for this."))
            }
        } label: {
            Text("Hear their ask").font(.system(size: 13)).foregroundStyle(Theme.gold).frame(maxWidth: .infinity, minHeight: 34).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle()).accessibilityIdentifier("hire-hear-ask")
    }

    private func chipButton(_ title: String, _ on: Bool, _ id: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.choose(); action() } label: {
            Text(title).font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundStyle(on ? Theme.ivory : Theme.ivoryMuted)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(on ? Theme.goldSelected : Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(on ? Theme.gold : Theme.border, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier(id)
    }

    private func offerSlider(_ s: HirePay, _ cur: Currency, _ shown: Double) -> some View {
        let step: Double = cur.stepSize(about: 500)
        let askNow: Double = s.ask ?? s.market
        let low: Double = max(step, min(askNow, s.market) * 0.5)
        let top: Double = max(askNow, s.market) * 1.6
        let high: Double = max(top, low + step * 4)
        let clamped: Double = min(max(shown, low), high)
        let binding = Binding<Double>(get: { clamped }, set: { (v: Double) -> Void in
            let snapped: Double = (v / step).rounded() * step
            model.offer = snapped
            model.offerSet = true
        })
        return HStack(spacing: 8) {
            Button { model.offer = max(low, shown - step); model.offerSet = true } label: { Image(systemName: "minus.circle").foregroundStyle(Theme.ivoryMuted) }
                .buttonStyle(PressableStyle()).accessibilityLabel("Offer less")
            LedgerSlider(value: binding, in: low...high).tint(Theme.gold)
            Button { model.offer = shown + step; model.offerSet = true } label: { Image(systemName: "plus.circle").foregroundStyle(Theme.ivoryMuted) }
                .buttonStyle(PressableStyle()).accessibilityLabel("Offer more")
        }
    }

    // MARK: Pay basis and sellers' plan

    private func planTitle(_ p: HireDraft.Plan) -> String {
        switch p {
        case .salary: return "Salary"
        case .mix: return "Mix"
        case .com: return "Commission"
        }
    }

    private func basisTitle(_ p: HireDraft.Pay, _ opts: HireDraftOptions) -> String {
        if p == .usual { return "Usual" }
        let wantFix: Bool = p == .fix
        return opts.payBases.first { (b: HireOption) -> Bool in (b.id == "fix") == wantFix }?.title ?? p.rawValue
    }

    private func basisCard(_ e: GameEngine, _ opts: HireDraftOptions) -> some View {
        let more: [HireDraft.Pay] = opts.payBases.map { (b: HireOption) -> HireDraft.Pay in b.id == "fix" ? HireDraft.Pay.fix : HireDraft.Pay.hour }
        let keys: [HireDraft.Pay] = [HireDraft.Pay.usual] + more
        let seller: Bool = sells(e)
        return cardBox {
            VStack(alignment: .leading, spacing: 8) {
                block("Pay basis") {
                    SegmentedChoice(items: keys, title: { (p: HireDraft.Pay) -> String in basisTitle(p, opts) }, selection: $model.draft.pay)
                }
                if seller {
                    block("Sales pay") {
                        SegmentedChoice(items: HireDraft.Plan.allCases, title: { (p: HireDraft.Plan) -> String in planTitle(p) }, selection: $model.draft.plan)
                    }
                }
            }
        }
    }

    private func costLine(_ talk: HireSalaryTalk?, _ cur: Currency, _ comOnly: Bool) -> some View {
        let monthly: String = talk.map { (t: HireSalaryTalk) -> String in cur.tidyShort(t.monthlyEmployerCost) } ?? ""
        let hourly: String = talk.map { (t: HireSalaryTalk) -> String in HireWords.hourly(t.hourlyWage, cur) } ?? ""
        let full: String = "\(hourly) an hour \u{00B7} costs you \(monthly) a month in all"
        let line: String = comOnly ? "No base wage: you pay a share of their sales" : full
        let lifted: Bool = talk?.liftedToMinimum ?? false
        return VStack(alignment: .leading, spacing: 2) {
            Text(line).font(.system(size: 12.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
            if lifted { Text("Lifted to the minimum wage.").font(.system(size: 11.5)).foregroundStyle(Theme.caution) }
        }
    }

    // MARK: More terms (contract type, seasons, pay basis, commission, benefits, promises, expectations)

    private func moreTerms(_ e: GameEngine, _ opts: HireDraftOptions) -> some View {
        let bonus: Int = model.draft.bonusPlan == nil ? 0 : 1
        let picked: Int = model.draft.expectations.count + model.draft.expenses.count + model.draft.promises.count + bonus
        let label: String = picked == 0 ? "More terms" : "More terms (\(picked) chosen)"
        let seller: Bool = sells(e) && model.draft.plan != .salary
        return DisclosureGroup(label) {
            VStack(alignment: .leading, spacing: 10) {
                if has(opts, "contractType") { contractBlock(opts); basisCard(e, opts) }
                if model.draft.kind == .temporary { weeksStepper(opts) }
                if model.draft.kind == .seasonal { seasonBlock(opts) }
                if seller { rateBlock() }
                if has(opts, "benefits") { benefitsBlock(opts) }
                if has(opts, "expectations") { expectationsBlock(opts) }
                promisesBlock(opts)
            }
            .padding(.top, 6)
        }
        .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
    }

    private func rateBlock() -> some View {
        let rates: [Double] = [0.0] + PayPlans.rateSteps
        return block("Commission share") {
            WrapRow {
                ForEach(rates, id: \.self) { (r: Double) -> AnyView in
                    let on: Bool = abs(model.draft.rate - r) < 0.0001
                    let title: String = r == 0 ? "Usual" : "\(Int((r * 100).rounded()))%"
                    return AnyView(chip(title, on) { model.draft.rate = r })
                }
            }
        }
    }

    private func benefitsBlock(_ opts: HireDraftOptions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !opts.companyPerks.isEmpty {
                Text("Already given: " + opts.companyPerks.joined(separator: ", ")).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }
            if !opts.bonusPlans.isEmpty { bonusBlock(opts) }
            if !opts.expenses.isEmpty { expensesBlock(opts) }
            if has(opts, "vehicle") && opts.canUseOwnCar { vehicleBlock() }
        }
    }

    private func bonusBlock(_ opts: HireDraftOptions) -> some View {
        block("Bonus plan") {
            WrapRow {
                chip("None", model.draft.bonusPlan == nil) { model.draft.bonusPlan = nil }
                ForEach(opts.bonusPlans) { (p: HireOption) -> AnyView in
                    AnyView(chip(p.title, model.draft.bonusPlan == p.id) { model.draft.bonusPlan = p.id })
                }
            }
        }
    }

    private func expensesBlock(_ opts: HireDraftOptions) -> some View {
        block("Expenses paid") {
            WrapRow {
                ForEach(opts.expenses) { (x: HireOption) -> AnyView in
                    let on: Bool = model.draft.expenses.contains(x.id)
                    return AnyView(chip(x.title, on) { if on { model.draft.expenses.remove(x.id) } else { model.draft.expenses.insert(x.id) } })
                }
            }
        }
    }

    private func vehicleBlock() -> some View {
        block("Vehicle") {
            WrapRow {
                chip("No car deal", !model.draft.ownCar) { model.draft.ownCar = false }
                chip("Own car, mileage paid", model.draft.ownCar) { model.draft.ownCar = true }
            }
        }
    }

    private func expectationsBlock(_ opts: HireDraftOptions) -> some View {
        block("What you expect") {
            WrapRow {
                ForEach(opts.expectations) { (x: HireOption) -> AnyView in
                    let on: Bool = model.draft.expectations.contains(x.id)
                    return AnyView(chip(x.title, on) { if on { model.draft.expectations.remove(x.id) } else { model.draft.expectations.insert(x.id) } })
                }
            }
        }
    }

    // MARK: Buttons

    private func actions(_ talk: HireSalaryTalk?, _ cur: Currency, _ terms: Hiring.Terms, _ shown: Double, blocked: Bool) -> some View {
        let annual: Double = talk?.annualEmployerCost ?? 0
        return VStack(spacing: 4) {
            QuietButton(title: "Make the offer", fullWidth: true) { confirm(shown, annual, cur, terms) }
                .opacity(blocked ? 0.5 : 1).disabled(blocked)
                .accessibilityIdentifier("hire-make-offer")
            HStack {
                Button { go(1) } label: {
                    Text("Back").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(PressableStyle()).accessibilityIdentifier("hire-back")
                Button { Haptics.tap(); dismiss() } label: {
                    Text("Walk away").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(PressableStyle()).accessibilityIdentifier("hire-walk-away")
            }
        }
    }

    // MARK: Actions

    private func confirm(_ amount: Double, _ annual: Double, _ cur: Currency, _ terms: Hiring.Terms) {
        let cost: String = annual > 0 ? " The company pays about \(cur.tidyShort(annual)) a year in total employer cost." : ""
        let message: String = "If \(first) accepts, they start at once at \(cur.tidyShort(amount)) a month.\(cost) If not, they may name a figure of their own, take offence or lose patience."
        pending = PendingAction(title: "Offer \(cur.tidyShort(amount)) a month to \(first)?", message: message, button: "Make the offer") { send(amount, cur, terms) }
    }

    private func send(_ amount: Double, _ cur: Currency, _ terms: Hiring.Terms) {
        let post = request.post, cid = request.companyID, chain = request.chainID, city = request.city, pid = request.personID
        let result: HireOutcome? = store.act { $0.hireOffer(post: post, companyID: cid, chainID: chain, city: city, personID: pid, monthlyWage: amount, terms: terms) }
        guard let result else { store.show("No game is loaded.", tone: "warn"); return }
        let name: String = store.engine?.state.people[pid]?.name ?? first
        let said = HireOutcomeWords.line(result, name: name, cur: cur, hourFactor: hourFactor)
        model.lines.append(HireLine(mine: true, text: "I can offer \(cur.tidyShort(amount)) a month."))
        model.lines.append(HireLine(mine: false, text: said.text))
        switch result {
        case .hired:
            model.hired = true; model.closing = "\(name) has joined as \(request.roleTitle.lowercased())."
            Haptics.option(); store.show(model.closing, tone: "good"); request.onHired()
        case .countered(let amount, _): model.offer = amount; model.offerSet = true; Haptics.tap()
        case .refused, .termsRefused, .blocked: Haptics.warning(); if case .blocked = result { store.show(said.text, tone: "warn") }
        case .walkedAway, .taken:
            model.gone = true; model.closing = said.text; Haptics.warning(); store.show(said.text, tone: "warn")
        }
    }

    // MARK: Ended

    private var ended: some View {
        scrolled {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                VStack(spacing: 8) { ForEach(model.lines) { (l: HireLine) -> SpeechBubble in SpeechBubble(text: l.text, mine: l.mine) } }
                Text(model.closing).font(.system(size: 14, weight: .medium)).foregroundStyle(model.hired ? Theme.gain : Theme.ivoryMuted)
                QuietButton(title: "Done", fullWidth: true) { model.finished = true }.accessibilityIdentifier("hire-done")
            }
        }
    }
}

/// The frame of `HireOnePage`: the app screen when pushed, or just the popup's title when embedded in the hiring popup.
private struct HireFrame: ViewModifier {
    @EnvironmentObject var store: GameStore
    var embedded: Bool
    var title: String
    var subtitle: String

    @ViewBuilder func body(content: Content) -> some View {
        if embedded {
            content.centerSheetTitle(title)
        } else {
            content.appScreen(title: title, subtitle: subtitle, tab: store.tab)
        }
    }
}
