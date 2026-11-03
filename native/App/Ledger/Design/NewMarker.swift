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
                withAnimation(.easeOut(duration: 0.7)) { pulsed = true }
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

/// A marker tied to one item: shown while the item is new, cleared after it has been on screen for about a second.
struct NewMarker: View {
    var app: PhoneApp
    var id: String
    var style: NewMarkerStyle = .dot
    var important: Bool = false
    @EnvironmentObject var store: GameStore

    var body: some View {
        if store.isNew(app, id) {
            NewMarkerShape(style: style, important: important)
                .transition(.opacity)
                .task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    if !Task.isCancelled { withAnimation(.easeOut(duration: 0.25)) { store.markItemSeen(app, id) } }
                }
        }
    }
}

extension View {
    /// Puts the item's marker in a corner (dot for list rows, capsule for cards).
    func newMarker(_ app: PhoneApp, _ id: String, style: NewMarkerStyle = .dot, important: Bool = false, alignment: Alignment = .topTrailing) -> some View {
        overlay(alignment: alignment) { NewMarker(app: app, id: id, style: style, important: important).padding(style == .dot ? 6 : 4) }
    }

    /// A marker that is simply on or off (a standing alert, a tab that holds something new).
    func flagMarker(_ on: Bool, style: NewMarkerStyle = .dot, important: Bool = false, alignment: Alignment = .topTrailing) -> some View {
        overlay(alignment: alignment) {
            if on { NewMarkerShape(style: style, important: important).padding(style == .dot ? 6 : 4) }
        }
    }
}
