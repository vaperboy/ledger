import Foundation
import Businesses

/// News about real players, as the app sees it: public events only, already limited to what this viewer may see (the server enforces privacy;
/// the rules in `PlayerNewsRules` are the same ones the stand-in uses). `MockNewsFeedService` stands in for the server.
protocol NewsFeedService: AnyObject {
    /// Events the viewer may see, newest first. Never includes a Private player; a Friends-level player's events only for their friends.
    func events(now: Date) async -> [PlayerEvent]
    /// Whether the player who made the event is a friend of the viewer (they may then see the company named).
    func isFriend(_ playerID: String) -> Bool
}

/// Observable holder the News app watches.
final class NewsFeedStore: ObservableObject {
    static let shared = NewsFeedStore()
    var service: NewsFeedService
    init(service: NewsFeedService = MockNewsFeedService()) { self.service = service }
}
