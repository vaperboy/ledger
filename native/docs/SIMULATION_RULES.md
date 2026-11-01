# Core simulation and sales rules (binding)

Owner's rules, 23 Oct 2026. They apply to all future implementation, balancing, audits and refactors. Every agent working on engine rules,
balance, marketing, sales methods, chains or franchises reads this file first (it is referenced from DESIGN_RULES.md and IMPLEMENTATION_ROADMAP.md).

## 1. No arbitrary growth caps or floors
- Do not impose artificial minimum or maximum growth percentages, profit margins, customer growth or business performance.
- Do not clamp, normalise or secretly adjust outcomes to force businesses into a predetermined balance range.
- Growth, stagnation, decline, exceptional success and failure must emerge from the underlying simulation.
- Player capabilities and decisions materially influence outcomes through relevant factors: management, staffing, capital, pricing, reputation, demand, location, competition, operational capacity and execution.
- Do not guarantee success to a capable player or failure to an inexperienced one.
- Legitimate economic and operational constraints are allowed and encouraged when they represent real mechanisms. Model them explicitly.
- No hidden rubber-banding, no automatic rescue bonuses, no automatic penalties for successful businesses.

## 2. Balance the causal system, not the outcome
- Investigate why businesses make or lose money before changing numerical parameters.
- Separate player skill, business model, market conditions, random variation, operational constraints and external shocks.
- Use multi-seed testing to find systematic problems and unrealistic edge cases.
- Averages and target ranges may be used to detect suspicious results, never as automatic growth limits or mandatory outcomes.
- Preserve legitimate high-performing and failing scenarios when the underlying conditions justify them.
- Fix broken formulas, unrealistic cost structures, exploit loops and missing constraints rather than masking symptoms with arbitrary modifiers.

## 3. How you sell must have real consequences
- Sales methods are operating decisions, not free customer-growth buttons. No guarantee that a method increases customers, revenue or profit.
- Where relevant model setup and recurring costs, commissions, discounts, extra staffing, training, equipment, fulfilment, documentation, capacity and other genuine requirements; do not invent costs where they do not logically apply.
- Outcomes depend on business type, target market, location, demand, reputation, competition, execution quality, pricing, capacity and operating costs.
- Trade-offs: more sales can mean lower margins, higher workload, poorer service, extra capital needs or losses.
- Some methods are unavailable, unsuitable, ineffective or unprofitable for particular businesses. Allow uncertain and negative outcomes; not every option is worthwhile.
- No double-counting: each method affects shared demand, conversion, costs and capacity through one integrated implementation.

## 4. Sales methods respect business structure
- Independent businesses configure their own appropriate methods.
- Chains: chain-wide defaults, mandatory standards or per-store settings, by explicit rules.
- Franchises follow their actual agreement: mandatory requirements, permitted options, fees, royalties, standards, local discretion.
- Stores in a chain or franchise are not assumed identical unless the rules require it. Changes at chain or franchise level propagate only to the businesses they govern.
- Store-level exceptions work where permitted and never silently override mandatory rules.
- A holding company does not impose shared policies on unrelated businesses. Shared services, negotiated arrangements and central purchasing have explicit costs, benefits, eligibility and effects.

## 5. Implementation safety
- First inspect the current engine and UI to find the real source of each rule. Reuse existing systems; no parallel sales, demand, marketing, cost or growth systems.
- Preserve saves, existing functionality and working interfaces. No rewrites of unrelated files; no rebalancing of every business for a focused fix.
- Add regression tests for the rules changed; test representative business types, structures, successful and unsuccessful outcomes and multiple seeds.
- Report what was verified, what remains uncertain and any data gaps. Do not claim realism or balance because the game compiles or tests pass.

**Priority:** causal realism, meaningful player agency, coherent economics and consistent rules over artificial numerical balance or feature count.
