import SwiftUI
import GameCore
import Businesses
import Simulation

private struct HidesRootBackKey: EnvironmentKey { static let defaultValue: Bool = false }
extension EnvironmentValues {
    var hidesRootBack: Bool {
        get { self[HidesRootBackKey.self] }
        set { self[HidesRootBackKey.self] = newValue }
    }
}

/// The Store tab: the one home of plans, gold, boxes and the season pass.
struct CustomTabView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        NavigationStack(path: Binding<[NavRoute]>(get: { store.customPath }, set: { store.setCustomPath($0) })) {
            StoreApp()
                .environment(\.hidesRootBack, true)
                .id(store.rootToken(.custom))
                .companyRouteDestinations()
        }
        .accessibilityIdentifier("store-tab")
    }
}
