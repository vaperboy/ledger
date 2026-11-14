import SwiftUI
import Simulation
#if canImport(UIKit)
import UIKit
#endif

/// EVENT BOXES: the six boxes of the current event, each with exclusive epic and legendary items, until the rotation changes.
struct EventBoxesSection: View {
    private let session = StoreSession.shared

    var body: some View {
        let boxes: [EventBox] = session.eventBoxes
        let title: String = boxes.first?.setTitle ?? "Event boxes"
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            StoreBand(title: title, glyph: Glyph.luxury, tint: StoreColors.pink, trailing: session.eventsEnd)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 3), spacing: Theme.Space.s) {
                ForEach(boxes) { (b: EventBox) in
                    NavigationLink { BoxView(kind: b.kind, paidBoxesAllowed: true) } label: { EventBoxTile(box: b) }
                        .buttonStyle(PressableStyle())
                        .adminPrice(kind: "box", id: b.kind.rawValue, current: b.kind.price)
                        .accessibilityIdentifier("store-event-" + b.kind.rawValue)
                }
            }
            .padding(.horizontal, Theme.Space.m)
            Text("Six new event boxes every two weeks. Their epic and legendary items come only from that box, never from other boxes, the shelf or the pass.")
                .textStyle(.caption).fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.m)
        }
    }
}

struct EventBoxTile: View {
    var box: EventBox

    var body: some View {
        let kind: BoxKind = box.kind
        VStack(spacing: Theme.Space.xs) {
            Text(box.title.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(.white).multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.7).frame(minHeight: 28)
            EventBoxArt(box: box, size: 52).padding(.vertical, 2)
            StorePriceBar(gold: kind.price)
        }
        .padding(Theme.Space.xs)
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(StoreColors.gradient(tint)))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var tint: Color { Color(hex: box.colors.first ?? 0xEC3D8C) }
}

/// The set's box picture when its file exists, else the drawn box in the event's colours.
struct EventBoxArt: View {
    var box: EventBox
    var size: CGFloat

    var body: some View {
        #if canImport(UIKit)
        if let img = ArtAsset.uiImage(box.art) {
            Image(uiImage: img).resizable().scaledToFit().frame(width: size * 1.04, height: size * 0.95).accessibilityHidden(true)
        } else {
            BoxArt(kind: box.kind, size: size)
        }
        #else
        BoxArt(kind: box.kind, size: size)
        #endif
    }
}

// MARK: Administrator prices

/// A small pencil on a store price for administrators: type a new price for every player, or go back to the catalogue price.
private struct AdminPriceEdit: ViewModifier {
    var kind: String
    var id: String
    var current: Int
    private let session = StoreSession.shared
    @State private var editing = false
    @State private var text = ""

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if session.isAdmin {
                Button { text = String(current); editing = true } label: {
                    Image(systemName: "pencil.circle.fill").font(.title3).symbolRenderingMode(.palette).foregroundStyle(.white, Color.black.opacity(0.55))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change the price")
                .accessibilityIdentifier("admin-price-" + kind + "-" + id)
            }
        }
        .alert("Price for everyone", isPresented: $editing) {
            TextField("Gold", text: $text).keyboardType(.numberPad)
            Button("Save") { save(Int(text.filter { $0.isNumber })) }
            Button("Catalogue price") { save(nil) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Now \(StoreText.gold(current)). Every player pays the new price from their next store refresh.")
        }
    }

    private func save(_ price: Int?) {
        if let price, price <= 0 { return }
        Task { if await session.setPrice(kind: kind, id: id, price: price) { Haptics.success() } }
    }
}

extension View {
    /// Lets an administrator change this store price (kind: box, bundle, item, rarity or service).
    func adminPrice(kind: String, id: String, current: Int) -> some View {
        modifier(AdminPriceEdit(kind: kind, id: id, current: current))
    }
}

// MARK: Opening a bundle

/// A bundle just bought: its boxes are opened one by one from stock.
struct BundleRun: Identifiable {
    let id = UUID()
    var kind: BoxKind
    var total: Int
}

/// Opens a bought bundle box by box with the usual box-opening card ("box 2 of 5"), or skips to a summary of everything won.
/// Each box is opened from stock on the server, so boxes left when the app closes stay in the stock.
struct BundleOpenSequence: View {
    var run: BundleRun
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private let session = StoreSession.shared
    @State private var opened: OpenedBox?
    @State private var won: [BoxResult] = []
    @State private var done = false
    @State private var working = false

    private var count: Int { won.count }
    private var left: Int { max(0, run.total - count) }
    private func close() { if let c = popupClose { c() } else { systemDismiss() } }

    var body: some View {
        Group {
            if done {
                summary
            } else if let opened {
                VStack(spacing: Theme.Space.s) {
                    BoxResultCard(opened: opened, paidBoxesAllowed: false, onShort: {}, onNew: { (next: OpenedBox) in take(next) },
                                  onRevealed: { (_: UUID) in session.acknowledgeOpening() })
                    if left > 0 {
                        Button { skip() } label: { Text(working ? "Opening..." : "Skip to results (\(left) more)").frame(maxWidth: .infinity) }
                            .buttonStyle(SecondaryButtonStyle(size: .compact, fullWidth: true))
                            .disabled(working)
                            .accessibilityIdentifier("bundle-skip")
                    }
                }
                .centerSheetTitle("Box \(count) of \(max(run.total, count))")
            } else {
                VStack(spacing: Theme.Space.m) {
                    ProgressView()
                    Text(session.problem ?? "Opening your first box").textStyle(.caption).multilineTextAlignment(.center)
                    if session.problem != nil {
                        Button { close() } label: { Text("Close").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .task(id: run.id) { await first() }
    }

    private func first() async {
        guard opened == nil, !done else { return }
        session.acknowledgeOpening()
        if let out = await session.openBoxes(run.kind, count: 1, paidBoxesAllowed: false) { take(OpenedBox(opening: out)) }
    }

    private func take(_ next: OpenedBox) {
        won.append(contentsOf: next.opening.results)
        opened = next
    }

    /// Opens what is left of the bundle in one go (ten at most per call) and shows the haul.
    private func skip() {
        guard !working else { return }
        working = true
        session.acknowledgeOpening()
        Task {
            var todo: Int = min(left, session.state.count(run.kind))
            while todo > 0 {
                guard let out = await session.openBoxes(run.kind, count: min(10, todo), paidBoxesAllowed: false) else { break }
                session.acknowledgeOpening()
                won.append(contentsOf: out.results)
                todo -= out.results.count
            }
            working = false
            done = true
        }
    }

    private var summary: some View {
        let entries: [HaulEntry] = HaulEntry.group(won)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(won.count == 1 ? "1 box opened" : "\(won.count) boxes opened").textStyle(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ForEach(entries) { (e: HaulEntry) in
                        HStack(spacing: Theme.Space.s) {
                            Text(e.count > 1 ? "\(e.count)x" : "").textStyle(.caption, numeric: true).frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.title).textStyle(.body, weight: .semibold).lineLimit(1)
                                Text(e.line).textStyle(.caption, tint: e.rarity.tint)
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxHeight: 360)
            if session.state.count(run.kind) > 0 {
                Text("\(session.state.count(run.kind)) left in your stock.").textStyle(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle("Everything you won")
        .popupFooter { PopupFooter(cancel: "Back to the Store", action: "Done", onCancel: { close() }, onAction: { close() }) }
    }
}
