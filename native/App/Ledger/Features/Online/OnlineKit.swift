import SwiftUI

/// Country names for profile codes (the game uses "UK" where the system says "GB").
enum OnlineCountry {
    static let codes: [String] = ["NO", "UK", "FR", "SE", "DK", "FI", "DE", "NL", "US", "CA", "ES", "IT", "PL", "IE", "JP", "BR", "IN", "AU", "ZA"]
    static func name(_ code: String) -> String { Locale.current.localizedString(forRegionCode: code == "UK" ? "GB" : code) ?? code }
}

/// A round avatar: the player's initials on one of eight muted colours.
struct ProfileAvatar: View {
    var initials: String
    var colour: Int
    var size: CGFloat = 44

    static let colours: [Color] = [Color(hex: 0xD6B889), Color(hex: 0x86B4A0), Color(hex: 0x7F9BC4), Color(hex: 0xC48CB8),
                                   Color(hex: 0xCF9A6A), Color(hex: 0xA8B88A), Color(hex: 0xC8706A), Color(hex: 0x9A94C4)]

    var body: some View {
        let fill: Color = Self.colours[((colour % Self.colours.count) + Self.colours.count) % Self.colours.count]
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .serif))
            .foregroundStyle(Theme.accentInk)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .accessibilityHidden(true)
    }
}

/// How a company is doing, as a coloured word.
extension OnlineCompanyHealth {
    var tint: Color {
        switch self {
        case .thriving, .growing: return Theme.gain
        case .steady, .new: return Theme.inkSoft
        case .struggling: return Theme.loss
        }
    }
}

extension PlayerProfile {
    /// "Norway · Level 14" with whatever this viewer is allowed to see.
    var subline: String {
        var parts: [String] = [OnlineCountry.name(countryCode)]
        if let l = level { parts.append("Level \(l)") }
        return parts.joined(separator: " · ")
    }
}

/// One player in a list: avatar, name, a grey line and an optional trailing view.
struct PlayerRow<Trailing: View>: View {
    var player: PlayerProfile
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            PlayerAvatar(player: player, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.displayName).textStyle(.headline).lineLimit(1)
                Text(player.subline).textStyle(.caption).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            trailing()
        }
        .padding(.vertical, Theme.Space.s).frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

/// A row of a card made of icon, title, grey note and value, used by the account and profile screens.
struct OnlineLine: View {
    var glyph: String
    var title: String
    var note: String = ""
    var value: String = ""
    var tint: Color = Theme.gold
    var chevron = false

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            LedgerGlyph(glyph: glyph, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textStyle(.headline).fixedSize(horizontal: false, vertical: true)
                if !note.isEmpty { Text(note).textStyle(.caption).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: Theme.Space.s)
            if !value.isEmpty { Text(value).textStyle(.body, tint: Theme.inkSoft) }
            if chevron { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint) }
        }
        .padding(.vertical, Theme.Space.s).frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A titled card: capitals label, rows inside, optional grey footer.
struct OnlineGroup<Content: View>: View {
    var title: String
    var footer: String = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if !title.isEmpty { Text(title).capsLabel(Theme.inkFaint).padding(.horizontal, Theme.Space.m) }
            Card(padding: 0) {
                VStack(alignment: .leading, spacing: 0) { content() }.padding(.horizontal, Theme.Space.m)
            }
            if !footer.isEmpty {
                Text(footer).textStyle(.caption).padding(.horizontal, Theme.Space.m).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A list of companies in words: name, trade and city, and how it is doing.
struct OnlineCompanyList: View {
    var companies: [OnlineCompany]

    var body: some View {
        ForEach(Array(companies.enumerated()), id: \.element.id) { (i: Int, c: OnlineCompany) in
            if i > 0 { Hairline() }
            HStack(spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).textStyle(.headline).lineLimit(2)
                    Text(c.trade + " · " + c.city + ", " + OnlineCountry.name(c.countryCode)).textStyle(.caption).lineLimit(2)
                }
                Spacer(minLength: Theme.Space.s)
                Text(c.health.title).textStyle(.body, tint: c.health.tint)
            }
            .padding(.vertical, Theme.Space.s).frame(minHeight: 52)
            .accessibilityElement(children: .combine)
        }
    }
}
