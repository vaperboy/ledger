import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Simulation

/// Start a company, last screen: the setup, what it costs now and to keep, and how long the cash lasts with no sales. Money moves only on "Open the company".
struct StartConfirmView: View {
    @EnvironmentObject var store: GameStore
    @EnvironmentObject var estimator: StartEstimator
    @Environment(Entitlements.self) private var ent
    @Environment(\.dismiss) private var dismiss
    var tradeID: String
    @State var cityID: String
    @State private var estimate: StartEstimate?
    @State private var facts: StartFacts?
    @State private var refusal: String?
    /// The company's own name (blank: the trade's name) and where it works.
    @State private var name = ""
    @State private var rentIndex: Int?
    @State private var buying = false

    init(tradeID: String, cityID: String) {
        self.tradeID = tradeID
        _cityID = State(initialValue: cityID)
    }

    var body: some View {
        if let e = store.engine {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    if let f = facts {
                        setup(e, f)
                        if let plan = premisesPlan(e, f) { PremisesPicker(plan: plan, cur: e.homeCurrency, rentIndex: $rentIndex, buying: $buying) }
                        ifYouOpen(f)
                        if let refusal {
                            Text(refusal).textStyle(.body, tint: Theme.loss).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("register-refusal")
                        }
                    } else {
                        EmptyState(title: "This business cannot be priced here.", message: "Choose something else.")
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StartBar {
                    PrimaryAction(title: "Open the company", blockedReason: blocked(facts), identifier: "start-open") { open(e) }
                    QuietButton(title: "Choose something else", fullWidth: true) { dismiss() }
                }
            }
            .appScreen(title: facts?.name ?? "Open a company", subtitle: "Check it before you open", tab: .company)
            .task(id: cityID) {
                rentIndex = nil
                buying = false
                estimate = nil
                facts = e.startFacts(tradeID: tradeID, cityID: cityID)
                estimate = await estimator.estimate(e, tradeID: tradeID, cityID: cityID)
            }
        }
    }

    private func blocked(_ f: StartFacts?) -> String? {
        guard let f else { return "This business cannot be priced here." }
        return f.shortfall > 0 ? "You are \(store.money(f.shortfall)) short of what this needs." : nil
    }

    // MARK: Setup

    private func setup(_ e: GameEngine, _ f: StartFacts) -> some View {
        let cities: [Country.City] = e.homeCountry.cities
        return CardSection("The setup") {
            HStack {
                Text("Name").textStyle(.caption)
                Spacer(minLength: Theme.Space.m)
                TextField(f.name, text: $name).textFieldStyle(.plain).multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("start-company-name")
            }
            CardLine()
            HStack {
                Text("City").textStyle(.caption)
                Spacer(minLength: Theme.Space.m)
                Menu {
                    ForEach(cities) { (c: Country.City) in Button(c.name) { cityID = c.id } }
                } label: {
                    HStack(spacing: 4) {
                        Text(f.cityName).textStyle(.body, tint: Theme.accent, weight: .medium)
                        LedgerGlyph(glyph: Glyph.chevronDown, size: 12, tint: Theme.accent)
                    }
                }
            }
            CardLine()
            row("Size", "\(String(format: "%.1f", f.size)) · team of \(f.staffCount)")
            CardLine()
            row("Opening cost", store.money(f.startCost))
        }
    }

    // MARK: Premises

    private func premisesPlan(_ e: GameEngine, _ f: StartFacts) -> NewCompanyPlan? {
        e.newCompanyPlan(tradeID: f.tradeID, cityID: f.cityID, size: f.size, withAlternatives: false)
    }

    /// The place picked, or nil for the standard rented one.
    private func currentPick(_ plan: NewCompanyPlan?) -> NewCompanyPlan.Pick? {
        guard let plan, plan.premisesKind == .place else { return nil }
        let chosen: Int = rentIndex ?? plan.standardIndex
        let canBuy: Bool = plan.options.first { (o: NewCompanyPlan.PremisesOption) -> Bool in o.index == chosen }?.canBuy ?? false
        let buy: Bool = buying && canBuy
        if rentIndex == nil && !buy { return nil }
        return NewCompanyPlan.Pick(listingIndex: chosen, buy: buy)
    }

    // MARK: If you open it

    private func ifYouOpen(_ f: StartFacts) -> some View {
        let weeks: Int = f.runwayWeeks ?? 0
        let year: Double = 52
        return CardSection("If you open it") {
            row("You pay now", store.money(f.payNow))
            CardLine()
            row("Cash left with you", store.money(f.cashLeft))
            CardLine()
            row("Weekly costs before sales", store.money(f.weeklyCosts))
            CardLine()
            if let est = estimate {
                row("Usual payback", StartText.payback(est))
                CardLine()
                row("If you close, you get back about", store.money(est.closeReturn))
            } else {
                row("Usual payback", "working it out")
                CardLine()
                row("If you close, you get back about", "working it out")
            }
            CardLine()
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ProgressLine(fraction: Double(weeks) / year, tint: Theme.accent,
                             label: "Cash lasts with zero sales", value: f.runwayWeeks.map { "\($0) weeks" } ?? "no fixed costs")
                Text("The bar is one year.").textStyle(.caption, tint: Theme.inkFaint)
            }
            Text("Most \(f.name.lowercased()) businesses lose money for the first weeks. Some never pay back.")
                .textStyle(.caption, tint: Theme.warn).fixedSize(horizontal: false, vertical: true)
            if let est = estimate {
                Text(est.riskLine).textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(label).textStyle(.caption)
            Spacer(minLength: Theme.Space.m)
            Text(value).textStyle(.body, numeric: true).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Open

    private func open(_ e: GameEngine) {
        guard let f = facts else { return }
        let cost: Double? = e.startableRows(cityID: f.cityID).first { $0.tradeID == f.tradeID }?.startUpCost
        let unlocked: Bool = TradeAccess.isUnlocked(tradeID: f.tradeID, startUpCost: cost, medianWage: e.homeCountry.medianMonthlyWage, entitlements: ent.effective, now: Date())
        if !unlocked { ent.run(.tradeAboveCostLine, "Open a " + f.name.lowercased()) {}; return }
        let choices: SetupChoices = e.suggestedChoices(tradeID: f.tradeID, cityID: f.cityID, size: f.size)
        let typed: String = name.trimmingCharacters(in: .whitespaces)
        let pick: NewCompanyPlan.Pick? = currentPick(premisesPlan(e, f))
        let r = store.act { $0.startCompanyChoosingPremises(tradeID: f.tradeID, cityID: f.cityID, size: f.size, name: typed.isEmpty ? nil : typed, pick: pick, fundWith: f.invest, choices: choices, accountantID: nil) }
        switch r {
        case .success(let out)?:
            Haptics.success()
            PlayerHistory.noteStarted()
            var text = "Registered. Set it up, then open for business."
            var tone = "good"
            if out.premises == .notEnoughCash { text = "Registered, but the company could not pay for the place. Choose premises in AirStay."; tone = "warn" }
            else if !out.skipped.isEmpty { text = "Registered. Left for you to decide: " + out.skipped.map { $0.title }.prefix(3).joined(separator: ", ") + (out.skipped.count > 3 ? " and more." : "."); tone = "warn" }
            else if !out.setupNotes.isEmpty { text = "Registered. Some set-up is left (usually cash): see the checklist in the company."; tone = "warn" }
            store.show(text, tone: tone)
            store.openCompany(out.companyID, section: .setup)
        case .failure(.banned(let why))?: Haptics.failure(); refusal = why
        case .failure(.notYetAvailable)?: Haptics.warning(); refusal = "This kind of business is coming in a later update."
        case .failure(.notEnoughCash)?: Haptics.warning(); refusal = "Not enough cash for the registration costs."
        case .failure(.notAllowedHere)?: Haptics.warning(); refusal = "This company can't be started here."
        case nil: refusal = "Nothing happened: the game is not ready. Try again."
        }
    }
}
