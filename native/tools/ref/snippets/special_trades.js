(() => {
  // Golden numbers for the energy, salmon, holding and football models, from the ORIGINAL game.
  // Random draws are replaced by fixed values so the arithmetic can be compared exactly.
  newGame({ seed: 12345, country: 'NO', name: 'Test Player' });
  S.cash += 5e10;
  const out = { power: [], oilPrice: [], field: [], salmon: [], clubs: {}, club: [], hold: [] };
  const realGauss = gauss, realChance = chance;
  // ---- power ----
  const o = { name: 'P', form: 'AS', acc: S.pool.acc[0].id };
  const p = startCompany('power', o);
  const bd = BD.power;
  gauss = () => 0.37;
  window.staffFTE = (co, role) => 3.2;
  const realMod = modProd;
  modProd = (co, k) => (k === 'cap' ? 0.9 : k === 'dem' ? 1.05 : 1);
  for (const src of [0, 1, 2]) for (const hedge of [0, 1, 2]) for (const week of [3, 20, 57, 100]) {
    S.week = week; S.econ.power = 1.2; S.econ.infl = 0.031;
    p.knob.src = src; p.knob.hedge = hedge;
    p.eq.turb = { n: 30, cond: 0.8, bv: 1, cost: 1 };
    p.fm = { build: [{ n: 4, ready: week + 10 }, { n: 2, ready: week - 1 }] };
    const ctx = { D: 0, cap: 0, units: 0, rev: 0, cogs: 0, util: 0, price: 0, extra: {}, cr: 0 };
    FAM.energy.power(p, bd, ctx);
    out.power.push({ src, hedge, week, bought: 30, building: 4, cond: 0.8, fte: 3.2, capMod: 0.9, demMod: 1.05, econPower: 1.2, infl: 0.031, noise: 0.37,
      mwh: ctx.units, rev: ctx.rev, cogs: ctx.cogs, cap: ctx.cap, price: ctx.price });
  }
  // ---- oil ----
  const q = startCompany('oilgas', { name: 'O', form: 'AS', acc: S.pool.acc[0].id });
  modProd = (co, k) => (k === 'cap' ? 0.95 : k === 'dem' ? 1.02 : 1);
  for (const sell of [0, 1]) for (const week of [5, 60]) {
    S.week = week; S.econ.oil = 1.3; S.econ.mat = 1.1; S.econ.infl = 0.03; q.knob.sell = sell; q.mgr = null;
    q.fm = { fields: [
      { id: 1, name: 'A', st: 'prod', res: 8000, q0: 27.2, age: 10, bv: 1.5e9, plat: 0 },
      { id: 2, name: 'B', st: 'prod', res: 60000, q0: 168, age: 120, bv: 4e9, plat: 104 },
      { id: 3, name: 'C', st: 'dev', res: 30000, q0: 84, wl: 40, capex: 3.9e9, bv: 1e9, plat: 104 }
    ] };
    q.cash = 5e10;
    const cash0 = q.cash;
    const ctx = { D: 0, cap: 0, units: 0, rev: 0, cogs: 0, util: 0, price: 0, extra: {}, cr: 0 };
    FAM.energy.oil(q, BD.oilgas, ctx);
    out.field.push({ sell, week, econOil: 1.3, mat: 1.1, infl: 0.03, capMod: 0.95, demMod: 1.02, fte: 3.2, crew: Math.min(1, 3.2 / Math.max(1, 10 * q.size)), size: q.size,
      units: ctx.units, rev: ctx.rev, cogs: ctx.cogs, price: ctx.price, assets: q.fm.assets, devPaid: cash0 - q.cash,
      fields: q.fm.fields.map(f => ({ res: f.res, bv: f.bv, st: f.st, age: f.age, wl: f.wl })) });
  }
  out.stake = [1000, 5000, 10000].map(k => { S.econ.oil = 1.3; return { k, price: Math.round(k * 1000 * 190 * S.econ.oil ** 0.5) }; });
  S.week = 77; S.econ.infl = 0.03;
  out.explore = { cost: Math.round(300e6 * Math.pow(1 + S.econ.infl, S.week / 52)), week: 77, infl: 0.03 };
  // ---- salmon ----
  gauss = realGauss; chance = () => false;
  const sm = startCompany('salmon', { name: 'S', form: 'AS', acc: S.pool.acc[0].id });
  modProd = realMod;
  S.econ.salmon = 1.15;
  sm.flags.autoStock = 0;
  sm.knob.feed = 1; sm.knob.den = 2;
  sm.fm = { coh: [{ n: 700000, kg: 0.1, age: 0, dead: 0 }, { n: 650000, kg: 2.0, age: 40, dead: 0, illx: 0.05 }] };
  S.week = 30;
  for (let w = 0; w < 90; w++) {
    S.week++;
    const ctx = { D: 0, cap: 0, units: 0, rev: 0, cogs: 0, util: 0, price: 0, extra: {}, cr: 0 };
    FAM.salmon.custom(sm, BD.salmon, ctx);
    out.salmon.push({ week: S.week, rev: ctx.rev, cogs: ctx.cogs, units: ctx.units, bio: sm.fm.bio, coh: sm.fm.coh.map(c => ({ n: c.n, kg: c.kg, age: c.age, illx: c.illx || 0 })) });
  }
  // ---- clubs of a league (deterministic from the seed) ----
  for (const cc of ['NO', 'UK', 'DE', 'US']) {
    out.clubs[cc] = clubsOf(cc).map(c => ({ id: c.id, name: c.name, city: c.city, val: c.val, fixed: c.fixed, rank0: c.rank0 }));
  }
  out.seed = S.seed;
  return JSON.stringify(out);
})()
