import Foundation
import GameCore
import Countries

/// The one in-game rate between gold and game money. The real-money price of gold is separate (GoldPrices.goldPerNok).
public enum GoldValue {
    /// Game money (reference NOK) for an amount of gold.
    public static func gameMoney(gold: Double) -> Double { gold * GoldPrices.gameNokPerGold }

    /// The same amount in a country's own money, by the game's exchange rate.
    public static func local(gold: Double, currency: Currency) -> Double { gameMoney(gold: gold) / currency.rate }

    /// Gold worth an amount of game money.
    public static func gold(gameMoney: Double) -> Double { GoldPrices.gameNokPerGold > 0 ? gameMoney / GoldPrices.gameNokPerGold : 0 }
}
