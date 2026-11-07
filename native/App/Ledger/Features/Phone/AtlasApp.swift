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

    private enum Step: Equatable { case home, checkout, activated }

    @State private var step: Step = .home
    @State private var companyID = 0
    @State private var choosing = false
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
        ShopBand(title: "Atlas Insurance", glyph: Glyph.atlas, color: P.accent, onBack: { back() }, backLabel: step == .home ? "Back to Phone" : "Back")
            .environment(\.outsidePalette, P)
    }

    @ViewBuilder private var page: some View {
        if let e = store.engine {
            if let co = current(e) {
                switch step {
                case .home: homeView(e, co)
                case .checkout: checkoutView(e, co)
                case .activated: activatedView(e, co)
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
        let live: Int = e.state.companies.filter { (c: Company) -> Bool in c.status.isLive }.count
        return ShopPage {
            hero
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ShopCompanyBar(caption: "Insured company", name: co.name, detail: "\(e.tradeName(co)) \u{00B7} \(e.cityName(co))",
                               canChange: live > 1, open: $choosing, identifier: "atlas-change")
                    .newGroupMarker(.atlas, store.messageItemIDs(.atlas, companyID: co.id), style: .capsule, alignment: .topTrailing)
                if choosing { companyPicker(e) }
            }
            if let o {
                coverageSection(co, o)
                policiesSection(e, co, o)
                AtlasAccountantSection(companyID: co.id)
            }
        }
        .accessibilityIdentifier("atlas-home")
    }

    /// The insurer's welcome: an office photo under the brand colour, and the line it is about.
    private var hero: some View {
        ShopPhoto(name: "airstay-office-3", glyph: Glyph.building, height: 120)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.accent.opacity(0.85)).allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                Text("Protect what you\u{2019}ve built").textStyle(.title).containerInk(P.onAccent)
                    .lineLimit(2).minimumScaleFactor(0.6)
                    .padding(Theme.Space.l)
            }
    }

    private func companyPicker(_ e: GameEngine) -> some View {
        VStack(spacing: Theme.Space.s) {
            ForEach(e.state.companies.filter { (c: Company) -> Bool in c.status.isLive }, id: \.id) { (c: Company) in
                ShopChoiceRow(title: c.name, subtitle: "\(e.tradeName(c)) \u{00B7} \(e.cityName(c))", selected: c.id == companyID, identifier: "atlas-company-\(c.id)") {
                    companyID = c.id
                    receiptID = c.id
                    choosing = false
                }
            }
        }
    }

    /// The yearly cost of cover, whether everything is on, and the one way to add cover.
    private func coverageSection(_ co: Company, _ o: CoverageOverview) -> some View {
        let yearly: Double = o.weeklyPremiums * 52
        let off: Int = o.policies.count - o.activeCount
        let next: InsurancePolicyRow? = o.policies.first { (p: InsurancePolicyRow) -> Bool in !p.isOn }
        let note: String = off == 0 && !o.policies.isEmpty
            ? "All \(o.policies.count) policies are on, paid every week from the company account."
            : "\(o.activeCount) of \(o.policies.count) policies in force \u{00B7} insured with Atlas"
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Figure(label: "What cover costs a year", value: money(yearly, co), note: note, size: .display)
            if off > 0 {
                InlineMessage(text: "\(off) \(off == 1 ? "cover is" : "covers are") not on. Anything uninsured comes out of company cash.", isError: false)
            }
            PrimaryAction(title: "Get a quote", blockedReason: next == nil ? "Every cover is already on." : nil, identifier: "atlas-get-quote") {
                if let next { quote(next.id) }
            }
        }
    }

    private func policiesSection(_ e: GameEngine, _ co: Company, _ o: CoverageOverview) -> some View {
        let on: [InsurancePolicyRow] = o.policies.filter { (p: InsurancePolicyRow) -> Bool in p.isOn }
        let off: [InsurancePolicyRow] = o.policies.filter { (p: InsurancePolicyRow) -> Bool in !p.isOn }
        return VStack(alignment: .leading, spacing: Theme.Space.xl) {
            ShopSection(title: "Your policies", trailing: on.isEmpty ? "" : "\(on.count)") {
                if on.isEmpty { EmptyState(glyph: Glyph.opsShield, title: "No policy is on yet", message: "Choose a cover below.", centered: false) }
                ForEach(Array(on.enumerated()), id: \.element.id) { (n: Int, p: InsurancePolicyRow) in
                    if n > 0 { Hairline() }
                    policyRow(e, co, p, isOn: true)
                }
            }
            if !off.isEmpty {
                ShopSection(title: "Available cover", trailing: "\(off.count)") {
                    ForEach(Array(off.enumerated()), id: \.element.id) { (n: Int, p: InsurancePolicyRow) in
                        if n > 0 { Hairline() }
                        policyRow(e, co, p, isOn: false)
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
            policyIcon(p, size: 40, glyphSize: Theme.Icon.medium, tint: isOn ? P.gain : P.accent)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(p.name).textStyle(.headline).multilineTextAlignment(.leading)
                Text(sub).textStyle(.caption, tint: isOn ? P.gain : P.inkFaint).multilineTextAlignment(.leading)
            }
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                Text(money(p.weeklyPremium * 52, co) + " / year").textStyle(.headline, numeric: true)
                if isOn {
                    Button("Cancel policy") { askToCancel(co, p) }
                        .buttonStyle(TertiaryButtonStyle(size: .compact, tint: P.loss))
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
                                button: "Cancel policy", destructive: true) {
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
            ShopPageTitle(title: "Checkout", subtitle: "Review your details and confirm")
            policyHeader(co, p)
            periodSection(e)
            includesSection(co, o, p, cur)
            ShopSection(title: "Payment method") {
                ShopChoiceRow(title: "Company account", subtitle: "\(co.name) \u{00B7} balance \(money(co.cash, co)). This account pays.", selected: true, identifier: "atlas-account") { }
            }
            ShopReceiptPicker(companies: companies, selection: $receiptID, idPrefix: "atlas")
            VStack(spacing: Theme.Space.xs) {
                PrimaryAction(title: "Confirm purchase", identifier: "atlas-confirm") { askToBuy(e, co, p, cur) }
                Text("Your information stays in your company records.").textStyle(.caption, tint: P.inkFaint).frame(maxWidth: .infinity)
            }
        })
    }

    private func policyHeader(_ co: Company, _ p: InsurancePolicyRow) -> some View {
        HStack(spacing: Theme.Space.m) {
            policyIcon(p, size: 56, glyphSize: Theme.Icon.large, tint: P.accent)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(p.name).textStyle(.headline)
                Figure(label: "", value: money(p.weeklyPremium * 52, co) + " / year", note: "Annual premium")
            }
        }
    }

    private func periodSection(_ e: GameEngine) -> some View {
        let today: String = GameCalendar.dateString(week: e.state.week, dayOffset: e.state.day)
        return ShopSection(title: "Coverage period", note: "The premium is paid every week.") {
            Text("From \(today), until you switch it off").textStyle(.body, weight: .medium)
        }
    }

    private func includesSection(_ co: Company, _ o: CoverageOverview, _ p: InsurancePolicyRow, _ cur: Currency) -> some View {
        ShopSection(title: "Coverage includes") {
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
        pending = PendingAction(title: "Buy \(p.name)?", message: message.tidyMoney, button: "Buy cover", amount: yearly, currency: cur) {
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
