import SwiftUI

extension PhoneApp {
    var helpText: String? {
        switch self {
        case .bank: return "Your bank holds your money and your loans. Check balances, pay bills, move money between accounts and borrow when a company needs to grow."
        case .market: return "The Market shows your customers and the wider economy, and the Exchange trades every stock, raw material and public company. Look here before you set prices or spend on a new idea."
        case .inbox: return "The Inbox holds every decision, offer and warning waiting for you. Answer here: the day cannot move on while a question is open."
        case .news: return "News tells you what is happening in the world, among other players and in government, with the weather alongside. Headlines can lift or hurt your sales, so read them before big choices."
        case .competition: return "Reviews shows what customers say about your companies."
        case .atlas: return "Atlas sells insurance for your companies. Cover costs a little each month and pays out when something goes wrong."
        case .techPro: return "TechPro sells software, equipment and vehicles. Buy what makes a company faster or cheaper to run."
        case .airStay: return "AirStay lists offices, shops and storage to rent. Pick the place a company works from and see the rent before you commit."
        case .luxury: return "Luxury is where wealth is spent: cars, watches, art, yachts, jets and homes. Nothing here helps a company, but it shows how far you have come."
        case .marketplace: return "The Marketplace sells used items from private sellers. Make an offer and haggle: the price is rarely the last word."
        case .auctions: return "Auctions is where artifacts and cards are bought and sold for cash. Bid on other players' pieces, or put your own up and see what they fetch."
        default: return nil
        }
    }
}

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
                guard app.helpText != nil, !CoachTours.coversApp(app), !FirstRunFlags.seen(FirstRunFlags.appHelp(app.rawValue)) else { return }
                for _ in 0..<12 {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    if Task.isCancelled { return }
                    let hidden: Bool = !store.showsApp(app)
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
    func appFirstOpenHelp(_ app: PhoneApp) -> some View { modifier(AppFirstOpenHelp(app: app)) }
}
