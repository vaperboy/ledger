import SwiftUI
import GameCore
import Businesses
import Simulation

private struct ScreenBackdropKey: EnvironmentKey { static let defaultValue: String = "" }

extension EnvironmentValues {
    /// The backdrop id of the company or group a screen belongs to; empty when the screen has none.
    var screenBackdropID: String {
        get { self[ScreenBackdropKey.self] }
        set { self[ScreenBackdropKey.self] = newValue }
    }
}

extension View {
    /// Shows this backdrop behind every screen below, so all menus of a company carry its look.
    func screenBackdrop(_ reward: SeasonReward?) -> some View {
        environment(\.screenBackdropID, reward?.id ?? "")
    }
}

extension LookKit {
    /// A group entity shows the backdrop of its lead company.
    static func entityBackdrop(_ e: GameEngine, _ entity: GroupEntity) -> SeasonReward? {
        companyBackdrop(e, entity.companyID)
    }

    /// A board shows the backdrop of the first company it governs.
    static func boardBackdrop(_ e: GameEngine, _ key: String) -> SeasonReward? {
        guard let first = ManagerModel.boardCompanies(e.state, key: key).first else { return nil }
        return companyBackdrop(e, first.id)
    }
}

/// The company backdrop behind a whole screen: a still picture under a dark scrim that fades into the page, pinned to the
/// top of the screen so nested backgrounds line up. No blur and no animation, so it costs nothing per frame.
struct ScreenBackdropFill: View {
    var reward: SeasonReward

    var body: some View {
        GeometryReader { (g: GeometryProxy) in
            let top: CGFloat = g.frame(in: .global).minY
            let w: CGFloat = g.size.width
            let h: CGFloat = max(360, w * 1.25)
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(hex: LookKit.tint(reward)), Color(hex: LookKit.deep(reward))], startPoint: .top, endPoint: .bottom)
                    .opacity(0.5)
                picture(w, h)
                LinearGradient(stops: [.init(color: Color.black.opacity(0.5), location: 0), .init(color: Color.black.opacity(0.35), location: 0.4),
                                       .init(color: Theme.page.opacity(0.9), location: 1)], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: w, height: h)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.4), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .offset(y: -top)
            .frame(width: w, height: g.size.height, alignment: .top)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func picture(_ w: CGFloat, _ h: CGFloat) -> some View {
        #if canImport(UIKit)
        if let ui = ArtLibrary.catalogueImage(.backdrop, reward.id) {
            Image(uiImage: ui).resizable().interpolation(.medium).scaledToFill()
                .frame(width: w, height: h)
                .clipped()
        }
        #endif
    }
}
