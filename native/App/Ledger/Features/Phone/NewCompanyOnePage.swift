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
    let r = store.act { $0.startCompanyChoosingPremises(tradeID: d.tradeID, cityID: d.cityID, form: d.form, size: size, name: nm, pick: d.pick, fundWith: fund, choices: d.choices) }
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

/// New company on one page (brief 6.2): the trade (already chosen), a name, the whole start-up cost as one number and `Start`. Premises,
/// tools and papers are bought by the engine's own default plan (`pick: nil`, default `SetupChoices`). The detailed set-up stays behind
/// `Choose each item yourself`.
struct NewCompanySetupView: View {
    @EnvironmentObject var store: GameStore
    var tradeID: String
    var cityID: String
    @State private var name = ""
    @State private var working = false
    @State private var refusal: String?

    private func draft(_ t: Trade) -> NewCompanyDraft {
        let form: LegalForm = t.needsLimitedCompany ? .limited : .soleTrader
        return NewCompanyDraft(tradeID: tradeID, cityID: cityID, form: form, name: name.trimmingCharacters(in: .whitespaces), pick: nil, choices: SetupChoices())
    }

    var body: some View {
        if let e = store.engine, let t = e.data.catalog[tradeID] {
            let d: NewCompanyDraft = draft(t)
            let plan: NewCompanyPlan? = d.plan(e)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    TextField(t.name, text: $name).textFieldStyle(.plain).font(.system(size: 16)).foregroundStyle(Theme.ivory)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                        .accessibilityIdentifier("new-company-name")
                    costBlock(plan)
                    if let refusal { Text(refusal).font(.system(size: 13)).foregroundStyle(Theme.loss).accessibilityIdentifier("register-refusal") }
                    NavigationLink { NewCompanyDetailedSetupView(tradeID: tradeID, cityID: cityID) } label: {
                        Text("Choose each item yourself").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(PressableStyle()).accessibilityIdentifier("new-company-detail")
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { startBar(e, d, plan) }
            .appScreen(title: "Start: \(t.name)", tab: .company)
        } else {
            Text("This trade is not available.").foregroundStyle(Theme.ivoryMuted).appScreen(title: "Start", tab: .company)
        }
    }

    @ViewBuilder private func costBlock(_ plan: NewCompanyPlan?) -> some View {
        if let plan {
            let total: Double = plan.intoCompany + plan.estimate.shareCapital + plan.estimate.registration + plan.estimate.abroad
            VStack(alignment: .leading, spacing: 4) {
                Text("Premises, tools and papers included").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                Text(store.money(total)).font(.serifTitle(34)).foregroundStyle(Theme.ivory).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text("Start-up cost").capsLabel()
                if plan.registrationShortfall > 0 {
                    Text("Needs \(store.money(plan.registrationShortfall)) more cash.").font(.system(size: 12)).foregroundStyle(Theme.caution)
                }
            }
        }
    }

    private func startBar(_ e: GameEngine, _ d: NewCompanyDraft, _ plan: NewCompanyPlan?) -> some View {
        let ok: Bool = plan != nil && (plan?.registrationShortfall ?? 0) <= 0 && !working
        return HStack {
            QuietButton(title: "Start", fullWidth: true) {
                guard ok else { return }
                working = true
                refusal = registerNewCompany(store, engine: e, draft: d)
                working = false
            }
            .opacity(ok ? 1 : 0.4).disabled(!ok).accessibilityIdentifier("new-company-start")
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Theme.page)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}
