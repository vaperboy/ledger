import Foundation
import GameCore

enum SignInProvider: String, Codable, CaseIterable, Sendable {
    case apple, google
    var title: String { self == .apple ? "Apple" : "Google" }
}

enum PrivacyLevel: String, Codable, CaseIterable, Sendable {
    case everyone, friends, onlyMe
    var title: String {
        switch self {
        case .everyone: return "Public"
        case .friends: return "Friends"
        case .onlyMe: return "Private"
        }
    }
    var note: String {
        switch self {
        case .everyone: return "Anyone sees your name, level, badges and how many companies you run. Only friends see the companies."
        case .friends: return "Everyone sees your name, level and badges. Only friends see your companies and how many you run."
        case .onlyMe: return "Everyone sees your name only."
        }
    }
}

enum OnlineCompanyHealth: String, Codable, CaseIterable, Sendable {
    case new, struggling, steady, growing, thriving
    var title: String {
        switch self {
        case .new: return "Just opened"
        case .struggling: return "Struggling"
        case .steady: return "Steady"
        case .growing: return "Growing"
        case .thriving: return "Thriving"
        }
    }
}

struct OnlineCompany: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var trade: String
    var city: String
    var countryCode: String
    var health: OnlineCompanyHealth
}

enum FriendRelation: String, Codable, Sendable {
    case none, you, friend, requestSent, requestReceived, blocked
}

struct PlayerProfile: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var code: String
    var displayName: String
    var avatarColour: Int
    var countryCode: String
    var level: Int?
    var badges: [String]
    var privacy: PrivacyLevel
    var companyCount: Int?
    var companies: [OnlineCompany]?
    var gameWeek: Int?
    var tradesCompleted: Int?
    var relation: FriendRelation
    var avatarIcon: String? = nil
    var lastSeen: Double? = nil

    static let avatarColourCount = 8
    var initials: String {
        let parts: [Substring] = displayName.split(separator: " ")
        let letters: [Character] = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

struct ProfileUpdate: Codable, Sendable {
    var avatarColour: Int?
    var countryCode: String?
    var privacy: PrivacyLevel?
    var companies: [OnlineCompany]?
    var level: Int?
    var badges: [String]?
    var gameWeek: Int?
    var avatarIcon: String?
    init(avatarColour: Int? = nil, countryCode: String? = nil, privacy: PrivacyLevel? = nil,
         companies: [OnlineCompany]? = nil, level: Int? = nil, badges: [String]? = nil, gameWeek: Int? = nil, avatarIcon: String? = nil) {
        self.avatarColour = avatarColour; self.countryCode = countryCode; self.privacy = privacy
        self.companies = companies; self.level = level; self.badges = badges; self.gameWeek = gameWeek
        self.avatarIcon = avatarIcon
    }
}

enum UsernameResult: String, Codable, Equatable, Sendable {
    case ok, taken, invalid
}

struct OnlineAccount: Codable, Hashable, Sendable {
    var playerID: String
    var provider: SignInProvider?
    var createdAt: Date
}

struct FriendRequest: Codable, Hashable, Identifiable, Sendable {
    var id: String { player.id }
    var player: PlayerProfile
    var sentAt: Date
}

struct FriendsOverview: Codable, Sendable {
    var friends: [PlayerProfile]
    var incoming: [FriendRequest]
    var outgoing: [FriendRequest]
}

enum ReportReason: String, Codable, CaseIterable, Sendable {
    case offensiveName, impersonation, harassment, cheating, spam, other
    var title: String {
        switch self {
        case .offensiveName: return "Offensive name"
        case .impersonation: return "Pretending to be someone"
        case .harassment: return "Harassment"
        case .cheating: return "Cheating"
        case .spam: return "Spam"
        case .other: return "Something else"
        }
    }
}

enum OnlineError: Error, Equatable, LocalizedError, Sendable {
    case notSignedIn, notFound, blocked, alreadyFriends, requestPending, cannotTargetYourself, nameRejected(String), offline
    case adultRequired
    case notAdmin
    case cancelled
    case rejected(String)
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to use this."
        case .notFound: return "No player found."
        case .blocked: return "This player is blocked."
        case .alreadyFriends: return "You are already friends."
        case .requestPending: return "A request is already waiting."
        case .cannotTargetYourself: return "That is you."
        case .nameRejected(let why): return why
        case .offline: return "Could not reach the server."
        case .adultRequired: return "A profile needs the 18+ confirmation."
        case .notAdmin: return "This account is not an administrator."
        case .cancelled: return nil
        case .rejected(let why): return why
        }
    }
}

struct AccountStatus: Codable, Equatable, Sendable {
    var hasProfile: Bool
    var adultConfirmed: Bool
    var isAdmin: Bool
    var linkRewardGold: Int
    var linkRewardClaimed: Bool
    var fakePlayersRemoved: Bool? = nil
}

struct LinkRewardResult: Codable, Equatable, Sendable {
    var granted: Bool
    var gold: Int
    var reason: String
}

struct WorldPulse: Decodable, Equatable, Sendable {
    var online: Int
    var players: Int
}

struct FriendActivityItem: Decodable, Equatable, Identifiable, Sendable {
    var id: String
    var playerID: String
    var playerName: String
    var kind: String
    var count: Int?
    var label: String?
    var at: Double

    var sentence: String {
        switch kind {
        case "joined": return "\(playerName) joined Ledger."
        case "levelUp": return count.map { "\(playerName) reached level \($0)." } ?? "\(playerName) moved up a level."
        case "exchangeListed": return "\(playerName) listed a company on the stock exchange."
        case "auctionSold": return label.map { "\(playerName) sold \($0) at auction." } ?? "\(playerName) sold a piece at auction."
        case "officeOpened": return "\(playerName) opened an accountant office."
        case "tradeMilestone": return count.map { "\(playerName) completed \($0) trades." } ?? "\(playerName) reached a trading milestone."
        default: return "\(playerName) was active."
        }
    }
}

struct FriendPresence: Decodable, Equatable, Sendable {
    var playerID: String
    var lastSeen: Double?
    var online: Bool
}

struct FriendActivity: Decodable, Equatable, Sendable {
    var activity: [FriendActivityItem]
    var presence: [FriendPresence]
    static let empty = FriendActivity(activity: [], presence: [])
}

struct OnlineSettlementRow: Decodable, Equatable, Sendable {
    var id: String
    var amount: Double
    var currency: String
    var kind: String
    var label: String
    var companyKey: String?
    var units: Int?
    var unitPrice: Double?
    var meta: JSONValue

    private enum Keys: String, CodingKey { case id, amount, currency, kind, label, meta }

    init(id: String, amount: Double, currency: String, kind: String, label: String, meta: JSONValue = .null) {
        self.id = id; self.amount = amount; self.currency = currency; self.kind = kind; self.label = label; self.meta = meta
        companyKey = meta["companyKey"].string.isEmpty ? nil : meta["companyKey"].string
        units = meta["units"] == .null ? nil : Int(meta["units"].double)
        unitPrice = meta["unitPrice"] == .null ? nil : meta["unitPrice"].double
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let raw: JSONValue = (try? c.decodeIfPresent(JSONValue.self, forKey: .meta)) ?? .null
        self.init(id: try c.decode(String.self, forKey: .id), amount: try c.decode(Double.self, forKey: .amount),
                  currency: try c.decode(String.self, forKey: .currency), kind: try c.decode(String.self, forKey: .kind),
                  label: (try? c.decode(String.self, forKey: .label)) ?? "", meta: raw)
    }
}

protocol OnlineWorldService: Sendable {
    func heartbeat() async throws -> WorldPulse
    func registerDevice(_ device: String) async throws
    func friendActivity() async throws -> FriendActivity
    func pendingSettlements() async throws -> [OnlineSettlementRow]
    func acknowledgeSettlements(_ ids: [String]) async throws
}

protocol OnlineService: AdminService, OnlineWorldService, FriendPlayService, PushService, MarketplaceService, Sendable {
    var createsAccountsItself: Bool { get }
    func currentAccount() async -> OnlineAccount?
    func startSession(createIfMissing: Bool) async throws -> OnlineAccount
    func signIn(with provider: SignInProvider) async throws -> OnlineAccount
    func accountStatus() async throws -> AccountStatus
    func createProfile(adultConfirmed: Bool) async throws -> PlayerProfile
    func claimLinkReward() async throws -> LinkRewardResult
    func signOut() async
    func deleteAccount() async throws
    func exportMyData() async throws -> Data

    func myProfile() async throws -> PlayerProfile
    func updateMyProfile(_ update: ProfileUpdate) async throws -> PlayerProfile
    func usernameAvailable(_ name: String) async throws -> UsernameResult
    func claimUsername(_ name: String) async throws -> UsernameResult
    func profile(id: String) async throws -> PlayerProfile
    func profile(code: String) async throws -> PlayerProfile
    func searchPlayers(query: String) async throws -> [PlayerProfile]

    func friends() async throws -> FriendsOverview
    func sendFriendRequest(to playerID: String) async throws
    func acceptFriendRequest(from playerID: String) async throws
    func declineFriendRequest(from playerID: String) async throws
    func cancelFriendRequest(to playerID: String) async throws
    func removeFriend(_ playerID: String) async throws
    func blockPlayer(_ playerID: String) async throws
    func unblockPlayer(_ playerID: String) async throws
    func blockedPlayers() async throws -> [PlayerProfile]
    func report(_ playerID: String, reason: ReportReason, note: String) async throws
}

extension OnlineService {
    var createsAccountsItself: Bool { false }

    func startSession(createIfMissing: Bool) async throws -> OnlineAccount {
        guard let account = await currentAccount() else { throw OnlineError.notSignedIn }
        return account
    }
}
