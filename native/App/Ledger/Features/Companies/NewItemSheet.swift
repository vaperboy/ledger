import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// "Add a product" / "Add a service": the engine's choices as compact rows (name, ready or development time and cost, and, with a market
/// advisor, the profit and market change). A tap asks for confirmation, then adds the item (or starts its development).
struct NewItemSheet: View {
    @EnvironmentObject var store: GameStore
    let companyID: Int
    let isService: Bool
    var onClose: () -> Void
    var onHireAdvisor: () -> Void
    /// Called with the name of an item that went on sale at once (not for a development), so the caller can open its page.
    var onAdded: ((String) -> Void)? = nil
    @State private var pending: PendingAction?
    @State private var own = ""

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            content(e, co)
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted)
        }
    }

    private func content(_ e: GameEngine, _ co: Company) -> some View {
        let cur: Currency = e.currency(for: co)
        let list: NewItemOptionList = e.newItemOptions(companyID: companyID, isService: isService)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(isService ? "Add a service" : "Add a product").popupText(.title)
            ForEach(list.options) { (o: NewItemOption) -> AnyView in AnyView(optionRow(o, list.hasMarketAdvisor, cur)) }
            catalogueRows(e, list)
            if list.options.isEmpty && e.retailAddableItems(companyID: companyID).isEmpty { Text("Nothing new to add right now.").popupText(.subtitle) }
            if !list.hasMarketAdvisor { lockedLine }
            ownName
        }
        .confirmAction($pending)
    }

    private func optionRow(_ o: NewItemOption, _ advisor: Bool, _ cur: Currency) -> some View {
        Button { ask(o, cur) } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.name).popupText(.rowValue).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(badge(o, cur)).popupText(o.needsDevelopment ? .effect : .caption).lineLimit(2)
                }
                Spacer(minLength: 4)
                if advisor {
                    figure("Profit change", o.profitChange, o.profitChange.map { (v: Double) -> String in sign(v) + cur.tidyShort(abs(v)) + "/wk" })
                    figure("Market change", o.marketChange, o.marketChange.map { (v: Double) -> String in String(format: "%+.1f pts", v) })
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func figure(_ label: String, _ value: Double?, _ text: String?) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label).popupText(.caption).lineLimit(1).minimumScaleFactor(0.8)
            Text(text ?? "-").popupText((value ?? 0) >= 0 ? .effect : .risk)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(minWidth: 62, alignment: .trailing)
    }

    private var lockedLine: some View {
        Button { onHireAdvisor() } label: {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 11))
                Text("Hire a market advisor to see this").popupText(.caption)
            }
            .foregroundStyle(Theme.ivoryMuted)
        }
        .buttonStyle(PressableStyle())
    }

    private var ownName: some View {
        HStack(spacing: 8) {
            TextField("Or name your own", text: $own).popupField()
            Button { addOwn() } label: { Text("Add").popupText(.effect) }
                .buttonStyle(PressableStyle())
                .disabled(own.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func badge(_ o: NewItemOption, _ cur: Currency) -> String {
        guard o.needsDevelopment else { return "Ready at once" }
        return "Development: \(o.developmentWeeks) weeks, " + cur.tidyDisplay(o.developmentCost)
    }

    private func sign(_ v: Double) -> String { v >= 0 ? "+" : "-" }

    private func ask(_ o: NewItemOption, _ cur: Currency) {
        let id: Int = companyID
        let oid: String = o.id
        let name: String = o.name
        let dev: Bool = o.needsDevelopment
        pending = PendingAction(title: "Add \(name)?",
                                message: dev ? "Development takes \(o.developmentWeeks) weeks and costs " + cur.tidyDisplay(o.developmentCost) + "." : "It goes on sale at once.",
                                button: "Add", alwaysAsk: true,
                                amount: dev ? o.developmentCost : nil, currency: cur,
                                run: {
            let r = store.act { $0.addNewItem(companyID: id, optionID: oid) }
            if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
            else { Haptics.success(); store.show(dev ? "Started developing \(name)." : "Added \(name).", tone: "good"); onClose(); if !dev { onAdded?(name) } }
        })
    }

    /// Items of the trade's real range this company does not sell yet (shops and garages), added at once.
    @ViewBuilder private func catalogueRows(_ e: GameEngine, _ list: NewItemOptionList) -> some View {
        let taken: Set<String> = Set(list.options.map { (o: NewItemOption) -> String in o.name.lowercased() })
        let extra: [RetailItems.Def] = e.retailAddableItems(companyID: companyID)
            .filter { (d: RetailItems.Def) -> Bool in d.isService == isService && !taken.contains(d.name.lowercased()) }
        ForEach(extra, id: \.id) { (d: RetailItems.Def) in
            Button { askCatalogue(d) } label: {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name).popupText(.rowValue).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text("From the trade's range, ready at once").popupText(.caption).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func askCatalogue(_ d: RetailItems.Def) {
        let id: Int = companyID
        let did: String = d.id
        let name: String = d.name
        pending = PendingAction(title: "Add \(name)?", message: "It goes on sale at once.", button: "Add", alwaysAsk: true, run: {
            let r = store.act { $0.addRetailItem(companyID: id, defID: did) }
            if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
            else { Haptics.success(); store.show("Added \(name).", tone: "good"); onClose(); onAdded?(name) }
        })
    }

    private func addOwn() {
        let id: Int = companyID
        let svc: Bool = isService
        let name: String = own.trimmingCharacters(in: .whitespaces)
        let r = store.act { $0.addSalesItem(companyID: id, name: name, isService: svc) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
        else { Haptics.success(); store.show("Added \(name).", tone: "good"); onClose(); onAdded?(name) }
    }
}
