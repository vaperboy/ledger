import SwiftUI

@MainActor
final class ProfileLocal: ObservableObject {
    static let shared = ProfileLocal()
    private static let nameKey = "ledger.profile.name"

    private static let showcaseKey = "ledger.profile.showcase"
    static let showcaseSlots = 3
    private static let avatarKey = "ledger.profile.avatar"
    private static let badgesKey = "ledger.profile.cardBadges"
    static let badgeSlots = 3

    @Published private(set) var name: String
    @Published private(set) var showcase: [String]
    @Published private(set) var avatar: AvatarLook
    @Published private(set) var hasAvatar: Bool
    @Published private(set) var cardBadges: [String]
    @Published var nameTaken = false

    private init() {
        let storedName: String = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
        name = storedName
        showcase = UserDefaults.standard.stringArray(forKey: Self.showcaseKey) ?? []
        let saved: AvatarLook? = UserDefaults.standard.string(forKey: Self.avatarKey).flatMap { (c: String) -> AvatarLook? in AvatarLook(code: c) }
        hasAvatar = saved != nil
        avatar = saved ?? AvatarLook.generated(for: storedName)
        // The icon a player used to wear becomes a badge on the card.
        cardBadges = UserDefaults.standard.stringArray(forKey: Self.badgesKey) ?? AvatarModel.shared.equipped.map { (id: String) -> [String] in [id] } ?? []
    }

    func setAvatar(_ look: AvatarLook) {
        avatar = look
        hasAvatar = true
        UserDefaults.standard.set(look.code, forKey: Self.avatarKey)
    }

    func setCardBadges(_ ids: [String]) {
        cardBadges = Array(ids.prefix(Self.badgeSlots))
        UserDefaults.standard.set(cardBadges, forKey: Self.badgesKey)
    }

    /// The text stored with the online profile so other players see this look.
    func shareCode(worn: [String: String]) -> String {
        ProfileLookCode.encode(avatar: avatar, worn: worn, badges: cardBadges)
    }

    func setShowcase(_ ids: [String]) {
        showcase = Array(ids.prefix(Self.showcaseSlots))
        UserDefaults.standard.set(showcase, forKey: Self.showcaseKey)
    }

    func setName(_ value: String) {
        nameTaken = false
        name = value
        UserDefaults.standard.set(value, forKey: Self.nameKey)
    }
}

struct ProfilePicture: View {
    var name: String
    var size: CGFloat

    var body: some View {
        PlayerAvatar(name: name, isYou: true, size: size)
    }
}
