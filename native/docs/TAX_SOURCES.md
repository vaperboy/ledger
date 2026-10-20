# Tax data: what the game models, what is real, what changed

Checked in October 2026 against the 2025/26 (and where already published 2026/27) rules, from my own knowledge plus public web
sources: government and tax-authority pages where the search reached them (Skatteverket, Skatteetaten, HMRC/gov.uk,
service-public.fr, Belastingdienst/KVK, Agenzia delle Entrate summaries, IBFD, KPMG, Baker McKenzie, BDO), otherwise tax-adviser
and payroll-calculator sites. **Several 2026 figures (Finland's state scale, Lithuania's exact 2026 thresholds, Denmark's church/
municipal averages, Mexico's 2026 table) rest on secondary sources that disagree with each other; they are marked "unsure"
below.** Nothing here is tax advice.

The game is a simplification on purpose. Amounts are in the country's own currency in `countries.json` and become accounting
units via `fx`. Every country now has `dataBasis.status = "checked"`, `dataBasis.checked = "2026-10"` and a `dataBasis.note`
that says what is simplified; the Finance screen shows "Estimate." plus the first text. Fees (company registration, licences) and
policy rates were **not** rechecked in this pass. The data has no statutory minimum wage: wages come from the role tables
times the country's wage level (`economy.medianWage`).

## Changes to figures (every deliberate difference from the original game)

Golden tests (`FoundationTests`, `FinanceDifferentialTests`) still compare everything else with the original's numbers; for the
rows below the old golden expectation no longer applies. The affected checks skip exactly these (country, field) pairs, and
`FoundationTests.testCorrectedTaxFiguresArePinned` pins the new values. `FinanceDifferentialTests` replays the original UK case
with the original dividend rate and says so.

| Country | Field | Was | Now | Why |
|---|---|---|---|---|
| NO | `tax.income.allowance` | `108550` | `114540` | Personal allowance 2026 NOK 114,540 |
| NO | `tax.income.wageDeduction` | `[0.46, 92000]` | `[0.46, 95700]` | Standard deduction cap 2026 NOK 95,700 |
| NO | `tax.wealth.threshold` | `1760000` | `1900000` | Wealth tax threshold 2026 NOK 1.9 M |
| SE | `tax.income.brackets` | `[[0, 0], [45000, 0.32], [625800, 0.52]]` | `[[0, 0], [45000, 0.32], [643100, 0.52]]` | State-tax threshold 2026 SEK 643,100 (was the 2025 value) |
| LT | `tax.corporate` | `0.16` | `0.17` | Corporate rate 17% from 1 Jan 2026 |
| LT | `tax.income.brackets` | `[[0, 0.2], [114000, 0.32]]` | `[[0, 0.2], [83000, 0.25], [138300, 0.32]]` | Three-step PIT from 2026 (20/25/32%) |
| DE | `tax.income.brackets` | `[[0, 0], [12100, 0.3], [68500, 0.42], [278000, 0.45]]` | `[[0, 0], [12348, 0.3], [69879, 0.42], [277827, 0.45]]` | Basic allowance 2026 EUR 12,348; 42% from EUR 69,879; 45% from EUR 277,827 |
| DE | `tax.income.social.employee` | `0.205` | `0.2115` | 2026 contributions: 9.3 + 1.3 + 7.3 + 1.45 (average add-on) + 1.8 |
| DE | `tax.employer.social` | `0.21` | `0.2115` | Same rates for the employer |
| UK | `tax.dividend` | `0.3375` | `0.3575` | Upper-rate dividend tax 35.75% from 6 April 2026 (Autumn Budget 2025) |
| UK | `tax.inherit.bizFree` | `1000000` | `2500000` | Business relief at 100% up to GBP 2.5 M from April 2026 (raised from the planned 1 M in Dec 2025) |
| FR | `tax.dividend` | `0.3` | `0.314` | PFU 31.4% from 2026 (social levies 18.6%) |
| FR | `tax.income.brackets` | `[[0, 0], [11500, 0.11], [29300, 0.3], [83800, 0.41], [180300, 0.45]]` | `[[0, 0], [11600, 0.11], [29579, 0.3], [84577, 0.41], [181917, 0.45]]` | Barème 2026, thresholds +0.9% |
| NL | `tax.income.brackets` | `[[0, 0.3582], [38400, 0.3748], [76800, 0.495]]` | `[[0, 0.3575], [38883, 0.3756], [78426, 0.495]]` | Box 1 2026 rates and thresholds |
| US | `tax.income.brackets` | `[[0, 0], [15000, 0.1], [26925, 0.12], [63475, 0.22], [118350, 0.24], [212300, 0.32], [265525, 0.35], [641350, 0.37]]` | `[[0, 0], [16100, 0.1], [28500, 0.12], [66500, 0.22], [121800, 0.24], [217875, 0.32], [272325, 0.35], [656700, 0.37]]` | 2026 single-filer brackets (Rev. Proc. 2025-32) with the USD 16,100 standard deduction as the first step |
| CA | `tax.income.brackets` | `[[0, 0.2], [55000, 0.28], [110000, 0.34], [170000, 0.41], [240000, 0.48]]` | `[[0, 0.2], [55000, 0.28], [110000, 0.34], [170000, 0.41], [220000, 0.48], [253000, 0.5353]]` | Added the top combined bracket (53.53% above CAD 253,000); 48% from CAD 220,000 |
| BR | `tax.income.brackets` | `[[0, 0], [27500, 0.075], [40000, 0.15], [55000, 0.225], [65000, 0.275]]` | `[[0, 0], [60000, 0.4735], [88200, 0.275]]` | Law 15.270/2025: exempt to BRL 5,000 a month from 2026, phase-out to 7,350, standard table above |
| AE | `tax.corporate` | `0.08` | `0.09` | Federal corporate tax is 9% (0% below AED 375,000) |
| DK | `tax.income.brackets` | `[[0, 0], [54100, 0.34], [697000, 0.41], [845500, 0.48], [2818000, 0.52]]` | `[[0, 0], [54100, 0.3706], [641200, 0.4456], [777900, 0.5206], [2592700, 0.5706]]` | 2026: municipal ~25.05% + base tax 12.01% above DKK 54,100; new middle tax (7.5%), top tax cut to 7.5%, new top-top tax (5%) |

Unchanged after checking (the original already matched current law or the simplification is acceptable): PL, ES, AU, JP, KR, CH,
MX, IT (already 2026-like: 25/35/45 = 23/33/43 + ~2 points of local surcharges), FI, IE, SG. Of these, FI (state scale and
municipal average) and MX (2026 table indexing) are **unsure** and should be checked on the official pages when someone has them
open.

## Per country

| Country | Corporate | Dividend | VAT standard | Employer contr. | Employee contr. | Wealth tax |
|---|---:|---:|---:|---:|---:|---|
| NO Norway | 22% | 37.84% | 25% | 16.6% | 7.6% | 1% above 1,900,000 |
| SE Sweden | 20.6% | 30% | 25% | 31.42% | 7% | none |
| PL Poland | 19% | 19% | 23% | 22.17% | 22% | none |
| LT Lithuania | 17% | 15% | 21% | 1.77% | 19.5% | none |
| DE Germany | 30% | 26.38% | 19% | 22.15% | 21.15% | none |
| UK United Kingdom | 25% | 35.75% | 20% | 18% | 8% | none |
| FR France | 25% | 31.4% | 20% | 43% | 22% | none |
| ES Spain | 25% | 23% | 21% | 31% | 6.48% | 0.7% above 700,000 |
| NL Netherlands | 25.8% | 31% | 21% | 23% | 0% | none |
| US United States | 26% | 23.8% | 6.6% (sales tax) | 13% | 7.65% | none |
| CA Canada | 12.2% | 30% | 13% | 8.5% | 7% | none |
| AU Australia | 25% | 20% | 10% | 18% | 2% | none |
| JP Japan | 30% | 20.32% | 10% | 15.5% | 15% | none |
| KR South Korea | 22% | 15.4% | 10% | 11% | 9% | none |
| BR Brazil | 34% | 10% | 17% | 30% | 9% | none |
| CH Switzerland | 14.7% | 20% | 8.1% | 14.4% | 6.4% | 0.3% above 80,000 |
| MX Mexico | 37% | 10% | 16% | 30% | 2.8% | none |
| AE United Arab Emirates | 9% | 0% | 5% | 6.5% | 0% | none |
| IT Italy | 27.9% | 26% | 22% | 37.9% | 9.19% | none |
| DK Denmark | 22% | 42% | 25% | 9.5% | 8% | none |
| FI Finland | 20% | 28% | 25.5% | 20.1% | 9.5% | none |
| IE Ireland | 12.5% | 52% | 23% | 12.75% | 4.2% | none |
| SG Singapore | 17% | 0% | 9% | 17.5% | 20% | none |

### Notes, real rates and caveats

**NO Norway** (NOK, checked 2026-10). Income: 22% flat on ordinary income after the personal allowance (2026: NOK 114,540) and the standard deduction (46%, max NOK 95,700) plus bracket tax (trinnskatt) in five steps from NOK 226,100. Wealth tax 1.0% above NOK 1.9 M (2026). Dividends: 22% x 1.72 = 37.84%, with a risk-free-return shield. Employer contributions are zone 1 (14.1%).

**SE Sweden** (SEK, checked 2026-10). Income: municipal tax about 32% plus 20% state tax above the 2026 threshold (SEK 643,100 taxable income, written here as 52% above). The basic allowance is simplified to a SEK 45,000 tax-free amount. 3:12 rules for owner-managed companies are not modelled (dividends flat 30% = capital income tax).

**PL Poland** (PLN, checked 2026-10). Scale tax: 12% to PLN 120,000, 32% above, PLN 30,000 tax-free (2022 Polish Deal). Health contribution (9%) is lumped into the 22% employee contributions. Employer 20.48% social plus 1.67% accident. 19% flat dividend and CIT.

**LT Lithuania** (EUR, checked 2026-10). From 2026: corporate 17% (small companies 7% not modelled), personal income tax 20% / 25% / 32% in three steps (steps are multiples of the average wage and are rounded here), dividends 15%. Employee contributions 19.5%, employer 1.77% (plus a small accident premium).

**DE Germany** (EUR, checked 2026-10). Income tax is a formula in the law (progression 14% to 42%); the game uses four steps: tax-free amount EUR 12,348 (2026), about 30% averaged over the progression zone, 42% from EUR 69,879, 45% from EUR 277,827. Soli surcharge ignored (abolished for most people). Corporate: 15% + 5.5% solidarity + about 14% trade tax = 30% (a cut to 25% by 2032 is planned from 2028). Contributions 2026: pension 9.3, unemployment 1.3, health 7.3 + about 1.45 average add-on, care 1.8 = 21.15% each side.

**UK United Kingdom** (GBP, checked 2026-10). Rates for England, Wales and Northern Ireland, 2026/27. Dividend rate 35.75% is the upper rate from 6 April 2026 (ordinary 10.75%, additional 39.35%). Employer NI 15% (from April 2025) plus 3% minimum pension; employee NI 8% and class 4 for the self-employed 6%. Inheritance: nil-rate band GBP 325,000; business relief 100% on the first GBP 2.5 M of business assets from April 2026, 50% above.

**FR France** (EUR, checked 2026-10). Barème 2026 (income of 2025): 11% / 30% / 41% / 45% from EUR 11,600 / 29,579 / 84,577 / 181,917. Dividends: flat tax (PFU) 31.4% from 2026 (12.8% tax + 18.6% social levies). Employer charges about 42% at average pay (reductions for low pay not modelled). CEHR surcharge on high incomes not modelled.

**ES Spain** (EUR, checked 2026-10). State + average regional scale. Dividends: savings scale 19-28%, 23% used. Social contributions: employer about 30-31%, employee 6.5%, self-employed (RETA) about 30% of a chosen base. Wealth tax (patrimonio) 0.2-3.5% with regional rebates, approximated by a flat 0.7% above EUR 700,000 and only 30% of company shares counted.

**NL Netherlands** (EUR, checked 2026-10). Box 1 2026: 35.75% to EUR 38,883, 37.56% to EUR 78,426, 49.5% above (the first two steps include the national insurance contributions, so social is 0 here). Box 2 (dividends and substantial interest) 31% above EUR 68,843 (24.5% below). Corporate 19% to EUR 200,000 and 25.8% above (25.8% used).

**US United States** (USD, checked 2026-10). Federal income tax for a single filer, 2026: standard deduction USD 16,100 (written as the first step) then 10% / 12% / 22% / 24% / 32% / 35% / 37%; state and local income tax not modelled. Payroll tax 7.65% each side (employer 9% in the data includes unemployment insurance); self-employed 15.3%. Corporate: 21% federal + about 5% state. Dividends: 23.8% (20% + 3.8% NIIT). Sales tax: average combined state + local about 6.6%, charged to consumers. Estate tax exemption USD 15 M (2026).

**CA Canada** (CAD, checked 2026-10). Federal + Ontario-type combined brackets, rounded (federal 14% bottom rate from July 2025). Corporate: 12.2% is the small-business combined rate; the general rate is about 26.5%. Dividends ~30% (eligible/non-eligible mix). No inheritance tax exists in Canada: a deemed sale at death is taxed as capital gains, approximated here by an 18% rate. GST 5% / HST 13% (Ontario).

**AU Australia** (AUD, checked 2026-10). Resident rates 2025-26: 0 to AUD 18,200, 16% to 45,000, 30% to 135,000, 37% to 190,000, 45% above; Medicare levy 2% as the social rate. Super guarantee 12% (employer pension) from July 2025. Company tax 25% (base-rate entity) or 30%. Dividends 20% stands for the franking-credit system.

**JP Japan** (JPY, checked 2026-10). National income tax 5-45% in seven steps plus 10% resident tax (flat part), basic deduction simplified to JPY 430,000. Social insurance about 15% each side. Corporate: effective about 30%. Dividends 20.315% (separate taxation). Consumption tax 10% (8% food). Inheritance tax up to 55%, simplified.

**KR South Korea** (KRW, checked 2026-10). Income tax 6-45% in eight steps (since 2023); local income tax (10% of tax) ignored. Corporate 9-24% progressive; 22% used for a mid-sized company incl. local tax. Dividend withholding 15.4%. VAT 10%, simplified-taxpayer threshold KRW 104 M. Inheritance tax 10-50%, simplified.

**BR Brazil** (BRL, checked 2026-10). Law 15.270/2025 from January 2026: income up to BRL 5,000 a month (60,000 a year) is exempt, a phase-out up to BRL 7,350 a month (88,200), the standard table above; written here as 0 / 47.35% (average of the phase-out) / 27.5%. Dividends: 10% withholding above BRL 50,000 a month per payer (simplified to 10% flat); a minimum tax for incomes above BRL 600,000 is not modelled. Brazil has no VAT: the 17% stands for ICMS/ISS/PIS/COFINS; the IBS/CBS reform phases in from 2026-2033. Corporate 34% = IRPJ 25% + CSLL 9%.

**CH Switzerland** (CHF, checked 2026-10). Federal + cantonal + municipal averages, very simplified (cantons differ widely: corporate 12-21%). VAT 8.1% / 2.6% / 3.8% (a temporary rise for the AHV pension is planned from 2028). AHV/IV/EO 5.3% + unemployment 1.1% each side; self-employed AHV about 10%. Wealth tax 0.3% average, cantonal.

**MX Mexico** (MXN, checked 2026-10). ISR table 2025/26 (annual, monthly table x 12); corporate 30% plus the 10% employee profit share (PTU) = 37% effective on profit. Dividends 10% withholding. IVA 16%. Employer IMSS + SAR + Infonavit about 29%. Update the table when SAT publishes the 2027 indexing.

**AE United Arab Emirates** (AED, checked 2026-10). Federal corporate tax 9% above AED 375,000 of profit (0% below; large multinationals 15% top-up not modelled). No personal income tax, no dividend tax, no wealth tax. VAT 5%, threshold AED 375,000. Employer cost: end-of-service gratuity and pension for nationals (6%) simplified.

**IT Italy** (EUR, checked 2026-10). IRPEF 2026: 23% to EUR 28,000, 33% to 50,000, 43% above, plus regional/municipal surcharges of about 2 points: written as 25% / 35% / 45% with the first EUR 8,500 untaxed (no-tax area for employees). Corporate: IRES 24% + IRAP 3.9%. Dividends 26%. INPS employee 9.19%, employer about 30%. Flat-rate regime for small businesses (VAT threshold EUR 85,000) simplified.

**DK Denmark** (DKK, checked 2026-10). 2026 (after the 8% AM contribution): base tax 12.01% + municipal about 25.05% above the personal allowance of DKK 54,100 = 37.06%; middle tax +7.5% above DKK 641,200; top tax +7.5% above DKK 777,900; top-top tax +5% above DKK 2,592,700. Church tax ignored. Dividends 27% to DKK 67,500 and 42% above (42% used). Employer pension is collectively agreed (8% used).

**FI Finland** (EUR, checked 2026-10). Combined state + municipal scale, rounded and partly out of date (state steps for 2026 are 0 / 12.64% / 19% / 30.25% / 34% / 44% from about EUR 21,000, and the municipal average is about 7.5% since the 2023 social and health reform). Capital income 30% up to EUR 30,000, 34% above (dividends are partly taxed: 28% used). Corporate 20%. VAT 25.5% (food 13.5% from 2026).

**IE Ireland** (EUR, checked 2026-10). Income tax 20% / 40% (EUR 44,000 band, single) combined with USC (0.5% / 2% / 3% / 8%) and PRSI 4% in the data as five steps; tax credits (about EUR 3,750) shown as a tax-free band to EUR 20,000. Corporate 12.5% (15% for large groups). Dividends taxed at the marginal rate: 40% + USC 8% + PRSI 4% = 52%. Employer PRSI 11.25%. Inheritance: group A threshold EUR 400,000, 33%.

**SG Singapore** (SGD, checked 2026-10). Resident rates (YA 2024 on): 0% to SGD 20,000 rising to 24% above SGD 1 M, in 11 steps, simplified at the 19.5-20% steps. CPF employee 20% / employer 17% (citizens and PRs under 55). Corporate 17% (partial exemption for new companies not modelled). No dividend tax, no wealth or inheritance tax. GST 9%.

## How to update

Edit `Engine/Sources/Countries/Resources/countries.json` (`tax`, `vat`, `companies`), update `dataBasis.note` and `checked`, add the
changed pair to `FoundationTests.correctedBrackets` (or the other skip sets) with the new value in
`testCorrectedTaxFiguresArePinned`, and list the change in the table above.
