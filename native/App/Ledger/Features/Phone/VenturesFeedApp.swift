import SwiftUI
import GameCore

/// The standalone Ventures phone app: its own header and the Ventures palette around `VenturesHome`, the same portfolio that Projects shows
/// in place. It adds no logic of its own.
struct VenturesFeedApp: View {
    private var P: OutsidePalette { .ventures }
    @EnvironmentObject var store: GameStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    OutsideBack()
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text("Ventures").textStyle(.title).accessibilityAddTraits(.isHeader)
                        Text("Startups, funds and stakes").textStyle(.caption)
                    }
                    Spacer(minLength: 0)
                }
                VenturesHome()
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden).noSidewaysDrag()
        .outsideScreen(P)
        .accessibilityIdentifier("ventures-app")
    }
}
