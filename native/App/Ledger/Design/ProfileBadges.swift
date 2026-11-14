import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Badges that cannot be bought: given to the creator (admin accounts) and to beta testers (accounts that redeemed a beta key).
/// Art files badge.creator.png and badge.beta.png in the art folder; a drawn symbol shows until they exist.
enum ProfileBadge: String, CaseIterable {
    case creator = "badge.creator"
    case beta = "badge.beta"

    var title: String { self == .creator ? "Creator" : "Beta tester" }
    var symbol: String { self == .creator ? "hammer.fill" : "flask.fill" }
    var tint: Color { self == .creator ? Theme.gold : Color(hex: 0x6FC3B8) }

    /// Ids for the badges an account holds, in the order they are shown.
    static func ids(isAdmin: Bool, isBeta: Bool) -> [String] {
        var out: [String] = []
        if isAdmin { out.append(ProfileBadge.creator.rawValue) }
        if isBeta { out.append(ProfileBadge.beta.rawValue) }
        return out
    }

    /// The exclusive badges in a list of shared profile badge ids and texts.
    static func exclusive(in list: [String]) -> [String] {
        ProfileBadge.allCases.map { (b: ProfileBadge) -> String in b.rawValue }.filter { (id: String) -> Bool in list.contains(id) }
    }
}

struct ProfileBadgeMark: View {
    var badge: ProfileBadge
    var size: CGFloat = 22

    var body: some View {
        picture
            .frame(width: size, height: size)
            .accessibilityLabel(badge.title)
            .accessibilityIdentifier(badge.rawValue)
    }

    @ViewBuilder private var picture: some View {
        #if canImport(UIKit)
        if let ui = ArtLibrary.droppedImage(badge.rawValue) {
            Image(uiImage: ui).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            symbol
        }
        #else
        symbol
        #endif
    }

    private var symbol: some View {
        Image(systemName: badge.symbol).font(.system(size: size * 0.7, weight: .semibold)).foregroundStyle(badge.tint)
    }
}

/// The badges shown beside a name.
struct ProfileBadgeRow: View {
    var ids: [String]

    var body: some View {
        ForEach(ids, id: \.self) { (id: String) in
            if let b = ProfileBadge(rawValue: id) { ProfileBadgeMark(badge: b) }
        }
    }
}
