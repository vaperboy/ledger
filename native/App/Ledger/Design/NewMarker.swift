import SwiftUI

/// What a marker looks like: a small dot (list rows) or a "NEW" capsule (cards and headers).
enum NewMarkerStyle { case dot, capsule }

/// The marker itself, in the palette of the app it sits in. `important` fills it with the app's alert colour and a tiny exclamation mark.
/// Pulses once, very softly, the first time it appears (not with Reduce Motion).
struct NewMarkerShape: View {
    var style: NewMarkerStyle = .dot
    var important: Bool = false
    @Environment(\.outsidePalette) private var P
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsed = false

    private var fill: Color { important ? P.loss : P.accent }

    var body: some View {
        mark
            .scaleEffect(pulsed ? 1.0 : 1.18)
            .onAppear {
                if reduceMotion { pulsed = true; return }
                Motion.animate(Motion.revealAnimation) { pulsed = true }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(important ? "Important" : "New")
    }

    @ViewBuilder private var mark: some View {
        switch style {
        case .dot:
            if important {
                Text("!").font(.system(size: 7, weight: .heavy)).foregroundStyle(P.onAccent)
                    .frame(width: 11, height: 11).background(Circle().fill(fill))
            } else {
                Circle().fill(fill).frame(width: 8, height: 8)
            }
        case .capsule:
            HStack(spacing: 2) {
                if important { Text("!").font(.system(size: 8, weight: .heavy)) }
                Text("NEW").font(.system(size: 8.5, weight: .bold)).tracking(0.6)
            }
            .foregroundStyle(P.onAccent)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(fill))
        }
    }
}

/// Markers per screen are capped (about 8): the first ones drawn keep their place, or an explicit `rank` (0 is most important) decides.
final class MarkerBudget {
    static let cap: Int = 8
    private var claimed: [String] = []
    func allows(_ key: String, rank: Int?) -> Bool {
        if let r = rank { return r < Self.cap }
        if claimed.contains(key) { return true }
        if claimed.count >= Self.cap { return false }
        claimed.append(key)
        return true
    }
    func release(_ key: String) { claimed.removeAll { (k: String) -> Bool in k == key } }
}

private struct MarkerBudgetKey: EnvironmentKey { static let defaultValue: MarkerBudget? = nil }
/// False while the page holding a marker is not the selected one (a tab or segment that is alive but off screen): its markers are not cleared then.
private struct MarkerPageActiveKey: EnvironmentKey { static let defaultValue: Bool = true }
extension EnvironmentValues {
    var markerBudget: MarkerBudget? {
        get { self[MarkerBudgetKey.self] }
        set { self[MarkerBudgetKey.self] = newValue }
    }
    var markerPageActive: Bool {
        get { self[MarkerPageActiveKey.self] }
        set { self[MarkerPageActiveKey.self] = newValue }
    }
}

/// Gives a screen its own marker budget (see `MarkerBudget`).
private struct MarkerBudgetScope: ViewModifier {
    @State private var budget = MarkerBudget()
    func body(content: Content) -> some View { content.environment(\.markerBudget, budget) }
}

/// A marker tied to one item: shown while the item is new, cleared after it has been on screen for about a second.
struct NewMarker: View {
    var app: PhoneApp
    var id: String
    var style: NewMarkerStyle = .dot
    var important: Bool = false
    var rank: Int? = nil
    @EnvironmentObject var store: GameStore
    @Environment(\.markerBudget) var budget: MarkerBudget?
    @Environment(\.markerPageActive) var pageActive: Bool

    private var key: String { app.rawValue + "." + id }

    var body: some View {
        if store.isNew(app, id) && (budget?.allows(key, rank: rank) ?? true) {
            NewMarkerShape(style: style, important: important)
                .transition(.opacity)
                .task(id: pageActive) {
                    guard pageActive else { return }
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    if !Task.isCancelled {
                        Motion.animate(Motion.quickAnimation) { store.markItemSeen(app, id) }
                        budget?.release(key)
                    }
                }
        }
    }
}

/// One marker for a group of items (an account's messages, a company's orders): shown while any is new, clears them all after a second.
struct NewGroupMarker: View {
    var app: PhoneApp
    var ids: [String]
    var style: NewMarkerStyle = .dot
    var important: Bool = false
    var rank: Int? = nil
    @EnvironmentObject var store: GameStore
    @Environment(\.markerBudget) var budget: MarkerBudget?
    @Environment(\.markerPageActive) var pageActive: Bool

    var body: some View {
        let live: [String] = ids.filter { (id: String) -> Bool in store.isNew(app, id) }
        let key: String = app.rawValue + ".g." + (live.first ?? "")
        if !live.isEmpty && (budget?.allows(key, rank: rank) ?? true) {
            NewMarkerShape(style: style, important: important)
                .transition(.opacity)
                .task(id: pageActive) {
                    guard pageActive else { return }
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    if !Task.isCancelled {
                        Motion.animate(Motion.quickAnimation) { for id in live { store.markItemSeen(app, id) } }
                        budget?.release(key)
                    }
                }
        }
    }
}

extension View {
    /// Caps this screen's in-app markers at about eight (the first drawn, or the lowest `rank`).
    func markerBudget() -> some View { modifier(MarkerBudgetScope()) }

    /// A marker for a group of item ids (see `NewGroupMarker`).
    func newGroupMarker(_ app: PhoneApp, _ ids: [String], style: NewMarkerStyle = .dot, important: Bool = false, rank: Int? = nil, alignment: Alignment = .topTrailing) -> some View {
        overlay(alignment: alignment) { NewGroupMarker(app: app, ids: ids, style: style, important: important, rank: rank).padding(style == .dot ? 6 : 4) }
    }

    /// Puts the item's marker in a corner (dot for list rows, capsule for cards).
    func newMarker(_ app: PhoneApp, _ id: String, style: NewMarkerStyle = .dot, important: Bool = false, rank: Int? = nil, alignment: Alignment = .topTrailing) -> some View {
        overlay(alignment: alignment) { NewMarker(app: app, id: id, style: style, important: important, rank: rank).padding(style == .dot ? 6 : 4) }
    }

    /// A marker that is simply on or off (a standing alert, a tab that holds something new).
    func flagMarker(_ on: Bool, style: NewMarkerStyle = .dot, important: Bool = false, alignment: Alignment = .topTrailing) -> some View {
        overlay(alignment: alignment) {
            if on { NewMarkerShape(style: style, important: important).padding(style == .dot ? 6 : 4) }
        }
    }
}
