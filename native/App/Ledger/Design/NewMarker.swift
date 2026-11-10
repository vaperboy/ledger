import SwiftUI

enum NewMarkerStyle { case dot, capsule }

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

private struct MarkerBudgetScope: ViewModifier {
    @State private var budget = MarkerBudget()
    func body(content: Content) -> some View { content.environment(\.markerBudget, budget) }
}

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
    func markerBudget() -> some View { modifier(MarkerBudgetScope()) }

    func newGroupMarker(_ app: PhoneApp, _ ids: [String], style: NewMarkerStyle = .dot, important: Bool = false, rank: Int? = nil, alignment: Alignment = .topTrailing) -> some View {
        overlay(alignment: alignment) { NewGroupMarker(app: app, ids: ids, style: style, important: important, rank: rank).padding(style == .dot ? 6 : 4) }
    }

    func newMarker(_ app: PhoneApp, _ id: String, style: NewMarkerStyle = .dot, important: Bool = false, rank: Int? = nil, alignment: Alignment = .topTrailing) -> some View {
        overlay(alignment: alignment) { NewMarker(app: app, id: id, style: style, important: important, rank: rank).padding(style == .dot ? 6 : 4) }
    }

    func flagMarker(_ on: Bool, style: NewMarkerStyle = .dot, important: Bool = false, alignment: Alignment = .topTrailing) -> some View {
        overlay(alignment: alignment) {
            if on { NewMarkerShape(style: style, important: important).padding(style == .dot ? 6 : 4) }
        }
    }
}
