import Foundation
import GameCore
import Countries
import Finance

enum MarketSettlements {
    static let sender = "Marketplace"

    static func tell(_ s: inout GameState, title: String, body: String, tone: String) {
        s.addMessage(kind: "info", from: sender, title: title, body: body, companyID: 0, tone: tone.isEmpty ? "n" : tone, app: "marketplace")
    }

    static func book(_ s: inout GameState, _ item: OnlineSettlement, amount: Double, data: GameData) {
        let title = item.meta["title"].string
        let tone = item.meta["tone"].string
        let itemID = item.meta["itemID"].string
        let dealID = item.meta["dealID"].string
        switch item.kind {
        case "market_notice":
            tell(&s, title: title.isEmpty ? "Marketplace" : title, body: item.label, tone: tone)
        case "market_sale":
            let sold = PlayerInventory.item(s, id: itemID)
            PlayerInventory.remove(&s, id: itemID)
            if amount.isFinite, amount != 0 { Payments.playerReceives(&s, amount, label: item.label.isEmpty ? "Marketplace sale" : item.label) }
            if let sold, amount > sold.paid { s.tax.gains += amount - sold.paid }
            tell(&s, title: title.isEmpty ? "Sold" : title, body: item.label, tone: tone.isEmpty ? "good" : tone)
        case "market_purchase":
            let price = item.meta["price"].double
            guard let got = PlayerInventory.takeDelivery(&s, dealID: dealID, wire: item.meta["item"], price: price, currency: item.currency, data: data) else {
                tell(&s, title: "Purchase not delivered", body: "The item could not be added to your inventory. Contact support with the deal in the Marketplace.", tone: "bad")
                return
            }
            tell(&s, title: title.isEmpty ? "Bought" : title, body: item.label, tone: tone.isEmpty ? "good" : tone)
            if let note = PlayerInventory.revealNote(got) { tell(&s, title: "About the \(got.title) you bought", body: note.text, tone: note.tone) }
        case "market_refund":
            let back = PlayerInventory.release(&s, dealID: dealID)
            guard back > 0 else { return }
            Payments.playerReceives(&s, back, label: "Marketplace: money back")
            tell(&s, title: title.isEmpty ? "Deal closed" : title, body: item.label, tone: tone)
        case "market_unlist":
            PlayerInventory.unlock(&s, id: itemID)
            tell(&s, title: title.isEmpty ? "Listing closed" : title, body: item.label, tone: tone)
        default:
            break
        }
    }
}
