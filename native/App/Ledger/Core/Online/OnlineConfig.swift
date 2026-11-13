import Foundation

enum OnlineConfig {
    static let useServer: Bool = true

    static let projectURL: URL? = URL(string: "https://ktcjbitrwuieuxthrqhu.supabase.co")
    static let publishableKey: String = "sb_publishable_ekG7VV_D0WCnGxqgStYOyQ_kkwGvB9H"

    static let callbackScheme: String = "ledger"
    static let callbackURL: String = "ledger://auth-callback"
}
