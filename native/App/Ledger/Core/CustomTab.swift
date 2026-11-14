import SwiftUI
import GameCore
import Simulation

extension GameStore {
    func title(for tab: AppTab) -> String { tab.title }
    func glyph(for tab: AppTab) -> String { tab.glyph }
}
