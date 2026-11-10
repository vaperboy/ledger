import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

@MainActor func registerNewCompany(_ store: GameStore, engine e: GameEngine, draft d: NewCompanyDraft) -> String? {
    guard let plan = d.plan(e) else { return "This company can no longer be priced." }
    let size: Double? = d.size(e)
    let fund: Double = plan.intoCompany
    let nm: String? = d.name.isEmpty ? nil : d.name
    let r = store.act { $0.startCompanyChoosingPremises(tradeID: d.tradeID, cityID: d.cityID, size: size, name: nm, pick: d.pick, choices: d.choices) }
    switch r {
    case .success(let out)?:
        Haptics.success()
        PlayerHistory.noteStarted()
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

struct NewCompanySetupView: View {
    @EnvironmentObject var store: GameStore
    var tradeID: String
    var cityID: String
    @State private var name = ""
    @State private var channel: SalesChannel = .consumers
    @State private var goReview = false

    private func draft(_ t: Trade, _ e: GameEngine) -> NewCompanyDraft {
        var d = NewCompanyDraft(tradeID: tradeID, cityID: cityID, name: name.trimmingCharacters(in: .whitespaces), pick: nil, choices: SetupChoices())
        if let s = d.size(e) { d.choices = e.suggestedChoices(tradeID: tradeID, cityID: cityID, size: s) }
        d.choices.channel = channel
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
                    SalesChannelPicker(tradeID: tradeID, channel: $channel)
                    NavigationLink { NewCompanyDetailedSetupView(tradeID: tradeID, cityID: cityID) } label: {
                        LedgerRow(leading: .glyph(Glyph.settings), title: "Customise", subtitle: "City, premises and each item", chevron: true)
                    }
                    .buttonStyle(AcctPressStyle()).accessibilityIdentifier("new-company-detail")
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissable()
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

    private func startBar(_ plan: NewCompanyPlan?) -> some View {
        let reason: String? = plan == nil ? "This company can no longer be priced."
            : ((plan?.registrationShortfall ?? 0) > 0 ? "Needs \(store.money(plan?.registrationShortfall ?? 0)) more cash." : nil)
        return NewCompanyStepBar(title: "Review · \(store.money(plan?.payToday ?? 0))", blockedReason: reason, identifier: "new-company-start") { goReview = true }
    }
}

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
    var payToday: Double { intoCompany + estimate.shareCapital + estimate.registration + estimate.abroad }
}
