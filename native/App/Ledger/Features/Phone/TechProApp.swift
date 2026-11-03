import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The shelves of the store. Equipment, software, tools and vehicles used to be four tabs of the Equipment screen; here they are the
/// departments of one shop.
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

    /// Which department an item of equipment is sold in.
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

/// What the store shows in its list: everything, what is on sale, or one department.
enum TechShelf: Hashable {
    case all, sale, dept(TechCategory)

    var title: String {
        switch self {
        case .all: return "All items"
        case .sale: return "On sale"
        case .dept(let c): return c.rawValue
        }
    }

    /// All items, on sale, then one chip for each department the store really has items in.
    static func every(_ present: Set<TechCategory>) -> [TechShelf] {
        let depts: [TechCategory] = TechCategory.allCases.filter { (c: TechCategory) -> Bool in present.contains(c) }
        return [.all, .sale] + depts.map { (c: TechCategory) -> TechShelf in .dept(c) }
    }
}

/// The order of the list: what the business needs first, or by price.
enum PriceSort: String, CaseIterable, Hashable {
    case needs = "Needed first", low = "Price: low to high", high = "Price: high to low", deal = "Biggest discount", az = "A to Z", life = "Longest life", warranty = "Longest warranty"
}

/// TechPro Store (Phone, green): equipment, software, tools and vehicles for your companies, in one online shop. It merges the old Equipment and
/// Software screens. The store front shows what each kind of business usually needs; a basket goes to checkout (which store buys and so which
/// account is charged, where the receipt is filed, how it is delivered), then the payment details, then "Order placed" with the order number
/// and the delivery date. Delivery days are the engine's (`StoreOrders`): the goods arrive on that day, not before.
struct TechProApp: View {
    private let P = OutsidePalette.techPro
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss

    private enum Step: Equatable { case store, category, suppliers, product, basket, checkout, payment, placed, orders, owned }

    @State private var step: Step = .store
    @State private var companyID = 0
    @State private var picking = false
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

    // MARK: Chrome

    /// The four tabs under the band: the store front, every product in one list, what the company owns and its orders.
    private var showsTabs: Bool { step == .store || step == .category || step == .owned || step == .orders }

    private var tabBar: some View {
        HStack(spacing: 6) {
            tabButton("Store", on: step == .store) { step = .store }
            tabButton("Products", on: step == .category) { shelf = .all; step = .category }
            tabButton("My items", on: step == .owned) { step = .owned }
            tabButton("My orders", on: step == .orders) { step = .orders }
        }
        .padding(.horizontal, 16).padding(.vertical, 8).background(P.ground)
    }

    private func tabButton(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.choose()
            action()
        } label: {
            Text(title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                .foregroundStyle(on ? P.onAccent : P.ink)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(Capsule().fill(on ? P.accent : P.card))
                .overlay(Capsule().strokeBorder(on ? P.accent : P.line, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("tp-tab-\(title)")
    }

    private var band: some View {
        ShopBand(title: "TechPro Store", glyph: Glyph.techPro, color: P.accent, onBack: { back() }, backLabel: step == .store ? "Back to Phone" : "Back") {
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
                GlyphView(glyph: Glyph.cart, size: 24, weight: 1.7, tint: Color.white)
                    .frame(width: 40, height: 40)
                    .overlay(alignment: .topTrailing) { ShopCount(count: basket.count, color: P.accent2).offset(x: 4, y: -2) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(basket.isEmpty ? "Basket" : "Basket, \(basket.count) items")
            .accessibilityIdentifier("tp-cart")
        }
    }

    private enum TpTab: Hashable, CaseIterable { case store, products, owned, orders }

    /// The four tabs slide sideways in one pager; the tab bar above (in the top inset) stays fixed and follows the page.
    private func tabsPager(_ e: GameEngine, _ co: Company) -> some View {
        let selection: Binding<TpTab> = Binding<TpTab>(
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
        return SegmentPager(items: TpTab.allCases, selection: selection) { (t: TpTab) in
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
        VStack(spacing: 8) {
            Text("Nothing to buy for").font(.system(size: 17, weight: .semibold)).foregroundStyle(P.ink)
            Text("The store sells to your companies. Start one first.").font(.system(size: 14)).foregroundStyle(P.inkSoft)
        }
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

    // MARK: Which store

    /// The companies that buy equipment: live ones with something to buy.
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
        picking = false
    }

    private func money(_ v: Double) -> String {
        if let co = store.engine?.state.company(companyID) { return store.short(v, in: co) }
        return store.short(v)
    }

    // MARK: Store front

    private func storeView(_ e: GameEngine, _ co: Company) -> some View {
        let needs: [EquipmentMarket.Need] = e.equipmentNeeds(companyID: co.id)
        return ShopScroll {
            VStack(alignment: .leading, spacing: 16) {
                storeCard(e, co)
                if picking { storePicker(e) }
                hero
                categoryRow(needs)
                dealsStrip(e, co, needs)
                popular(e, co, needs)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 20)
        }
        .accessibilityIdentifier("tp-store")
    }

    private func storeCard(_ e: GameEngine, _ co: Company) -> some View {
        Card(padding: 12) {
            HStack(spacing: 12) {
                GlyphView(glyph: Glyph.techPro, size: 22, weight: 1.6, tint: P.accent)
                    .frame(width: 42, height: 42).background(Circle().fill(P.accent.opacity(0.1)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Shopping for").font(.system(size: 12)).foregroundStyle(P.inkFaint)
                    Text(co.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(P.ink).lineLimit(1)
                    Text("\(e.tradeName(co)) \u{00B7} cash \(store.short(co.cash, in: co))").font(.system(size: 12.5)).foregroundStyle(P.inkFaint).lineLimit(1)
                }
                Spacer(minLength: 8)
                if shoppers(e).count > 1 {
                    Button(picking ? "Close" : "Change") { picking.toggle() }.buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("tp-change-store")
                }
            }
        }
    }

    private func storePicker(_ e: GameEngine) -> some View {
        VStack(spacing: 8) {
            ForEach(shoppers(e), id: \.id) { (c: Company) in
                ShopChoiceRow(title: c.name, subtitle: "\(e.tradeName(c)) \u{00B7} \(e.cityName(c))", selected: c.id == companyID, identifier: "tp-store-\(c.id)") { select(c.id) }
            }
        }
    }

    private var hero: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack(alignment: .leading) {
            shape.fill(LinearGradient(colors: [P.accent, Color(hex: 0x2E8B5A)], startPoint: .topLeading, endPoint: .bottomTrailing))
            GlyphView(glyph: Glyph.hardware, size: 92, weight: 1.2, tint: Color.white.opacity(0.22))
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 16)
            VStack(alignment: .leading, spacing: 8) {
                Text("Equip your business for success").font(.system(size: 22, weight: .bold)).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true)
                Button {
                    Haptics.tap()
                    shelf = .all
                    step = .category
                } label: {
                    Text("Shop now").font(.system(size: 14, weight: .semibold)).foregroundStyle(P.accent)
                        .padding(.horizontal, 16).frame(minHeight: 38)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("tp-shop-now")
            }
            .padding(16).frame(maxWidth: 250, alignment: .leading)
        }
        .frame(minHeight: 120)
    }

    private func categoryRow(_ needs: [EquipmentMarket.Need]) -> some View {
        let shown: [TechCategory] = TechCategory.allCases.filter { (c: TechCategory) -> Bool in needs.contains { (n: EquipmentMarket.Need) -> Bool in TechCategory.of(n) == c } }
        return ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 6) {
            ForEach(shown, id: \.self) { (c: TechCategory) in
                let count: Int = needs.filter { (n: EquipmentMarket.Need) -> Bool in TechCategory.of(n) == c }.count
                Button {
                    Haptics.tap()
                    shelf = .dept(c)
                    step = .category
                } label: {
                    VStack(spacing: 6) {
                        GlyphView(glyph: c.glyph, size: 24, weight: 1.6, tint: count > 0 ? P.accent : P.inkDim)
                            .frame(width: 54, height: 54).background(Circle().fill(P.card)).overlay(Circle().strokeBorder(P.line, lineWidth: 1))
                        Text(c.rawValue).font(.system(size: 12, weight: .medium)).foregroundStyle(count > 0 ? P.ink : P.inkFaint).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(width: 74)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .disabled(count == 0)
                .accessibilityIdentifier("tp-category-\(c.rawValue)")
            }
        }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: What this business needs

    private func rank(_ n: EquipmentMarket.Need) -> Int {
        let have: Double = n.have + n.leased
        if n.required && have < 1 { return 0 }
        if n.need > 0 && have < n.need { return 1 }
        if have > 0 { return 3 }
        return 2
    }

    private func status(_ n: EquipmentMarket.Need) -> (text: String, tint: Color) {
        let have: Double = n.have + n.leased
        let haveText: String = String(Int(have.rounded()))
        switch rank(n) {
        case 0: return ("Missing", P.loss)
        case 1: return ("\(haveText) of \(Int(n.need))", P.caution)
        case 3: return ("In place", P.gain)
        default: return ("Upgrade", P.inkFaint)
        }
    }

    @ViewBuilder private func popular(_ e: GameEngine, _ co: Company, _ needs: [EquipmentMarket.Need]) -> some View {
        let top: [EquipmentMarket.Need] = Array(needs.sorted { (a: EquipmentMarket.Need, b: EquipmentMarket.Need) -> Bool in rank(a) < rank(b) }.prefix(4))
        VStack(alignment: .leading, spacing: 10) {
            ShopHeading(text: "What \(e.tradeName(co).lowercased()) businesses need", trailing: "\(needs.count)")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(top) { (n: EquipmentMarket.Need) in tile(e, co, n) }
            }
            Button("See all \(needs.count) product groups") { shelf = .all; sort = .needs; step = .category }
                .buttonStyle(QuietButtonStyle())
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
        let have: Double = n.have + n.leased
        let label: String = have <= 0 ? "Buy" : (n.need > 0 && have < n.need ? "Upgrade" : "Owned")
        return Button {
            Haptics.tap()
            showItem(n.equipmentID)
        } label: {
            TechTile(photo: n.isVehicle ? vehiclePhoto(e, co, n) : "", glyph: TechCategory.of(n).glyph, title: n.name, from: from, deal: n.dealPercent,
                     label: label, tint: status(n).tint, item: tileItem(e, co, n))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("tp-tile-\(n.equipmentID)")
    }

    private func showItem(_ equipmentID: String) {
        itemID = equipmentID
        groupFrom = step == .category || step == .owned ? step : .store
        step = .suppliers
    }

    /// The best discounts of the week, with the headline when it is a big sale day.
    @ViewBuilder private func dealsStrip(_ e: GameEngine, _ co: Company, _ needs: [EquipmentMarket.Need]) -> some View {
        let onSale: [EquipmentMarket.Need] = needs.filter { (n: EquipmentMarket.Need) -> Bool in n.dealPercent > 0 }
            .sorted { (a: EquipmentMarket.Need, b: EquipmentMarket.Need) -> Bool in a.dealPercent > b.dealPercent }
        if !onSale.isEmpty {
            let top: [EquipmentMarket.Need] = Array(onSale.prefix(4))
            let headline: String = StoreDeals.isBlackFridayWeek(e.state.week) ? "Black Friday: \(onSale.count) items up to \(top[0].dealPercent)% off" : "Deals this week"
            VStack(alignment: .leading, spacing: 10) {
                ShopHeading(text: headline, trailing: "\(onSale.count)")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(top) { (n: EquipmentMarket.Need) in tile(e, co, n) }
                }
                Button("See all \(onSale.count) on sale") { shelf = .sale; sort = .needs; step = .category }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("tp-see-sale")
            }
        }
    }

    // MARK: A department

    /// The items of the shelf on show: every item the store sells this company, narrowed by department or sale and by the search words, in the order chosen.
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
        return ShopScroll {
            VStack(alignment: .leading, spacing: 14) {
                searchField
                categoryChips(presentDepartments(e, co))
                sortChips
                ShopHeading(text: shelf.title, trailing: needs.count == 1 ? "1 item" : "\(needs.count) items")
                if needs.isEmpty {
                    ShopEmptyNote(text: "Nothing here matches.", buttonTitle: "Show all items") { shelf = .all; query = ""; sort = .needs }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(needs) { (n: EquipmentMarket.Need) in tile(e, co, n) }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 20)
        }
        .accessibilityIdentifier("tp-category")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            GlyphView(glyph: Glyph.search, size: 18, weight: 1.7, tint: P.inkFaint)
            TextField("Search the store", text: $query)
                .font(.system(size: 15)).foregroundStyle(P.ink)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("tp-search")
        }
        .padding(.horizontal, 14).frame(minHeight: 44)
        .background(Capsule().fill(P.card))
        .overlay(Capsule().strokeBorder(P.line, lineWidth: 1))
    }

    private func presentDepartments(_ e: GameEngine, _ co: Company) -> Set<TechCategory> {
        var out: Set<TechCategory> = []
        for n in e.equipmentNeeds(companyID: co.id) { out.insert(TechCategory.of(n)) }
        return out
    }

    private func categoryChips(_ present: Set<TechCategory>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TechShelf.every(present), id: \.self) { (s: TechShelf) in
                    ShopChip(title: s.title, selected: shelf == s) { shelf = s }
                }
            }
        }
    }

    private var sortChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PriceSort.allCases, id: \.self) { (s: PriceSort) in
                    ShopChip(title: s.rawValue, selected: sort == s) { sort = s }
                        .accessibilityIdentifier("tp-sort-\(s.rawValue)")
                }
            }
        }
    }

    // MARK: An item

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
        TechProProduct(companyID: co.id, equipmentID: itemID, offerKey: offerKey, onBack: { step = .suppliers }, onAdd: { (line: StoreOrders.Line) in addToBasket(line) })
            .id(itemID + offerKey + String(co.id))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !basket.isEmpty {
                    ShopActionBar(left: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(basket.count == 1 ? "1 item" : "\(basket.count) items").font(.system(size: 16, weight: .bold)).foregroundStyle(P.ink)
                            Text("in your basket").font(.system(size: 12)).foregroundStyle(P.inkFaint)
                        }
                    }, action: {
                        Button("View basket") { step = .basket }.buttonStyle(ShopFilledButtonStyle()).accessibilityIdentifier("tp-view-basket")
                    })
                    .environment(\.outsidePalette, P)
                }
            }
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

    // MARK: Basket

    private func linePrice(_ q: StoreOrders.LineQuote) -> String {
        if q.monthly > 0 { return money(q.monthly) + "/mo" }
        return money(q.goods)
    }

    private func lineNote(_ q: StoreOrders.LineQuote) -> String {
        switch q.payment {
        case .lease: return "Lease \u{00B7} nothing due at checkout"
        case .finance: return "Finance \u{00B7} \(money(q.chargeNow)) down now"
        case .cash: return q.monthly > 0 ? "First month due now" : (q.digital ? "Arrives at once" : "")
        }
    }

    private func basketView(_ e: GameEngine, _ co: Company) -> some View {
        let singles: [StoreOrders.Quote?] = basket.map { (l: StoreOrders.Line) -> StoreOrders.Quote? in e.storeQuote(companyID: co.id, lines: [l], delivery: .standard) }
        let broken: Bool = singles.contains { (q: StoreOrders.Quote?) -> Bool in q == nil }
        let due: Double = singles.compactMap { (q: StoreOrders.Quote?) -> Double? in q.map { (x: StoreOrders.Quote) -> Double in x.lines.first?.chargeNow ?? 0 } }.reduce(0, +)
        return ShopScroll {
            VStack(alignment: .leading, spacing: 14) {
                ShopHeading(text: "Your basket", trailing: co.name)
                if basket.isEmpty {
                    Text("Your basket is empty. Choose something from the store.").font(.system(size: 14)).foregroundStyle(P.inkSoft)
                }
                ForEach(Array(basket.enumerated()), id: \.element.id) { n, l in basketRow(l, singles[n]) }
                if broken {
                    Text("Something in the basket is not on offer any more. Remove it to go on.").font(.system(size: 13)).foregroundStyle(P.loss)
                }
                if !basket.isEmpty { basketTotals(due) }
                basketButtons(e, co, broken)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 20)
        }
        .accessibilityIdentifier("tp-basket")
    }

    private func basketRow(_ l: StoreOrders.Line, _ q: StoreOrders.Quote?) -> some View {
        let lq: StoreOrders.LineQuote? = q?.lines.first
        return Card(padding: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lq?.name ?? "Not on offer").font(.system(size: 15, weight: .semibold)).foregroundStyle(lq == nil ? P.loss : P.ink)
                    if let lq {
                        Text(lq.subtitle).font(.system(size: 12.5)).foregroundStyle(P.inkFaint)
                        let note: String = lineNote(lq)
                        if !note.isEmpty { Text(note).font(.system(size: 12)).foregroundStyle(P.inkSoft) }
                    }
                }
                Spacer(minLength: 8)
                if let lq { Text(linePrice(lq)).font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(P.ink) }
                Button {
                    Haptics.tap()
                    basket.removeAll { (x: StoreOrders.Line) -> Bool in x.id == l.id }
                } label: {
                    GlyphView(glyph: Glyph.close, size: 14, weight: 1.8, tint: P.inkFaint).frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(P.line, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Remove")
            }
        }
    }

    private func basketTotals(_ due: Double) -> some View {
        Card(padding: 14) {
            VStack(spacing: 8) {
                ShopFact(label: "Due for the items at checkout", value: money(due), strong: true)
                Text("Shipping and the delivery date come next. Leases, finance and plans continue every month.")
                    .font(.system(size: 12.5)).foregroundStyle(P.inkFaint).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func basketButtons(_ e: GameEngine, _ co: Company, _ broken: Bool) -> some View {
        VStack(spacing: 6) {
            Button("Checkout") { goCheckout(e) }
                .buttonStyle(ShopFilledButtonStyle())
                .disabled(basket.isEmpty || broken)
                .accessibilityIdentifier("tp-checkout")
            Button("Continue shopping") { step = .store }.buttonStyle(PlainTextButtonStyle(tint: P.accent))
        }
    }

    // MARK: Checkout

    private func goCheckout(_ e: GameEngine) {
        delivery = e.storeShipping().ownCompanyID != nil ? .own : .standard
        if e.state.company(receiptID) == nil { receiptID = companyID }
        step = .checkout
    }

    private func checkoutView(_ e: GameEngine, _ co: Company) -> some View {
        let std: StoreOrders.Quote? = e.storeQuote(companyID: co.id, lines: basket, delivery: .standard)
        let chosen: StoreOrders.Quote? = e.storeQuote(companyID: co.id, lines: basket, delivery: delivery) ?? std
        let companies: [Company] = e.state.companies.filter { (c: Company) -> Bool in c.status.isLive }
        return ShopScroll {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Checkout").font(.system(size: 24, weight: .bold)).foregroundStyle(P.ink)
                    Text("Complete your order").font(.system(size: 14)).foregroundStyle(P.inkSoft)
                }
                itemsCard(chosen)
                storeSection(co)
                deliverySection(e, std)
                receiptSection(companies)
                totalsSection(chosen)
                payButton(e, chosen)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 20)
        }
        .accessibilityIdentifier("tp-checkout-page")
    }

    private func itemsCard(_ q: StoreOrders.Quote?) -> some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(q?.lines ?? []) { (l: StoreOrders.LineQuote) in
                    HStack(alignment: .firstTextBaseline) {
                        Text(l.name).font(.system(size: 14.5, weight: .medium)).foregroundStyle(P.ink)
                        Spacer(minLength: 8)
                        Text(linePrice(l)).font(.system(size: 14.5, weight: .semibold).monospacedDigit()).foregroundStyle(P.ink)
                    }
                }
            }
        }
    }

    private func storeSection(_ co: Company) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ShopHeading(text: "Store")
            ShopChoiceRow(title: co.name, subtitle: "Company account \u{00B7} balance \(store.short(co.cash, in: co)). This account pays.", selected: true, identifier: "tp-store-account") { }
        }
    }

    private func deliverySection(_ e: GameEngine, _ std: StoreOrders.Quote?) -> some View {
        let ship: StoreOrders.ShippingOptions = e.storeShipping()
        let exp: StoreOrders.Quote? = e.storeQuote(companyID: companyID, lines: basket, delivery: .express)
        let own: StoreOrders.Quote? = ship.ownCompanyID != nil ? e.storeQuote(companyID: companyID, lines: basket, delivery: .own) : nil
        return VStack(alignment: .leading, spacing: 8) {
            ShopHeading(text: "Delivery method")
            if let std, !std.needsShipping {
                ShopChoiceRow(title: "Digital delivery", subtitle: "Licences and plans arrive at once.", trailing: "Free", selected: true) { }
            } else {
                if let own, let name = ship.ownCompanyName {
                    ShopChoiceRow(title: "Own delivery (\(name))", subtitle: "Your own company delivers \u{00B7} arrives \(own.deliveryText)", trailing: own.shipping == 0 ? "Free" : money(own.shipping),
                                  selected: delivery == .own, identifier: "tp-delivery-own") { delivery = .own }
                }
                if let std {
                    ShopChoiceRow(title: "Standard shipping", subtitle: "\(std.days) \(std.days == 1 ? "day" : "days") \u{00B7} arrives \(std.deliveryText)", trailing: money(std.shipping),
                                  selected: delivery == .standard, identifier: "tp-delivery-standard") { delivery = .standard }
                }
                if let exp {
                    ShopChoiceRow(title: "Express shipping", subtitle: "\(exp.days) \(exp.days == 1 ? "day" : "days") \u{00B7} arrives \(exp.deliveryText)", trailing: money(exp.shipping),
                                  selected: delivery == .express, identifier: "tp-delivery-express") { delivery = .express }
                }
            }
        }
    }

    private func receiptSection(_ companies: [Company]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ShopHeading(text: "Receipt goes to")
            ForEach(companies, id: \.id) { (c: Company) in
                ShopChoiceRow(title: c.name, subtitle: "Accounting records", selected: receiptID == c.id, identifier: "tp-receipt-\(c.id)") { receiptID = c.id }
            }
        }
    }

    private func totalsSection(_ q: StoreOrders.Quote?) -> some View {
        let goodsNow: Double = (q?.chargeNow ?? 0) - (q?.shipping ?? 0)
        let monthly: Double = (q?.lines ?? []).reduce(0) { (sum: Double, l: StoreOrders.LineQuote) -> Double in sum + l.monthly }
        return Card(padding: 14) {
            VStack(spacing: 8) {
                ShopFact(label: "Items", value: money(goodsNow))
                ShopFact(label: "Delivery", value: (q?.shipping ?? 0) == 0 ? "Free" : money(q?.shipping ?? 0))
                if monthly > 0 { ShopFact(label: "Then every month", value: money(monthly)) }
                ShopFact(label: "Arrives", value: (q?.days ?? 0) == 0 ? "Today" : (q?.deliveryText ?? ""))
                ShopFact(label: "Total due now", value: money(q?.chargeNow ?? 0), strong: true)
            }
        }
    }

    private func payButton(_ e: GameEngine, _ q: StoreOrders.Quote?) -> some View {
        VStack(spacing: 6) {
            Button("Pay securely") { goPayment(e) }
                .buttonStyle(ShopFilledButtonStyle())
                .disabled(q == nil)
                .accessibilityIdentifier("tp-pay")
            Text("Secure checkout by your bank").font(.system(size: 12)).foregroundStyle(P.inkFaint).frame(maxWidth: .infinity)
        }
    }

    // MARK: Payment details

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
        return ShopScroll {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Payment details").font(.system(size: 24, weight: .bold)).foregroundStyle(P.ink)
                    Text("Pay from the company account").font(.system(size: 14)).foregroundStyle(P.inkSoft)
                }
                if let d { savedAccount(d) }
                if let d { autofillCard(d) }
                fields(d)
                Toggle(isOn: $remember) {
                    Text("Remember me for this store").font(.system(size: 15)).foregroundStyle(P.ink)
                }
                .tint(P.accent)
                .accessibilityIdentifier("tp-remember")
                if !payError.isEmpty { InlineMessage(text: payError) }
                Button("Continue") { checkPayment(e, d) }
                    .buttonStyle(ShopFilledButtonStyle())
                    .disabled(holder.isEmpty || number.isEmpty)
                    .accessibilityIdentifier("tp-continue")
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 20)
        }
        .accessibilityIdentifier("tp-payment")
    }

    private func savedAccount(_ d: BankPaymentDetails) -> some View {
        ShopChoiceRow(title: "Saved account", subtitle: "\(d.accountName) \u{00B7} \(masked(d.accountNumber))", selected: true, identifier: "tp-saved") {
            holder = d.holder
            number = d.accountNumber
        }
    }

    private func masked(_ n: String) -> String { CardNumberDisplay.masked(n, companyID: companyID) }

    private func autofillCard(_ d: BankPaymentDetails) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Autofill from Bank").font(.system(size: 16, weight: .semibold)).foregroundStyle(P.ink)
                Text("Use the account name and number from your bank to fill this in instantly.").font(.system(size: 13)).foregroundStyle(P.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Autofill") {
                    Haptics.tap()
                    holder = d.holder
                    number = d.accountNumber
                    payError = ""
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("tp-autofill")
            }
        }
    }

    private func fields(_ d: BankPaymentDetails?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Account holder", "Name on the account", $holder, id: "tp-holder")
            field("Account number", "0000 0000 0000 0000", numberShown(d), id: "tp-number")
        }
    }

    /// The number field shows the bank's number as sixteen digits with the first twelve starred; the engine's number stays what is kept and compared.
    private func numberShown(_ d: BankPaymentDetails?) -> Binding<String> {
        let hidden: String = d.map { (x: BankPaymentDetails) -> String in masked(x.accountNumber) } ?? ""
        return Binding<String>(
            get: { (d != nil && number == d?.accountNumber) ? hidden : number },
            set: { (v: String) in if v != hidden { number = v } })
    }

    private func field(_ title: String, _ prompt: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(P.inkFaint)
            TextField(prompt, text: text)
                .font(.system(size: 16)).foregroundStyle(P.ink)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.horizontal, 12).frame(minHeight: 46)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(P.card))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(P.line, lineWidth: 1))
                .accessibilityIdentifier(id)
        }
    }

    private func normalised(_ s: String) -> String { s.lowercased().filter { (c: Character) -> Bool in c.isLetter || c.isNumber } }

    /// The details must be the company account's own (the Bank's name and number): a typed account that is not it is refused.
    private func checkPayment(_ e: GameEngine, _ d: BankPaymentDetails?) {
        guard let d else { return }
        if normalised(holder) != normalised(d.holder) || normalised(number) != normalised(d.accountNumber) {
            Haptics.warning()
            payError = "These details do not match the company account. Use Autofill from Bank."
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
        pending = PendingAction(title: "Pay for this order?", message: message.tidyMoney, button: "Pay", amount: q.chargeNow, currency: cur) {
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
            store.show("The company account is short by \(cur.tidyShort(missing)).", tone: "warn")
            step = .checkout
        default:
            Haptics.warning()
            store.show("The order could not be placed. Something in it is not on offer any more.", tone: "warn")
            step = .basket
        }
    }

    // MARK: Order placed and orders

    private func placedView(_ e: GameEngine, _ co: Company) -> some View {
        let facts: [(label: String, value: String)] = [
            (label: "Order number", value: "#" + placedNumber),
            (label: "Arrives", value: placedDate),
            (label: "Delivery", value: placedCarrier),
            (label: "Total paid", value: placedTotal),
            (label: "Store", value: co.name)
        ]
        return ShopSuccess(title: "Order placed", message: "Your order has been placed. The goods reach \(co.name) on the delivery date.", facts: facts,
                           primary: "View order", secondary: "Continue shopping",
                           onPrimary: { step = .orders }, onSecondary: { step = .store })
    }

    private func ordersView(_ e: GameEngine, _ co: Company) -> some View {
        let all: [(company: Company, order: StoreOrders.Record)] = e.state.companies.flatMap { (c: Company) -> [(company: Company, order: StoreOrders.Record)] in
            e.storeOrders(companyID: c.id).map { (r: StoreOrders.Record) -> (company: Company, order: StoreOrders.Record) in (company: c, order: r) }
        }
        return ShopScroll {
            VStack(alignment: .leading, spacing: 14) {
                ShopHeading(text: "My orders", trailing: all.isEmpty ? "" : "\(all.count)")
                if all.isEmpty {
                    Text("No orders yet.").font(.system(size: 14)).foregroundStyle(P.inkSoft)
                }
                ForEach(Array(all.enumerated()), id: \.offset) { _, x in orderCard(x.company, x.order) }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 20)
        }
        .accessibilityIdentifier("tp-orders")
    }

    private func orderCard(_ c: Company, _ r: StoreOrders.Record) -> some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("#" + r.number).font(.system(size: 15, weight: .semibold)).foregroundStyle(P.ink)
                    Spacer(minLength: 8)
                    Text(r.delivered ? "Delivered" : "On its way").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(r.delivered ? P.gain : P.caution)
                }
                Text(r.items.joined(separator: ", ")).font(.system(size: 13)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
                Text("\(c.name) \u{00B7} placed \(r.placedText) \u{00B7} " + (r.delivered ? "arrived" : "arrives") + " \(r.deliveryText) \u{00B7} \(r.carrier)")
                    .font(.system(size: 12)).foregroundStyle(P.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
