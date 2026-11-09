import Foundation

// The contract between the app and the online side: accounts, profiles and friends. The app only ever talks to `OnlineService`;
// `MockOnlineService` stands in for the real server until one exists, and has the same shape (async, Codable, errors by kind).
// Other features (the supplier marketplace) add their own protocol in their own file and the mock conforms in an extension.

/// How the player signed in. Guests have no provider and no server profile.
enum SignInProvider: String, Codable, CaseIterable, Sendable {
    case apple, google
    var title: String { self == .apple ? "Apple" : "Google" }
}

/// Who can see what on a profile, as the server enforces it (the view only shows what it was given):
/// Public: everyone sees name, level, badges and company count, friends also see the companies and how they are doing.
/// Friends: everyone sees name, level and badges; only friends see the company count and the companies. Private: the name only, to everyone.
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

/// How a company is doing, in words (never figures: other players do not see another player's books).
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

/// A company as other players see it: a name, what it does and where, and how it is doing in words.
struct OnlineCompany: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    /// A trade in plain words ("Bakery", "Dental clinic").
    var trade: String
    var city: String
    var countryCode: String
    var health: OnlineCompanyHealth
}

/// The viewer's relationship to a profile.
enum FriendRelation: String, Codable, Sendable {
    case none, you, friend, requestSent, requestReceived, blocked
}

/// A player as the viewer is allowed to see them. A nil `level`, `companyCount`, `companies`, `gameWeek` or `tradesCompleted` is hidden from this
/// viewer by the player's privacy level. `gameWeek` is the week the player's own game has reached (players are on different dates).
struct PlayerProfile: Codable, Hashable, Identifiable, Sendable {
    var id: String
    /// The shareable code, "K7M-4PQ2".
    var code: String
    var displayName: String
    /// Index into the avatar colours (0..<`PlayerProfile.avatarColourCount`).
    var avatarColour: Int
    var countryCode: String
    var level: Int?
    var badges: [String]
    var privacy: PrivacyLevel
    var companyCount: Int?
    var companies: [OnlineCompany]?
    /// True for a computer player standing in for a person.
    var isSimulated: Bool
    var gameWeek: Int?
    var tradesCompleted: Int?
    var relation: FriendRelation

    static let avatarColourCount = 8
    var initials: String {
        let parts: [Substring] = displayName.split(separator: " ")
        let letters: [Character] = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

/// What the player may change on their own profile; nil leaves a field as it is.
struct ProfileUpdate: Codable, Sendable {
    var displayName: String?
    var avatarColour: Int?
    var countryCode: String?
    var privacy: PrivacyLevel?
    var companies: [OnlineCompany]?
    var level: Int?
    var badges: [String]?
    var gameWeek: Int?
    init(displayName: String? = nil, avatarColour: Int? = nil, countryCode: String? = nil, privacy: PrivacyLevel? = nil,
         companies: [OnlineCompany]? = nil, level: Int? = nil, badges: [String]? = nil, gameWeek: Int? = nil) {
        self.displayName = displayName; self.avatarColour = avatarColour; self.countryCode = countryCode; self.privacy = privacy
        self.companies = companies; self.level = level; self.badges = badges; self.gameWeek = gameWeek
    }
}

/// The signed-in account (what the provider vouched for; no password ever reaches the app).
struct OnlineAccount: Codable, Hashable, Sendable {
    var playerID: String
    var provider: SignInProvider
    var createdAt: Date
}

/// A pending friend request in either direction.
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
        }
    }
}

/// Everything the app asks of the online side. Methods that need an account throw `.notSignedIn` for a guest.
/// Single-player never needs any of it: a failed or missing service must leave the offline game untouched.
protocol OnlineService: Sendable {
    // Account and session
    func currentAccount() async -> OnlineAccount?
    /// Signs in with Apple or Google (the mock simulates it). A guest who signs in keeps nothing else to merge: the profile is new.
    func signIn(with provider: SignInProvider) async throws -> OnlineAccount
    /// Same as `signIn`, named for a guest who adds an account later.
    func linkAccount(with provider: SignInProvider) async throws -> OnlineAccount
    func signOut() async
    /// Removes the account, its profile, friendships and requests. Not reversible.
    func deleteAccount() async throws
    /// Everything the server holds about the player, as JSON.
    func exportMyData() async throws -> Data

    // Profiles
    func myProfile() async throws -> PlayerProfile
    func updateMyProfile(_ update: ProfileUpdate) async throws -> PlayerProfile
    func profile(id: String) async throws -> PlayerProfile
    func profile(code: String) async throws -> PlayerProfile
    /// By display name (substring) or profile code; never returns the player or players who blocked them.
    func searchPlayers(query: String) async throws -> [PlayerProfile]

    // Friends
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
