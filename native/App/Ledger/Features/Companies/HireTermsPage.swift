import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

/// PAGE 1 of the hiring flow: the contract terms. Contract type, working percentage, seasonal or temporary duration, benefits, a vehicle or an own car,
/// promises and what you expect of the job. Only the parts that apply to the post are shown (the engine's `hireDraftOptions` says which). "Next" opens
/// page 2, the salary negotiation; coming back from it keeps every term (`HireFlowModel`).
struct HireTermsPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var request: HireRequest
    @StateObject private var model = HireFlowModel()

    var body: some View {
        Group {
            if let e = store.engine, let person = e.state.people[request.personID], person.employerID == 0 || model.hired,
               let opts = e.hireDraftOptions(post: request.post, companyID: request.companyID, personID: request.personID) {
                page(e, person, opts)
            } else {
                Text("\(HireWords.first(store.engine?.state.people[request.personID]?.name ?? "This person")) is no longer on the market.")
                    .font(.bodyText).foregroundStyle(Theme.ivoryMuted).padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .appScreen(title: store.engine?.state.people[request.personID]?.name ?? "Terms", subtitle: "\(request.roleTitle) \u{00B7} contract terms", tab: store.tab)
        .onChange(of: model.finished) { _, done in if done { finish() } }
        .onAppear { if model.finished || model.hired { finish() } }
    }

    /// Hired (or done): close the flow.
    private func finish() { dismiss() }

    // MARK: Helpers

    private var isWorker: Bool { if case .worker = request.post { return true }; return false }

    private func sells(_ e: GameEngine) -> Bool {
        guard isWorker, let id = request.companyID, let co = e.state.company(id), let role = e.state.people[request.personID]?.role else { return false }
        return PayPlans.eligible(role: role, trade: co.type, salesRoles: e.salesRoles)
    }

    private func terms(_ e: GameEngine, _ opts: HireDraftOptions) -> Hiring.Terms {
        model.draft.terms(worker: isWorker, sells: sells(e), busy: opts.busyMonths)
    }

    private func has(_ opts: HireDraftOptions, _ field: String) -> Bool { opts.fields.contains(field) }

    // MARK: The page

    @ViewBuilder private func page(_ e: GameEngine, _ person: Person, _ opts: HireDraftOptions) -> some View {
        let cur: Currency = currency(e)
        let problem: String? = e.hireTermsProblem(post: request.post, companyID: request.companyID, personID: request.personID, terms: terms(e, opts))
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                candidateHeader(e, person, cur)
                if has(opts, "contractType") { contractType(opts) }
                if has(opts, "percent") { percent(opts) }
                if has(opts, "duration") && model.draft.kind != .permanent { duration(opts) }
                if has(opts, "contractType") { payBasis(e, opts) }
                if has(opts, "benefits") { benefits(opts) }
                promisesSection(opts)
                expectations(opts)
                nextBar(e, opts, problem)
            }
            .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }

    private func currency(_ e: GameEngine) -> Currency {
        if let id = request.companyID, let co = e.state.company(id) { return e.currency(for: co) }
        return e.homeCurrency
    }

    private func candidateHeader(_ e: GameEngine, _ person: Person, _ cur: Currency) -> some View {
        let line: String = CandidateClaims.line(e, person)
        let market: Double = e.goingRate(for: request.post, companyID: request.companyID)
        return HStack(spacing: 12) {
            ThumbnailView(kind: .person, key: person.role, size: 44, initials: person.name, face: person.faceKey)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.serifTitle(20)).foregroundStyle(Theme.ivory)
                Text(line).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                Text("Market pay for the post: \(cur.tidyShort(market)) a month").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Contract type and working percentage

    private func contractType(_ opts: HireDraftOptions) -> some View {
        let kinds: [HireDraft.Kind] = opts.contractKinds.compactMap { HireDraft.Kind(rawValue: $0.id) }
        let detail: String = opts.contractKinds.first { $0.id == model.draft.kind.rawValue }?.detail ?? ""
        return LedgerSection("Contract type") {
            VStack(alignment: .leading, spacing: 8) {
                SegmentedChoice(items: kinds, title: { k in opts.contractKinds.first { $0.id == k.rawValue }?.title ?? k.rawValue }, selection: $model.draft.kind)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func percent(_ opts: HireDraftOptions) -> some View {
        let p: Double = model.draft.percent
        let hours: Double = p / 100 * StaffModel.fullWeekHours
        let over: Bool = opts.hoursLimit.map { hours > $0 + 1e-9 } ?? false
        return LedgerSection("Working percentage") {
            VStack(alignment: .leading, spacing: 8) {
                WrapRow {
                    ForEach(opts.percents, id: \.self) { v in
                        Button("\(Int(v)) percent") { model.draft.percent = v }
                            .buttonStyle(QuietButtonStyle(tint: abs(p - v) < 0.0001 ? Theme.gold : Theme.ivoryMuted))
                    }
                }
                Stepper("Other: \(HireWords.percentText(p))", value: $model.draft.percent, in: opts.percentRange, step: 5)
                    .font(.system(size: 13)).foregroundStyle(Theme.ivory)
                Text(HireWords.hours(hours)).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                if let limit = opts.hoursLimit {
                    Text("They can work at most \(HireWords.hours(limit)).").font(.system(size: 11.5)).foregroundStyle(over ? Theme.caution : Theme.ivoryFaint)
                }
            }
        }
    }

    // MARK: Seasonal or temporary duration

    @ViewBuilder private func duration(_ opts: HireDraftOptions) -> some View {
        if model.draft.kind == .temporary {
            LedgerSection("Duration") {
                VStack(alignment: .leading, spacing: 8) {
                    WrapRow {
                        ForEach(opts.temporaryWeekChoices, id: \.self) { w in
                            Button(HireWords.weeksText(w)) { model.draft.weeks = w }
                                .buttonStyle(QuietButtonStyle(tint: model.draft.weeks == w ? Theme.gold : Theme.ivoryMuted))
                        }
                    }
                    Stepper("Ends after \(HireWords.weeksText(model.draft.weeks))", value: $model.draft.weeks, in: opts.temporaryWeekRange, step: 1)
                        .font(.system(size: 13)).foregroundStyle(Theme.ivory)
                }
            }
        } else {
            LedgerSection("Seasons") { seasonChoices(opts) }
        }
    }

    private func seasonChoices(_ opts: HireDraftOptions) -> some View {
        let ids: Set<String> = model.draft.seasonIDs
        return VStack(alignment: .leading, spacing: 8) {
            WrapRow {
                ForEach(opts.seasons) { s in
                    Button(s.title) {
                        if ids.contains(s.id) { model.draft.seasonIDs.remove(s.id) } else { model.draft.seasonIDs.insert(s.id) }
                    }
                    .buttonStyle(QuietButtonStyle(tint: ids.contains(s.id) ? Theme.gold : Theme.ivoryMuted))
                }
            }
            if ids.isEmpty { Text("Nothing chosen: they work the busy months of the business.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }
            WrapRow {
                Button("Returns every year") { model.draft.seasonCount = 0 }.buttonStyle(QuietButtonStyle(tint: model.draft.seasonCount == 0 ? Theme.gold : Theme.ivoryMuted))
                Button("This season only") { model.draft.seasonCount = 1 }.buttonStyle(QuietButtonStyle(tint: model.draft.seasonCount == 1 ? Theme.gold : Theme.ivoryMuted))
                Button("Two seasons") { model.draft.seasonCount = 2 }.buttonStyle(QuietButtonStyle(tint: model.draft.seasonCount == 2 ? Theme.gold : Theme.ivoryMuted))
            }
        }
    }

    // MARK: Pay basis and sellers' plan

    @ViewBuilder private func payBasis(_ e: GameEngine, _ opts: HireDraftOptions) -> some View {
        let seller: Bool = sells(e)
        LedgerSection("Pay") {
            VStack(alignment: .leading, spacing: 8) {
                WrapRow {
                    Button("The job's usual") { model.draft.pay = .usual }.buttonStyle(QuietButtonStyle(tint: model.draft.pay == .usual ? Theme.gold : Theme.ivoryMuted))
                    ForEach(opts.payBases) { b in
                        let key: HireDraft.Pay = b.id == "fix" ? .fix : .hour
                        Button(b.title) { model.draft.pay = key }.buttonStyle(QuietButtonStyle(tint: model.draft.pay == key ? Theme.gold : Theme.ivoryMuted))
                    }
                }
                if seller { sellerPlan() }
            }
        }
    }

    private func sellerPlan() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SegmentedChoice(items: HireDraft.Plan.allCases, title: { $0.rawValue }, selection: $model.draft.plan)
            if model.draft.plan != .salary {
                WrapRow {
                    ForEach([0.0] + PayPlans.rateSteps, id: \.self) { r in
                        let on: Bool = abs(model.draft.rate - r) < 0.0001
                        Button(r == 0 ? "Usual share" : "\(Int((r * 100).rounded())) percent") { model.draft.rate = r }
                            .buttonStyle(QuietButtonStyle(tint: on ? Theme.gold : Theme.ivoryMuted))
                    }
                }
                let note: String = model.draft.plan == .com
                    ? "No base pay: what you offer is the pay they expect to earn. Someone who wants security may refuse."
                    : "What you offer is the base salary; commission on their sales comes on top."
                Text(note).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Benefits and vehicle

    @ViewBuilder private func benefits(_ opts: HireDraftOptions) -> some View {
        LedgerSection("Benefits") {
            VStack(alignment: .leading, spacing: 10) {
                if !opts.companyPerks.isEmpty {
                    Text("Already given here: " + opts.companyPerks.joined(separator: ", ")).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted)
                }
                if !opts.bonusPlans.isEmpty { bonusPlans(opts) }
                if !opts.expenses.isEmpty { expenses(opts) }
                if has(opts, "vehicle") && opts.canUseOwnCar { vehicle() }
            }
        }
    }

    private func bonusPlans(_ opts: HireDraftOptions) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bonus plan").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            WrapRow {
                Button("None") { model.draft.bonusPlan = nil }.buttonStyle(QuietButtonStyle(tint: model.draft.bonusPlan == nil ? Theme.gold : Theme.ivoryMuted))
                ForEach(opts.bonusPlans) { p in
                    Button(p.title) { model.draft.bonusPlan = p.id }.buttonStyle(QuietButtonStyle(tint: model.draft.bonusPlan == p.id ? Theme.gold : Theme.ivoryMuted))
                }
            }
        }
    }

    private func expenses(_ opts: HireDraftOptions) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Expenses paid for them").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            WrapRow {
                ForEach(opts.expenses) { x in
                    let on: Bool = model.draft.expenses.contains(x.id)
                    Button(x.title) { if on { model.draft.expenses.remove(x.id) } else { model.draft.expenses.insert(x.id) } }
                        .buttonStyle(QuietButtonStyle(tint: on ? Theme.gold : Theme.ivoryMuted))
                }
            }
        }
    }

    private func vehicle() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Vehicle").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            WrapRow {
                Button("No car arrangement") { model.draft.ownCar = false }.buttonStyle(QuietButtonStyle(tint: model.draft.ownCar ? Theme.ivoryMuted : Theme.gold))
                Button("Own car, mileage paid") { model.draft.ownCar = true }.buttonStyle(QuietButtonStyle(tint: model.draft.ownCar ? Theme.gold : Theme.ivoryMuted))
            }
        }
    }

    // MARK: Promises

    @ViewBuilder private func promisesSection(_ opts: HireDraftOptions) -> some View {
        if has(opts, "promises") && !opts.promiseKinds.isEmpty {
            LedgerSection("Promises") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(model.draft.promises.enumerated()), id: \.offset) { i, d in
                        HStack {
                            Text(d.kind.title).font(.system(size: 13)).foregroundStyle(Theme.ivory)
                            Spacer(minLength: 6)
                            Text("in \(HireWords.weeksText(d.dueInWeeks))").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                            Button { model.draft.promises.remove(at: i) } label: { Image(systemName: "xmark.circle").foregroundStyle(Theme.ivoryFaint) }
                                .buttonStyle(PressableStyle()).accessibilityLabel("Remove this promise")
                        }
                    }
                    PromiseMaker(options: opts, current: model.draft.percent) { model.draft.promises.append($0) }
                }
            }
        }
    }

    // MARK: Expectations

    @ViewBuilder private func expectations(_ opts: HireDraftOptions) -> some View {
        if has(opts, "expectations") {
            LedgerSection("What you expect") {
                VStack(alignment: .leading, spacing: 8) {
                    WrapRow {
                        ForEach(opts.expectations) { x in
                            let on: Bool = model.draft.expectations.contains(x.id)
                            Button(x.title) { if on { model.draft.expectations.remove(x.id) } else { model.draft.expectations.insert(x.id) } }
                                .buttonStyle(QuietButtonStyle(tint: on ? Theme.gold : Theme.ivoryMuted))
                        }
                    }
                    let shown: [HireOption] = opts.expectations.filter { model.draft.expectations.contains($0.id) }
                    ForEach(shown) { x in Text(x.detail).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
                }
            }
        }
    }

    // MARK: Next

    @ViewBuilder private func nextBar(_ e: GameEngine, _ opts: HireDraftOptions, _ problem: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let problem { Text(problem).font(.system(size: 12.5)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true) }
            NavigationLink { HireSalaryPage(request: request, model: model, termsOf: { terms(e, opts) }, commissionOnly: model.draft.isCommissionOnly(sells: sells(e))) } label: {
                Text("Next: salary").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                    .frame(maxWidth: .infinity, minHeight: 28).padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(problem == nil ? Theme.gold : Theme.border, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .disabled(problem != nil)
            .accessibilityIdentifier("hire-next")
        }
    }
}

/// Adds one promise to a draft: what, in how many weeks, and for the kinds that need it what exactly (a benefit, a working percentage).
/// Used by the hiring terms page and by the contract discussion; the engine records and checks the promise (`StaffPromises`).
struct PromiseMaker: View {
    struct Choice: Identifiable { var id: String; var title: String }
    var kinds: [StaffPromises.Kind]
    /// What fulfils each kind, in words, by the kind's raw value.
    var details: [String: String]
    var benefits: [Choice]
    var percents: [Double]
    /// The working percentage now (a promised change must differ from it).
    var current: Double
    var label = "Add a promise"
    var add: (StaffPromises.Draft) -> Void
    @State private var kind: StaffPromises.Kind = .salaryReview
    @State private var weeks = 13
    @State private var detail = ""
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(open ? "Close" : label) { open.toggle(); if let k = kinds.first, !kinds.contains(kind) { kind = k } }
                .buttonStyle(QuietButtonStyle(tint: Theme.gold)).accessibilityIdentifier("hire-add-promise")
            if open { maker }
        }
    }

    private var maker: some View {
        VStack(alignment: .leading, spacing: 8) {
            WrapRow {
                ForEach(kinds, id: \.self) { k in
                    Button(k.title) { kind = k; detail = "" }.buttonStyle(QuietButtonStyle(tint: kind == k ? Theme.gold : Theme.ivoryMuted))
                }
            }
            Text(details[kind.rawValue] ?? "").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            detailChoices
            Text("Due in").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            WrapRow {
                ForEach([4, 8, 13, 26, 52], id: \.self) { w in
                    Button(HireWords.weeksText(w)) { weeks = w }.buttonStyle(QuietButtonStyle(tint: weeks == w ? Theme.gold : Theme.ivoryMuted))
                }
            }
            let draft = StaffPromises.Draft(kind, dueInWeeks: weeks, detail: detail)
            QuietButton(title: "Promise \(kind.title.lowercased())") { add(draft); open = false; detail = "" }
                .opacity(draft.isPlausible ? 1 : 0.4).disabled(!draft.isPlausible)
                .accessibilityIdentifier("promise-confirm")
        }
    }

    @ViewBuilder private var detailChoices: some View {
        if kind == .futureBenefits {
            WrapRow {
                ForEach(benefits) { c in
                    Button(c.title) { detail = c.id }.buttonStyle(QuietButtonStyle(tint: detail == c.id ? Theme.gold : Theme.ivoryMuted))
                }
            }
        } else if kind == .percentageChange {
            WrapRow {
                ForEach(percents.filter { abs($0 - current) > 0.5 }, id: \.self) { p in
                    Button("\(Int(p)) percent") { detail = String(Int(p)) }.buttonStyle(QuietButtonStyle(tint: detail == String(Int(p)) ? Theme.gold : Theme.ivoryMuted))
                }
            }
        }
    }
}

extension PromiseMaker {
    /// The hiring terms page: kinds, wording, benefits and percentages come from the engine's draft options.
    init(options: HireDraftOptions, current: Double, add: @escaping (StaffPromises.Draft) -> Void) {
        let plans: [Choice] = options.bonusPlans.map { Choice(id: "plan:" + $0.id, title: $0.title) }
        let exps: [Choice] = options.expenses.map { Choice(id: "exp:" + $0.id, title: $0.title) }
        let perks: [Choice] = StaffPerks.all.map { Choice(id: "perk:" + $0.id, title: $0.name) }
        var words: [String: String] = [:]
        for k in options.promiseKinds { words[k.id] = k.detail }
        self.init(kinds: options.promiseKinds.compactMap { StaffPromises.Kind(rawValue: $0.id) }, details: words, benefits: plans + exps + perks,
                  percents: options.percents, current: current, add: add)
    }
}
