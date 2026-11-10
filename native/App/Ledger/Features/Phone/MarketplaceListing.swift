import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct ShakeEffect: GeometryEffect {
    var count: CGFloat
    var travel: CGFloat = 7

    var animatableData: CGFloat {
        get { count }
        set { count = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let dx: CGFloat = travel * sin(count * CGFloat.pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}

struct ShakeOnChange: ViewModifier {
    var count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .modifier(ShakeEffect(count: CGFloat(count)))
                .animation(Motion.quickAnimation, value: count)
        }
    }
}

extension View {
    func shake(_ trigger: Int) -> some View { modifier(ShakeOnChange(count: trigger)) }
}

struct MarketEqualButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonStyle(fullWidth: true).makeBody(configuration: configuration)
    }
}

struct MarketplaceListingPage: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var listing: MarketListing
    var cur: Currency
    var companyID: Int
    var today: Int
    var refusedHere: Bool
    var onRefused: (String) -> Void
    var onBought: () -> Void

    @State private var talking = false
    @State private var blocked = false

    var body: some View {
        let key: String = ArtLibrary.itemKey(group: "", familyKey: listing.family, seed: listing.id) ?? ""
        let ago: Int = max(0, today - listing.postedDay)
        let agoText: String = ago == 0 ? "today" : (ago == 1 ? "yesterday" : "\(ago) days ago")
        let notSelling: Bool = blocked || refusedHere
        return ShopPage {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ShopPhoto(name: "", glyph: Glyph.marketplace, height: 280, item: key)
                    .padding(.bottom, Theme.Space.m)
                Text(cur.tidyShort(listing.askingPrice)).textStyle(.display)
                Text(listing.title).textStyle(.title).accessibilityAddTraits(.isHeader).fixedSize(horizontal: false, vertical: true)
                Text("\(listing.city) \u{00B7} posted \(agoText)").textStyle(.caption)
            }
            Text(listing.blurb).textStyle(.body, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
            ShopSection(title: "Seller") {
                LedgerRow(leading: .initials(initials(listing.sellerName)), leadingTint: P.accent, title: listing.sellerName, subtitle: "Private seller in \(listing.city)")
            }
            lotCard
        }
        .accessibilityIdentifier("mk-listing")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ShopBottomAction { action(notSelling) }
                .environment(\.outsidePalette, P)
        }
        .onAppear { blocked = store.marketRefused(listingID: listing.id, companyID: companyID) }
        .centerSheet(isPresented: $talking, title: "Message seller", category: .medium, tone: .info) {
            MarketplaceDealView(listing: listing, cur: cur, companyID: companyID, onRefused: { (id: String) in
                blocked = true
                onRefused(id)
            }, onClose: { talking = false }, onBought: {
                talking = false
                onBought()
            })
            .environment(\.outsidePalette, OutsidePalette.marketplace)
            .environmentObject(store)
        }
    }

    private func initials(_ name: String) -> String {
        String(name.split(separator: " ").prefix(2).compactMap { (w: Substring) -> Character? in w.first })
    }

    private var yardLot: UsedCarLot? {
        guard let e = store.engine, let co = e.state.company(companyID), co.type == UsedCarDealer.tradeID else { return nil }
        let cat: MarketplaceApp.Filter = MarketplaceApp.category(listing.family)
        guard cat == .cars || cat == .vans else { return nil }
        return e.usedCarLot(companyID: companyID)
    }

    @ViewBuilder private var lotCard: some View {
        if let lot = yardLot {
            ShopSection(title: "Your lot") {
                ShopFacts(facts: [(label: "Spaces used", value: "\(lot.used) of \(lot.spaces)"), (label: "Free spaces", value: "\(lot.free)")],
                          tints: lot.free == 0 ? [1: P.caution] : [:])
            }
            .accessibilityIdentifier("mk-lot")
        }
    }

    @ViewBuilder private func action(_ notSelling: Bool) -> some View {
        let lotFull: Bool = (yardLot?.free ?? 1) == 0
        let reason: String? = lotFull
            ? ((yardLot?.spaces ?? 0) == 0 ? "These premises have no space for cars. You cannot buy this one." : "The lot is full. Sell a car before you buy this one.")
            : (notSelling ? "Not selling to you." : nil)
        VStack(spacing: Theme.Space.xs) {
            Button("Message seller") {
                Haptics.tap()
                talking = true
            }
            .buttonStyle(ShopFilledButtonStyle())
            .disabled(reason != nil)
            .accessibilityIdentifier("mk-message")
            if let reason {
                Text(reason).textStyle(.caption, tint: P.caution).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(lotFull ? "mk-lot-full" : "mk-not-selling")
            }
        }
    }
}

struct MarketplaceDealView: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var listing: MarketListing
    var cur: Currency
    var companyID: Int
    var onRefused: (String) -> Void
    var onClose: () -> Void
    var onBought: () -> Void

    @State private var neg: MarketNegotiation? = nil
    @State private var started = false
    @State private var closedDoor = false
    @State private var topPatience = 1
    @State private var green = false
    @State private var greenToken = 0
    @State private var shakes = 0
    @State private var pending: PendingAction?

    private var price: Double { neg?.price ?? listing.askingPrice }
    private var stuck: Bool {
        if closedDoor { return true }
        guard let n = neg else { return false }
        return !n.canDiscuss || n.mood == .refusing
    }

    var body: some View {
        let p: Double = price
        let priceText: String = cur.tidyShort(p)
        return VStack(spacing: Theme.Space.m) {
            Text(listing.title).textStyle(.headline, tint: P.inkSoft).multilineTextAlignment(.center).lineLimit(2)
            CountedFigure(value: p, format: { (v: Double) -> String in cur.tidyShort(v) }, tint: green ? P.gain : P.ink)
                .textStyle(.display)
                .lineLimit(2).minimumScaleFactor(0.8)
                .shake(shakes)
                .accessibilityLabel("Price " + priceText)
            Text(closedDoor ? "Not selling to you." : (neg?.lastMessage ?? " "))
                .popupText(.body).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 40, alignment: .top)
            patienceBar
            HStack(spacing: Theme.Space.s) {
                if stuck {
                    Button("Don't buy") {
                        Haptics.tap()
                        onClose()
                    }
                    .buttonStyle(MarketEqualButtonStyle())
                    .accessibilityIdentifier("mk-dont-buy")
                } else {
                    Button("Discuss price") { discuss() }
                        .buttonStyle(MarketEqualButtonStyle())
                        .accessibilityIdentifier("mk-discuss")
                }
                Button("Buy at " + priceText) { askToBuy(priceText) }
                    .buttonStyle(MarketEqualButtonStyle())
                    .accessibilityIdentifier("mk-buy")
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity)
        .confirmAction($pending)
        .onAppear { begin() }
    }

    private var patienceBar: some View {
        let left: Int = neg?.patienceLeft ?? 0
        let ratio: Double = min(1, max(0, Double(left) / Double(max(topPatience, 1))))
        return ProgressLine(fraction: ratio)
            .accessibilityLabel("Seller's patience")
            .accessibilityValue(ratio > 0.5 ? "high" : (ratio > 0.2 ? "running low" : "almost gone"))
    }

    private func begin() {
        if started { return }
        started = true
        guard let n = store.marketBegin(listingID: listing.id, companyID: companyID) else {
            closedDoor = true
            shakes += 1
            onRefused(listing.id)
            return
        }
        neg = n
        topPatience = max(1, n.patienceLeft)
    }

    private func discuss() {
        let old: Double = price
        guard let n = store.marketPush(listingID: listing.id, companyID: companyID) else { return }
        neg = n
        topPatience = max(topPatience, n.patienceLeft)
        if n.price < old - 0.0001 {
            Haptics.choose()
            flashGreen()
        }
        if !n.canDiscuss || n.mood == .refusing {
            shakes += 1
            Haptics.warning()
            if n.mood == .refusing { onRefused(listing.id) }
        }
    }

    private func flashGreen() {
        green = true
        greenToken += 1
        let mine: Int = greenToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            if mine == greenToken { green = false }
        }
    }

    private func askToBuy(_ priceText: String) {
        let at: Double = price
        pending = PendingAction(title: "Buy " + listing.title + "?", message: "If you do this, " + priceText + " leaves the company account and goes to " + listing.sellerName + ". The item is yours.", button: "Buy", amount: at, currency: cur, tone: .info, icon: "tag") {
            buy(at, priceText)
        }
    }

    private func buy(_ at: Double, _ priceText: String) {
        let r: SettingResult = store.marketBuy(listingID: listing.id, companyID: companyID, price: at)
        if let why = r.reason {
            Haptics.warning()
            store.show(why, tone: "warn")
        } else {
            Haptics.success()
            store.show("Bought " + listing.title + " for " + priceText + ".", tone: "n")
            onBought()
        }
    }
}
