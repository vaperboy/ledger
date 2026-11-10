import Foundation
import Businesses

protocol NewsFeedService: AnyObject {
    func events(now: Date) async -> [PlayerEvent]
    func isFriend(_ playerID: String) -> Bool
}

final class NewsFeedStore: ObservableObject {
    static let shared = NewsFeedStore()
    var service: NewsFeedService
    init(service: NewsFeedService = NewsFeedBackend.make()) { self.service = service }
}
