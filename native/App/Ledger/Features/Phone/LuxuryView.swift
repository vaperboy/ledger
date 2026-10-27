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
        .accessibilityIdentifier("luxury-app")
    }

    private func app(_ e: GameEngine) -> some View {
        VStack(spacing: 0) {
            LuxuryHeader()
            content
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        .sheet(item: Binding(get: { itemSheet.map { LuxuryID(id: $0) } }, set: { itemSheet = $0?.id })) { (s: LuxuryID) in
            LuxuryItemSheet(itemID: s.id) { itemSheet = nil; tab = .vault }
        }
        .sheet(item: Binding(get: { inspected.map { LuxuryPieceID(id: $0) } }, set: { inspected = $0?.id })) { (s: LuxuryPieceID) in
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
        .padding(.top, 8).padding(.bottom, 4)
        .background(P.ground.opacity(0.96).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(P.line).frame(height: 1) }
    }

    private func tabButton(_ t: Tab, _ name: String, _ glyph: String) -> some View {
        let on: Bool = tab == t
        return Button { tab = t } label: {
            VStack(spacing: 4) {
                GlyphView(glyph: glyph, size: 20, weight: 1.5, tint: on ? P.accent : P.inkFaint)
                Text(name).font(.system(size: 11, weight: on ? .semibold : .regular)).foregroundStyle(on ? P.accent : P.inkFaint)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("luxury-tab-" + t.rawValue)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct LuxuryID: Identifiable { let id: String }
struct LuxuryPieceID: Identifiable { let id: Int }

/// The masthead shown on both tabs: back button, title, and the two figures that matter before buying.
struct LuxuryHeader: View {
    @EnvironmentObject var store: GameStore
    private var P: OutsidePalette { .luxury }

    var body: some View {
        if let e = store.engine {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    OutsideBack()
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            GlyphView(glyph: Glyph.luxury, size: 12, weight: 1.4, tint: P.accent)
                            Text("PRIVATE SALES").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2.4).foregroundStyle(P.accent)
                        }
                        Text("Private sales").font(.serifTitle(26)).foregroundStyle(P.ink).accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 0)
                }
                figures(e)
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 10)
        }
    }

    private func figures(_ e: GameEngine) -> some View {
        HStack(spacing: 0) {
            cell("LIQUID CASH", store.short(max(0, e.state.cash)), P.gain)
            Rectangle().fill(P.line).frame(width: 1, height: 30)
            cell("NET WORTH", store.short(e.netWorth.total), P.ink).padding(.leading, 14)
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(P.line, lineWidth: 1))
    }

    private func cell(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9.5, weight: .semibold, design: .monospaced)).tracking(1.4).foregroundStyle(P.inkFaint)
            Text(value).font(.system(size: 17, weight: .semibold, design: .monospaced)).foregroundStyle(tint).minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A luxury item's picture: the owner's catalogue asset or the sheet cell, cropped to fill the given height; the icon until art exists.
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
