import Foundation
import CryptoKit

// A sign-in the player started: Apple hands over a signed token, Google runs in the browser.
enum SignInRequest: Equatable, Sendable {
    case apple(idToken: String, nonce: String)
    case google

    var provider: SignInProvider {
        switch self {
        case .apple: return .apple
        case .google: return .google
        }
    }
}

// What the account's saved game is, read without opening it.
struct AccountGameInfo: Codable, Equatable, Sendable {
    var updatedAt: Date
    var week: Int?
    var title: String?
}

// An existing account found for a sign-in. It is held until the player decides whether to switch to it.
struct AccountSwitchOffer: Equatable, Sendable {
    var provider: SignInProvider
    var playerID: String
    var name: String?
    var savedGame: AccountGameInfo?
}

// The plain list of what deleting the account settles with other players.
struct DeletionPreview: Decodable, Equatable, Sendable {
    var items: [String]
}

// Sign-in, switching accounts, the game saved on the account, and deletion.
protocol AccountService: Sendable {
    func signIn(with provider: SignInProvider) async throws -> OnlineAccount
    func link(_ request: SignInRequest) async throws -> OnlineAccount
    func signInOptions() async -> [SignInProvider]
    func prepareSwitch(_ request: SignInRequest) async throws -> AccountSwitchOffer
    func completeSwitch() async throws -> OnlineAccount
    func cancelSwitch() async
    func accountGame() async throws -> String?
    func saveAccountGame(_ text: String) async throws
    func deletionPreview() async throws -> DeletionPreview
}

// The local stand-in links straight away and has no other accounts to switch to.
extension AccountService {
    func link(_ request: SignInRequest) async throws -> OnlineAccount { try await signIn(with: request.provider) }
    func signInOptions() async -> [SignInProvider] { SignInProvider.allCases }
    func prepareSwitch(_ request: SignInRequest) async throws -> AccountSwitchOffer { throw OnlineError.rejected("Switching accounts needs the server.") }
    func completeSwitch() async throws -> OnlineAccount { throw OnlineError.notSignedIn }
    func cancelSwitch() async {}
    func accountGame() async throws -> String? { nil }
    func saveAccountGame(_ text: String) async throws {}
    func deletionPreview() async throws -> DeletionPreview { DeletionPreview(items: []) }
}

// The nonce Apple signs into its token. Supabase checks the token against the raw value.
enum AppleNonce {
    static func make() -> String { PKCE.base64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })) }

    static func hash(_ raw: String) -> String {
        SHA256.hash(data: Data(raw.utf8)).map { (b: UInt8) -> String in String(format: "%02x", b) }.joined()
    }
}

// The game saved on the account: a header line, a small info line, then the game compressed.
enum AccountGameCodec {
    static let header = "ledger-save-1"

    static func pack(stateJSON: Data, info: AccountGameInfo) -> String? {
        guard let infoData = try? encoder().encode(info), let infoLine = String(data: infoData, encoding: .utf8),
              let packed = try? (stateJSON as NSData).compressed(using: .zlib) else { return nil }
        return header + "\n" + infoLine + "\n" + (packed as Data).base64EncodedString()
    }

    static func info(of text: String) -> AccountGameInfo? {
        let lines: [Substring] = text.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false)
        guard lines.count == 3, lines[0] == header else { return nil }
        return try? decoder().decode(AccountGameInfo.self, from: Data(lines[1].utf8))
    }

    // The game as the text a backup restore reads.
    static func unpack(_ text: String) -> String? {
        let lines: [Substring] = text.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false)
        guard lines.count == 3, lines[0] == header, let packed = Data(base64Encoded: String(lines[2])),
              let raw = try? (packed as NSData).decompressed(using: .zlib) else { return nil }
        return String(data: raw as Data, encoding: .utf8)
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
