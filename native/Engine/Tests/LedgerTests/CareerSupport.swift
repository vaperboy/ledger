import Countries

func UKCurrency() throws -> Currency {
    let book = try CountryBook.bundled()
    return Currency(country: book.countries.first { $0.code == "UK" } ?? book.countries[0], rates: ExchangeRates())
}
