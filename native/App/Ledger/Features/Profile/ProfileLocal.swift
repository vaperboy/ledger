import SwiftUI

@MainActor
final class ProfileLocal: ObservableObject {
    static let shared = ProfileLocal()
    private static let nameKey = "ledger.profile.name"

    @Published private(set) var name: String

    private init() {
        name = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
    }

    func setName(_ value: String) {
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
