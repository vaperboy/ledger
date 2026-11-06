import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Showroom tab: category pills, one flagship, a sort control and a feed of big photo cards.
struct LuxuryShowroom: View {
    @EnvironmentObject var store: GameStore
    var onOpen: (String) -> Void
    @State private var category = "all"
    @State private var highFirst = true

    private var P: OutsidePalette { .luxury }

    private var items: [Luxury.Item] {
        let all: [Luxury.Item] = Luxury.categories.filter { category == "all" || $0.id == category }.flatMap { $0.items }
        return all.sorted { highFirst ? $0.price > $1.price : $0.price < $1.price }
    }

    var body: some View {
        if let e = store.engine {
            let flagship: Luxury.Item? = items.max { $0.price < $1.price }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    pills
                    if let f = flagship { LuxuryHero(item: f, owned: owned(e, f.id)) { onOpen(f.id) } }
                    feedHeader
                    LazyVStack(spacing: Theme.Space.l) {
                        ForEach(items.filter { $0.id != flagship?.id }, id: \.id) { (it: Luxury.Item) in
                            LuxuryCard(item: it, owned: owned(e, it.id)) { onOpen(it.id) }
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.m).padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func owned(_ e: GameEngine, _ id: String) -> Bool { e.luxuryPieces.contains { $0.item.id == id } }

    private var pills: some View {
        let ids: [String] = ["all"] + Luxury.categories.map { $0.id }
        return WrapRow(spacing: Theme.Space.s) {
            ForEach(ids, id: \.self) { (id: String) in
                ShopChip(title: id == "all" ? "All" : (Luxury.categories.first { $0.id == id }?.name ?? id), selected: category == id) { category = id }
            }
        }
    }

    private var feedHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Curated acquisitions").textStyle(.figure)
                Text("\(items.count) pieces").textStyle(.caption, tint: P.inkFaint)
            }
            Spacer(minLength: Theme.Space.s)
            Button(highFirst ? "Price: high to low" : "Price: low to high") { Haptics.choose(); highFirst.toggle() }
                .buttonStyle(TertiaryButtonStyle(size: .compact))
                .accessibilityLabel("Sort")
                .accessibilityValue(highFirst ? "Price high to low" : "Price low to high")
        }
    }
}

/// The two money lines under a name: price and monthly upkeep, both in the player's currency.
struct LuxuryPriceLine: View {
    @EnvironmentObject var store: GameStore
    var item: Luxury.Item
    private var P: OutsidePalette { .luxury }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(store.short(item.price)).textStyle(.figure, tint: P.accent)
            Spacer(minLength: Theme.Space.s)
            Text(store.short(item.monthlyUpkeep) + " / month upkeep").textStyle(.caption, tint: P.loss, numeric: true)
        }
    }
}

/// A word on a picture (Flagship, Owned, the category): small caps on a flat scrim, or on the accent when `filled`.
struct LuxuryChip: View {
    var text: String
    var filled = false
    private var P: OutsidePalette { .luxury }
    var body: some View {
        Text(text).textStyle(.label, tint: filled ? P.onAccent : P.ink)
            .environment(\.containerInk, filled ? P.onAccent : nil)
            .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xs)
            .background(Capsule().fill(filled ? P.accent : P.scrim))
    }
}

struct LuxuryHero: View {
    var item: Luxury.Item
    var owned: Bool
    var action: () -> Void
    private var P: OutsidePalette { .luxury }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                LuxuryPhoto(itemID: item.id, height: 224)
                    .overlay(alignment: .topLeading) { LuxuryChip(text: "Flagship", filled: true).padding(Theme.Space.s) }
                    .overlay(alignment: .topTrailing) { if owned { LuxuryChip(text: "In your vault").padding(Theme.Space.s) } }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(LuxuryFacts.categoryName(item)).textStyle(.label)
                    Text(item.name).textStyle(.title).multilineTextAlignment(.leading)
                    LuxuryPriceLine(item: item)
                    Text(owned ? "Inspect" : "View details").textStyle(.headline, tint: P.accent)
                        .frame(minHeight: 44)
                }
                .padding(Theme.Space.l)
            }
            .background(P.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("luxury-hero")
        .accessibilityLabel(item.name + ", flagship")
    }
}

struct LuxuryCard: View {
    var item: Luxury.Item
    var owned: Bool
    var action: () -> Void
    private var P: OutsidePalette { .luxury }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                LuxuryPhoto(itemID: item.id, height: 176)
                    .overlay(alignment: .topLeading) { LuxuryChip(text: LuxuryFacts.categoryName(item)).padding(Theme.Space.s) }
                    .overlay(alignment: .topTrailing) { if owned { LuxuryChip(text: "Owned", filled: true).padding(Theme.Space.s) } }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(item.name).textStyle(.figure).multilineTextAlignment(.leading)
                    specs
                    LuxuryPriceLine(item: item)
                }
                .padding(Theme.Space.l)
            }
            .background(P.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(item.name + (owned ? ", owned" : ""))
    }

    private var specs: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(item.detail).textStyle(.caption).multilineTextAlignment(.leading)
            Text(item.trend + " · " + LuxuryFacts.percent(item.growth) + " a year").textStyle(.caption, tint: item.growth >= 0 ? P.gain : P.inkFaint, numeric: true)
        }
    }
}
