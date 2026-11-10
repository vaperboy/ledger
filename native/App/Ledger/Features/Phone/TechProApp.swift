import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

enum TechCategory: String, CaseIterable, Hashable {
    case software = "Software", services = "Services", hardware = "IT equipment", payment = "Terminals", machines = "Machines", tools = "Tools", vehicles = "Vehicles", office = "Furniture"

    var glyph: String {
        switch self {
        case .software: return Glyph.software
        case .services: return Glyph.team
        case .hardware: return Glyph.hardware
        case .payment: return Glyph.bank
        case .machines: return Glyph.capacity
        case .tools: return Glyph.opsWrench
        case .vehicles: return Glyph.vehicle
        case .office: return Glyph.building
        }
    }

    static func of(_ n: EquipmentMarket.Need) -> TechCategory {
        if n.isVehicle { return .vehicles }
        if n.isSoftware { return .software }
        if n.kind == "svc" { return .services }
        if n.kind == "it" { return .hardware }
        if n.kind == "pos" { return .payment }
        if n.kind == "tool" { return .tools }
        if n.kind == "furn" { return .office }
        return .machines
    }
}

enum TechShelf: Hashable {
    case all, sale, dept(TechCategory)

    var title: String {
        switch self {
        case .all: return "All items"
        case .sale: return "On sale"
        case .dept(let c): return c.rawValue
        }
    }

    static func every(_ present: Set<TechCategory>) -> [TechShelf] {
        let depts: [TechCategory] = TechCategory.allCases.filter { (c: TechCategory) -> Bool in present.contains(c) }
        return [.all, .sale] + depts.map { (c: TechCategory) -> TechShelf in .dept(c) }
    }
}

enum PriceSort: String, CaseIterable, Hashable {
    case needs = "Needed first", low = "Price: low to high", high = "Price: high to low", deal = "Biggest discount", az = "A to Z", life = "Longest life", warranty = "Longest warranty"
}

struct TechProApp: View {
    private let P = OutsidePalette.techPro
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }

    private enum Step: Equatable { case store, category, suppliers, product, basket, checkout, payment, placed, orders, owned }

    @State private var step: Step = .store
    @State private var companyID = 0
    @State private var shelf: TechShelf = .all
    @State private var sort: PriceSort = .needs
    @State private var query = ""
    @State private var itemID = ""
    @State private var offerKey = ""
    @State private var groupFrom: Step = .store
    @State private var basket: [StoreOrders.Line] = []
    @State private var delivery: StoreOrders.Delivery = .standard
    @State private var receiptID = 0
    @State private var holder = ""
    @State private var number = ""
    @State private var remember = false
    @State private var payError = ""
    @State private var placedNumber = ""
    @State private var placedDate = ""
    @State private var placedTotal = ""
    @State private var placedCarrier = ""
    @State private var pending: PendingAction?

    var body: some View {
        page
            .confirmAction($pending)
            .outsideScreen(P)
            .swipeBackEnabled(canStep: { step != .store }, step: { back() })
            .safeAreaInset(edge: .top, spacing: 0) { VStack(spacing: 0) { band; if showsTabs { tabBar } } }
            .onAppear { start() }
            .onChange(of: store.appRequest) { _, _ in take() }
    }

    private var showsTabs: Bool { step == .store || step == .category || step == .owned || step == .orders }

    private var tabBar: some View {
        ShopTabs(items: TpTab.allCases, title: { (t: TpTab) -> String in t.title }, selection: tabSelection,
                 identifier: { (t: TpTab) -> String in "tp-tab-\(t.title)" },
                 badges: { (t: TpTab) -> Bool in t == .orders && !store.messageItemIDs(.techPro, companyID: nil).isEmpty })
            .environment(\.outsidePalette, P)
    }

    private var band: some View {
        ShopBand(title: "TechPro", glyph: Glyph.techPro, color: P.accent, onBack: { back() }, backLabel: step == .store ? "Back to Phone" : "Back") {
            cartButton
        }
        .environment(\.outsidePalette, P)
    }

    @ViewBuilder private var cartButton: some View {
        if step != .placed && step != .payment {
            Button {
                Haptics.tap()
                step = .basket
            } label: {
                LedgerGlyph(glyph: Glyph.cart, size: Theme.Icon.medium, tint: P.ink)
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) { ShopCount(count: basket.count, color: P.accent).offset(x: 2, y: 4) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(basket.isEmpty ? "Basket" : "Basket, \(basket.count) items")
            .accessibilityIdentifier("tp-cart")
        }
    }

    private enum TpTab: Hashable, CaseIterable {
        case store, products, owned, orders
        var title: String {
            switch self {
            case .store: return "Store"
            case .products: return "Products"
            case .owned: return "My items"
            case .orders: return "My orders"
            }
        }
    }

    private var tabSelection: Binding<TpTab> {
        Binding<TpTab>(
            get: {
                switch step {
                case .category: return TpTab.products
                case .owned: return TpTab.owned
                case .orders: return TpTab.orders
                default: return TpTab.store
                }
            },
            set: { (t: TpTab) in
                switch t {
                case .store: step = .store
                case .products: shelf = .all; step = .category
                case .owned: step = .owned
                case .orders: step = .orders
                }
            })
    }

    private func tabsPager(_ e: GameEngine, _ co: Company) -> some View {
        SegmentPager(items: TpTab.allCases, selection: tabSelection) { (t: TpTab) in
            tabPage(e, co, t)
        }
    }

    @ViewBuilder private func tabPage(_ e: GameEngine, _ co: Company, _ t: TpTab) -> some View {
        switch t {
        case .store: storeView(e, co)
        case .products: categoryView(e, co)
        case .owned: TechProOwnedView(companyID: co.id) { (id: String) in showItem(id) }
        case .orders: ordersView(e, co)
        }
    }

    @ViewBuilder private var page: some View {
        if let e = store.engine {
            if let co = current(e) {
                switch step {
                case .store, .category, .owned, .orders: tabsPager(e, co)
                case .suppliers: suppliersView(co)
                case .product: productView(e, co)
                case .basket: basketView(e, co)
                case .checkout: checkoutView(e, co)
                case .payment: paymentView(e, co)
                case .placed: placedView(e, co)
                }
            } else {
                emptyView
            }
        } else {
            Color.clear
        }
    }

    private var emptyView: some View {
        EmptyState(glyph: Glyph.techPro, title: "Nothing to buy for", message: "The store sells to your companies. Start one first.")
            .padding(.horizontal, Theme.Space.page)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func back() {
        switch step {
        case .store: dismiss()
        case .category: step = .store
        case .suppliers: step = groupFrom
        case .product: step = .suppliers
        case .basket: step = .store
        case .checkout: step = .basket
        case .payment: step = .checkout
        case .placed: step = .store
        case .orders: step = .store
        case .owned: step = .store
        }
    }

    private func shoppers(_ e: GameEngine) -> [Company] {
        e.state.companies.filter { (c: Company) -> Bool in c.status.isLive }
    }

    private func current(_ e: GameEngine) -> Company? {
        if let c = e.state.company(companyID), c.status.isLive { return c }
        return shoppers(e).first
    }

    private func start() {
        if let e = store.engine, let c = current(e) {
            if companyID != c.id { companyID = c.id }
            if receiptID == 0 { receiptID = c.id }
        }
        take()
    }

    private func take() {
        guard let r = store.takeTechProRequest(), let e = store.engine, let c = e.state.company(r.companyID), c.status.isLive else { return }
        select(c.id, silently: true)
        if r.equipmentID.isEmpty {
            step = .store
        } else {
            itemID = r.equipmentID
            groupFrom = .store
            step = .suppliers
        }
    }

    private func select(_ id: Int, silently: Bool = false) {
        if id != companyID {
            if !basket.isEmpty {
                basket = []
                if !silently { store.show("Basket emptied: what you chose belongs to the other store.", tone: "n") }
            }
            companyID = id
            receiptID = id
        }
    }

    private func money(_ v: Double) -> String {
        if let co = store.engine?.state.company(companyID) { return store.short(v, in: co) }
        return store.short(v)
    }

    private func storeView(_ e: GameEngine, _ co: Company) -> some View {
        let needs: [EquipmentMarket.Need] = e.equipmentNeeds(companyID: co.id)
        return ShopPage {
            ShopCompanyMenu(caption: "Shopping for", choices: shoppers(e).map { (c: Company) -> ShopCompanyMenu.Choice in
                ShopCompanyMenu.Choice(id: c.id, name: c.name, detail: e.tradeName(c))
            }, selected: co.id, identifier: "tp-change-store", idPrefix: "tp-store") { (id: Int) in select(id) }
            hero(e, co, needs)
            categoryRow(needs)
            dealsStrip(e, co, needs)
            popular(e, co, needs)
        }
        .accessibilityIdentifier("tp-store")
    }

    private func hero(_ e: GameEngine, _ co: Company, _ needs: [EquipmentMarket.Need]) -> some View {
        let missing: Int = needs.filter { (n: EquipmentMarket.Need) -> Bool in rank(n) <= 1 }.count
        let onSale: Int = needs.filter { (n: EquipmentMarket.Need) -> Bool in n.dealPercent > 0 }.count
        let value: String = missing == 0 ? "All set" : (missing == 1 ? "1 thing to buy" : "\(missing) things to buy")
        let note: String = "Cash \(store.short(co.cash, in: co))" + (onSale > 0 ? " \u{00B7} \(onSale) on sale this week" : "")
        return ShopHero(value: value, note: note) {
            Button(missing == 0 ? "Browse the store" : "Shop what you need") {
                Haptics.tap()
                shelf = .all
                sort = .needs
                step = .category
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            .accessibilityIdentifier("tp-shop-now")
        }
    }

    private func categoryRow(_ needs: [EquipmentMarket.Need]) -> some View {
        let shown: [TechCategory] = TechCategory.allCases.filter { (c: TechCategory) -> Bool in needs.contains { (n: EquipmentMarket.Need) -> Bool in TechCategory.of(n) == c } }
        return ShopChipRow {
            ForEach(shown, id: \.self) { (c: TechCategory) in
                Button {
                    Haptics.tap()
                    shelf = .dept(c)
                    step = .category
                } label: {
                    VStack(spacing: Theme.Space.s) {
                        LedgerGlyph(glyph: c.glyph, size: Theme.Icon.large, tint: P.ink)
                            .frame(width: 64, height: 64).background(Circle().fill(P.surface))
                        Text(c.rawValue).textStyle(.caption, tint: P.ink, weight: .medium).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(width: 76)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("tp-category-\(c.rawValue)")
            }
        }
    }

    private func rank(_ n: EquipmentMarket.Need) -> Int {
        let have: Double = n.have + n.leased
        if n.required && have < 1 { return 0 }
        if n.need > 0 && have < n.need { return 1 }
        if have > 0 { return 3 }
        return 2
    }

    private func status(_ n: EquipmentMarket.Need) -> (text: String, tint: Color) {
        let have: Double = n.have + n.leased
        let haveText: String = String(Int(saturating: have.rounded()))
        switch rank(n) {
        case 0: return ("Missing", P.loss)
        case 1: return ("\(haveText) of \(Int(n.need))", P.caution)
        case 3: return ("In place", P.gain)
        default: return ("Upgrade", P.inkFaint)
        }
    }

    @ViewBuilder private func popular(_ e: GameEngine, _ co: Company, _ needs: [EquipmentMarket.Need]) -> some View {
        let top: [EquipmentMarket.Need] = Array(needs.sorted { (a: EquipmentMarket.Need, b: EquipmentMarket.Need) -> Bool in rank(a) < rank(b) }.prefix(4))
        ShopSection(title: "For \(e.tradeName(co).lowercased()) businesses", trailing: "\(needs.count) groups") {
            ShopGrid {
                ForEach(top) { (n: EquipmentMarket.Need) in tile(e, co, n) }
            }
            Button("See all \(needs.count)") { shelf = .all; sort = .needs; step = .category }
                .buttonStyle(TertiaryButtonStyle(size: .compact))
                .padding(.leading, -Theme.Space.s)
                .accessibilityIdentifier("tp-see-all")
        }
    }

    private func vehiclePhoto(_ e: GameEngine, _ co: Company, _ n: EquipmentMarket.Need) -> String {
        let model: String = e.data.catalog[co.type]?.equipment.first(where: { (x: EquipmentSpec) -> Bool in x.id == n.equipmentID })?.vehicleModels?.first ?? ""
        return TechPhotos.vehicle(model: model)
    }

    private func tileItem(_ e: GameEngine, _ co: Company, _ n: EquipmentMarket.Need) -> String {
        if n.isVehicle {
            let model: String = e.data.catalog[co.type]?.equipment.first(where: { (x: EquipmentSpec) -> Bool in x.id == n.equipmentID })?.vehicleModels?.first ?? ""
            return ArtLibrary.itemKey(group: "vehicle", familyKey: model, seed: n.equipmentID) ?? ""
        }
        let group: String = n.kind == "soft" ? "software" : "equipment"
        return ArtLibrary.itemKey(group: group, familyKey: n.equipmentID, seed: n.equipmentID) ?? ""
    }

    private func tile(_ e: GameEngine, _ co: Company, _ n: EquipmentMarket.Need) -> some View {
        let from: String = n.subscription ? "from " + money(n.fromPrice / max(1, n.lifeYears) / 12) + "/mo" : "from " + money(n.fromPrice)
        let st = status(n)
        return Button {
            Haptics.tap()
            showItem(n.equipmentID)
        } label: {
            TechTile(photo: n.isVehicle ? vehiclePhoto(e, co, n) : "", glyph: TechCategory.of(n).glyph, title: n.name, from: from, deal: n.dealPercent,
                     label: st.text, tint: st.tint, item: tileItem(e, co, n))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("tp-tile-\(n.equipmentID)")
    }

    private func showItem(_ equipmentID: String) {
        itemID = equipmentID
        groupFrom = step == .category || step == .owned ? step : .store
        step = .suppliers
    }

    @ViewBuilder private func dealsStrip(_ e: GameEngine, _ co: Company, _ needs: [EquipmentMarket.Need]) -> some View {
        let onSale: [EquipmentMarket.Need] = needs.filter { (n: EquipmentMarket.Need) -> Bool in n.dealPercent > 0 }
            .sorted { (a: EquipmentMarket.Need, b: EquipmentMarket.Need) -> Bool in a.dealPercent > b.dealPercent }
        if !onSale.isEmpty {
            let top: [EquipmentMarket.Need] = Array(onSale.prefix(2))
            let headline: String = StoreDeals.isBlackFridayWeek(e.state.week) ? "Black Friday: up to \(top[0].dealPercent)% off" : "Deals this week"
            ShopSection(title: headline, trailing: "\(onSale.count) on sale") {
                ShopGrid {
                    ForEach(top) { (n: EquipmentMarket.Need) in tile(e, co, n) }
                }
                if onSale.count > top.count {
                    Button("See all \(onSale.count) on sale") { shelf = .sale; sort = .deal; step = .category }
                        .buttonStyle(TertiaryButtonStyle(size: .compact))
                        .padding(.leading, -Theme.Space.s)
                        .accessibilityIdentifier("tp-see-sale")
                }
            }
        }
    }

    private func shelfItems(_ e: GameEngine, _ co: Company) -> [EquipmentMarket.Need] {
        let words: String = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let list: [EquipmentMarket.Need] = e.equipmentNeeds(companyID: co.id).filter { (n: EquipmentMarket.Need) -> Bool in
            let inShelf: Bool
            switch shelf {
            case .all: inShelf = true
            case .sale: inShelf = n.dealPercent > 0
            case .dept(let c): inShelf = TechCategory.of(n) == c
            }
            return inShelf && (words.isEmpty || n.name.lowercased().contains(words) || EquipmentMarket.kindName(n.kind).lowercased().contains(words))
        }
        return list.sorted { (a: EquipmentMarket.Need, b: EquipmentMarket.Need) -> Bool in
            switch sort {
            case .needs: return rank(a) != rank(b) ? rank(a) < rank(b) : a.name < b.name
            case .low: return a.fromPrice != b.fromPrice ? a.fromPrice < b.fromPrice : a.name < b.name
            case .high: return a.fromPrice != b.fromPrice ? a.fromPrice > b.fromPrice : a.name < b.name
            case .deal: return a.dealPercent != b.dealPercent ? a.dealPercent > b.dealPercent : a.name < b.name
            case .az: return a.name < b.name
            case .life: return a.lifeYears != b.lifeYears ? a.lifeYears > b.lifeYears : a.name < b.name
            case .warranty: return a.warrantyYears != b.warrantyYears ? a.warrantyYears > b.warrantyYears : a.name < b.name
            }
        }
    }

    private func categoryView(_ e: GameEngine, _ co: Company) -> some View {
        let needs: [EquipmentMarket.Need] = shelfItems(e, co)
        return ShopPage(spacing: Theme.Space.l) {
            ShopSearchField(prompt: "Search the store", text: $query, identifier: "tp-search")
            ShopChipRow {
                ForEach(TechShelf.every(presentDepartments(e, co)), id: \.self) { (s: TechShelf) in
                    ShopChip(title: s.title, selected: shelf == s) { shelf = s }
                }
            }
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(shelf.title).textStyle(.title).lineLimit(1).minimumScaleFactor(0.7)
                        Text(needs.count == 1 ? "1 item" : "\(needs.count) items").textStyle(.caption)
                    }
                    Spacer(minLength: Theme.Space.s)
                    sortMenu
                }
                if needs.isEmpty {
                    ShopEmptyNote(text: "Nothing here matches.", glyph: Glyph.search, buttonTitle: "Show all items") { shelf = .all; query = ""; sort = .needs }
                }
                ShopGrid {
                    ForEach(needs) { (n: EquipmentMarket.Need) in tile(e, co, n) }
                }
            }
        }
        .accessibilityIdentifier("tp-category")
    }

    private var sortMenu: some View {
        Menu {
            ForEach(PriceSort.allCases, id: \.self) { (s: PriceSort) in
                Button { Haptics.choose(); sort = s } label: {
                    if s == sort { Label(s.rawValue, systemImage: "checkmark") } else { Text(s.rawValue) }
                }
                .accessibilityIdentifier("tp-sort-\(s.rawValue)")
            }
        } label: {
            ShopMenuLabel(text: sort.rawValue)
        }
        .accessibilityLabel("Sort: \(sort.rawValue)")
    }

    private func presentDepartments(_ e: GameEngine, _ co: Company) -> Set<TechCategory> {
        var out: Set<TechCategory> = []
        for n in e.equipmentNeeds(companyID: co.id) { out.insert(TechCategory.of(n)) }
        return out
    }

    private func suppliersView(_ co: Company) -> some View {
        TechProSuppliers(companyID: co.id, equipmentID: itemID, onBack: { step = groupFrom }, onPick: { (key: String) in
            if key == "mk" {
                store.openApp(.marketplace)
                return
            }
            offerKey = key
            step = .product
        })
        .id(itemID + String(co.id))
    }

    private func productView(_ e: GameEngine, _ co: Company) -> some View {
        TechProProduct(companyID: co.id, equipmentID: itemID, offerKey: offerKey, basketCount: basket.count, onBack: { step = .suppliers },
                       onAdd: { (line: StoreOrders.Line) in addToBasket(line) }, onBasket: { step = .basket })
            .id(itemID + offerKey + String(co.id))
    }

    private func addToBasket(_ line: StoreOrders.Line) {
        if let i = basket.firstIndex(where: { (l: StoreOrders.Line) -> Bool in l.id == line.id }) {
            guard line.kind == .new else {
                store.show("That is already in your basket.", tone: "n")
                return
            }
            basket[i].quantity = min(50, basket[i].quantity + line.quantity)
        } else {
            basket.append(line)
        }
        store.show("Added to your basket.", tone: "good")
    }

    private func linePrice(_ q: StoreOrders.LineQuote) -> String {
        if q.monthly > 0 { return money(q.monthly) + "/mo" }
        return money(q.goods)
    }

    private func lineNote(_ q: StoreOrders.LineQuote) -> String {
        switch q.payment {
        case .lease: return "Lease, nothing due now"
        case .finance: return "Finance, \(money(q.chargeNow)) down"
        case .cash: return q.monthly > 0 ? "First month due now" : (q.digital ? "Arrives at once" : "")
        }
    }

    private func basketView(_ e: GameEngine, _ co: Company) -> some View {
        let singles: [StoreOrders.Quote?] = basket.map { (l: StoreOrders.Line) -> StoreOrders.Quote? in e.storeQuote(companyID: co.id, lines: [l], delivery: .standard) }
        let broken: Bool = singles.contains { (q: StoreOrders.Quote?) -> Bool in q == nil }
        let due: Double = singles.compactMap { (q: StoreOrders.Quote?) -> Double? in q.map { (x: StoreOrders.Quote) -> Double in x.lines.first?.chargeNow ?? 0 } }.reduce(0, +)
        let reason: String? = basket.isEmpty ? "Add something to the basket first." : (broken ? "Something in the basket is not on offer any more. Remove it to go on." : nil)
        return ShopPage {
            if basket.isEmpty {
                ShopHero(label: "Your basket", value: "Empty", note: "Choose something from the store.")
                Button("Go to the store") { step = .store }.buttonStyle(TertiaryButtonStyle(size: .compact)).padding(.leading, -Theme.Space.s)
            } else {
                ShopHero(label: "Your basket", value: money(due),
                         note: (basket.count == 1 ? "1 item" : "\(basket.count) items") + " \u{00B7} due at checkout, before delivery")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(basket.enumerated()), id: \.element.id) { (n: Int, l: StoreOrders.Line) in
                        if n > 0 { Hairline() }
                        basketRow(e, co, l, singles[n])
                    }
                }
                Text("Delivery and the arrival date come next. Leases, finance and plans continue every month.")
                    .textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("tp-basket")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !basket.isEmpty {
                ShopBottomAction {
                    PrimaryAction(title: "Checkout", blockedReason: reason, identifier: "tp-checkout") { goCheckout(e) }
                }
                .environment(\.outsidePalette, P)
            }
        }
    }

    private func basketRow(_ e: GameEngine, _ co: Company, _ l: StoreOrders.Line, _ q: StoreOrders.Quote?) -> some View {
        let lq: StoreOrders.LineQuote? = q?.lines.first
        let note: String = lq.map { (x: StoreOrders.LineQuote) -> String in lineNote(x) } ?? ""
        let sub: String = lq.map { (x: StoreOrders.LineQuote) -> String in note.isEmpty ? x.subtitle : x.subtitle + " \u{00B7} " + note } ?? "Remove it to go on"
        let need: EquipmentMarket.Need? = e.equipmentNeeds(companyID: co.id).first { (n: EquipmentMarket.Need) -> Bool in n.equipmentID == l.equipmentID }
        return HStack(alignment: .center, spacing: Theme.Space.m) {
            ShopThumb(glyph: need.map { (n: EquipmentMarket.Need) -> String in TechCategory.of(n).glyph } ?? Glyph.techPro,
                      item: need.map { (n: EquipmentMarket.Need) -> String in tileItem(e, co, n) } ?? "")
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(lq?.name ?? "Not on offer").textStyle(.headline, tint: lq == nil ? P.loss : nil).lineLimit(2)
                Text(sub).textStyle(.caption).lineLimit(2)
            }
            Spacer(minLength: Theme.Space.s)
            if let lq { Text(linePrice(lq)).textStyle(.headline, numeric: true).lineLimit(1) }
            Button {
                Haptics.tap()
                basket.removeAll { (x: StoreOrders.Line) -> Bool in x.id == l.id }
                store.show("Removed from your basket.", tone: "n")
            } label: {
                LedgerGlyph(glyph: Glyph.close, size: Theme.Icon.small, tint: P.inkFaint).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Remove")
        }
        .padding(.vertical, Theme.Space.s)
    }

    private func goCheckout(_ e: GameEngine) {
        delivery = e.storeShipping().ownCompanyID != nil ? .own : .standard
        if e.state.company(receiptID) == nil { receiptID = companyID }
        step = .checkout
    }

    private func checkoutView(_ e: GameEngine, _ co: Company) -> some View {
        let std: StoreOrders.Quote? = e.storeQuote(companyID: co.id, lines: basket, delivery: .standard)
        let chosen: StoreOrders.Quote? = e.storeQuote(companyID: co.id, lines: basket, delivery: delivery) ?? std
        let companies: [Company] = e.state.companies.filter { (c: Company) -> Bool in c.status.isLive }
        let arrives: String = (chosen?.days ?? 0) == 0 ? "Arrives today" : "Arrives \(chosen?.deliveryText ?? "")"
        return ShopPage {
            ShopHero(label: "Total due now", value: money(chosen?.chargeNow ?? 0), note: arrives + " \u{00B7} paid from \(co.name)")
            deliverySection(e, std)
            ShopReceiptPicker(companies: companies, selection: $receiptID, idPrefix: "tp")
            summarySection(co, chosen)
        }
        .accessibilityIdentifier("tp-checkout-page")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ShopBottomAction {
                PrimaryAction(title: "Pay securely", blockedReason: chosen == nil ? "Something in the basket is not on offer any more." : nil, identifier: "tp-pay") { goPayment(e) }
            }
            .environment(\.outsidePalette, P)
        }
    }

    private func deliverySection(_ e: GameEngine, _ std: StoreOrders.Quote?) -> some View {
        let ship: StoreOrders.ShippingOptions = e.storeShipping()
        let exp: StoreOrders.Quote? = e.storeQuote(companyID: companyID, lines: basket, delivery: .express)
        let own: StoreOrders.Quote? = ship.ownCompanyID != nil ? e.storeQuote(companyID: companyID, lines: basket, delivery: .own) : nil
        return ShopSection(title: "Delivery") {
            VStack(spacing: Theme.Space.xxs) {
                if let std, !std.needsShipping {
                    ShopChoiceRow(title: "Digital delivery", subtitle: "Licences and plans arrive at once.", trailing: "Free", selected: true) { }
                } else {
                    if let own, let name = ship.ownCompanyName {
                        ShopChoiceRow(title: "Own delivery (\(name))", subtitle: "Arrives \(own.deliveryText)", trailing: own.shipping == 0 ? "Free" : money(own.shipping),
                                      selected: delivery == .own, identifier: "tp-delivery-own") { delivery = .own }
                    }
                    if let std {
                        ShopChoiceRow(title: "Standard", subtitle: "\(std.days) \(std.days == 1 ? "day" : "days") \u{00B7} arrives \(std.deliveryText)", trailing: money(std.shipping),
                                      selected: delivery == .standard, identifier: "tp-delivery-standard") { delivery = .standard }
                    }
                    if let exp {
                        ShopChoiceRow(title: "Express", subtitle: "\(exp.days) \(exp.days == 1 ? "day" : "days") \u{00B7} arrives \(exp.deliveryText)", trailing: money(exp.shipping),
                                      selected: delivery == .express, identifier: "tp-delivery-express") { delivery = .express }
                    }
                }
            }
        }
    }

    private func summarySection(_ co: Company, _ q: StoreOrders.Quote?) -> some View {
        let monthly: Double = (q?.lines ?? []).reduce(0) { (sum: Double, l: StoreOrders.LineQuote) -> Double in sum + l.monthly }
        var facts: [(label: String, value: String)] = (q?.lines ?? []).map { (l: StoreOrders.LineQuote) -> (label: String, value: String) in (label: l.name, value: linePrice(l)) }
        facts.append((label: "Delivery", value: (q?.shipping ?? 0) == 0 ? "Free" : money(q?.shipping ?? 0)))
        if monthly > 0 { facts.append((label: "Then every month", value: money(monthly))) }
        facts.append((label: "Paid from", value: "\(co.name), balance \(store.short(co.cash, in: co))"))
        return ShopSection(title: "Summary") {
            ShopFacts(facts: facts)
        }
        .accessibilityIdentifier("tp-store-account")
    }

    private func goPayment(_ e: GameEngine) {
        payError = ""
        let own: BankPaymentDetails? = e.bankPaymentDetails(companyID: companyID)
        if let d = RememberedDetails.load(app: "techpro", game: RememberedDetails.gameID(e), companyID: companyID, own: own) {
            holder = d.holder
            number = d.accountNumber
            remember = true
        } else {
            holder = ""
            number = ""
            remember = false
        }
        step = .payment
    }

    private func paymentView(_ e: GameEngine, _ co: Company) -> some View {
        let d: BankPaymentDetails? = e.bankPaymentDetails(companyID: co.id)
        let q: StoreOrders.Quote? = e.storeQuote(companyID: co.id, lines: basket, delivery: delivery) ?? e.storeQuote(companyID: co.id, lines: basket, delivery: .standard)
        return ShopPage {
            ShopHero(label: "Pay", value: money(q?.chargeNow ?? 0), note: "From your account")
            if let d {
                ShopSection(title: "Saved account") {
                    savedAccount(d)
                    Button("Autofill from Bank") {
                        Haptics.tap()
                        holder = d.holder
                        number = d.accountNumber
                        payError = ""
                    }
                    .buttonStyle(TertiaryButtonStyle(size: .compact))
                    .padding(.leading, -Theme.Space.s)
                    .accessibilityIdentifier("tp-autofill")
                }
            }
            ShopSection(title: "Account details") {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    field("Account holder", "Name on the account", $holder, id: "tp-holder")
                    field("Account number", "0000 0000 0000 0000", numberShown(d), id: "tp-number")
                    Toggle(isOn: $remember) {
                        Text("Save my details for this store").textStyle(.body)
                    }
                    .tint(P.accent)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("tp-remember")
                    if !payError.isEmpty { InlineMessage(text: payError) }
                }
            }
        }
        .accessibilityIdentifier("tp-payment")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ShopBottomAction {
                PrimaryAction(title: "Continue", blockedReason: holder.isEmpty || number.isEmpty ? "Fill in the account holder and number, or use Autofill." : nil,
                              identifier: "tp-continue") { checkPayment(e, d) }
            }
            .environment(\.outsidePalette, P)
        }
    }

    private func savedAccount(_ d: BankPaymentDetails) -> some View {
        ShopChoiceRow(title: d.accountName, subtitle: masked(d.accountNumber), selected: normalised(number) == normalised(d.accountNumber) && !number.isEmpty, identifier: "tp-saved") {
            holder = d.holder
            number = d.accountNumber
            payError = ""
        }
    }

    private func masked(_ n: String) -> String { CardNumberDisplay.masked(n, companyID: companyID) }

    private func numberShown(_ d: BankPaymentDetails?) -> Binding<String> {
        let hidden: String = d.map { (x: BankPaymentDetails) -> String in masked(x.accountNumber) } ?? ""
        return Binding<String>(
            get: { (d != nil && number == d?.accountNumber) ? hidden : number },
            set: { (v: String) in if v != hidden { number = v } })
    }

    private func field(_ title: String, _ prompt: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).textStyle(.caption)
            LedgerField(placeholder: prompt, text: text, identifier: id)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }

    private func normalised(_ s: String) -> String { s.lowercased().filter { (c: Character) -> Bool in c.isLetter || c.isNumber } }

    private func checkPayment(_ e: GameEngine, _ d: BankPaymentDetails?) {
        guard let d else { return }
        if normalised(holder) != normalised(d.holder) || normalised(number) != normalised(d.accountNumber) {
            Haptics.warning()
            payError = "These details do not match your account. Use Autofill from Bank."
            return
        }
        payError = ""
        askToPay(e)
    }

    private func askToPay(_ e: GameEngine) {
        guard let co = e.state.company(companyID),
              let q = e.storeQuote(companyID: companyID, lines: basket, delivery: delivery) ?? e.storeQuote(companyID: companyID, lines: basket, delivery: .standard) else { return }
        let cur: Currency = e.currency(for: co)
        let lines: [StoreOrders.Line] = basket
        let how: StoreOrders.Delivery = q.delivery
        let id: Int = companyID
        let rid: Int = receiptID
        let message: String = "\(cur.tidyShort(q.chargeNow)) leaves \(co.name)'s account now. " + (q.days == 0 ? "Everything arrives today." : "It arrives on \(q.deliveryText), \(q.carrier.lowercased()).")
        pending = PendingAction(title: "Pay for this order?", message: message.tidyMoney, button: "Pay", amount: q.chargeNow, currency: cur, tone: .info, icon: "cart") {
            place(lines, how, id, rid, cur)
        }
    }

    private func place(_ lines: [StoreOrders.Line], _ how: StoreOrders.Delivery, _ id: Int, _ rid: Int, _ cur: Currency) {
        let r: StoreOrders.PlaceOutcome? = store.act { $0.placeStoreOrder(companyID: id, lines: lines, delivery: how, receiptCompanyID: rid) }
        switch r {
        case .placed(let no, let date, let total)?:
            Haptics.success()
            placedNumber = no
            placedDate = date
            placedTotal = cur.tidyShort(total)
            placedCarrier = store.engine?.storeOrders(companyID: id).first?.carrier ?? ""
            if let e2 = store.engine {
                RememberedDetails.save(app: "techpro", game: RememberedDetails.gameID(e2), companyID: id, own: e2.bankPaymentDetails(companyID: id), on: remember)
            }
            basket = []
            step = .placed
        case .notEnoughCash(let missing)?:
            Haptics.warning()
            store.show("Your account is short by \(cur.tidyShort(missing)).", tone: "warn")
            step = .checkout
        default:
            Haptics.warning()
            store.show("The order could not be placed. Something in it is not on offer any more.", tone: "warn")
            step = .basket
        }
    }

    private func placedView(_ e: GameEngine, _ co: Company) -> some View {
        let facts: [(label: String, value: String)] = [
            (label: "Order number", value: "#" + placedNumber),
            (label: "Arrives", value: placedDate),
            (label: "Delivery", value: placedCarrier),
            (label: "Total paid", value: placedTotal)
        ]
        return ShopSuccess(title: "Order placed", message: "The goods reach \(co.name) on the delivery date.", facts: facts,
                           primary: "View order", secondary: "Continue shopping",
                           onPrimary: { step = .orders }, onSecondary: { step = .store })
    }

    private func ordersView(_ e: GameEngine, _ co: Company) -> some View {
        let all: [(company: Company, order: StoreOrders.Record)] = e.state.companies.flatMap { (c: Company) -> [(company: Company, order: StoreOrders.Record)] in
            e.storeOrders(companyID: c.id).map { (r: StoreOrders.Record) -> (company: Company, order: StoreOrders.Record) in (company: c, order: r) }
        }
        let coming: Int = all.filter { (x: (company: Company, order: StoreOrders.Record)) -> Bool in !x.order.delivered }.count
        return ShopPage {
            if all.isEmpty {
                ShopHero(label: "My orders", value: "No orders yet", note: "What you buy shows here with its delivery date.")
                Button("Go to the store") { step = .store }.buttonStyle(TertiaryButtonStyle(size: .compact)).padding(.leading, -Theme.Space.s)
            } else {
                ShopHero(label: "My orders", value: coming == 0 ? "All delivered" : (coming == 1 ? "1 on its way" : "\(coming) on their way"),
                         note: all.count == 1 ? "1 order" : "\(all.count) orders")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(all.enumerated()), id: \.offset) { (n: Int, x: (company: Company, order: StoreOrders.Record)) in
                        if n > 0 { Hairline() }
                        orderRow(x.company, x.order)
                    }
                }
            }
        }
        .accessibilityIdentifier("tp-orders")
    }

    private func orderRow(_ c: Company, _ r: StoreOrders.Record) -> some View {
        let fresh: [String] = r.delivered ? store.messageItemIDs(.techPro, companyID: c.id) : []
        return HStack(alignment: .center, spacing: Theme.Space.m) {
            LedgerGlyph(glyph: r.delivered ? Glyph.check : Glyph.cart, size: Theme.Icon.large, tint: r.delivered ? P.gain : P.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(r.items.joined(separator: ", ")).textStyle(.headline).lineLimit(2)
                Text("#\(r.number) \u{00B7} \(c.name) \u{00B7} \(r.carrier)").textStyle(.caption).lineLimit(2)
            }
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                Text(r.delivered ? "Delivered" : "Arrives").textStyle(.caption, tint: r.delivered ? P.gain : P.inkFaint, weight: .semibold)
                Text(r.deliveryText).textStyle(.headline, numeric: true).lineLimit(1)
            }
        }
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .newGroupMarker(.techPro, fresh, style: .capsule, alignment: .topTrailing)
    }
}
