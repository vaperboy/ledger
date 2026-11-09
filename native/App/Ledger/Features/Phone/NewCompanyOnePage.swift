import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Registers the company the draft describes (the engine pays the mandatory set-up, skips what the cash cannot carry), tells the player and
/// opens the company. Returns the refusal text, or nil when the company was registered. Shared by the one-page start and the review step.
@MainActor func registerNewCompany(_ store: GameStore, engine e: GameEngine, draft d: NewCompanyDraft) -> String? {
    guard let plan = d.plan(e) else { return "This company can no longer be priced." }
    let size: Double? = d.size(e)
    let fund: Double = plan.intoCompany
    let nm: String? = d.name.isEmpty ? nil : d.name
    let r = store.act { $0.startCompanyChoosingPremises(tradeID: d.tradeID, cityID: d.cityID, form: d.form, size: size, name: nm, pick: d.pick, fundWith: fund, choices: d.choices, accountantID: d.accountantID) }
    switch r {
    case .success(let out)?:
        Haptics.success()
        var text = "Registered. Set it up, then open for business."
        var tone = "good"
        if out.premises == .notEnoughCash { text = "Registered, but the company could not pay for the place you picked. Choose premises in AirStay."; tone = "warn" }
        else if !out.skipped.isEmpty { text = "Registered. Left for you to decide: " + out.skipped.map { $0.title }.prefix(3).joined(separator: ", ") + (out.skipped.count > 3 ? " and more." : "."); tone = "warn" }
        else if !out.setupNotes.isEmpty { text = "Registered. Some set-up is left (usually cash): see the checklist in the company."; tone = "warn" }
        store.show(text, tone: tone)
        store.openCompany(out.companyID, section: .setup)
        return nil
    case .failure(.banned(let why))?:
        Haptics.failure(); return why
    case .failure(.notYetAvailable)?:
        Haptics.warning(); return "This kind of business is coming in a later update."
    case .failure(.notEnoughCash)?:
        Haptics.warning(); return "Not enough cash for the registration costs."
    case .failure(.notAllowedHere)?:
        Haptics.warning(); return "This company can't be started here."
    case nil:
        return "Nothing happened: the game is not ready. Try again."
    }
}

/// New company, step 2 of 3 on one page: a name, the whole start-up cost as one number (premises, tools and papers from the engine's
/// default plan, `pick: nil`) and the accountant. "Customise" opens the detailed set-up; both end in the review,
/// the only place money is paid.
struct NewCompanySetupView: View {
    @EnvironmentObject var store: GameStore
    var tradeID: String
    var cityID: String
    @State private var name = ""
    @State private var accountantID: Int?
    @State private var goReview = false

    private func draft(_ t: Trade, _ e: GameEngine) -> NewCompanyDraft {
        let form: LegalForm = .limited
        var d = NewCompanyDraft(tradeID: tradeID, cityID: cityID, form: form, name: name.trimmingCharacters(in: .whitespaces), pick: nil, choices: SetupChoices())
        d.accountantID = accountantID
        if let s = d.size(e) { d.choices = e.suggestedChoices(tradeID: tradeID, cityID: cityID, form: form, size: s) }
        return d
    }

    var body: some View {
        if let e = store.engine, let t = e.data.catalog[tradeID] {
            let d: NewCompanyDraft = draft(t, e)
            let plan: NewCompanyPlan? = d.plan(e)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    costBlock(plan)
                    LedgerField(placeholder: t.name, text: $name, identifier: "new-company-name", hint: "Company name. Leave it empty and one is chosen for you.")
                    AccountantStep(countryCode: e.state.homeCountryCode, currency: e.homeCurrency, accountantID: $accountantID)
                    NavigationLink { NewCompanyDetailedSetupView(tradeID: tradeID, cityID: cityID) } label: {
                        LedgerRow(leading: .glyph(Glyph.settings), title: "Customise", subtitle: "City, premises and each item", chevron: true)
                    }
                    .buttonStyle(AcctPressStyle()).accessibilityIdentifier("new-company-detail")
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { startBar(plan) }
            .appScreen(title: "Start: \(t.name)", subtitle: "Step 2 of 3 · your company", tab: .company)
            .navigationDestination(isPresented: $goReview) { NewCompanyReviewView(draft: d) }
        } else {
            EmptyState(title: "This trade is not available.").appScreen(title: "Start", tab: .company)
        }
    }

    @ViewBuilder private func costBlock(_ plan: NewCompanyPlan?) -> some View {
        if let plan {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Figure(label: "Start-up cost", value: store.money(plan.payToday), note: "Premises, tools and papers included", size: .display)
                if plan.registrationShortfall > 0 {
                    Text("Needs \(store.money(plan.registrationShortfall)) more cash.").textStyle(.caption, tint: Theme.warn)
                }
            }
        }
    }

    /// Goes to the review: nothing is paid on this step.
    private func startBar(_ plan: NewCompanyPlan?) -> some View {
        let reason: String? = plan == nil ? "This company can no longer be priced."
            : ((plan?.registrationShortfall ?? 0) > 0 ? "Needs \(store.money(plan?.registrationShortfall ?? 0)) more cash in your current account." : nil)
        return NewCompanyStepBar(title: "Review · \(store.money(plan?.payToday ?? 0))", blockedReason: reason, identifier: "new-company-start") { goReview = true }
    }
}

/// The bottom bar of a new-company step: the one primary action, with the reason under it when it is blocked.
struct NewCompanyStepBar: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var blockedReason: String? = nil
    var identifier: String = ""
    var action: () -> Void

    var body: some View {
        PrimaryAction(title: title, blockedReason: blockedReason, identifier: identifier, action: action)
            .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity)
            .background(P.page)
            .overlay(alignment: .top) { Hairline() }
    }
}

extension NewCompanyPlan {
    /// What leaves the personal account today: the money put into the company, share capital, registration and any abroad costs.
    var payToday: Double { intoCompany + estimate.shareCapital + estimate.registration + estimate.abroad }
}
