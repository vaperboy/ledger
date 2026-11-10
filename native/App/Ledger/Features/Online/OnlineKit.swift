import SwiftUI

enum OnlineCountry {
    static let codes: [String] = ["NO", "UK", "FR", "SE", "DK", "FI", "DE", "NL", "US", "CA", "ES", "IT", "PL", "IE", "JP", "BR", "IN", "AU", "ZA"]
    static func name(_ code: String) -> String { Locale.current.localizedString(forRegionCode: code == "UK" ? "GB" : code) ?? code }
}

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
    var subline: String {
        var parts: [String] = [OnlineCountry.name(countryCode)]
        if let l = level { parts.append("Level \(l)") }
        if let t = lastSeen { parts.append(Self.seenText(t)) }
        return parts.joined(separator: " · ")
    }

    private static func seenText(_ t: Double) -> String {
        let s: Double = max(0, Date().timeIntervalSince1970 - t)
        if s < 300 { return "Online now" }
        if s < 3_600 { return "Active \(Int(s / 60)) min ago" }
        if s < 86_400 { return "Active \(Int(s / 3_600)) h ago" }
        return "Active \(Int(s / 86_400)) d ago"
    }
}

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

enum HallOfFameBadge {
    static let name = "Hall of Fame"
}

struct HallOfFameMark: View {
    var body: some View {
        LedgerGlyph(glyph: Glyph.achievements, size: Theme.Icon.small, tint: Theme.gold)
            .accessibilityLabel(HallOfFameBadge.name)
            .accessibilityIdentifier("hall-of-fame-mark")
    }
}

struct OnlineCompanyList: View {
    @EnvironmentObject var store: GameStore
    var companies: [OnlineCompany]

    var body: some View {
        ForEach(Array(companies.enumerated()), id: \.element.id) { (i: Int, c: OnlineCompany) in
            if i > 0 { Hairline() }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).textStyle(.headline).lineLimit(2)
                        Text(c.trade + " · " + c.city + ", " + OnlineCountry.name(c.countryCode)).textStyle(.caption).lineLimit(2)
                    }
                    Spacer(minLength: Theme.Space.s)
                    Text(c.health.title).textStyle(.body, tint: c.health.tint)
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: Theme.Space.s) {
                    Button("Visit") { Haptics.tap(); store.openMarket(tab: .companies) }
                        .buttonStyle(TertiaryButtonStyle(size: .compact))
                        .accessibilityIdentifier("friend-company-visit-\(c.id)")
                    Button("Trade") { Haptics.tap(); store.openMarket(tab: .exchange) }
                        .buttonStyle(TertiaryButtonStyle(size: .compact))
                        .accessibilityIdentifier("friend-company-trade-\(c.id)")
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, Theme.Space.s).frame(minHeight: 52)
        }
    }
}

struct InviteAcceptCard: View {
    @Environment(OnlineSession.self) private var online
    @State private var found: PlayerProfile?
    @State private var message = ""
    @State private var working = false

    var body: some View {
        if let code = online.pendingInvite {
            OnlineGroup(title: "Friend invite", footer: message) {
                if !online.isSignedIn {
                    OnlineLine(glyph: Glyph.person, title: "Link an account to accept", note: "Invite code " + code)
                } else if let p = found {
                    PlayerRow(player: p) { EmptyView() }
                    Hairline()
                    Button { Task { await add(p) } } label: {
                        OnlineLine(glyph: Glyph.people, title: "Add " + p.displayName, note: "Sends a friend request", chevron: true)
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(working)
                    .accessibilityIdentifier("invite-accept")
                } else {
                    OnlineLine(glyph: Glyph.person, title: "Looking up the invite", note: "Code " + code)
                }
                Hairline()
                Button { online.dismissInvite() } label: {
                    Text("Not now").textStyle(.body, tint: Theme.inkSoft).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PressableStyle())
            }
            .task(id: code + (online.isSignedIn ? "+" : "-")) { await lookUp(code) }
        }
    }

    private func lookUp(_ code: String) async {
        guard online.isSignedIn else { found = nil; return }
        message = ""
        do {
            found = try await online.service.profile(code: code)
        } catch {
            found = nil
            message = (error as? LocalizedError)?.errorDescription ?? "That invite did not work."
        }
    }

    private func add(_ p: PlayerProfile) async {
        working = true
        defer { working = false }
        do {
            try await online.service.sendFriendRequest(to: p.id)
            online.dismissInvite()
        } catch OnlineError.alreadyFriends {
            online.dismissInvite()
        } catch OnlineError.requestPending {
            online.dismissInvite()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "Could not send the request. Try again."
        }
    }
}
