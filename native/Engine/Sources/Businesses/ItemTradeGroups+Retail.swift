import Foundation

extension ItemTradeGroups {
    /// Trades that use retail item records (STK resale and parts): items per `Resources/retail_items.json`, installed by `RetailItems`.
    public static let retail: Set<String> = ["kiosk", "boutique", "grocery", "hardware", "webshop", "pets", "carrepair"]
}
