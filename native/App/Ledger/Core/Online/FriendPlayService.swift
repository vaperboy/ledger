import Foundation
import Simulation

struct GiftRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var fromName: String
    var defID: String
    var serial: Int
}

protocol FriendPlayService: Sendable {
    func raceEntries(week: Int, day: Int, friends: [PlayerProfile]) async throws -> [RaceEntry]
    func groupContributions(week: Int, day: Int, friends: [PlayerProfile]) async throws -> [Double]
    func sendGift(to playerID: String, item: ArtifactItem, fromName: String) async throws
    func receivedGifts() async throws -> [GiftRecord]
    func acknowledgeGifts(_ ids: [String]) async throws
    func sendPassNotice(to playerIDs: [String], text: String) async throws
    func passNotices() async throws -> [String]
}

extension FriendPlayService {
    func raceEntries(week: Int, day: Int, friends: [PlayerProfile]) async throws -> [RaceEntry] { [] }
    func groupContributions(week: Int, day: Int, friends: [PlayerProfile]) async throws -> [Double] { [] }
    func sendGift(to playerID: String, item: ArtifactItem, fromName: String) async throws { throw OnlineError.offline }
    func receivedGifts() async throws -> [GiftRecord] { [] }
    func acknowledgeGifts(_ ids: [String]) async throws {}
    func sendPassNotice(to playerIDs: [String], text: String) async throws {}
    func passNotices() async throws -> [String] { [] }
}

extension MockOnlineService {
    func raceEntries(week: Int, day: Int, friends: [PlayerProfile]) async throws -> [RaceEntry] {
        let progress: Double = Double(day % 7 + 1) / 7
        return friends.filter { (p: PlayerProfile) -> Bool in p.privacy != .onlyMe }.map { (p: PlayerProfile) -> RaceEntry in
            var s = SampleRoster.Stream("race:\(p.id):\(week)")
            let end: Double = Double(s.next(1200) - 300) / 10_000
            return RaceEntry(id: p.id, name: p.displayName, growth: (end * progress * 10_000).rounded() / 10_000)
        }
    }

    func groupContributions(week: Int, day: Int, friends: [PlayerProfile]) async throws -> [Double] {
        let progress: Double = Double(day % 7 + 1) / 7
        return friends.map { (p: PlayerProfile) -> Double in
            var s = SampleRoster.Stream("goal:\(p.id):\(week)")
            return (Double(200 + s.next(200)) * progress).rounded()
        }
    }

    func sendGift(to playerID: String, item: ArtifactItem, fromName: String) async throws {
        guard await currentAccount() != nil else { throw OnlineError.notSignedIn }
        let overview: FriendsOverview = try await friends()
        guard overview.friends.contains(where: { (p: PlayerProfile) -> Bool in p.id == playerID }) else { throw OnlineError.notFound }
    }
}
