import SwiftUI
import UIKit

@MainActor
final class ProfileLocal: ObservableObject {
    static let shared = ProfileLocal()
    private static let nameKey = "ledger.profile.name"
    private static let side: CGFloat = 400

    @Published private(set) var photo: UIImage?
    @Published private(set) var name: String

    private static var photoURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("profile-photo.jpg")
    }

    private init() {
        name = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
        if let url = Self.photoURL, let data = try? Data(contentsOf: url) { photo = UIImage(data: data) }
    }

    func setName(_ value: String) {
        name = value
        UserDefaults.standard.set(value, forKey: Self.nameKey)
    }

    func setPhoto(data: Data) {
        guard let source = UIImage(data: data) else { return }
        let size: CGSize = CGSize(width: Self.side, height: Self.side)
        let scale: CGFloat = max(size.width / source.size.width, size.height / source.size.height)
        let drawn: CGSize = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let format: UIGraphicsImageRendererFormat = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image: UIImage = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
        }
        photo = image
        guard let url = Self.photoURL, let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? jpeg.write(to: url, options: .atomic)
    }

    func removePhoto() {
        photo = nil
        if let url = Self.photoURL { try? FileManager.default.removeItem(at: url) }
    }
}

struct ProfilePicture: View {
    @ObservedObject private var local = ProfileLocal.shared
    var name: String
    var size: CGFloat

    var body: some View {
        if let photo = local.photo {
            Image(uiImage: photo)
                .resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                .accessibilityHidden(true)
        } else {
            PlayerAvatar(name: name, isYou: true, size: size)
        }
    }
}
