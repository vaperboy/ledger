import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Events
import Simulation

struct VenturesSoftwareSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var type = SoftwareProducts.types.first?.id ?? ""
    @State private var model = "sub"
    @State private var pending: PendingAction?

    var body: some View {
        let builders = engine.state.companies.filter { SoftwareProducts.canBuild($0) || (engine.softwareProduct(companyID: $0.id) != nil && $0.status.isLive) }
        return Group {
            if !builders.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Software").capsLabel(Theme.inkFaint)
                    ForEach(builders) { co in
                        if let p = engine.softwareProduct(companyID: co.id) { product(co, p) } else { start(co) }
                    }
                }
            }
        }
        .confirmAction($pending)
    }

    private func start(_ co: Company) -> some View {
        let cur = engine.currency(for: co)
        let coder = cur.scaledPrice(65000) / 12
        return CardSection(title: co.name, trailing: { Text("no product yet").textStyle(.caption, tint: Theme.inkFaint) }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Picker("Kind", selection: $type) { ForEach(SoftwareProducts.types, id: \.id) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                Picker("Customers pay", selection: $model) { ForEach(SoftwareProducts.models, id: \.id) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                Text("List price \(cur.tidyShort(SoftwareProducts.listPrice(model, scale: cur.scaledPrice)))\(model == "once" ? " once" : " a year") · one coder at about \(cur.tidyShort(coder)) a month, paid by \(co.name). A test version comes at half way; your companies can try it from the equipment shop.")
                    .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                Button("Start building") {
                    let name = SoftwareProducts.types.first { $0.id == type }?.name ?? type
                    pending = PendingAction(title: "Build \(name) software in \(co.name)?", message: "It starts with one coder at about \(cur.tidyShort(coder)) a month from your account, until you change the team. Nothing sells until it is published.", button: "Start", amount: coder, currency: cur, tone: .investment, icon: "chevron.left.forwardslash.chevron.right") {
                        let ok = store.act { $0.startSoftware(companyID: co.id, type: type, model: model) } ?? false
                        store.show(ok ? "\(co.name) has started building it." : "\(co.name) cannot start a product now (it must be open).", tone: ok ? "good" : "warn")
                    }
                }.buttonStyle(SecondaryButtonStyle(size: .compact))
            }
        }
    }

    private func product(_ co: Company, _ p: SoftwareProducts.Product) -> some View {
        let cur = engine.currency(for: co)
        let coder = cur.scaledPrice(65000) / 12
        let phase = p.phase == .live ? "On sale" : p.phase == .beta ? "Test version" : "Being built"
        return CardSection(title: p.name, trailing: { Text(co.name).textStyle(.caption, tint: Theme.inkFaint) }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                FigureCard(items: [
                    .init(label: "Stage", value: phase, sub: p.phase == .live ? "" : "\(Int(saturating: (p.progress * 100).rounded()))% done"),
                    .init(label: "Customers", value: "\(p.customers)"),
                    .init(label: "Sales", value: cur.tidyShort(p.weeklyRevenue), sub: "last week"),
                    .init(label: "Team", value: "\(p.coders) coder\(p.coders == 1 ? "" : "s")", sub: "\(cur.tidyShort(Double(p.coders) * coder)) a month"),
                    .init(label: "Price", value: cur.tidyShort(p.price), sub: p.modelName),
                    .init(label: "Your companies pay", value: "\(p.internalPercent)%", sub: "of list price"),
                ])
                WrapRow(spacing: Theme.Space.s) {
                    Button("− coder") { store.settle(store.act { $0.setSoftwareCoders(companyID: co.id, coders: p.coders - 1) }, "Team: \(max(0, p.coders - 1)) coders.") }.buttonStyle(SecondaryButtonStyle(size: .compact)).disabled(p.coders == 0)
                    Button("+ coder") { store.settle(store.act { $0.setSoftwareCoders(companyID: co.id, coders: p.coders + 1) }, "Team: \(min(10, p.coders + 1)) coders, about \(cur.tidyShort(coder)) a month more.") }.buttonStyle(SecondaryButtonStyle(size: .compact)).disabled(p.coders >= 10)
                    Button(p.selfHours > 0 ? "Stop coding" : "Code yourself") {
                        store.act { $0.setSoftwareSelfCoding(companyID: co.id, on: p.selfHours == 0) }
                        store.show(p.selfHours > 0 ? "You stopped coding on it." : "You code 20 hours a week on it.", tone: "n")
                    }.buttonStyle(SecondaryButtonStyle(size: .compact))
                }
                if engine.canRaiseFunding(companyID: co.id) {
                    let wait = engine.weeksUntilNextPitch(companyID: co.id)
                    let ask = engine.suggestedFundingAmount(companyID: co.id)
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text("Raise money for \(co.name)").textStyle(.body)
                            Text(wait > 0 ? "Pitch again in \(wait.weeksText)." : "Investors: \(engine.investorInterest(companyID: co.id).word). Asks for about \(cur.tidyShort(ask)) for new shares.")
                                .textStyle(.caption, tint: wait > 0 ? Theme.warn : Theme.inkFaint)
                        }
                        Spacer(minLength: 8)
                        Button("Pitch") {
                            switch store.act({ $0.pitchToInvestors(companyID: co.id, amount: ask) }) {
                            case .offers(let n)?: Haptics.success(); store.show("\(n) investor\(n == 1 ? "" : "s") made an offer: the offers wait with the company.", tone: "good")
                            case .none?: store.show("No investor bit this time.", tone: "warn")
                            case .tooSoon(let w)?: store.show("Too soon to pitch again: \(w.weeksText) to go.", tone: "n")
                            default: store.show("Only a limited company can raise money from investors.", tone: "warn")
                            }
                        }.buttonStyle(SecondaryButtonStyle(size: .compact)).disabled(wait > 0)
                    }
                }
                HStack {
                    Text("Customers pay").textStyle(.caption)
                    Spacer()
                    Menu(p.modelName) {
                        ForEach(SoftwareProducts.models, id: \.id) { m in
                            Button(m.name) { store.settle(store.act { $0.setSoftwareModel(companyID: co.id, model: m.id) }, "Customers now pay: \(m.name.lowercased()).", same: "Customers already pay that way.") }
                        }
                    }.textStyle(.body, tint: Theme.accent, weight: .medium)
                }
                HStack(spacing: Theme.Space.m) {
                    Text("Your companies pay").textStyle(.caption)
                    Spacer(minLength: Theme.Space.s)
                    SegmentedPill(items: [0, 50, 100], title: { (pct: Int) -> String in "\(pct)%" },
                                  selection: Binding<Int>(get: { p.internalPercent }, set: { (pct: Int) in
                                      store.act { $0.setSoftwareInternalPercent(companyID: co.id, percent: pct) }
                                      store.saved("\(pct)% of the product's capacity goes to your own companies.")
                                  }))
                        .frame(maxWidth: 200)
                }
            }
        }
    }
}
