import Foundation
import GameCore
import Simulation

enum RememberedDetails {
    static let prefix = "remember."

    static func gameID(_ e: GameEngine) -> String {
        let g: String = e.state.rest["gameID"]?.string ?? ""
        return g.isEmpty ? "seed\(e.state.seed)" : g
    }

    static func key(app: String, game: String, companyID: Int) -> String {
        prefix + app + "." + game + "." + String(companyID)
    }

    static func load(app: String, game: String, companyID: Int, own: BankPaymentDetails?) -> BankPaymentDetails? {
        guard let own else { return nil }
        guard let saved = UserDefaults.standard.string(forKey: key(app: app, game: game, companyID: companyID)) else { return nil }
        let parts: [String] = saved.components(separatedBy: "|")
        let holder: String = parts.first ?? ""
        let number: String = parts.count > 1 ? parts[1] : ""
        if holder == own.holder && number == own.accountNumber { return own }
        return nil
    }

    static func save(app: String, game: String, companyID: Int, own: BankPaymentDetails?, on: Bool) {
        let k: String = key(app: app, game: game, companyID: companyID)
        if on, let own {
            UserDefaults.standard.set(own.holder + "|" + own.accountNumber, forKey: k)
        } else {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }

    static func clearAll() {
        let keys: [String] = Array(UserDefaults.standard.dictionaryRepresentation().keys)
        for k in keys where k.hasPrefix(prefix) || k.hasPrefix("techpro.remember.") {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }
}
