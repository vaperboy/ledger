import SwiftUI

/// Changing the username: the first one is free, later ones cost gold. One flow for every screen that shows the pencil.
private struct UsernameChange: ViewModifier {
    @Binding var isPresented: Bool
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @ObservedObject private var local = ProfileLocal.shared
    @StateObject private var checker = UsernameChecker()
    @State private var draft = ""
    @State private var pending: PendingAction?
    @State private var shortOfGold = false
    @State private var shortNeed = 0
    @State private var showPacks = false

    private var hasUsername: Bool { ProfileRules.problem(with: local.name) == nil }
    private var cost: Int { hasUsername ? UsernameCost.change : 0 }

    func body(content: Content) -> some View {
        content
            .confirmAction($pending)
            .centerSheet(isPresented: $isPresented, title: "Username") { card }
            .centerSheet(isPresented: $shortOfGold, title: "Not enough gold") { ShortOfGoldCard(needed: shortNeed, onPacks: { shortOfGold = false; showPacks = true }) }
            .navigationDestination(isPresented: $showPacks) { StoreApp() }
            .onChange(of: isPresented) { _, open in
                if open { draft = hasUsername ? local.name : ""; checker.reset() }
            }
    }

    private var card: some View {
        let price: Int = cost
        return RenameCard(placeholder: "Username", text: $draft,
                          note: price > 0 ? "3 to 16 letters, numbers or _. Changing costs \(StoreText.gold(price)). Your old name is never given to anyone else." : "3 to 16 letters, numbers or _. Your first username is free.",
                          buttonTitle: price > 0 ? "Change \u{00B7} \(StoreText.gold(price))" : "Save", enabled: checker.canUse, identifier: "profile-name",
                          onSubmit: { submit(price) }) { UsernameStatusLine(checker: checker) }
            .onChange(of: draft) { _, new in checker.check(new, current: local.name, online: online) }
    }

    private func submit(_ price: Int) {
        let name: String = ProfileRules.clean(draft)
        guard checker.canUse else { return }
        isPresented = false
        if price == 0 {
            Task { await apply(name, price: 0) }
        } else {
            StorePurchase.afterPopup {
                StorePurchase.ask(offer: StorePurchase.offer(.username(price)), pending: $pending, onShort: { (need: Int) in shortNeed = need; shortOfGold = true }) {
                    Task { await apply(name, price: price) }
                }
            }
        }
    }

    private func apply(_ name: String, price: Int) async {
        if online.isSignedIn {
            switch await online.claimUsername(name) {
            case .ok?: break
            case .taken?: store.show("That username was just taken.", tone: "warn"); return
            case .invalid?: store.show("That username is not allowed.", tone: "warn"); return
            case nil: store.show("Could not reach the server. Try again.", tone: "warn"); return
            }
        }
        if price > 0, !(await StoreSession.shared.buy(.username(price), paidBoxesAllowed: true)) { return }
        Haptics.success()
        local.setName(name)
    }
}

extension View {
    /// Opens the username change sheet when `isPresented` turns on.
    func usernameChange(isPresented: Binding<Bool>) -> some View { modifier(UsernameChange(isPresented: isPresented)) }
}
