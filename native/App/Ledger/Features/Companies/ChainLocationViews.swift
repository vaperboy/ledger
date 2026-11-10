import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

enum ChainWords {
    static func ownerText(_ e: GameEngine, companyID: Int, showFull: Bool = false) -> String {
        let o: OwnerLine = e.ownerLine(companyID: companyID)
        if let hid = o.holdingID, let hp = o.holdingPercent {
            return "Held by " + (e.state.company(hid)?.name ?? "a holding") + " " + StructureWords.percent(hp)
        }
        if o.youPercent >= 99.5 && !showFull { return "Owned by you" }
        return "Owned by you " + StructureWords.percent(o.youPercent)
    }

    static func lowered(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }

    static func runnerName(_ gm: GroupManagement?, companyID: Int) -> String {
        guard let line = gm?.lines.first(where: { (l: GroupManagement.Line) -> Bool in l.id == companyID }) else { return "you" }
        return line.runner?.name ?? line.above.first?.name ?? "you"
    }

    static func place(_ s: Chains.StoreLine, brand: String) -> String {
        let prefix: String = brand + " "
        if s.name.hasPrefix(prefix) && s.name.count > prefix.count { return String(s.name.dropFirst(prefix.count)) }
        return s.cityName.isEmpty ? s.name : s.cityName
    }
}

struct ChainHeadOffice: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var chainID: Int

    var body: some View {
        if let h = engine.chainHeadOffice(chainID: chainID) {
            let nodes: [StructureNode] = store.memo("structureTree") { (e: GameEngine) -> [StructureNode] in e.structureTree() } ?? []
            let health: StructureNode.Health? = nodes.first(where: { (n: StructureNode) -> Bool in n.id == "chain:\(chainID)" })?.health
            let head: Chains.StoreLine? = engine.chainSummary(id: chainID)?.stores.first
            MoreBlock(title: h.title, card: true, trailing: { headPill(health) }) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if let head {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(ChainWords.ownerText(engine, companyID: head.id)).textStyle(.body, weight: .medium)
                                .accessibilityIdentifier("chain-owner-line")
                            Text("Head-office store: \(head.name)").textStyle(.caption, tint: Theme.inkFaint)
                        }
                    }
                    RateBar(label: "Value of the name", fraction: h.brandScore / 100, word: BrandWords.label(score: h.brandScore))
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        line("CEO", h.ceoName ?? "None yet")
                        line("Chain manager", h.chainManagerName ?? "None yet")
                        line("Locations", "\(h.locations) in \(h.cities) \(h.cities == 1 ? "city" : "cities")")
                    }
                    ForEach(h.services) { sv in
                        HStack(alignment: .top, spacing: Theme.Space.s) {
                            Image(systemName: sv.active ? "checkmark.circle.fill" : "circle").foregroundStyle(sv.active ? Theme.ink : Theme.inkFaint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(sv.title).textStyle(.body, tint: Theme.ink, weight: .medium)
                                Text(sv.detail).textStyle(.caption, tint: Theme.inkFaint)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func headPill(_ health: StructureNode.Health?) -> some View {
        if let health { StructureHealthPill(health: health) }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).textStyle(.caption, tint: Theme.inkFaint)
            Spacer()
            Text(value).textStyle(.caption, tint: Theme.ink)
        }
    }
}

struct ChainLocationCard: View {
    var line: Chains.StoreLine
    var place: String
    var tradeID: String
    var isHead: Bool
    var health: StructureNode.Health?
    var action: StructureNode.Action
    var runnerName: String?
    var runnerRole: String?
    var runnerFace: String?
    var profitText: String
    var revenueText: String
    var canLeave: Bool
    var rulesOpen: Bool
    var onRules: () -> Void
    var onSell: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                ThumbnailView(kind: .trade, key: tradeID, size: 40, glyph: Glyph.home)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack(spacing: Theme.Space.s) {
                        Text(place).textStyle(.headline).lineLimit(1)
                        if isHead { AcctPill(text: "Head office", tone: .neutral) }
                    }
                    Text(detail).textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s)
                if let health { StructureHealthPill(health: health) }
            }
            HStack(alignment: .center, spacing: Theme.Space.s) {
                runner
                Spacer(minLength: Theme.Space.s)
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    Text(profitText + " a month").textStyle(.body, tint: line.profit < 0 ? Theme.loss : Theme.ink, numeric: true, weight: .medium)
                    Text(revenueText + " revenue").textStyle(.caption, tint: Theme.inkFaint, numeric: true)
                }
            }
            HStack(spacing: Theme.Space.s) {
                actionLink
                Spacer(minLength: Theme.Space.s)
                moreMenu
            }
        }
    }

    private var detail: String {
        let status: String = line.status == .setup ? "setting up" : line.staff.peopleText
        let rules: String = line.ownRules > 0 ? " \u{00B7} own rules" : ""
        return line.cityName.isEmpty ? status + rules : line.cityName + " \u{00B7} " + status + rules
    }

    @ViewBuilder private var runner: some View {
        if let name = runnerName {
            HStack(spacing: Theme.Space.s) {
                StructureAvatar(name: name, role: runnerRole, face: runnerFace, size: 28)
                Text(name).textStyle(.caption).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: Theme.Space.s) {
                LedgerGlyph(glyph: Glyph.person, size: Theme.Icon.small, tint: Theme.inkFaint)
                Text("You run it").textStyle(.caption)
            }
        }
    }

    private var route: CompanyRoute {
        if case .appointManager = action { return CompanyRoute.companyAt(line.id, .staff) }
        return CompanyRoute.company(line.id)
    }

    private var actionTint: Color {
        if case .fix = action { return Theme.loss }
        return Theme.accent
    }

    private var actionLink: some View {
        let title: String = StructureWords.actionTitle(action)
        return NavigationLink(value: route) {
            Text(title).textStyle(.caption, tint: actionTint, weight: .semibold)
                .lineLimit(2).multilineTextAlignment(.leading)
                .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                .frame(minHeight: 36)
                .background(Capsule().fill(actionTint.opacity(0.14)))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title + ", " + line.name)
        .accessibilityIdentifier("chain-location-\(line.id)")
    }

    private var moreMenu: some View {
        Menu {
            Button(rulesOpen ? "Hide this store's own rules" : "This store's own rules") { onRules() }
            if canLeave {
                Button("Sell as a going concern\u{2026}") { onSell() }
                Button("Close this branch\u{2026}", role: .destructive) { onClose() }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More for " + line.name)
        .accessibilityIdentifier("chain-branch-\(line.id)")
    }
}

struct ChainAddLocation: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var summary: Chains.Summary
    var currency: Currency
    @State private var newCity = ""
    @State private var pending: PendingAction?

    var body: some View {
        let cities = engine.state.company(summary.stores.first?.id ?? 0).flatMap { engine.data.countries[$0.countryCode] }?.cities ?? []
        let cityID = newCity.isEmpty ? (cities.first?.id ?? "") : newCity
        let quote = engine.locationQuote(chainID: summary.id, cityID: cityID)
        MoreBlock("Add a location") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Picker("City", selection: Binding(get: { cityID }, set: { newCity = $0 })) {
                    ForEach(cities) { c in
                        let n = summary.stores.filter { $0.cityName == c.name }.count
                        Text(c.name + (n > 0 ? " \u{00B7} \(n) \(n == 1 ? "location" : "locations")" : "")).tag(c.id)
                    }
                }.pickerStyle(.menu)
                if let q = quote {
                    Text(q.name).textStyle(.body, tint: Theme.ink, weight: .medium)
                    FigureStrip(items: [
                        .init(label: "Fit-out and equipment", value: currency.tidyShort(q.fitOut)),
                        .init(label: "Rent a month", value: currency.tidyShort(q.monthlyRent)),
                        .init(label: "Deposit", value: currency.tidyShort(q.deposit)),
                        .init(label: "Licences", value: currency.tidyShort(q.licences)),
                        .init(label: "Total now", value: currency.tidyShort(q.total)),
                        .init(label: "You have available", value: store.money(Payments.liquid(engine.state))),
                    ], columns: 2)
                    Text(q.managerFromChain ? "The chain team appoints its manager." : "Without a chain manager or CEO you appoint its manager yourself.")
                        .textStyle(.caption, tint: Theme.inkFaint)
                    QuietButton(title: "Add \(q.name)", fullWidth: true) {
                        pending = PendingAction(title: "Add \(q.name)?",
                                                message: "About \(currency.tidyShort(q.total)) now for the place, equipment, licences and first staff. It takes a few weeks to set up and earns nothing until it opens.",
                                                button: "Add the location", amount: q.total, currency: currency) { open(q) }
                    }
                } else {
                    Text("A location is not possible in that city.").textStyle(.caption, tint: Theme.inkFaint)
                }
            }
        }
        .confirmAction($pending)
    }

    private func open(_ q: ChainLocations.Quote) {
        if let head = summary.stores.first, let pct = ManagerModel.boardGate(engine.state, kind: "open", companyID: head.id) {
            Haptics.warning()
            store.outcome(chosen: "Add \(q.name)", result: "The co-owners voted it down: \(pct)% of the shares were for it. Nothing was opened.")
            return
        }
        switch store.act({ $0.openLocation(chainID: q.chainID, cityID: q.cityID) }) {
        case .success?: Haptics.success(); store.show("\(q.name) is being set up.", tone: "good")
        case .failure(.notEnoughCash)?: Haptics.warning(); store.show("You don't have enough for a new location.", tone: "warn")
        default: Haptics.warning(); store.show("A new location is not possible here.", tone: "warn")
        }
    }
}
