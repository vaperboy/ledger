# City data and demand by place

Where the data lives: `Engine/Sources/Countries/Resources/city_market.json` (merged into `countries.json` when the country book loads,
`CityMarketData.merge`), trade classes in `Engine/Sources/Businesses/Resources/market_classes.json`. The code is `Countries/CityMarket.swift`
(income model) and `Businesses/CityMarket.swift` (demand factor, rivals, awareness ceiling, tourists, read model).

## Audit of the model before this change
* A city had population, rent, wage, price level and a demand level that is purely `0.42 + 0.55 log10(pop / 20)` (clamped 0.35 to 2.4).
  Income, inequality, tourists and premium or luxury customers were not modelled per city. Country-level affluence only entered through
  `buyingPower` (affordability, larger for dear tickets) and the trade-country fit table.
* Rivals per market: `1 + pop / 120` plus noise, at most 5 named; the rival penalty saturated at 30% from about 9 rivals.
* Tourists: the country's share only, the same in every city. Organic awareness: a mild population term; no limit by city size.
* Check of the 23 countries' existing cities against real figures: populations are city proper (Australia, Singapore: metro/district) and
  all agree with national statistics to rounding; rent, wage and price columns follow the country indices consistently. No population
  was clearly wrong, so none was changed. The gaps were the spread (one "small town" per country, large countries without obvious
  cities) and the lack of metro size, income spread and tourist draw.

## What was added
* **123 cities** (large second-tier cities, resorts, small towns and villages, 3 to 11 per country; none for Singapore, a city-state).
  Their rent, wage and price are interpolated from the country's own cities by log10(population); demand level from the original formula
  (floor 0.22 for villages). Flagged `isExtra`; league clubs, rival group names and average demand still use the original cities.
* Per city: `metro` (metropolitan population), `tour` (tourist draw against the country's tourism share), optional `inc` (median household
  income against the country's) and `gini`. Derived when missing: `inc` = city wage / country wage level (0.55 to 1.6); city Gini = country
  Gini + 0.04 log10(pop / 200) (clamped).
* Per country: `gini` (disposable income).
* **Income model** (`IncomeModel`): household income is log-normal around the city median, spread from the Gini (Gini = erf(sigma / 2)).
  Bands in multiples of the reference median wage, thresholds scaled by `sqrt(city price)`: budget below 0.7, middle 0.7 to 1.5, upper 1.5 to
  4 (can afford premium), affluent above 4 (luxury). `Country.incomeBands(in:)`.
* **Demand by class**: trades listed in `market_classes.json` have `need` (income needed at an average price) and `lean`. The company's
  price position raises the threshold (`0.85 x need x priceMultiplier^2.4`). Demand step "market class" (after affordability) multiplies by
  `(share of households above the threshold in the city / in the country)^lean`, clamped 0.08 to 3. Everyday trades: 1. Country-level wealth stays
  in the existing `affordability` step, this step only moves demand between places inside a country.
* **Competition and costs**: for these trades the initial rival count uses `pop / 120 x (same ratio at an average price)`, new markets get
  a strength bonus up to 0.2 and the rival penalty cap rises from 0.3 up to 0.42 with city size. Rent, wage and price already rise with city size.
* **Tourists**: visitor share = country share x city `tour`. **Awareness**: a local business's awareness is capped at 100 minus up to 14 for a
  city of about 6 million (`awarenessCeiling`); walk-ins already scale with the log of the real population via the city demand level.
* **Read model**: `CityMarket.profile(cityID:countryCode:state:data:)` returns population, metro, households, median monthly income, Gini,
  income bands, tourist draw, rent/wage/price/demand levels, three tiers (everyday, premium, luxury: potential households, demand factor,
  average rivals) and per-trade rows (affordable share, demand factor, rivals).

## Deliberate changes to goldens and tests
* `FoundationTests.testCountryDerivedValuesMatchOriginal`, `CompanyModelDifferentialTests`, `ProjectDifferentialTests` load the original
  city data (`CountryBook.bundled(realCityMarket: false)`); the golden files themselves are unchanged.
* The trades with a class (boutique, cardealer, hotel, casino, restaurant, nightclub, airline, skires, indoorski, vineyard, furniture, estate,
  photo, dental, fun, carrental) are added to `TradeTuning.tunedTradeIDs`, so the demand parity checks skip them (as for the other tuned trades).

## Sources (rounded, 2023 to 2025 values from memory of the official series; not scraped, verify before relying on them)
City populations and metros: national statistical offices (SSB, SCB, GUS, Destatis, ONS, INSEE, INE, CBS, US Census, Statistics Canada, ABS,
Statistics Japan, KOSTAT, IBGE, FSO, INEGI, FCSC, ISTAT, Statistics Denmark, Statistics Finland, CSO), UN World Urbanization Prospects 2018/2024.
Gini of disposable income: OECD Income Distribution Database, Eurostat, World Bank PIP (UAE estimated). Tourist draw: judgement from
overnight-stay statistics (rank of destinations), not a measured figure. Checked: 2026-10.
