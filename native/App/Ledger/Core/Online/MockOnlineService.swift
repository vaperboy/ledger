import Foundation
import Businesses

/// The stand-in for the online server: about forty sample players in memory, the signed-in player's own state saved in UserDefaults.
/// It enforces profile privacy and the friend rules the way the real server will, so the screens never have to.
/// Other features add their own service protocol and conform this actor to it in an extension, keeping their state through
/// `extensionData(for:)` / `setExtensionData(_:for:)` (extensions cannot add stored properties).
actor MockOnlineService: OnlineService {
    private struct Report: Codable { var playerID: String; var reason: ReportReason; var note: String; var at: Date }

    private struct State: Codable {
        var account: OnlineAccount?
        var me: PlayerProfile?
        var friendIDs: [String] = []
        var incoming: [String: Date] = [:]
        var outgoing: [String: Date] = [:]
        var blocked: [String] = []
        var reports: [Report] = []
        var extra: [String: Data] = [:]
    }

    private let defaults: UserDefaults
    private let key: String
    private let latency: UInt64
    private let roster: [PlayerProfile]
    private var state: State

    init(suiteName: String? = nil, key: String = "ledger.online.mock.v1", latencyMilliseconds: UInt64 = 350) {
        let defaults: UserDefaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.defaults = defaults
        self.key = key
        self.latency = latencyMilliseconds * 1_000_000
        self.roster = SampleRoster.players()
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(State.self, from: data) { state = saved } else { state = State() }
    }

    // MARK: Account

    func currentAccount() async -> OnlineAccount? { state.account }

    func signIn(with provider: SignInProvider) async throws -> OnlineAccount {
        await pause()
        let existing: String? = state.account?.playerID ?? state.me?.id
        let account = OnlineAccount(playerID: existing ?? "me-" + UUID().uuidString.prefix(8).lowercased(), provider: provider, createdAt: state.account?.createdAt ?? Date())
        if existing == nil { createMyProfile(account) }
        state.account = account
        if state.extra["testFriends.v1"] == nil {   // the test players start as friends once, so their friends-only profiles can be read
            for id in SampleRoster.testPlayerIDs where !state.friendIDs.contains(id) && !state.blocked.contains(id) { state.friendIDs.append(id) }
            state.extra["testFriends.v1"] = Data([1])
        }
        save()
        return account
    }

    func linkAccount(with provider: SignInProvider) async throws -> OnlineAccount { try await signIn(with: provider) }

    func signOut() async { state.account = nil; save() }

    func deleteAccount() async throws {
        await pause()
        try requireAccount()
        state = State()
        save()
    }

    func exportMyData() async throws -> Data {
        await pause()
        try requireAccount()
        struct Export: Codable {
            var account: OnlineAccount?; var profile: PlayerProfile?; var friends: [String]; var incomingRequests: [String]
            var outgoingRequests: [String]; var blocked: [String]; var reportsFiled: Int
        }
        let out = Export(account: state.account, profile: state.me, friends: state.friendIDs, incomingRequests: Array(state.incoming.keys),
                         outgoingRequests: Array(state.outgoing.keys), blocked: state.blocked, reportsFiled: state.reports.count)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(out)
    }

    // MARK: Profiles

    func myProfile() async throws -> PlayerProfile {
        try requireAccount()
        guard var me = state.me else { throw OnlineError.notSignedIn }
        me.relation = .you
        return me
    }

    func updateMyProfile(_ update: ProfileUpdate) async throws -> PlayerProfile {
        await pause()
        try requireAccount()
        guard var me = state.me else { throw OnlineError.notSignedIn }
        if let name = update.displayName {
            if let why = ProfileRules.problem(with: name) { throw OnlineError.nameRejected(why) }
            me.displayName = ProfileRules.clean(name)
        }
        if let c = update.avatarColour { me.avatarColour = ((c % PlayerProfile.avatarColourCount) + PlayerProfile.avatarColourCount) % PlayerProfile.avatarColourCount }
        if let cc = update.countryCode { me.countryCode = cc }
        if let p = update.privacy { me.privacy = p }
        if let c = update.companies { me.companies = c; me.companyCount = c.count }
        if let l = update.level { me.level = l }
        if let b = update.badges { me.badges = b }
        if let w = update.gameWeek { me.gameWeek = w }
        if let icon = update.avatarIcon, AvatarCatalog.def(icon) != nil { me.avatarIcon = icon }
        state.me = me
        save()
        me.relation = .you
        return me
    }

    func profile(id: String) async throws -> PlayerProfile {
        await pause()
        try requireAccount()
        settle()
        if id == state.me?.id, state.account != nil { return try await myProfile() }
        guard let p = roster.first(where: { $0.id == id }) else { throw OnlineError.notFound }
        return view(p)
    }

    func profile(code: String) async throws -> PlayerProfile {
        await pause()
        try requireAccount()
        settle()
        let wanted: String = Self.normalise(code)
        guard wanted.count == 6 else { throw OnlineError.notFound }
        if let me = state.me, state.account != nil, Self.normalise(me.code) == wanted { throw OnlineError.cannotTargetYourself }
        guard let p = roster.first(where: { Self.normalise($0.code) == wanted }) else { throw OnlineError.notFound }
        return view(p)
    }

    func searchPlayers(query: String) async throws -> [PlayerProfile] {
        await pause()
        let q: String = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        try requireAccount()
        settle()
        let code: String = Self.normalise(q)
        let hits: [PlayerProfile] = roster.filter { (p: PlayerProfile) -> Bool in
            guard !state.blocked.contains(p.id) else { return false }
            return p.displayName.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil || (code.count == 6 && Self.normalise(p.code) == code)
        }
        return hits.prefix(30).map { view($0) }
    }

    // MARK: Friends

    func friends() async throws -> FriendsOverview {
        await pause()
        try requireAccount()
        settle()
        return FriendsOverview(friends: state.friendIDs.compactMap { id in roster.first { $0.id == id } }.map { view($0) }.sorted { $0.displayName < $1.displayName },
                               incoming: requests(state.incoming), outgoing: requests(state.outgoing))
    }

    func sendFriendRequest(to playerID: String) async throws {
        await pause()
        try requireAccount()
        let p = try target(playerID)
        if state.blocked.contains(p.id) { throw OnlineError.blocked }
        if state.friendIDs.contains(p.id) { throw OnlineError.alreadyFriends }
        if state.incoming[p.id] != nil { state.incoming[p.id] = nil; state.friendIDs.append(p.id); save(); return }
        if state.outgoing[p.id] != nil { throw OnlineError.requestPending }
        state.outgoing[p.id] = Date()
        save()
    }

    func acceptFriendRequest(from playerID: String) async throws {
        await pause()
        try requireAccount()
        guard state.incoming[playerID] != nil else { throw OnlineError.notFound }
        state.incoming[playerID] = nil
        if !state.friendIDs.contains(playerID) { state.friendIDs.append(playerID) }
        save()
    }

    func declineFriendRequest(from playerID: String) async throws {
        await pause()
        try requireAccount()
        state.incoming[playerID] = nil
        save()
    }

    func cancelFriendRequest(to playerID: String) async throws {
        await pause()
        try requireAccount()
        state.outgoing[playerID] = nil
        save()
    }

    func removeFriend(_ playerID: String) async throws {
        await pause()
        try requireAccount()
        state.friendIDs.removeAll { $0 == playerID }
        save()
    }

    func blockPlayer(_ playerID: String) async throws {
        await pause()
        try requireAccount()
        let p = try target(playerID)
        state.friendIDs.removeAll { $0 == p.id }
        state.incoming[p.id] = nil
        state.outgoing[p.id] = nil
        if !state.blocked.contains(p.id) { state.blocked.append(p.id) }
        save()
    }

    func unblockPlayer(_ playerID: String) async throws {
        await pause()
        try requireAccount()
        state.blocked.removeAll { $0 == playerID }
        save()
    }

    func blockedPlayers() async throws -> [PlayerProfile] {
        try requireAccount()
        return state.blocked.compactMap { id in roster.first { $0.id == id } }.map { view($0) }
    }

    func report(_ playerID: String, reason: ReportReason, note: String) async throws {
        await pause()
        try requireAccount()
        let p = try target(playerID)
        state.reports.append(Report(playerID: p.id, reason: reason, note: String(note.prefix(500)), at: Date()))
        save()
    }

    // MARK: For features built on top (supplier marketplace and the like)

    /// The signed-in player's id, nil for a guest.
    func signedInPlayerID() -> String? { state.account == nil ? nil : state.me?.id }

    /// All sample players as the signed-in viewer may see them (privacy applied).
    func visibleDirectory() -> [PlayerProfile] { settle(); return roster.map { view($0) } }

    func extensionData(for key: String) -> Data? { state.extra[key] }

    func setExtensionData(_ data: Data?, for key: String) { state.extra[key] = data; save() }

    // MARK: Internals

    private func pause() async { if latency > 0 { try? await Task.sleep(nanoseconds: latency) } }

    private func requireAccount() throws { if state.account == nil { throw OnlineError.notSignedIn } }

    private func target(_ id: String) throws -> PlayerProfile {
        if id == state.me?.id { throw OnlineError.cannotTargetYourself }
        guard let p = roster.first(where: { $0.id == id }) else { throw OnlineError.notFound }
        return p
    }

    private static func normalise(_ code: String) -> String { String(code.uppercased().filter { $0.isLetter || $0.isNumber }) }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
    }

    /// A new player starts at level one with a country from the device and a few people already around them.
    private func createMyProfile(_ account: OnlineAccount) {
        let region: String = Locale.current.region?.identifier ?? "NO"
        let digits: String = String(account.playerID.suffix(4))
        state.me = PlayerProfile(id: account.playerID, code: SampleRoster.code(for: account.playerID), displayName: "Player " + digits.uppercased(), avatarColour: 0,
                                 countryCode: region == "GB" ? "UK" : region, level: 1, badges: [], privacy: .everyone, companyCount: 0, companies: [],
                                 gameWeek: nil, tradesCompleted: 0, relation: .you)
        state.friendIDs = ["p01", "p16"]
        state.incoming = ["p06": Date().addingTimeInterval(-3600 * 5), "p12": Date().addingTimeInterval(-3600 * 30)]
    }

    /// Computer players answer a request the way people do: after minutes or hours, inside their own waking hours (`PlayerRhythm`).
    private func settle(now: Date = Date()) {
        var changed = false
        for (id, at) in state.outgoing where SampleRoster.isComputer(id) {
            guard now >= PlayerRhythm.replyTime(id: id, countryCode: SampleRoster.countryCode(of: id), sentAt: at) else { continue }
            state.outgoing[id] = nil
            if !state.friendIDs.contains(id) { state.friendIDs.append(id) }
            changed = true
        }
        if changed { save() }
    }

    private func relation(_ id: String) -> FriendRelation {
        if state.account == nil { return .none }
        if state.blocked.contains(id) { return .blocked }
        if state.friendIDs.contains(id) { return .friend }
        if state.outgoing[id] != nil { return .requestSent }
        if state.incoming[id] != nil { return .requestReceived }
        return .none
    }

    /// The profile as this viewer is allowed to see it (see `PrivacyLevel`).
    private func view(_ p: PlayerProfile) -> PlayerProfile {
        var v = p
        v.relation = relation(p.id)
        let friend: Bool = v.relation == .friend
        func nameOnly() { v.level = nil; v.badges = []; v.companyCount = nil; v.companies = nil; v.gameWeek = nil; v.tradesCompleted = nil }
        if v.relation == .blocked { nameOnly(); return v }
        switch p.privacy {
        case .everyone: if !friend { v.companies = nil }
        case .friends: if !friend { v.companyCount = nil; v.companies = nil; v.tradesCompleted = nil }
        case .onlyMe: nameOnly()
        }
        return v
    }

    private func requests(_ table: [String: Date]) -> [FriendRequest] {
        table.compactMap { (id: String, at: Date) -> FriendRequest? in
            roster.first { $0.id == id }.map { FriendRequest(player: view($0), sentAt: at) }
        }.sorted { $0.sentAt > $1.sentAt }
    }
}
