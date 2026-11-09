import Foundation

/// Where the online side lives. The publishable key is meant for clients: Row Level Security on the server decides what it can reach.
/// Never put a database password, service-role key or access token here.
enum OnlineConfig {
    /// Off until the Supabase project is set up (migrations applied, providers enabled); while false the app uses the offline stand-in
    /// and makes no network calls.
    static let useServer: Bool = false

    static let projectURL: URL? = URL(string: "https://ktcjbitrwuieuxthrqhu.supabase.co")
    static let publishableKey: String = "sb_publishable_ekG7VV_D0WCnGxqgStYOyQ_kkwGvB9H"
}
