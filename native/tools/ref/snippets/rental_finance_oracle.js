// Oracle for the property and finance families (resrent, comrent, parking, insco, bank, fund).
// Plays a small game in the ORIGINAL, saves it, and then, for each company, runs the family's weekly model, the property
// actions and the finance events on a fresh copy of that save and records what came out.
// usage: node ev.js ledger.html rental_finance_oracle.js > rental_finance_oracle.json   (then split `save` out, see gen script)
(() => {
  newGame({ seed: 5150, country: 'UK', name: 'RF' });
  S.cash += 5e10;
  const ids = {};
  const make = (key, type, knobs) => {
    const o = { name: 'RF ' + key, form: 'AS', acc: S.pool.acc[0].id };
    const co = startCompany(type, o);
    if (typeof co === 'string') throw new Error(key + ': ' + co);
    Object.assign(co.knob, knobs || {});
    injectCash(co, Math.round(setupEstimate(type, o).total * 2.2));
    setupAndOpen(co);
    ids[key] = co.id;
    return co;
  };
  make('resrent', 'resrent');
  make('comrent', 'comrent', { seg: 1 });
  make('parking', 'parking', { type: 1 });
  make('insco', 'insco');
  make('bank', 'bank');
  make('bankw', 'bank', { liq: 1 });
  make('fund', 'fund');
  make('fundp', 'fund', { strat: 2, fees: 2 });
  for (let w = 0; w < 70; w++) nextWeek();
  const save = serialize();
  const out = { ids, save, weekly: {}, ops: {} };
  const ctxOf = c => ({ D: c.D, cap: c.cap, units: c.units, rev: c.rev, cogs: c.cogs, util: c.util, price: c.price });
  const snap = co => ({ fm: JSON.parse(JSON.stringify(co.fm)), props: JSON.parse(JSON.stringify(co.props || [])), flags: JSON.parse(JSON.stringify(co.flags)), cash: co.cash, books: JSON.parse(JSON.stringify(co.bk.w)), reval: co.reval || 0 });
  const fresh = () => { if (!deserialize(save)) throw new Error('reload'); };
  // 1. the weekly model of every company, three weeks in a row, on a fresh copy
  for (const key in ids) {
    fresh();
    const co = getCo(ids[key]), bd = BD[co.type];
    const rows = [];
    for (let k = 0; k < 3; k++) {
      S.week++;
      const ctx = { D: 0, cap: 0, units: 0, rev: 0, cogs: 0, util: 0, price: 0, extra: {}, cr: 0 };
      FAM[bd.fam].custom(co, bd, ctx);
      rows.push({ week: S.week, ctx: ctxOf(ctx), rs: S.rs, state: snap(co), lastW: co.lastW });
    }
    out.weekly[key] = rows;
  }
  // 2. values: assets, debts, company value and net worth on the saved game
  out.values = {};
  fresh();
  for (const key in ids) {
    const co = getCo(ids[key]);
    out.values[key] = { assets: companyAssets(co), debts: companyDebts(co), value: companyValue(co), coAssets: coAssets(co) };
  }
  out.netWorth = netWorth();
  // 3. property operations
  for (const key of ['resrent', 'comrent', 'parking']) {
    fresh();
    const co = getCo(ids[key]);
    const o = {};
    o.listings = propListings(co);
    o.listings2 = (S.week += 4, propListings(co));
    S.week -= 4;
    const loansBefore = S.loans.length;
    o.buyLoan = buyProp(co, o.listings[0], 0.5, 0);
    o.afterBuy = snap(co);
    o.newLoan = JSON.parse(JSON.stringify(S.loans.filter(l => l.co === co.id).slice(-1)[0] || null));
    o.loanCount = S.loans.length - loansBefore;
    o.buyBigLoan = buyProp(co, o.listings[3], 0.9, 0);
    o.buyNoLoan = buyProp(co, o.listings[1], 0, 0);
    o.afterBuy2 = snap(co);
    o.renovate = renovateProp(co, co.props[0].id);
    o.afterReno = snap(co);
    const pid = co.props[co.props.length - 1].id;
    const cashBefore = co.cash;
    o.sellNet = sellProp(co, pid);
    o.afterSell = snap(co);
    o.sellCashDelta = co.cash - cashBefore;
    o.loansAfterSell = S.loans.filter(l => l.co === co.id).map(l => ({ bal: l.bal, pay: l.pay, margin: l.margin }));
    out.ops[key] = o;
  }
  // 4. commercial lease of space and sale of the building to a buyer
  {
    fresh();
    const co = getCo(ids.comrent);
    const p = co.props[0];
    const tn = propTenants(co, p);
    const o = { tenants: tn.map(t => ({ m2: t.m2, rw: t.rw, yrs: t.yrs, buyPct: t.buyPct })), free: p.units - (p.lu || 0) };
    o.lease = leaseTo(co, p.id, { name: 'Test tenant', m2: 100, rw: p.rentU * 1.05, yrs: 5 });
    o.afterLease = JSON.parse(JSON.stringify(co.props[0]));
    const ctx = { D: 0, cap: 0, units: 0, rev: 0, cogs: 0, util: 0, price: 0, extra: {}, cr: 0 };
    S.week++;
    FAM.rent.custom(co, BD[co.type], ctx);
    o.weeklyWithLease = ctxOf(ctx);
    const cash0 = co.cash;
    o.sellTo = sellPropTo(co, p.id, { name: 'Buyer', buyPct: 1.07 });
    o.sellToDelta = co.cash - cash0;
    o.sellToBooks = JSON.parse(JSON.stringify(co.bk.w));
    out.ops.lease = o;
  }
  // 5. insurance products and verification
  {
    fresh();
    const co = getCo(ids.insco);
    const o = {};
    o.prods = JSON.parse(JSON.stringify(co.fm.prods));
    o.agents = co.staff.filter(s => s.role === 'agent').map(s => ({ id: s.id, ver: s.ver || null }));
    o.setProd = setProd(co, 'life', true);
    o.afterProd = { prods: JSON.parse(JSON.stringify(co.fm.prods)), doc: JSON.parse(JSON.stringify(co.docs.ins_life || null)), cash: co.cash };
    const ag = co.staff.find(s => s.role === 'agent');
    if (ag) {
      const rs0 = S.rs, c0 = co.cash;
      o.verify = verifyAgent(co, ag.id, 'life');
      o.afterVerify = { ver: JSON.parse(JSON.stringify(ag.ver)), cashDelta: co.cash - c0, week: S.week };
    }
    o.stop = setProd(co, 'life', false);
    o.afterStop = JSON.parse(JSON.stringify(co.fm.prods));
    o.checklist = openChecklist(co).map(x => ({ k: x.k, ok: x.ok }));
    out.ops.insco = o;
  }
  // 6. events
  out.events = {};
  for (const [key, ev] of [['insco', 'f_storm'], ['bank', 'f_run'], ['bankw', 'f_run'], ['bank', 'f_default']]) {
    fresh();
    const co = getCo(ids[key]);
    const bd = BD[co.type];
    const cash0 = co.cash, rs0 = S.rs;
    SPEC[ev](co, bd, EV[ev], {});
    out.events[key + ':' + ev] = { rs: S.rs, cashDelta: co.cash - cash0, fm: JSON.parse(JSON.stringify(co.fm)), books: JSON.parse(JSON.stringify(co.bk.w)) };
  }
  {
    fresh();
    const co = getCo(ids.fund);
    const aum0 = co.fm.aum;
    applyFx(co, { aum: 0.92 }, EV.f_fund, {});
    out.events['fund:aum'] = { aum0, aum1: co.fm.aum };
  }
  // 7. a bank loan out of the group, repaid (own bank lends cheaper)
  {
    fresh();
    const co = getCo(ids.resrent);
    const off = loanOffer('biz', 1000000, co);
    out.ownBankOffer = { margin: off.margin, ownBank: off.ownBank, max: off.max };
  }
  // 8. year-end performance fee of the fund
  {
    fresh();
    const co = getCo(ids.fund);
    co.fm.nav = 1.3; co.fm.hwm = 1.0; co.fm.nav52 = 1.2;
    while (!isYearEnd(S.week)) S.week++;
    const bd = BD[co.type];
    const ctx = { D: 0, cap: 0, units: 0, rev: 0, cogs: 0, util: 0, price: 0, extra: {}, cr: 0 };
    const c0 = co.cash;
    FAM.fin.custom(co, bd, ctx);
    out.yearEnd = { week: S.week, cashDelta: co.cash - c0, hwm: co.fm.hwm, nav: co.fm.nav, aum: co.fm.aum, rs: S.rs, rev: ctx.rev, books: JSON.parse(JSON.stringify(co.bk.w)), save: null };
    out.yearEndSetup = { nav: 1.3, hwm: 1.0, nav52: 1.2 };
  }
  return JSON.stringify(out);
})()
