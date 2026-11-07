import SwiftUI
import GameCore
import Businesses

extension GameStore {
    /// True when the ladder has opened `g` (or no game is loaded / the game has no ladder). Surfaces hidden until their gate ask this.
    func gateOpen(_ g: Gate) -> Bool {
        guard let e = engine else { return true }
        return Gates.visibility(g, e.state, data: e.data) == .open
    }
}
