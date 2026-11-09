import SwiftUI

extension PendingAction {
    /// The confirmation of an online action. It always asks, and it always says what will happen: "If you do this, ...".
    /// `effect` finishes that sentence in plain words; `risk` is the one thing that can go wrong, if there is one.
    static func online(title: String, effect: String, button: String, risk: String = "", destructive: Bool = false,
                       tone: PopupTone = .info, icon: String? = nil, run: @escaping () -> Void) -> PendingAction {
        PendingAction(title: title, message: "If you do this, " + effect, button: button, destructive: destructive, alwaysAsk: true,
                      risk: risk, tone: tone, icon: icon, run: run)
    }
}
