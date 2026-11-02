import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

/// "Hire <name>": the terms and the salary talk on ONE page for a worker. At the top what they ask, the market pay, hours, contract, promises asked
/// and the start date (the engine's `termsSummary`); the few terms a player changes (contract, working percentage, promises) sit under it, then the
/// counter options and your own figure. Every figure is the engine's: `termsSummary` for what is shown, `hireOffer` for the answer. Posts other than
/// workers (manager, assistant, team posts) still use the two-page flow (`HireTermsPage`, `HireSalaryPage`).
struct HireOnePage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var request: HireRequest
    @StateObject private var model = HireFlowModel()
    @State private var pending: PendingAction?

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
        .appScreen(title: "Hire \(HireWords.first(store.engine?.state.people[request.personID]?.name ?? "worker"))", subtitle: request.roleTitle, tab: store.tab)
        .confirmAction($pending)
        .onChange(of: model.finished) { _, done in if done { dismiss() } }
    }

    // MARK: Helpers

    private func currency(_ e: GameEngine) -> Currency {
        if let id = request.companyID, let co = e.state.company(id) { return e.currency(for: co) }
        return e.homeCurrency
    }

    private func sells(_ e: GameEngine) -> Bool {
        guard let id = request.companyID, let co = e.state.company(id), let role = e.state.people[request.personID]?.role else { return false }
        return PayPlans.eligible(role: role, trade: co.type, salesRoles: e.salesRoles)
    }

    private func termsOf(_ e: GameEngine, _ opts: HireDraftOptions) -> Hiring.Terms {
        model.draft.terms(worker: true, sells: sells(e), busy: opts.busyMonths)
    }

    private func has(_ opts: HireDraftOptions, _ field: String) -> Bool { opts.fields.contains(field) }

    // MARK: The page

    private func page(_ e: GameEngine, _ person: Person, _ opts: HireDraftOptions) -> some View {
        let cur: Currency = currency(e)
        let terms: Hiring.Terms = termsOf(e, opts)
        let cid: Int = request.companyID ?? 0
        let problem: String? = e.hireTermsProblem(post: request.post, companyID: request.companyID, personID: request.personID, terms: terms)
        let summary: TermsSummary? = e.termsSummary(companyID: cid, candidateID: request.personID, terms: terms, offer: model.offerSet ? model.offer : nil)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                candidateHeader(e, person)
                if let s = summary { summaryCard(s, cur) }
                termsControls(e, opts)
                if let problem { Text(problem).font(.system(size: 12.5)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true) }
                if !model.lines.isEmpty { VStack(spacing: 8) { ForEach(model.lines) { (l: HireLine) -> SpeechBubble in SpeechBubble(text: l.text, mine: l.mine) } } }
                if let s = summary { offers(e, opts, s, cur, blocked: problem != nil) }
            }
            .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }

    private func candidateHeader(_ e: GameEngine, _ person: Person) -> some View {
        HStack(spacing: 12) {
            ThumbnailView(kind: .person, key: person.role, size: 40, initials: person.name, face: person.faceKey)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.serifTitle(19)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text(CandidateClaims.line(e, person)).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: What they ask and what it means

    private func summaryCard(_ s: TermsSummary, _ cur: Currency) -> some View {
        let hours: String = HireWords.hours(s.hoursPerWeek)
        let start: String = GameCalendar.dateString(week: s.startWeek)
        let moodLine: String = s.talkMood.isEmpty ? "" : "How \(first) feels: \(s.talkMood)"
        return Card(padding: 12, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 0) {
                FlatRow(label: "They ask", value: cur.tidyShort(s.salaryAsk) + " a month", tint: Theme.caution, rule: false)
                FlatRow(label: "Market pay", value: cur.tidyShort(s.marketPay) + " a month")
                FlatRow(label: "Hours", value: hours, sub: HireWords.percentText(s.workingPercent))
                FlatRow(label: "Contract", value: s.contractType)
                FlatRow(label: "Promises asked", value: s.promisesAsked.isEmpty ? "None" : s.promisesAsked.joined(separator: "; "))
                FlatRow(label: "Starts", value: start, sub: moodLine)
            }
        }
    }

    // MARK: The few terms to change

    private func termsControls(_ e: GameEngine, _ opts: HireDraftOptions) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if has(opts, "contractType") { contractChoice(opts) }
            if has(opts, "percent") { percentChoice(opts) }
            promisesBlock(opts)
        }
    }

    private func contractChoice(_ opts: HireDraftOptions) -> some View {
        let kinds: [HireDraft.Kind] = opts.contractKinds.compactMap { (k: HireOption) -> HireDraft.Kind? in HireDraft.Kind(rawValue: k.id) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Contract").capsLabel()
            SegmentedChoice(items: kinds, title: { (k: HireDraft.Kind) -> String in opts.contractKinds.first { (o: HireOption) -> Bool in o.id == k.rawValue }?.title ?? k.rawValue }, selection: $model.draft.kind)
            if model.draft.kind == .temporary {
                Stepper("Ends after \(HireWords.weeksText(model.draft.weeks))", value: $model.draft.weeks, in: opts.temporaryWeekRange, step: 1)
                    .font(.system(size: 13)).foregroundStyle(Theme.ivory)
            }
        }
    }

    private func percentChoice(_ opts: HireDraftOptions) -> some View {
        let p: Double = model.draft.percent
        return VStack(alignment: .leading, spacing: 6) {
            Text("Working percentage").capsLabel()
            WrapRow {
                ForEach(opts.percents, id: \.self) { (v: Double) -> AnyView in
                    AnyView(Button("\(Int(v)) percent") { model.draft.percent = v }
                        .buttonStyle(QuietButtonStyle(tint: abs(p - v) < 0.0001 ? Theme.gold : Theme.ivoryMuted)))
                }
            }
        }
    }

    @ViewBuilder private func promisesBlock(_ opts: HireDraftOptions) -> some View {
        if has(opts, "promises") && !opts.promiseKinds.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Promises").capsLabel()
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

    // MARK: Counter options

    private func offers(_ e: GameEngine, _ opts: HireDraftOptions, _ s: TermsSummary, _ cur: Currency, blocked: Bool) -> some View {
        let terms: Hiring.Terms = termsOf(e, opts)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Your offer").capsLabel()
            ForEach(s.counterOptions) { (o: TermsCounterOption) -> AnyView in
                AnyView(optionRow(o, cur, terms, blocked: blocked))
            }
            ownFigure(s, cur, terms, blocked: blocked)
            Button { Haptics.tap(); dismiss() } label: {
                Text("Walk away").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(PressableStyle()).accessibilityIdentifier("hire-walk-away")
        }
    }

    private func optionRow(_ o: TermsCounterOption, _ cur: Currency, _ terms: Hiring.Terms, blocked: Bool) -> some View {
        let id: String = o.id == "ask" ? "hire-offer-ask" : o.id == "market" ? "hire-offer-market" : "hire-offer-" + o.id
        return Button { confirm(o.monthlyWage, o.annualEmployerCost, cur, terms) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(o.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text(cur.tidyShort(o.annualEmployerCost) + " a year to you in all").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer(minLength: 6)
                Text(cur.tidyShort(o.monthlyWage)).font(.system(size: 14, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(blocked)
        .opacity(blocked ? 0.5 : 1)
        .accessibilityIdentifier(id)
    }

    private func ownFigure(_ s: TermsSummary, _ cur: Currency, _ terms: Hiring.Terms, blocked: Bool) -> some View {
        let step: Double = cur.stepSize(about: 500)
        let shown: Double = model.offerSet ? model.offer : s.marketPay
        return VStack(alignment: .leading, spacing: 6) {
            Stepper("Your own: \(cur.tidyShort(shown)) a month", onIncrement: { model.offer = shown + step; model.offerSet = true },
                    onDecrement: { model.offer = max(step, shown - step); model.offerSet = true })
                .font(.system(size: 13)).foregroundStyle(Theme.ivory)
            QuietButton(title: "Offer \(cur.tidyShort(shown)) a month", fullWidth: true) { confirm(shown, 0, cur, terms) }
                .opacity(blocked ? 0.5 : 1).disabled(blocked)
                .accessibilityIdentifier("hire-make-offer")
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
            Haptics.success(); store.show(model.closing, tone: "good"); request.onHired()
        case .countered: Haptics.tap()
        case .refused, .termsRefused, .blocked: Haptics.warning(); if case .blocked = result { store.show(said.text, tone: "warn") }
        case .walkedAway, .taken:
            model.gone = true; model.closing = said.text; Haptics.warning(); store.show(said.text, tone: "warn")
        }
    }

    // MARK: Ended

    private var ended: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                VStack(spacing: 8) { ForEach(model.lines) { (l: HireLine) -> SpeechBubble in SpeechBubble(text: l.text, mine: l.mine) } }
                Text(model.closing).font(.system(size: 14, weight: .medium)).foregroundStyle(model.hired ? Theme.gain : Theme.ivoryMuted)
                QuietButton(title: "Done", fullWidth: true) { model.finished = true }.accessibilityIdentifier("hire-done")
            }
            .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
        }
    }
}
