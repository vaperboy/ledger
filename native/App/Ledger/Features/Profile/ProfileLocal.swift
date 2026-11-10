import SwiftUI

@MainActor
final class ProfileLocal: ObservableObject {
    static let shared = ProfileLocal()
    private static let nameKey = "ledger.profile.name"

    private static let showcaseKey = "ledger.profile.showcase"
    static let showcaseSlots = 3

    @Published private(set) var name: String
    @Published private(set) var showcase: [String]
    @Published var nameTaken = false

    private init() {
        name = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
        showcase = UserDefaults.standard.stringArray(forKey: Self.showcaseKey) ?? []
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
