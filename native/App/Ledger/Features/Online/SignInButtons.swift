import SwiftUI
import AuthenticationServices

// Sign in with Apple and Google. Each links this phone's account, or offers to switch to the account the sign-in already belongs to.
struct SignInButtons: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @State private var nonce: String = ""
    @State private var checked = false

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            if online.signInOptions.contains(.apple) {
                SignInWithAppleButton(.continue) { (request: ASAuthorizationAppleIDRequest) in
                    nonce = AppleNonce.make()
                    request.requestedScopes = [.email]
                    request.nonce = AppleNonce.hash(nonce)
                } onCompletion: { (result: Result<ASAuthorization, Error>) in
                    finishApple(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(maxWidth: .infinity, minHeight: LedgerButtonMetrics.regularHeight, maxHeight: LedgerButtonMetrics.regularHeight)
                .clipShape(RoundedRectangle(cornerRadius: LedgerButtonMetrics.radius, style: .continuous))
                .disabled(online.isLinking)
                .accessibilityIdentifier("sign-in-apple")
            }
            if online.signInOptions.contains(.google) {
                Button {
                    Haptics.tap()
                    Task { await online.connect(.google, engine: store.engine) }
                } label: { Text("Continue with Google").frame(maxWidth: .infinity) }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                    .disabled(online.isLinking)
                    .accessibilityIdentifier("sign-in-google")
            }
            if checked && online.signInOptions.isEmpty {
                Text("Sign-in is not available right now. Your game stays on this phone.").textStyle(.caption)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .task {
            await online.loadSignInOptions()
            checked = true
        }
    }

    private func finishApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential, let data = credential.identityToken,
                  let token = String(data: data, encoding: .utf8), !nonce.isEmpty else {
                online.problem = "Sign in with Apple did not finish. Try again."
                return
            }
            let raw: String = nonce
            Task { await online.connect(.apple(idToken: token, nonce: raw), engine: store.engine) }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            online.problem = "Sign in with Apple did not finish. Try again."
        }
    }
}

// Asks which account and which game to use when a sign-in belongs to another account.
struct AccountChoiceHost: ViewModifier {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online

    private var shown: Binding<Bool> {
        Binding(get: { online.accountChoice != nil }, set: { (on: Bool) -> Void in if !on { online.accountChoice = nil } })
    }

    private var hasLocalGame: Bool { store.engine != nil || store.hasSavedGame }

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: shown, titleVisibility: .visible, presenting: online.accountChoice) { (choice: AccountChoice) in
            switch choice {
            case .confirmSignIn:
                // Only the browser sign-in asks first; Apple's token is reused without a second prompt.
                Button("Sign in to that account") { Task { await online.offerSwitch(.google) } }
            case .chooseGame(let offer):
                if offer.savedGame != nil {
                    Button("Load the account's game") { Task { await online.finishSwitch(offer, loadGame: true, store: store) } }
                    if hasLocalGame {
                        Button("Keep this phone's game") { Task { await online.finishSwitch(offer, loadGame: false, store: store) } }
                    }
                } else {
                    Button("Switch to this account") { Task { await online.finishSwitch(offer, loadGame: false, store: store) } }
                }
            }
            Button("Cancel", role: .cancel) { online.cancelAccountChoice() }
        } message: { (choice: AccountChoice) in
            Text(message(choice))
        }
    }

    private var title: String {
        switch online.accountChoice {
        case .confirmSignIn(let provider)?: return "This \(provider.title) account already has a Ledger account"
        case .chooseGame(let offer)?: return "Switch to " + (offer.name.map { "\($0)'s account" } ?? "your account") + "?"
        case nil: return ""
        }
    }

    private func message(_ choice: AccountChoice) -> String {
        let leftBehind = "The online profile made on this phone is left behind."
        switch choice {
        case .confirmSignIn:
            return "Sign in to it to use that profile and its saved game on this phone. " + leftBehind
        case .chooseGame(let offer):
            guard let game = offer.savedGame else { return "The account has no saved game, so this phone's game is saved to it. " + leftBehind }
            let what: String = [game.title, game.week.map { "week \($0)" }].compactMap { $0 }.joined(separator: ", ")
            let saved: String = (what.isEmpty ? "A game" : what) + ", saved " + game.updatedAt.formatted(date: .abbreviated, time: .shortened)
            if !hasLocalGame { return "The account's game opens on this phone: \(saved). " + leftBehind }
            return "The account has a saved game: \(saved). Keeping this phone's game replaces it. Loading the account's game puts this phone's game aside in a save slot. " + leftBehind
        }
    }
}
