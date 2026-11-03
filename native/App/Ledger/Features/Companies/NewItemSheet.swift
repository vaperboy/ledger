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
            Text(isService ? "Add a service" : "Add a product").font(.headline).foregroundStyle(Theme.ivory)
            ForEach(list.options) { (o: NewItemOption) -> AnyView in AnyView(optionRow(o, list.hasMarketAdvisor, cur)) }
            if list.options.isEmpty { Text("Nothing new to add right now.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted) }
            if !list.hasMarketAdvisor { lockedLine }
            ownName
        }
        .confirmAction($pending)
    }

    private func optionRow(_ o: NewItemOption, _ advisor: Bool, _ cur: Currency) -> some View {
        Button { ask(o, cur) } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ivory).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(badge(o, cur)).font(.system(size: 11)).foregroundStyle(o.needsDevelopment ? Theme.gold : Theme.ivoryMuted).lineLimit(2)
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
            Text(label).font(.system(size: 9)).foregroundStyle(Theme.ivoryMuted).lineLimit(1).minimumScaleFactor(0.8)
            Text(text ?? "-").font(.system(size: 12, weight: .semibold))
                .foregroundStyle((value ?? 0) >= 0 ? Theme.gain : Theme.loss).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(minWidth: 62, alignment: .trailing)
    }

    private var lockedLine: some View {
        Button { onHireAdvisor() } label: {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 11))
                Text("Hire a market advisor to see this").font(.system(size: 12))
            }
            .foregroundStyle(Theme.ivoryMuted)
        }
        .buttonStyle(PressableStyle())
    }

    private var ownName: some View {
        HStack(spacing: 8) {
            TextField("Or name your own", text: $own).font(.system(size: 14)).textFieldStyle(.roundedBorder)
            Button { addOwn() } label: { Text("Add").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gold) }
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
            else { Haptics.success(); store.show(dev ? "Started developing \(name)." : "Added \(name).", tone: "good"); onClose() }
        })
    }

    private func addOwn() {
        let id: Int = companyID
        let svc: Bool = isService
        let name: String = own.trimmingCharacters(in: .whitespaces)
        let r = store.act { $0.addSalesItem(companyID: id, name: name, isService: svc) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
        else { Haptics.success(); store.show("Added \(name).", tone: "good"); onClose() }
    }
}
