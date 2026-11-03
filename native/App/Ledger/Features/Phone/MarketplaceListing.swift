import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// A light side-to-side shake: `count` goes up by one per shake (two swings). Animatable, so it runs inside an animation of `count`.
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

/// Shakes the view for 0.4 s whenever `count` changes. Reduce Motion: no shake.
struct ShakeOnChange: ViewModifier {
    var count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .modifier(ShakeEffect(count: CGFloat(count)))
                .animation(.linear(duration: 0.4), value: count)
        }
    }
}

extension View {
    /// A quick light shake each time `trigger` changes (see `ShakeOnChange`).
    func shake(_ trigger: Int) -> some View { modifier(ShakeOnChange(count: trigger)) }
}

/// The two buttons of the price popup look the same: outlined, none filled or preselected.
struct MarketEqualButtonStyle: ButtonStyle {
    @Environment(\.outsidePalette) private var P

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return configuration.label
            .font(.system(size: 16, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(P.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(shape.fill(P.card))
            .overlay(shape.strokeBorder(P.lineStrong, lineWidth: 1.2))
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The product page of one listing: picture, title, blurb, seller, city and the posted price, with ONE button, "Message seller".
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
        return ShopScroll {
            VStack(alignment: .leading, spacing: 14) {
                ShopPhoto(name: "", glyph: Glyph.marketplace, height: 220, cornerRadius: 16, item: key)
                Text(listing.title).font(.system(size: 24, weight: .bold)).foregroundStyle(P.ink).accessibilityAddTraits(.isHeader)
                Text(cur.tidyShort(listing.askingPrice)).font(.system(size: 28, weight: .bold).monospacedDigit()).foregroundStyle(P.accent2)
                Text(listing.blurb).font(.system(size: 15)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
                Card(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        ShopFact(label: "Seller", value: listing.sellerName)
                        ShopFact(label: "City", value: listing.city)
                        ShopFact(label: "Posted", value: agoText)
                    }
                }
                action(notSelling)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 20)
        }
        .accessibilityIdentifier("mk-listing")
        .onAppear { blocked = store.marketRefused(listingID: listing.id, companyID: companyID) }
        .centerSheet(isPresented: $talking, title: "Message seller") {
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

    @ViewBuilder private func action(_ notSelling: Bool) -> some View {
        if notSelling {
            Text("Not selling to you")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(P.caution)
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(P.line, lineWidth: 1))
                .accessibilityIdentifier("mk-not-selling")
        } else {
            Button("Message seller") {
                Haptics.tap()
                talking = true
            }
            .buttonStyle(ShopFilledButtonStyle())
            .accessibilityIdentifier("mk-message")
        }
    }
}

/// The price popup: the posted price large, the seller's line under it and two equal buttons. Discuss pushes the price down (the number
/// counts down and flashes green); when the seller will not talk any more the number shakes and "Discuss price" turns into "Don't buy".
struct MarketplaceDealView: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var listing: MarketListing
    var cur: Currency
    var companyID: Int
    var onRefused: (String) -> Void
    var onClose: () -> Void
    var onBought: () -> Void

    @State private var neg: Negotiation? = nil
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
        return VStack(spacing: 14) {
            Text(listing.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(P.inkSoft).multilineTextAlignment(.center).lineLimit(2)
            CountedFigure(value: p, format: { (v: Double) -> String in cur.tidyShort(v) }, tint: green ? P.gain : P.ink)
                .font(.system(size: 42, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.6)
                .shake(shakes)
                .accessibilityLabel("Price " + priceText)
            Text(closedDoor ? "Not selling to you." : (neg?.lastMessage ?? " "))
                .font(.system(size: 14)).foregroundStyle(P.inkSoft).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 40, alignment: .top)
            patienceBar
            HStack(spacing: 10) {
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
        .padding(16)
        .frame(maxWidth: .infinity)
        .confirmAction($pending)
        .onAppear { begin() }
    }

    /// A thin bar of the seller's patience left; no numbers.
    private var patienceBar: some View {
        let left: Int = neg?.patienceLeft ?? 0
        let ratio: Double = min(1, max(0, Double(left) / Double(max(topPatience, 1))))
        return GeometryReader { (geo: GeometryProxy) in
            ZStack(alignment: .leading) {
                Capsule().fill(P.line)
                Capsule().fill(P.accent).frame(width: geo.size.width * ratio)
                    .animation(.easeOut(duration: 0.3), value: ratio)
            }
        }
        .frame(height: 4)
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
        pending = PendingAction(title: "Buy " + listing.title + "?", message: "Pay " + priceText + " to " + listing.sellerName + " from the company account.", button: "Buy", amount: at, currency: cur) {
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
