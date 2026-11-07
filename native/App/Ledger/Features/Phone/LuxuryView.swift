import SwiftUI
import GameCore
import Businesses
import Simulation
#if canImport(UIKit)
import UIKit
#endif

/// The Luxury phone app: a private-sales app made by someone else (obsidian and muted gold, serif names, monospaced money).
/// First opening is by application (`LuxuryGateView`); once accepted it opens on the Showroom, with My Vault as the other tab.
/// Items, prices, upkeep, loans and sale values all come from the engine (`Luxury`, `luxuryFinanceQuote`, `luxurySellQuote`).
struct LuxuryView: View {
    enum Tab: String { case showroom, vault }

    @EnvironmentObject var store: GameStore
    @State private var tab: Tab = .showroom
    @State private var itemSheet: String? = nil
    @State private var inspected: Int? = nil

    private var P: OutsidePalette { .luxury }

    var body: some View {
        Group {
            if let e = store.engine {
                if e.luxuryGate == .accepted { app(e) } else { LuxuryGateView() }
            }
        }
        .outsideScreen(P)
    }

    private func app(_ e: GameEngine) -> some View {
        VStack(spacing: 0) {
            LuxuryHeader()
            content
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        .centerSheet(item: Binding(get: { itemSheet.map { LuxuryID(id: $0) } }, set: { itemSheet = $0?.id }), size: .fitBleed, category: .medium, tone: .prestige) { (s: LuxuryID) in
            LuxuryItemSheet(itemID: s.id) { itemSheet = nil; tab = .vault }
        }
        .centerSheet(item: Binding(get: { inspected.map { LuxuryPieceID(id: $0) } }, set: { inspected = $0?.id }), size: .fitBleed, category: .medium, tone: .prestige) { (s: LuxuryPieceID) in
            LuxuryInspectSheet(pieceID: s.id)
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .showroom: LuxuryShowroom { itemSheet = $0 }
        case .vault: LuxuryVaultTab(onInspect: { inspected = $0 }, onShowroom: { tab = .showroom })
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.showroom, "Showroom", Glyph.luxury)
            tabButton(.vault, "My Vault", Glyph.bank)
        }
        .padding(.top, Theme.Space.xs)
        .background(P.page.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Hairline() }
    }

    private func tabButton(_ t: Tab, _ name: String, _ glyph: String) -> some View {
        let on: Bool = tab == t
        return Button { Haptics.choose(); tab = t } label: {
            VStack(spacing: Theme.Space.xxs) {
                LedgerGlyph(glyph: glyph, size: Theme.Icon.medium, tint: on ? P.accent : P.inkFaint)
                Text(name).textStyle(.caption, tint: on ? P.accent : P.inkFaint, weight: on ? .semibold : .regular)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("luxury-tab-" + t.rawValue)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct LuxuryID: Identifiable { let id: String }
struct LuxuryPieceID: Identifiable { let id: Int }

/// The masthead shown on both tabs: back button, the house name, and the cash that can be spent.
struct LuxuryHeader: View {
    @EnvironmentObject var store: GameStore
    private var P: OutsidePalette { .luxury }

    var body: some View {
        if let e = store.engine {
            VStack(spacing: Theme.Space.xxs) {
                ZStack {
                    HStack { OutsideBack(); Spacer(minLength: 0) }
                    Text("PRIVATE SALES").font(.system(size: 15, weight: .medium, design: .serif)).tracking(4).foregroundStyle(P.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                Text("Cash available " + store.short(max(0, e.state.cash))).textStyle(.caption, tint: P.inkFaint, numeric: true)
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.top, Theme.Space.xs).padding(.bottom, Theme.Space.s)
            .overlay(alignment: .bottom) { Hairline() }
        }
    }
}

/// A luxury item's picture: the catalogue asset or the sheet cell, cropped to fill the given height; the icon until art exists.
struct LuxuryPhoto: View {
    var itemID: String
    var height: CGFloat
    private var P: OutsidePalette { .luxury }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity).frame(height: height)
            .overlay { picture }
            .background(P.cardDeep)
            .clipped()
    }

    @ViewBuilder private var picture: some View {
        if let ui = UIImage(named: ThumbnailView.assetName(.luxury, itemID)) ?? ArtLibrary.luxuryImage(itemID: itemID) {
            Image(uiImage: ui).resizable().scaledToFill()
        } else {
            ThumbnailView(kind: .luxury, key: itemID, size: 72, shape: .square)
        }
    }
}

/// Small helpers for the facts every card and sheet shows.
enum LuxuryFacts {
    static func item(_ id: String) -> Luxury.Item? { Luxury.item(id) }
    static func categoryName(_ it: Luxury.Item) -> String { Luxury.categories.first { $0.id == it.category }?.name ?? it.category }
    static func percent(_ v: Double) -> String {
        let n: Double = (v * 1000).rounded() / 10
        return (n > 0 ? "+" : "") + String(format: "%.1f%%", n)
    }
}
