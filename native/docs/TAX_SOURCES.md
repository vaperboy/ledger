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
| LT | `tax.income.brackets` (thresholds) | `[[0, 0.2], [83000, 0.25], [138300, 0.32]]` | `[[0, 0.2], [83237, 0.25], [138729, 0.32]]` | 36 and 60 x 2026 average wage EUR 2,312.15 = EUR 83,237.40 / 138,729 (KPMG Lithuania newsletter Jan 2026 https://kpmg.com/lt/lt/izvalgos/mokesciu-ir-teises-naujienlaiskiai/2026-sausis.html, citing VMI; earlier KPMG US flash had a preliminary 82,962 / 138,270) |
| MX | `tax.income.brackets` | 2025 table (`8952 ... 4511707`) | `[[0, 0.0192], [10135, 0.064], [86022, 0.1088], [151176, 0.16], [175736, 0.1792], [210404, 0.2136], [424354, 0.2352], [668840, 0.30], [1276926, 0.32], [1702568, 0.34], [5107704, 0.35]]` | Annual tariff 2026, SAT Anexo 8 RMF 2026 (DOF 28 Dec 2025) https://www.sat.gob.mx/minisitio/NormatividadRMFyRGCE/documentos2026/rmf/anexos/Anexo-8-RMF-2026_DOF-28122025.pdf (art. 152 indexation, +13.21%) |
| MX | `tax.corporate` | `0.37` | `0.30` | ISR 30% on taxable profit, not revenue; PTU no longer folded in. Source: owner-supplied 2026 rules |
| MX | `tax.employer` | `social 0.22, pension 0.07, injury 0.01` | `statePayroll 0.03` + IMSS `contributions` table (components, rate, cap in UMA) | State payroll tax about 3%; IMSS computed from payroll, contribution base and caps. Source: owner-supplied 2026 rules |
| BR | `tax.employer.pension` | `0` | `0.08` | Employer FGTS 8% of pay is a payroll cost; the termination fine is a separate one-off (`labour.fundFineRate`). Source: owner-supplied 2026 rules |
| LT | `vat.rates.food` | `0.09` | `0.12` | Reduced rate for certain categories is 12% from 2026 (old 9% replaced where applied); standard 21%, other reduced 5% and exemptions unchanged. Source: owner-supplied 2026 rules |
| FI | `tax.income.brackets` | `[[0, 0], [15000, 0.2], [21200, 0.265], [31500, 0.38], [52100, 0.415], [88200, 0.49]]` | `[[0, 0], [18600, 0.27], [27000, 0.33], [45000, 0.42], [58000, 0.44]]` | 2026 state scale 12.64 / 19 / 30.25 / 33.25 / 37.5% from 0 / 22,000 / 32,600 / 40,100 / 52,100 (https://www.veronmaksajat.fi/neuvot/henkiloverotus/tyo-elake-ja-etuudet/ansiotulojen-verot-ja-maksut/valtion-tulovero/ ; Vero 2026) plus municipal avg 7.57%, health contribution 1.10% (https://vero.fi/en/individuals/tax-cards-and-tax-returns/tax_card/tax-rate-and-income-ceiling/tax-bases/). The game's four steps are fitted by hand to the all-in 2026 income-tax curve (taxes minus 8.2% pension/unemployment contributions) of https://www.veronmaksajat.fi/luvut/Laskelmat/Palkansaajan-veroprosentit/ : 373 / 1,691 / 3,224 / 6,452 / 10,542 / 14,665 / 23,486 EUR at 20k / 25k / 30k / 40k / 50k / 60k / 80k, within about 3%. Church tax is included in that curve (average 1.38%) and not modelled separately |
| DK | `tax.income.brackets` | `[[0, 0], [54100, 0.34], [697000, 0.41], [845500, 0.48], [2818000, 0.52]]` | `[[0, 0], [54100, 0.3706], [641200, 0.4456], [777900, 0.5206], [2592700, 0.5706]]` | 2026: municipal ~25.05% + base tax 12.01% above DKK 54,100; new middle tax (7.5%), top tax cut to 7.5%, new top-top tax (5%) |

Unchanged after checking (the original already matched current law or the simplification is acceptable): PL, ES, AU, JP, KR, CH,
IT (already 2026-like: 25/35/45 = 23/33/43 + ~2 points of local surcharges), IE, SG.

**FI, LT, MX re-verified in the labour/tax pass (October 2026), no longer unsure:**
- FI: corporate 20% for 2026 (an 18% cut from tax year 2027 is only a government proposal: https://uutishuone.pwc.fi/en/finnish-corporate-income-tax-rate-to-be-reduced-to-18/, https://www.borenius.com/legal-alerts/2026/05/08/finnish-government-proposes-corporate-tax-rate-cut-and-extended-loss-carry-forward-period/); VAT 25.5%, reduced 13.5% (food, from 1 Jan 2026), 10% (newspapers), https://www.vero.fi/en/businesses-and-corporations/taxes-and-charges/vat/rates-of-vat/ ; capital income 30% to EUR 30,000 and 34% above (Vero tax bases 2026, link above). Dividend 28% and employee/employer contributions are unchanged simplifications (not re-derived; the all-in 8.2% pension/unemployment contribution in the Veronmaksajat table is lower than the game's 9.5% employee rate, left as is). Income brackets changed (table above).
- LT: corporate 17% from 2026 and dividends 15% (KPMG US Tax News Flash 4 Dec 2025 https://kpmg.com/kpmg-us/content/dam/kpmg/taxnewsflash/pdf/2025/12/tnf-lithuania-dec-4-2025.pdf ; the VMI PDF and Sodra pages could not be fetched, Cloudflare block). VAT 21% and registration threshold EUR 45,000 confirmed only by secondary summaries (workinlithuania.com, investlithuania.com 2026), not by a VMI page. Employee 19.5% / employer 1.77% unchanged, not re-fetched. Brackets updated (table above).
- MX: annual tariff verified against the SAT/DOF Anexo 8 (table above). Corporate ISR 30%, IVA 16% and dividend withholding 10% now come from owner-supplied 2026 rules (below).

## Per country

| Country | Corporate | Dividend | VAT standard | Employer contr. | Employee contr. | Wealth tax |
|---|---:|---:|---:|---:|---:|---|
| NO Norway | 22% | 37.84% | 25% | 16.6% | 7.6% | 1% above 1,900,000 |
| SE Sweden | 20.6% | 30% | 25% | 31.42% | 7% | none |
| PL Poland | 19% | 19% | 23% | 22.17% | 22% | none |
| LT Lithuania | 17% | 15% | 21% (12% / 5% reduced, 0% exempt) | 1.77% | 19.5% | none |
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
| MX Mexico | 30% | 10% | 16% | 30% | 2.8% | none |
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

**LT Lithuania** (EUR, checked 2026-10). From 2026: corporate 17% (small companies 7% not modelled), personal income tax 20% / 25% / 32% in three steps (steps at 36 and 60 times the average wage: EUR 83,237 and 138,729), dividends 15%. Employee contributions 19.5%, employer 1.77% (plus a small accident premium).

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

**MX Mexico** (MXN, checked 2026-10). ISR annual tariff 2026 (SAT Anexo 8, verified); corporate ISR 30% on taxable profit (not revenue; the 10% employee profit share PTU is no longer modelled as part of the rate). Dividends: 10% additional withholding on qualifying after-tax distributions. IVA 16% standard, on taxable sales less eligible input IVA. State payroll tax about 3% (employer expense, broad estimate). IMSS employer contributions are computed from payroll: `tax.employer.contributions` is a small table of components (rate, cap in UMA units; UMA MXN 117.31 a day, 30.4 days a month, from my own knowledge, not fetched) and `Country.employerSocialRate(monthlyWage:)` applies each rate to pay up to its cap, plus the 3% state tax; the flat `employerSocial` is that table at the median wage. Source: owner-supplied 2026 rules. Update the table when SAT publishes the 2027 indexing.

**AE United Arab Emirates** (AED, checked 2026-10). Federal corporate tax 9% above AED 375,000 of profit (0% below; large multinationals 15% top-up not modelled). No personal income tax, no dividend tax, no wealth tax. VAT 5%, threshold AED 375,000. Employer cost: end-of-service gratuity and pension for nationals (6%) simplified.

**IT Italy** (EUR, checked 2026-10). IRPEF 2026: 23% to EUR 28,000, 33% to 50,000, 43% above, plus regional/municipal surcharges of about 2 points: written as 25% / 35% / 45% with the first EUR 8,500 untaxed (no-tax area for employees). Corporate: IRES 24% + IRAP 3.9%. Dividends 26%. INPS employee 9.19%, employer about 30%. Flat-rate regime for small businesses (VAT threshold EUR 85,000) simplified.

**DK Denmark** (DKK, checked 2026-10). 2026 (after the 8% AM contribution): base tax 12.01% + municipal about 25.05% above the personal allowance of DKK 54,100 = 37.06%; middle tax +7.5% above DKK 641,200; top tax +7.5% above DKK 777,900; top-top tax +5% above DKK 2,592,700. Church tax ignored. Dividends 27% to DKK 67,500 and 42% above (42% used). Employer pension is collectively agreed (8% used).

**FI Finland** (EUR, checked 2026-10). Combined state + municipal scale for 2026 (verified, see the changes table): state 12.64 / 19 / 30.25 / 33.25 / 37.5% from EUR 0 / 22,000 / 32,600 / 40,100 / 52,100, municipal average about 7.57%; game steps 27 / 33 / 42 / 44% fitted to the all-in curve. Capital income 30% up to EUR 30,000, 34% above (dividends are partly taxed: 28% used). Corporate 20%. VAT 25.5% (food 13.5% from 2026).

**IE Ireland** (EUR, checked 2026-10). Income tax 20% / 40% (EUR 44,000 band, single) combined with USC (0.5% / 2% / 3% / 8%) and PRSI 4% in the data as five steps; tax credits (about EUR 3,750) shown as a tax-free band to EUR 20,000. Corporate 12.5% (15% for large groups). Dividends taxed at the marginal rate: 40% + USC 8% + PRSI 4% = 52%. Employer PRSI 11.25%. Inheritance: group A threshold EUR 400,000, 33%.

**SG Singapore** (SGD, checked 2026-10). Resident rates (YA 2024 on): 0% to SGD 20,000 rising to 24% above SGD 1 M, in 11 steps, simplified at the 19.5-20% steps. CPF employee 20% / employer 17% (citizens and PRs under 55). Corporate 17% (partial exemption for new companies not modelled). No dividend tax, no wealth or inheritance tax. GST 9%.

## Labour rules (`labour` in `country_traits.json`)

Added October 2026 from my own knowledge of the 2025/26 rules, then re-checked in a second pass (see the verification log below the table; figures marked *unsure* in the table that the log does not mention remain unverified). Money is in the country's own currency per
month for a standard week; the game converts it with the exchange rate and indexes it with inflation like the market wage.
`statutory: false` means there is no national statutory minimum: the figure is a floor from collective agreements (or a regional
minimum) and is enforced in the game as if it were law. Where the real minimum is higher than what the game's existing wage table
pays for its cheapest job, the data holds a **game-scaled** value (about 85% of the cheapest market wage) and `realMinMonthly` keeps
the real figure, so the wage tables are not rebalanced.

| Country | Min wage / month | Std week | Overtime premium | Notice (weeks) | Severance (weeks) | Leave days | Probation |
|---|---|---:|---:|---|---|---:|---|
| NO | 29,000 NOK game-scaled (real about 37,000: general-application cleaning minimum NOK 227.54/h in 2024 x 37.5 h, none national by law; 2026 figure unverified) | 37.5 | +40% | 4.3, +0.5/yr, max 13 | none | 25 | 26 wk, 2 wk notice |
| SE | 17,900 SEK game-scaled (real about 25,000, none by law) | 40 | +50% (agreements) | 4.3, +2.2/yr, max 26 (LAS 11 §: 1 / 2 / 3 / 4 / 5 / 6 months at 0 / 2 / 4 / 6 / 8 / 10 years) | none (agreements) | 25 | 26 wk |
| PL | 2,160 PLN game-scaled (real 4,806) | 40 | +50% | 2, +4/yr, max 13 | 0.5/yr, min 4.3, max 13 | 20 | 12 wk, 1 wk notice |
| LT | 650 EUR game-scaled (real 1,153) | 40 | +50% | 4.3 flat (2 weeks under 1 yr, not modelled) | 8.7 (2 months) after 1 yr, secondary sources | 20 | 12 wk, 1 wk |
| DE | 2,410 EUR (EUR 13.90/h from 1 Jan 2026, x 40 h) | 40 | +25% (custom, no statutory premium), *unsure* | by service (`noticeBands`): 4 weeks (to the 15th or month-end), 2 y 1 month, 5 y 2, 8 y 3, 10 y 4, 12 y 5, 15 y 6, 20 y 7 months (to month-end), as 4.3 / 8.7 / 13 / 17.4 / 21.7 / 26 / 30.4 weeks | none automatic: not due for every dismissal | 20 | 26 wk (notice bands apply instead of the probation notice) |
| UK | 2,065 GBP (GBP 12.71/h National Living Wage, age 21+, from 1 Apr 2026, x 37.5 h; lower age bands differ) | 37.5 | none by law | `noticeBands`: 1 week after 1 month up to 2 years, then 1 week per completed year 2 to 12, max 12 weeks | statutory redundancy pay separate from notice: eligible after 2 years, 0.5 / 1 / 1.5 weeks a year by age (under 22, 22-40, 41+), service counted to 20 years | 28 | 104 wk (qualifying period for unfair dismissal; shortens under the Employment Rights Act 2025, *unsure* when) |
| FR | 1,867 EUR (SMIC EUR 12.31/h from 1 Jun 2026 = EUR 1,867.02 at 35 h; EUR 12.02/h Jan-May) | 35 | +25% | 4.3, +2/yr, max 8.7 (kept from earlier data; no figure given) | needs 8 months uninterrupted service; 1/4 month of reference salary per year for the first 10 years, 1/3 month per year after (`severanceTiersMonths`; collective agreements may give more); separate from notice | 25 | 8 wk, 1 wk |
| ES | 1,424 EUR (SMI 1,221 x 14 payments / 12) | 40 | +25% (rest or pay at least the basic rate), *unsure* | 2 | 2.86/yr (20 days a year, objective dismissal), max 52 | 22 | 8 wk |
| NL | 2,598 EUR (WML EUR 14.99/h from 1 Jul 2026 x 40 h) | 40 | +25% (agreements), *unsure* | 4.3, +0.4/yr, max 17 | 1.44/yr (transition payment, 1/3 month a year) | 20 | 8 wk |
| US | 1,257 USD (federal USD 7.25/h x 40 h; higher state or local minimum can apply) | 40 | +50% (FLSA) | none by default (at will); WARN-type mass layoff notice only under `massLayoffNoticeWeeks` (60 days) when the caller flags a mass layoff | none | 0 | at will, no unfair dismissal |
| CA | 3,146 CAD (federal CAD 18.15/h from 1 Apr 2026 x 40 h; Ontario CAD 17.95 from 1 Oct 2026) | 40 | +50% | 2 (Canada Labour Code, federal) | 0.4/yr (2 days a year), at least 1 week, after 1 yr (federal) | 10 | 13 wk |
| AU | 4,354 AUD (national minimum AUD 26.44/h x 38 h from 1 Jul 2026) | 38 | +50% (awards) | 1, +0.8/yr, max 5 | 1.6/yr, at least 4, after 1 yr, max 16 (NES redundancy scale 4 weeks at 1 yr to 16 at 10 yrs, simplified) | 20 | 26 wk, 1 wk |
| JP | 204,000 JPY (national weighted average JPY 1,177/h, FY2026 revision, x 40 h; takes effect region by region Oct-Dec 2026) | 40 | +25% | 4.3 | none statutory | 10 | 13 wk |
| KR | 1,481,000 KRW game-scaled (real 2,156,880: KRW 10,320/h x 209 h = 40 h week with paid weekly rest, 2026) | 40 | +50% | 4.3 | 4.3/yr after 1 yr (30 days a year retirement pay) | 15 | 13 wk |
| BR | 510 BRL game-scaled (real 1,621: BRL 54.04/day, 7.37/h, 2026) | 44 | +50% | 30 days up to one year of service plus 3 days per year, max 90 days (in lieu or worked by termination type; the game pays in lieu, only without cause) | FGTS: employer 8% of pay is payroll cost (`tax.employer.pension`); the 40% fine on the FGTS balance is a one-off liability (`fundFineRate` x `fundRate` x months served), separate from wages and notice | 30 | 13 wk |
| CH | 4,000 CHF, none national (cantonal minima, e.g. Geneva about CHF 24.5/h), *unsure* | 42 | +25% above the legal maximum, *unsure* | 4.3, +0.9/yr, max 13 | none | 20 | 4.3 wk, 1 wk |
| MX | 1,370 MXN game-scaled (real 9,577: MXN 315.04/day general zone from 1 Jan 2026; 440.87/day northern border zone) | 48 | +100% | none | indemnity only for `severanceReasons` (unjustified dismissal or redundancy; none for justified or for-cause dismissal or resignation): 3 months (13 weeks) + 20 days a year + seniority premium 12 days a year (premium cap of twice the minimum wage not modelled); replaces the earlier 12.9 weeks / 4.0 a year | 12 | 4 wk |
| AE | 2,000 AED, none by law, *unsure* | 48 | +25% | 4.3 | 3.0/yr after 1 yr (21 days a year, gratuity) | 30 | 26 wk, 4.3 wk |
| IT | 920 EUR game-scaled (real about 1,500, none by law; agreements) | 40 | +25% (agreements), *unsure* | 4, +1/yr, max 16 | 3.6/yr (TFR, about 6.9% of annual pay) | 20 | 26 wk |
| DK | 21,000 DKK, none by law (agreements), *unsure* | 37 | +50% (agreements), *unsure* | 4.3, +0.6/yr, max 26 | 0.36/yr, at least 4.3, after 12 yrs (Funktionærloven: 1 month after 12 yrs, 2 after 17) | 25 | 13 wk, 2 wk |
| FI | 1,740 EUR game-scaled (real about 2,200, none by law; agreements) | 37.5 | +50% | 2, +1.5/yr, max 26 | none | 30 | 26 wk |
| IE | 2,391 EUR (EUR 14.15/h, age 20+, from 1 Jan 2026; lower for younger; x 39 h) | 39 | +25% (custom), *unsure* | `noticeBands`: 13 weeks to under 2 y 1 week; 2 to under 5 y 2; 5 to under 10 y 4; 10 to under 15 y 6; 15 y+ 8 (employee's own statutory notice generally 1 week after 13 weeks: `employeeNoticeWeeks`) | 2/yr after 2 yrs (+1 bonus week not modelled) | 20 | 52 wk |
| SG | 2,080 SGD, none by law (Progressive Wage Model cleaners from 1 Jul 2026, MOM) | 44 | +50% | 1, +0.8/yr, max 4 | 2/yr after 2 yrs (custom), *unsure* | 14 | 13 wk, 1 wk |

### Owner-supplied 2026 rules (source "owner-supplied 2026 rules")

Authoritative figures given by the project owner in October 2026; they replace any earlier conflicting value in this file. Not independently
fetched. Where the rule data keeps them: `labour` in `country_traits.json` (`minimumWage` list with amount, currency, period, ageBand,
region, effective date; `noticeBands`; `severanceTiersMonths`, `severanceAgeBands`, `severanceBaseWeeks`, `severancePremiumPerYear`,
`severanceReasons`, `noticeReasons`, `fundRate`, `fundFineRate`, `massLayoffNoticeWeeks`) and `tax` / `vat` in `countries.json`.

- Minimum wage 2026: MX MXN 315.04/day general zone from 1 Jan (440.87/day northern border); KR KRW 10,320/h (2,156,880/month, 40 h week with paid weekly rest); BR BRL 1,621/month (54.04/day, 7.37/h); FR EUR 12.31/h = 1,867.02/month at 35 h from 1 Jun (Jan-May 12.02); DE EUR 13.90/h from 1 Jan; UK GBP 12.71/h (21+, from 1 Apr); IE EUR 14.15/h (20+, from 1 Jan); US USD 7.25/h federal. The scaled game minima (SE, PL, LT, KR, BR, MX, IT, FI: about 85% of the cheapest market wage) depend only on the market wage, so re-deriving them with the same formula leaves them unchanged; only the real figures (`realMinMonthly`, KR 2,157,000 to 2,156,880) and unscaled minima (FR 1,823 to 1,867) changed.
- Dismissal: notice (or pay in lieu) and severance are separate payments, computed from the person's actual wage and tenure and gated by the termination reason (redundancy, unjustified, for cause, resignation); routine payroll (including employer FGTS) is separate from one-off termination liabilities (severance, the BR fund fine). Notice pay carries the employer charge at that wage; severance and the fine do not.
- Mexico tax: ISR 30%, IVA 16%, dividend withholding 10%, state payroll tax about 3%, IMSS from the table. Lithuania VAT: standard 21%, reduced category rate 12% from 2026 (was 9%), other reduced rates and exemptions kept separate.


### Labour verification log (second pass, October 2026)

Confirmed or corrected against fetched sources (URL, year of the figure):
- PL min wage PLN 4,806 for 2026 (Council of Ministers regulation Sept 2025; https://wageindicator.org/labour-laws/collective-bargaining/2025/poland-3-minimum-wage-hike-in-2026-august-31-2025): confirmed. LT EUR 1,153 for 2026 (https://www.lpsk.lt/en/2025/09/09/government-to-decide-on-minimum-monthly-wage-in-2026-could-increase-to-eur-1153/ and WageIndicator; a later EUR 1,245 resolution is for 2027): confirmed. The game-scaled values for these are derived from the market wage, not from the real figure, so they are unchanged.
- ES SMI EUR 1,221 x 14 = EUR 1,424.5 x 12 in 2026 (Real Decreto 126/2026, BOE-A-2026-3815; https://www.fieldfisher.com/es-es/locations/espana/actualidad/salario-minimo-interprofesional-2026): confirmed.
- NL WML EUR 14.71/h on 1 Jan 2026 and EUR 14.99/h on 1 Jul 2026 (Rijksoverheid figures via https://www.taxlive.nl/nl/documenten/nieuws/minimumloon-per-1-januari-2026/ and https://www.mkbservicedesk.nl): corrected 2,450 to 2,598.
- AU: Fair Work Commission Annual Wage Review 2026 (decision 2 Jun 2026): national minimum wage AUD 26.44/h, AUD 1,004.90/week from 1 Jul 2026 (https://www.squirepattonboggs.com/insights/publications/2026-annual-wage-review-decision-fwc-increases-the-national-minimum-wage-and-award-rates/): corrected. Redundancy minimum of 4 weeks (Fair Work Act NES) added as `severanceMin`, from knowledge.
- CA federal minimum wage CAD 18.15 from 1 Apr 2026 (https://hicksmorley.com/2026/03/24/federal-minimum-wage-to-increase-april-1-2026/); Ontario CAD 17.95 from 1 Oct 2026 (https://hicksmorley.com/2026/04/01/ontario-minimum-wage-to-increase-october-1-2026/). The labour block now follows the federal Canada Labour Code (40 h, +50%, 2 weeks notice, 2 days severance a year); the Ontario-type notice (1 week a year) was removed. The Code sections were not fetched: unverified.
- JP weighted average minimum wage JPY 1,177 for FY2026 (MHLW, 3 Sep 2026; https://www.kaiketsu-j.com/?p=23935): corrected 194,000 to 204,000 JPY.
- SG Progressive Wage Model cleaner basic wage SGD 2,080 from 1 Jul 2026 (https://www.mom.gov.sg/employment-practices/progressive-wage-model/cleaning-sector; NEA PWM guide Apr 2026): corrected. SG has no national minimum; this is the lowest sector rate.
- SE notice periods confirmed in the statute LAS 11 § (https://www.riksdagen.se/sv/dokument-och-lagar/dokument/svensk-forfattningssamling/lag-198280-om-anstallningsskydd_sfs-1982-80/): per-year rate raised from 0.5 to 2.2 weeks so that 2 / 4 / 6 / 8 / 10 years give 2 / 3 / 4 / 5 / 6 months. SE real minimum (SEK 25,000, agreements) not verified.
- LT notice: one month (two weeks under a year), Labour Code art. 57 (Eurofound ERM database https://apps.eurofound.europa.eu/legislationdb/notice-period-to-employees/lithuania); severance two months of average pay after a year, from secondary guides only (https://www.rippling.com/en-GB/blog/termination-in-lithuania): unverified against e-tar.lt. The old 0.5 weeks of notice a year is not in the Code.
- UK: the unfair-dismissal qualifying period is still two years until 1 Jan 2027, when the Employment Rights Act 2025 cuts it to six months (law-firm summaries only, e.g. https://www.lewissilkin.com/insights/2026/09/04/whats-in-the-employment-rights-act). Data left at 104 weeks; change to 26 when the date passes.
- MX severance: superseded by the owner-supplied 2026 rules (indemnity gated by termination reason, 3 months + 20 days a year + seniority premium; the previous 12.9 weeks / 4.0 a year is gone). MX, KR and BR minimum wages are now owner-supplied.
- DK: Funktionærloven severance (1 month after 12 years, 2 after 17) from knowledge only; the DK minimum (DKK 21,000, agreements) unverified.
- NO real minimum: Tariffnemnda regulation of 21 Oct 2024, cleaning minimum NOK 227.54/h (https://arbeidstilsynet.no/globalassets/regelverkspdfer/forskrift-om-delvis-allmenngjoring-av-tariffavtale-for-renholdsbedrifter); the 2026 agreement raises it, figure not found. The game value 29,000 is game-scaled (about 85% of the cheapest market wage); `realMinMonthly` 37,000 is informational.

Not verified in this pass (kept as in the table, from knowledge): DE overtime premium (customary, not statutory); the DE/FR/UK/IE/US/KR/BR/MX minimum wages are owner-supplied 2026 figures; CH cantonal minima, AE end-of-service gratuity, IT/FI/SE real agreement minima, and all notice/severance figures not named above.

Simplifications: notice is paid in lieu and paid separately from severance (and from any termination fund fine); notice
grows with whole years of service (or follows the country's `noticeBands`); the unfair dismissal claim (the existing 35-55% risk without two warnings on file) cannot happen
during probation or in an at-will country; part-timers' pay and the minimum are pro rata to the standard week; the premium is paid
only to hourly staff (not fixed-salary or commission staff) for hours above the standard or agreed week; wage claims for unpaid
wages already existed (`Payday.lateDay`) and are unchanged.

## How to update

Edit `Engine/Sources/Countries/Resources/countries.json` (`tax`, `vat`, `companies`), update `dataBasis.note` and `checked`, add the
changed pair to `FoundationTests.correctedBrackets` (or the other skip sets) with the new value in
`testCorrectedTaxFiguresArePinned`, and list the change in the table above.
