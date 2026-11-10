import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OutsideScreen: ViewModifier {
    var palette: OutsidePalette

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .swipeBackEnabled()
            .toolbar(.hidden, for: .navigationBar)
            .ledgerBackground()
            .environment(\.outsidePalette, palette)
            .preferredColorScheme(palette.isLight ? .light : .dark)
            .modifier(LightStatusBar(on: palette.isLight))
    }
}

extension View {
    func outsideScreen(_ palette: OutsidePalette) -> some View { modifier(OutsideScreen(palette: palette)) }
}

struct LightStatusBar: ViewModifier {
    var on: Bool
    @Environment(\.markerPageActive) private var activePage
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { StatusBarScheme.shared.set(id, on && activePage) }
            .onChange(of: activePage) { _, now in StatusBarScheme.shared.set(id, on && now) }
            .onChange(of: on) { _, now in StatusBarScheme.shared.set(id, now && activePage) }
            .onDisappear { StatusBarScheme.shared.set(id, false) }
    }
}

@MainActor
final class StatusBarScheme: ObservableObject {
    static let shared = StatusBarScheme()
    @Published private(set) var light = false
    private var shown: Set<UUID> = []

    func set(_ id: UUID, _ on: Bool) {
        if on { shown.insert(id) } else { shown.remove(id) }
        let now: Bool = !shown.isEmpty
        if now != light { light = now }
    }
}

struct OutsideBack: View {
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var body: some View {
        RoundBackButton { dismiss() }
    }
}
