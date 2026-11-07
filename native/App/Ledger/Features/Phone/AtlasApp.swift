import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Atlas Insurance (Phone, blue): the insurance of your companies as an insurer's app. The coverage screen that used to sit under Manage
/// ("Insurance and advisers": policies, insurer, law firm, accountant, security) moves here as it was and stays one tap away; around it the
/// app has a home (premiums, your policies, up-to-date banner, Get a quote), a checkout (insured company, period, what is covered, payment,
/// where the receipt goes) and "Insurance activated" with the policy number the engine recorded when the policy went on.
struct AtlasApp: View {
    private let P = OutsidePalette.atlas
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }

    private enum Step: Equatable { case home, checkout, activated, advisers }

    @State private var step: Step = .home
    @State private var companyID = 0
    @State private var policyID = ""
    @State private var receiptID = 0
    @State private var outcome: InsuranceOutcome?
    @State private var pending: PendingAction?

    var body: some View {
        page
            .confirmAction($pending)
            .outsideScreen(P)
            .swipeBackEnabled(canStep: { step != .home }, step: { back() })
            .safeAreaInset(edge: .top, spacing: 0) { band }
            .onAppear { start() }
            .onChange(of: store.appRequest) { _, _ in take() }
    }

    private var band: some View {
        ShopBand(title: "Atlas", glyph: Glyph.atlas, color: P.accent, onBack: { back() }, backLabel: step == .home ? "Back to Phone" : "Back")
            .environment(\.outsidePalette, P)
    }

    @ViewBuilder private var page: some View {
        if let e = store.engine {
            if let co = current(e) {
                switch step {
                case .home: homeView(e, co)
                case .checkout: checkoutView(e, co)
                case .activated: activatedView(e, co)
                case .advisers: advisersView(co)
                }
            } else {
                EmptyState(glyph: Glyph.atlas, title: "Nothing to insure", message: "Start a company to insure it.")
                    .padding(.horizontal, Theme.Space.page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Color.clear
        }
    }

    private func back() {
        switch step {
        case .home: dismiss()
        case .checkout: step = .home
        case .activated: step = .home
        case .advisers: step = .home
        }
    }

    private func current(_ e: GameEngine) -> Company? {
        if let c = e.state.company(companyID), c.status.isLive { return c }
        return e.state.companies.first { (c: Company) -> Bool in c.status.isLive }
    }

    private func start() {
        if let e = store.engine, let c = current(e) {
            if companyID != c.id { companyID = c.id }
            if receiptID == 0 { receiptID = c.id }
        }
        take()
    }

    private func take() {
        guard let id = store.takeAtlasRequest(), let e = store.engine, let c = e.state.company(id), c.status.isLive else { return }
        companyID = c.id
        receiptID = c.id
        step = .home
    }

    private func money(_ v: Double, _ co: Company) -> String { store.short(v, in: co) }

    // MARK: Home

    private func homeView(_ e: GameEngine, _ co: Company) -> some View {
        let o: CoverageOverview? = e.coverageOverview(companyID: co.id)
        let live: [Company] = e.state.companies.filter { (c: Company) -> Bool in c.status.isLive }
        return ShopPage {
            ShopCompanyMenu(caption: "Insured company", choices: live.map { (c: Company) -> ShopCompanyMenu.Choice in
                ShopCompanyMenu.Choice(id: c.id, name: c.name, detail: e.tradeName(c))
            }, selected: co.id, identifier: "atlas-change", idPrefix: "atlas-company") { (id: Int) in
                companyID = id
                receiptID = id
            }
            .newGroupMarker(.atlas, store.messageItemIDs(.atlas, companyID: co.id), style: .capsule, alignment: .topTrailing)
            if let o {
                coverageHero(co, o)
                policiesSection(e, co, o)
                adviserRow(e, co)
            }
        }
        .accessibilityIdentifier("atlas-home")
    }

    /// How covered the company is (policies in force out of those it can have), what that costs a year, and the one way to add cover.
    private func coverageHero(_ co: Company, _ o: CoverageOverview) -> some View {
        let yearly: Double = o.weeklyPremiums * 52
        let off: Int = o.policies.count - o.activeCount
        let next: InsurancePolicyRow? = o.policies.first { (p: InsurancePolicyRow) -> Bool in !p.isOn }
        let state: String = o.policies.isEmpty ? "No cover on offer" : (off == 0 ? "Fully covered" : "\(o.activeCount) of \(o.policies.count) covered")
        let note: String = off == 0 ? "\(money(yearly, co)) a year, paid weekly from company cash"
            : (o.activeCount == 0 ? "Nothing is insured: every loss comes out of company cash" : "\(money(yearly, co)) a year \u{00B7} uninsured losses come out of company cash")
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            ShopHero(label: "Your cover", value: state, note: note, noteTint: off > 0 ? P.caution : nil, valueTint: off == 0 && !o.policies.isEmpty ? P.gain : nil)
            if !o.policies.isEmpty {
                ProgressLine(fraction: Double(o.activeCount) / Double(max(1, o.policies.count)), tint: off == 0 ? P.gain : P.accent)
            }
            if next != nil {
                PrimaryAction(title: "Get a quote", identifier: "atlas-get-quote") {
                    if let next { quote(next.id) }
                }
                .padding(.top, Theme.Space.xs)
            }
        }
    }

    /// The accountant, one row: who keeps the books and their fee; it opens the advisers page.
    private func adviserRow(_ e: GameEngine, _ co: Company) -> some View {
        let now: AdviserOption? = e.adviserChoices(companyID: co.id, kind: .accountant).first { (a: AdviserOption) -> Bool in a.isCurrent }
        return ShopSection(title: "Advisers") {
            LedgerRow(leading: .glyph(Glyph.atlas), title: "Accountant", subtitle: now?.name ?? "Choose who keeps the books",
                      value: now.map { (a: AdviserOption) -> String in money(a.monthlyFee, co) + "/mo" } ?? "", identifier: "atlas-advisers") {
                step = .advisers
            }
        }
    }

    private func advisersView(_ co: Company) -> some View {
        ShopPage {
            ShopPageTitle(title: "Your accountant", subtitle: "Keeps the books and runs payroll for \(co.name). The fee is paid monthly from company cash.")
            AtlasAccountantSection(companyID: co.id)
        }
    }

    private func policiesSection(_ e: GameEngine, _ co: Company, _ o: CoverageOverview) -> some View {
        let on: [InsurancePolicyRow] = o.policies.filter { (p: InsurancePolicyRow) -> Bool in p.isOn }
        let off: [InsurancePolicyRow] = o.policies.filter { (p: InsurancePolicyRow) -> Bool in !p.isOn }
        return VStack(alignment: .leading, spacing: 28) {
            if !on.isEmpty {
                ShopSection(title: "In force", trailing: "\(on.count)") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(on.enumerated()), id: \.element.id) { (n: Int, p: InsurancePolicyRow) in
                            if n > 0 { Hairline().padding(.leading, 56) }
                            policyRow(e, co, p, isOn: true)
                        }
                    }
                }
            }
            if !off.isEmpty {
                ShopSection(title: "Not covered", trailing: "\(off.count)") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(off.enumerated()), id: \.element.id) { (n: Int, p: InsurancePolicyRow) in
                            if n > 0 { Hairline().padding(.leading, 56) }
                            policyRow(e, co, p, isOn: false)
                        }
                    }
                }
            }
        }
    }

    /// The product's card picture from the items sheet (clipped, rounded); the shield icon stays while the product has no picture.
    @ViewBuilder private func policyIcon(_ p: InsurancePolicyRow, size: CGFloat, glyphSize: CGFloat, tint: Color) -> some View {
        let key: String = ArtLibrary.itemKey(group: "insurance", familyKey: p.id, seed: p.id) ?? ""
        #if canImport(UIKit)
        if let ui = ArtLibrary.image(.items, key) {
            Image(uiImage: ui).resizable().scaledToFill().frame(width: size, height: size).clipped()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)).accessibilityHidden(true)
        } else {
            LedgerGlyph(glyph: Glyph.opsShield, size: glyphSize, tint: tint)
                .frame(width: size, height: size).background(Circle().fill(tint.opacity(0.12)))
        }
        #else
        LedgerGlyph(glyph: Glyph.opsShield, size: glyphSize, tint: tint)
            .frame(width: size, height: size).background(Circle().fill(tint.opacity(0.12)))
        #endif
    }

    private func policyRow(_ e: GameEngine, _ co: Company, _ p: InsurancePolicyRow, isOn: Bool) -> some View {
        let number: String = e.policyRecord(companyID: co.id, product: p.id)?.number ?? ""
        let sub: String = isOn ? (number.isEmpty ? "In force" : "In force \u{00B7} " + number) : "Not covered"
        let content = HStack(spacing: Theme.Space.m) {
            policyIcon(p, size: 44, glyphSize: Theme.Icon.medium, tint: isOn ? P.gain : P.accent)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(p.name).textStyle(.headline).multilineTextAlignment(.leading)
                Text(sub).textStyle(.caption, tint: isOn ? P.gain : P.inkFaint).multilineTextAlignment(.leading)
            }
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: 0) {
                Text(money(p.weeklyPremium * 52, co) + "/yr").textStyle(.headline, numeric: true).lineLimit(1)
                if isOn {
                    Button("Cancel") { askToCancel(co, p) }
                        .buttonStyle(TertiaryButtonStyle(size: .compact, tint: P.loss))
                        .padding(.trailing, -Theme.Space.s)
                        .accessibilityIdentifier("atlas-cancel-\(p.id)")
                }
            }
            if !isOn { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkDim) }
        }
        .padding(.vertical, Theme.Space.s)
        .contentShape(Rectangle())
        return Group {
            if isOn {
                content
            } else {
                Button {
                    Haptics.tap()
                    quote(p.id)
                } label: { content }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("atlas-policy-\(p.id)")
            }
        }
    }

    /// Cancels a policy that is in force. It is not linked to a company tab: it is done here, in the app.
    private func askToCancel(_ co: Company, _ p: InsurancePolicyRow) {
        let id: Int = co.id
        let name: String = p.name
        let saving: String = store.short(p.weeklyPremium * 52 / 12, in: co)
        pending = PendingAction(title: "Cancel \(name)?", message: "You save about \(saving) a month, but losses of this kind are no longer covered and come out of company cash.",
                                button: "Cancel policy", destructive: false, tone: .warning, icon: "shield.slash") {
            switch store.act({ $0.toggleInsurancePolicy(companyID: id, product: p.id) }) {
            case .done?: Haptics.success(); store.show("\(name) cancelled.", tone: "n")
            default: Haptics.warning(); store.show("That policy could not be cancelled.", tone: "warn")
            }
        }
    }

    private func quote(_ id: String) {
        policyID = id
        if receiptID == 0 { receiptID = companyID }
        step = .checkout
    }

    // MARK: Checkout

    private func checkoutView(_ e: GameEngine, _ co: Company) -> some View {
        guard let o = e.coverageOverview(companyID: co.id), let p = o.policies.first(where: { (x: InsurancePolicyRow) -> Bool in x.id == policyID }) else {
            return AnyView(ShopEmptyNote(text: "This cover is not on offer.", glyph: Glyph.opsShield, buttonTitle: "Back to My Insurance") { step = .home }
                .padding(Theme.Space.page).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        }
        let cur: Currency = e.currency(for: co)
        let companies: [Company] = e.state.companies.filter { (c: Company) -> Bool in c.status.isLive }
        return AnyView(ShopPage {
            policyHeader(co, p)
            includesSection(co, o, p, cur)
            ShopSection(title: "Policy") {
                ShopFacts(facts: [
                    (label: "Starts", value: GameCalendar.dateString(week: e.state.week, dayOffset: e.state.day)),
                    (label: "Runs", value: "Until you switch it off"),
                    (label: "Paid weekly", value: cur.tidyShort(p.weeklyPremium)),
                    (label: "Paid from", value: "\(co.name), balance \(money(co.cash, co))")
                ])
            }
            .accessibilityIdentifier("atlas-account")
            ShopReceiptPicker(companies: companies, selection: $receiptID, idPrefix: "atlas")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ShopBottomAction {
                PrimaryAction(title: "Confirm purchase", identifier: "atlas-confirm") { askToBuy(e, co, p, cur) }
            }
            .environment(\.outsidePalette, P)
        })
    }

    private func policyHeader(_ co: Company, _ p: InsurancePolicyRow) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            policyIcon(p, size: 56, glyphSize: Theme.Icon.large, tint: P.accent)
            ShopHero(label: p.name, value: money(p.weeklyPremium * 52, co) + " a year", note: "Your quote for \(co.name)")
        }
    }

    private func includesSection(_ co: Company, _ o: CoverageOverview, _ p: InsurancePolicyRow, _ cur: Currency) -> some View {
        ShopSection(title: "What is covered") {
            includeLine(p.blurb.tidyMoney)
            includeLine("A covered loss is paid after a deductible of about \(cur.tidyShort(cur.scaledPrice(10000))).")
            includeLine("Insurer: Atlas Insurance")
        }
    }

    private func includeLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            LedgerGlyph(glyph: Glyph.check, size: Theme.Icon.small, tint: P.gain).padding(.top, Theme.Space.xxs)
            Text(text).textStyle(.body).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func askToBuy(_ e: GameEngine, _ co: Company, _ p: InsurancePolicyRow, _ cur: Currency) {
        let id: Int = co.id
        let rid: Int = receiptID
        let product: String = p.id
        let yearly: Double = p.weeklyPremium * 52
        let message: String = "About \(cur.tidyShort(yearly)) a year, paid every week (\(cur.tidyShort(p.weeklyPremium)) a week) from \(co.name)'s account, starting now, until you switch it off."
        pending = PendingAction(title: "Buy \(p.name)?", message: message.tidyMoney, button: "Buy cover", amount: yearly, currency: cur, tone: .info, icon: "checkmark.shield") {
            let r: InsuranceOutcome? = store.act { $0.buyInsurance(companyID: id, product: product, receiptCompanyID: rid) }
            if let r, r.result == .done {
                Haptics.success()
                outcome = r
                step = .activated
            } else if r?.result == .needInsurer {
                Haptics.warning()
                store.show("Choose an insurer first.", tone: "warn")
            } else {
                Haptics.warning()
                store.show("That cover could not be bought.", tone: "warn")
            }
        }
    }

    // MARK: Insurance activated

    private func activatedView(_ e: GameEngine, _ co: Company) -> some View {
        let r: InsuranceOutcome? = outcome
        let policy: String = e.coverageOverview(companyID: co.id)?.policies.first(where: { (x: InsurancePolicyRow) -> Bool in x.id == policyID })?.name ?? "The policy"
        let facts: [(label: String, value: String)] = [
            (label: "Policy number", value: r?.number ?? ""),
            (label: "Coverage period", value: (r?.startText ?? "") + ", until switched off"),
            (label: "Insured company", value: co.name),
            (label: "Receipt filed with", value: e.state.company(receiptID)?.name ?? co.name)
        ]
        return ShopSuccess(title: "Insurance active", message: "\(policy) is now active for \(co.name).", facts: facts,
                           primary: "Go to My Insurance", secondary: "Back to Phone",
                           onPrimary: { step = .home }, onSecondary: { dismiss() })
    }
}
