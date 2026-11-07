import Foundation

extension ItemTradeGroups {
    /// Trades that use rental-unit item records: the RENT trades (buildings, rental cars, room types, gaming seats). See `RentalUnits.swift`.
    public static let rentals: Set<String> = ["resrent", "comrent", "parking", "carrental", "hotel", "pcbang"]
}
