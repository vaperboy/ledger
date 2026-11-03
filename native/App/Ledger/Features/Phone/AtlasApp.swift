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
    @Environment(\.dismiss) private var dismiss

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
                Text("Start a company to insure it.").font(.system(size: 15)).foregroundStyle(P.inkSoft).frame(maxWidth: .infinity, maxHeight: .infinity)
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
        return ShopScroll {
            VStack(alignment: .leading, spacing: 16) {
                hero
                companyCard(e, co)
                if choosing { companyPicker(e) }
                if let o {
                    coverageCard(co, o)
                    policiesSection(e, co, o)
                    banner(o)
                    homeButtons(e, co, o)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 20)
        }
        .accessibilityIdentifier("atlas-home")
    }

    private var hero: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack(alignment: .bottomLeading) {
            ShopPhoto(name: "airstay-office-3", glyph: Glyph.building, height: 120, cornerRadius: 16)
            shape.fill(LinearGradient(colors: [P.accent.opacity(0.92), P.accent.opacity(0.25)], startPoint: .leading, endPoint: .trailing))
            VStack(alignment: .leading, spacing: 6) {
                Text("Protect what you\u{2019}ve built").font(.system(size: 26, weight: .bold)).foregroundStyle(Color.white)
            }
            .padding(16).frame(maxWidth: 260, alignment: .leading)
        }
        .frame(height: 120)
        .clipShape(shape)
    }

    private func companyCard(_ e: GameEngine, _ co: Company) -> some View {
        Card(padding: 12) {
            HStack(spacing: 12) {
                GlyphView(glyph: Glyph.atlas, size: 22, weight: 1.6, tint: P.accent)
                    .frame(width: 42, height: 42).background(Circle().fill(P.accent.opacity(0.1)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Insured company").font(.system(size: 12)).foregroundStyle(P.inkFaint)
                    Text(co.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(P.ink).lineLimit(1)
                    Text("\(e.tradeName(co)) \u{00B7} \(e.cityName(co))").font(.system(size: 12.5)).foregroundStyle(P.inkFaint).lineLimit(1)
                }
                Spacer(minLength: 8)
                if e.state.companies.filter({ (c: Company) -> Bool in c.status.isLive }).count > 1 {
                    Button(choosing ? "Close" : "Change") { choosing.toggle() }.buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("atlas-change")
                }
            }
        }
    }

    private func companyPicker(_ e: GameEngine) -> some View {
        VStack(spacing: 8) {
            ForEach(e.state.companies.filter { (c: Company) -> Bool in c.status.isLive }, id: \.id) { (c: Company) in
                ShopChoiceRow(title: c.name, subtitle: "\(e.tradeName(c)) \u{00B7} \(e.cityName(c))", selected: c.id == companyID, identifier: "atlas-company-\(c.id)") {
                    companyID = c.id
                    receiptID = c.id
                    choosing = false
                }
            }
        }
    }

    private func coverageCard(_ co: Company, _ o: CoverageOverview) -> some View {
        let yearly: Double = o.weeklyPremiums * 52
        return Card(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What cover costs").font(.system(size: 15, weight: .semibold)).foregroundStyle(P.inkSoft)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(money(yearly, co)).font(.system(size: 32, weight: .bold).monospacedDigit()).foregroundStyle(P.ink)
                    Text("/ year").font(.system(size: 14)).foregroundStyle(P.inkSoft)
                }
                Text("\(o.activeCount) of \(o.policies.count) policies in force \u{00B7} insured with Atlas")
                    .font(.system(size: 13)).foregroundStyle(P.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func policiesSection(_ e: GameEngine, _ co: Company, _ o: CoverageOverview) -> some View {
        let on: [InsurancePolicyRow] = o.policies.filter { (p: InsurancePolicyRow) -> Bool in p.isOn }
        let off: [InsurancePolicyRow] = o.policies.filter { (p: InsurancePolicyRow) -> Bool in !p.isOn }
        return VStack(alignment: .leading, spacing: 12) {
            ShopHeading(text: "Your policies", trailing: on.isEmpty ? "" : "\(on.count)")
            if on.isEmpty { Text("No policy is on yet.").font(.system(size: 14)).foregroundStyle(P.inkSoft) }
            ForEach(on) { (p: InsurancePolicyRow) in policyRow(e, co, p, isOn: true) }
            if !off.isEmpty { ShopHeading(text: "Available cover", trailing: "\(off.count)") }
            ForEach(off) { (p: InsurancePolicyRow) in policyRow(e, co, p, isOn: false) }
        }
    }

    /// The product's card picture from the items sheet (clipped, rounded); the shield icon stays while the product has no picture.
    @ViewBuilder private func policyIcon(_ p: InsurancePolicyRow, size: CGFloat, glyphSize: CGFloat, tint: Color) -> some View {
        let key: String = ArtLibrary.itemKey(group: "insurance", familyKey: p.id, seed: p.id) ?? ""
        #if canImport(UIKit)
        if let ui = ArtLibrary.image(.items, key) {
            Image(uiImage: ui).resizable().scaledToFill().frame(width: size, height: size).clipped()
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)).accessibilityHidden(true)
        } else {
            GlyphView(glyph: Glyph.opsShield, size: glyphSize, weight: 1.6, tint: tint)
                .frame(width: size, height: size).background(Circle().fill(tint.opacity(0.12)))
        }
        #else
        GlyphView(glyph: Glyph.opsShield, size: glyphSize, weight: 1.6, tint: tint)
            .frame(width: size, height: size).background(Circle().fill(tint.opacity(0.12)))
        #endif
    }

    private func policyRow(_ e: GameEngine, _ co: Company, _ p: InsurancePolicyRow, isOn: Bool) -> some View {
        let number: String = e.policyRecord(companyID: co.id, product: p.id)?.number ?? ""
        let sub: String = isOn ? (number.isEmpty ? "In force" : "In force \u{00B7} " + number) : "Not covered"
        let content = Card(padding: 12) {
            HStack(spacing: 12) {
                policyIcon(p, size: 44, glyphSize: 22, tint: isOn ? P.gain : P.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(P.ink).multilineTextAlignment(.leading)
                    Text(sub).font(.system(size: 12.5)).foregroundStyle(isOn ? P.gain : P.inkFaint).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(money(p.weeklyPremium * 52, co) + " / year").font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(P.ink)
                    if isOn {
                        Button("Cancel policy") { askToCancel(co, p) }
                            .buttonStyle(QuietButtonStyle())
                            .accessibilityIdentifier("atlas-cancel-\(p.id)")
                    }
                }
                if !isOn { GlyphView(glyph: Glyph.chevron, size: 14, weight: 1.8, tint: P.inkDim) }
            }
        }
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

    private func banner(_ o: CoverageOverview) -> some View {
        let allOn: Bool = o.activeCount == o.policies.count && !o.policies.isEmpty
        let title: String = (allOn ? "All policies are on" : "\(o.policies.count - o.activeCount) \(o.policies.count - o.activeCount == 1 ? "cover is" : "covers are") not on")
        let note: String = (allOn ? "Premiums are paid every week from the company account." : "Anything uninsured comes out of company cash.")
        let tint: Color = !allOn ? P.caution : P.gain
        return HStack(spacing: 12) {
            GlyphView(glyph: allOn ? Glyph.check : Glyph.warning, size: 22, weight: 1.8, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(P.ink)
                Text(note).font(.system(size: 12.5)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.12)))
    }

    private func homeButtons(_ e: GameEngine, _ co: Company, _ o: CoverageOverview) -> some View {
        let next: InsurancePolicyRow? = o.policies.first { (p: InsurancePolicyRow) -> Bool in !p.isOn }
        return VStack(spacing: 10) {
            Button("Get a quote") {
                if let next { quote(next.id) }
            }
            .buttonStyle(ShopFilledButtonStyle())
            .disabled(next == nil)
            .accessibilityIdentifier("atlas-get-quote")

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
            return AnyView(Text("This cover is not on offer.").font(.system(size: 15)).foregroundStyle(P.inkSoft).frame(maxWidth: .infinity, maxHeight: .infinity))
        }
        let cur: Currency = e.currency(for: co)
        let companies: [Company] = e.state.companies.filter { (c: Company) -> Bool in c.status.isLive }
        return AnyView(ShopScroll {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Checkout").font(.system(size: 24, weight: .bold)).foregroundStyle(P.ink)
                    Text("Review your details and confirm").font(.system(size: 14)).foregroundStyle(P.inkSoft)
                }
                policyCard(co, p)
                periodCard(e)
                includesCard(co, o, p, cur)
                paymentCard(co, companies)
                confirmBlock(e, co, o, p, cur)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 20)
        })
    }

    private func policyCard(_ co: Company, _ p: InsurancePolicyRow) -> some View {
        Card(padding: 14) {
            HStack(spacing: 14) {
                policyIcon(p, size: 58, glyphSize: 30, tint: P.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(P.ink)
                    Text("Annual premium").font(.system(size: 12.5)).foregroundStyle(P.inkFaint)
                    Text(money(p.weeklyPremium * 52, co) + " / year").font(.system(size: 20, weight: .bold).monospacedDigit()).foregroundStyle(P.ink)
                }
            }
        }
    }

    private func periodCard(_ e: GameEngine) -> some View {
        let today: String = GameCalendar.dateString(week: e.state.week, dayOffset: e.state.day)
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Coverage period").font(.system(size: 13, weight: .semibold)).foregroundStyle(P.inkFaint)
                Text("From \(today), until you switch it off").font(.system(size: 15, weight: .medium)).foregroundStyle(P.ink)
                Text("The premium is paid every week.").font(.system(size: 12.5)).foregroundStyle(P.inkFaint)
            }
        }
    }

    private func includesCard(_ co: Company, _ o: CoverageOverview, _ p: InsurancePolicyRow, _ cur: Currency) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Coverage includes").font(.system(size: 13, weight: .semibold)).foregroundStyle(P.inkFaint)
                includeLine(p.blurb.tidyMoney)
                includeLine("A covered loss is paid after a deductible of about \(cur.tidyShort(cur.scaledPrice(10000))).")
                includeLine("Insurer: Atlas Insurance")
            }
        }
    }

    private func includeLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            GlyphView(glyph: Glyph.check, size: 16, weight: 2, tint: P.gain).padding(.top, 2)
            Text(text).font(.system(size: 14)).foregroundStyle(P.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func paymentCard(_ co: Company, _ companies: [Company]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ShopHeading(text: "Payment method")
            ShopChoiceRow(title: "Company account", subtitle: "\(co.name) \u{00B7} balance \(money(co.cash, co)). This account pays.", selected: true, identifier: "atlas-account") { }
            ShopHeading(text: "Receipt goes to")
            ForEach(companies, id: \.id) { (c: Company) in
                ShopChoiceRow(title: c.name, subtitle: "Accounting records", selected: receiptID == c.id, identifier: "atlas-receipt-\(c.id)") { receiptID = c.id }
            }
        }
    }

    private func confirmBlock(_ e: GameEngine, _ co: Company, _ o: CoverageOverview, _ p: InsurancePolicyRow, _ cur: Currency) -> some View {
        VStack(spacing: 8) {
            Button("Confirm purchase") { askToBuy(e, co, p, cur) }
                .buttonStyle(ShopFilledButtonStyle())
                .accessibilityIdentifier("atlas-confirm")
            Text("Your information stays in your company records.").font(.system(size: 12)).foregroundStyle(P.inkFaint).frame(maxWidth: .infinity)
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
        return ShopSuccess(title: "Insurance Activated!", message: "\(policy) is now active for \(co.name).", facts: facts,
                           primary: "Go to My Insurance", secondary: "Back to Phone",
                           onPrimary: { step = .home }, onSecondary: { dismiss() })
    }
}
