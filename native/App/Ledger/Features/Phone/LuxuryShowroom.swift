import SwiftUI
import GameCore
import Businesses
import Simulation

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
            let list: [Luxury.Item] = items
            let flagship: Luxury.Item? = list.max { $0.price < $1.price }
            VStack(spacing: 0) {
                categories
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                        if let f = flagship { LuxuryHero(item: f, owned: owned(e, f.id)) { onOpen(f.id) } }
                        feedHeader(list.count)
                        LazyVStack(spacing: 40) {
                            ForEach(list.filter { $0.id != flagship?.id }, id: \.id) { (it: Luxury.Item) in
                                LuxuryCard(item: it, owned: owned(e, it.id)) { onOpen(it.id) }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.l).padding(.bottom, Theme.Space.xxl)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func owned(_ e: GameEngine, _ id: String) -> Bool { e.luxuryPieces.contains { $0.item.id == id } }

    private var categories: some View {
        let ids: [String] = ["all"] + Luxury.categories.map { $0.id }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.xl) {
                ForEach(ids, id: \.self) { (id: String) in
                    let on: Bool = category == id
                    let name: String = id == "all" ? "All" : (Luxury.categories.first { $0.id == id }?.name ?? id)
                    Button { Haptics.choose(); category = id } label: {
                        VStack(spacing: Theme.Space.xs) {
                            Text(name.uppercased()).font(.system(size: 12, weight: on ? .semibold : .medium)).tracking(1.6)
                                .foregroundStyle(on ? P.ink : P.inkFaint)
                            Rectangle().fill(on ? P.accent : Color.clear).frame(height: 1.5)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(name)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.Space.page)
        }
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func feedHeader(_ count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(count) pieces").textStyle(.label, tint: P.inkFaint)
            Spacer(minLength: Theme.Space.s)
            Button(highFirst ? "Highest price first" : "Lowest price first") { Haptics.choose(); highFirst.toggle() }
                .buttonStyle(TertiaryButtonStyle(size: .compact))
                .accessibilityLabel("Sort")
                .accessibilityValue(highFirst ? "Price high to low" : "Price low to high")
        }
    }
}

struct LuxuryPriceLine: View {
    @EnvironmentObject var store: GameStore
    var item: Luxury.Item
    private var P: OutsidePalette { .luxury }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(store.short(item.price)).textStyle(.figure, tint: P.accent)
            Spacer(minLength: Theme.Space.s)
            Text(store.short(item.monthlyUpkeep) + " a month to keep").textStyle(.caption, tint: P.inkFaint, numeric: true)
        }
    }
}

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
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                LuxuryPhoto(itemID: item.id, height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                    .overlay(alignment: .topTrailing) { if owned { LuxuryChip(text: "In your vault").padding(Theme.Space.s) } }
                    .padding(.bottom, Theme.Space.s)
                Text("Flagship \u{00B7} " + LuxuryFacts.categoryName(item)).textStyle(.label)
                Text(item.name).font(.system(size: 30, weight: .regular, design: .serif)).foregroundStyle(P.ink)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                LuxuryPriceLine(item: item)
            }
            .contentShape(Rectangle())
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
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                LuxuryPhoto(itemID: item.id, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                    .overlay(alignment: .topTrailing) { if owned { LuxuryChip(text: "Owned", filled: true).padding(Theme.Space.s) } }
                    .padding(.bottom, Theme.Space.s)
                Text(LuxuryFacts.categoryName(item)).textStyle(.label, tint: P.inkFaint)
                Text(item.name).textStyle(.title).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Text(item.trend + " \u{00B7} " + LuxuryFacts.percent(item.growth) + " a year").textStyle(.caption, tint: item.growth >= 0 ? P.gain : P.inkFaint, numeric: true)
                LuxuryPriceLine(item: item)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(item.name + (owned ? ", owned" : ""))
    }
}
