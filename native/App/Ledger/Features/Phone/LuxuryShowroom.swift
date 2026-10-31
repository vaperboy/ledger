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
                VStack(alignment: .leading, spacing: 18) {
                    pills
                    if let f = flagship { LuxuryHero(item: f, owned: owned(e, f.id)) { onOpen(f.id) } }
                    feedHeader
                    LazyVStack(spacing: 16) {
                        ForEach(items.filter { $0.id != flagship?.id }, id: \.id) { (it: Luxury.Item) in
                            LuxuryCard(item: it, owned: owned(e, it.id)) { onOpen(it.id) }
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 24)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func owned(_ e: GameEngine, _ id: String) -> Bool { e.luxuryPieces.contains { $0.item.id == id } }

    private var pills: some View {
        let ids: [String] = ["all"] + Luxury.categories.map { $0.id }
        return WrapRow(spacing: 8) { ForEach(ids, id: \.self) { pill($0) } }
    }

    private func pill(_ id: String) -> some View {
        let on: Bool = category == id
        let name: String = id == "all" ? "All" : (Luxury.categories.first { $0.id == id }?.name ?? id)
        return Button { category = id } label: {
            Text(name).font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? P.onAccent : P.inkSoft)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(on ? P.accent : P.card))
                .overlay(Capsule().strokeBorder(on ? Color.clear : P.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var feedHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Curated acquisitions").font(.serifTitle(22)).foregroundStyle(P.ink)
                Text("\(items.count) pieces").font(.system(size: 12)).foregroundStyle(P.inkFaint)
            }
            Spacer(minLength: 8)
            Button { highFirst.toggle() } label: {
                Text(highFirst ? "Price: high to low" : "Price: low to high")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced)).foregroundStyle(P.accent)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .overlay(Capsule().strokeBorder(P.lineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
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
            Text(store.short(item.price)).font(.system(size: 19, weight: .semibold, design: .monospaced)).foregroundStyle(P.accent)
            Spacer(minLength: 8)
            Text(store.short(item.monthlyUpkeep) + " / month upkeep").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(P.loss)
        }
    }
}

struct LuxuryChip: View {
    var text: String
    var filled = false
    private var P: OutsidePalette { .luxury }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 9.5, weight: .bold, design: .monospaced)).tracking(1)
            .foregroundStyle(filled ? P.onAccent : P.ink)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(filled ? P.accent : Color.black.opacity(0.55)))
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
                    .overlay(alignment: .topLeading) { LuxuryChip(text: "Flagship", filled: true).padding(10) }
                    .overlay(alignment: .topTrailing) { if owned { LuxuryChip(text: "In your vault").padding(10) } }
                    .overlay(alignment: .bottom) { LinearGradient(colors: [.clear, P.card], startPoint: .top, endPoint: .bottom).frame(height: 70) }
                VStack(alignment: .leading, spacing: 8) {
                    Text(LuxuryFacts.categoryName(item).uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.6).foregroundStyle(P.accent)
                    Text(item.name).font(.serifTitle(24)).foregroundStyle(P.ink).multilineTextAlignment(.leading)
                    LuxuryPriceLine(item: item)
                    Text(owned ? "Inspect" : "View details").font(.system(size: 14, weight: .semibold)).foregroundStyle(P.accent)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(P.lineStrong, lineWidth: 1))
                }
                .padding(14)
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(P.card))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(P.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
                    .overlay(alignment: .topLeading) { LuxuryChip(text: LuxuryFacts.categoryName(item)).padding(10) }
                    .overlay(alignment: .topTrailing) { if owned { LuxuryChip(text: "Owned", filled: true).padding(10) } }
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.name).font(.serifTitle(20)).foregroundStyle(P.ink).multilineTextAlignment(.leading)
                    specs
                    LuxuryPriceLine(item: item)
                }
                .padding(14)
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(P.card))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(P.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name + (owned ? ", owned" : ""))
    }

    private var specs: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.detail).font(.system(size: 12.5)).foregroundStyle(P.inkSoft).multilineTextAlignment(.leading)
            Text(item.trend + " · " + LuxuryFacts.percent(item.growth) + " a year").font(.system(size: 12, design: .monospaced))
                .foregroundStyle(item.growth >= 0 ? P.gain : P.inkFaint)
        }
    }
}
