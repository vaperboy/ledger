import SwiftUI

extension PhoneApp {
    /// What the app is for in two plain sentences, shown once the first time it opens; nil for apps that need no introduction.
    var helpText: String? {
        switch self {
        case .bank: return "Your bank holds your money and your loans. Check balances, pay bills, move money between accounts and borrow when a company needs to grow."
        case .market: return "The Market shows your customers, your rivals and the wider economy. Look here before you set prices or spend on a new idea."
        case .inbox: return "The Inbox holds every decision, offer and warning waiting for you. Answer here: the day cannot move on while a question is open."
        case .news: return "News tells you what is happening in the world and in your trade. Headlines can lift or hurt your sales, so read them before big choices."
        case .reviews: return "Reviews shows what customers say about you and your rivals. Good reviews bring customers back; bad ones are a sign something needs fixing."
        case .atlas: return "Atlas sells insurance for your companies. Cover costs a little each month and pays out when something goes wrong."
        case .techPro: return "TechPro sells software, equipment and vehicles. Buy what makes a company faster or cheaper to run."
        case .airStay: return "AirStay lists offices, shops and storage to rent. Pick the place a company works from and see the rent before you commit."
        case .luxury: return "Luxury is where wealth is spent: cars, watches, art, yachts, jets and homes. Nothing here helps a company, but it shows how far you have come."
        case .marketplace: return "The Marketplace sells used items from private sellers. Make an offer and haggle: the price is rarely the last word."
        case .stats: return "Stats keeps your record: your figures, goals, reports and where your money went. Come here to see how you are doing over time."
        default: return nil
        }
    }
}

/// Opens a one-time "What this app does" sheet the first time an app is shown, once nothing else is on screen. The flag is per app.
private struct AppFirstOpenHelp: ViewModifier {
    @EnvironmentObject var store: GameStore
    var app: PhoneApp
    @State private var open = false

    func body(content: Content) -> some View {
        content
            .centerSheet(isPresented: $open, title: "What this app does", size: .fit) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(app.title).textStyle(.headline, tint: Theme.ink)
                    Text(app.helpText ?? "").popupText(.subtitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task {
                guard app.helpText != nil, !FirstRunFlags.seen(FirstRunFlags.appHelp(app.rawValue)) else { return }
                // After the app's opening splash, and only when no other popup is up; retried briefly while one is.
                for _ in 0..<12 {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    if Task.isCancelled { return }
                    // A Custom tab kept alive behind another tab must not raise its app's sheet there.
                    let hidden: Bool = store.tab != .phone && !(store.tab == .custom && store.customTarget == .app(app))
                    if !hidden && !store.popupOpen && store.unlockQueue.isEmpty {
                        FirstRunFlags.mark(FirstRunFlags.appHelp(app.rawValue))
                        open = true
                        return
                    }
                }
            }
    }
}

extension View {
    /// The first-open help sheet of a phone app (see `PhoneApp.helpText`).
    func appFirstOpenHelp(_ app: PhoneApp) -> some View { modifier(AppFirstOpenHelp(app: app)) }
}
