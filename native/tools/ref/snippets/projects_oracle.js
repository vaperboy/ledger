(() => {
  // Project businesses in the ORIGINAL game: five job trades and a developer, opened and played 40 days.
  // Returns the save (to load in Swift) and, for each company, the numbers the hours model works out each day
  // (D, capacity, ticket multiplier, hour value, hours a week, average hours of a request) and the developer's start() figures.
  newGame({ seed: 777, country: 'UK', name: 'Proj' });
  S.cash += 2e9;
  const types = ['plumber', 'electrician', 'construction', 'engcons', 'event', 'realdev'];
  types.forEach((t, i) => {
    const o = { name: 'P' + t, form: 'AS', acc: S.pool.acc[0].id };
    const co = startCompany(t, o);
    if (typeof co === 'string') return;
    injectCash(co, Math.round(setupEstimate(t, o).total * 2) + (t === 'realdev' ? 6e7 : 0));
    setupAndOpen(co);
    co.staff.forEach(s => onbItems(s.role).forEach(it => { s.onb = s.onb || {}; s.onb[it[0]] = 1; }));
  });
  S.dmode = 1;
  for (let d = 0; d < 40; d++) { dayStep(); S.inbox.forEach(m => { if (m.status === 'open' && m.act && /^pay29/.test(m.act)) { ACTS[m.act](m, 0); m.status = 'done'; } }); }
  const save = serialize();
  const out = { save, cos: {} };
  S.cos.forEach(co => {
    if (co.st !== 'open') return;
    const bd = BD[co.type];
    const dm = demand(co, bd), cp = capacity(co, bd);
    const o = { type: co.type, D: dm.D, cap: cp.cap, ticketMult: ticketMult(co, bd), knobT: knobFx(co, 't'), knobTT: knobFx(co, 'tt'), jobScale: R8.jobScale(co), rep: co.rep, vat: vatRate(co) };
    if (bd.tw.dev) {
      const r = [];
      [[1, true], [0.5, false], [0.4, true]].forEach(([sz, debt]) => {
        const cash0 = co.cash, n0 = co.fm.proj.length, loans0 = S.loans.length;
        const res = FAM.dev.start(co, bd, { size: sz, debt });
        const p = co.fm.proj[co.fm.proj.length - 1];
        r.push({ sz, debt, res, cashDelta: co.cash - cash0, p: res === 'ok' ? { units: p.units, land: p.land, build: p.build, price: p.price, wip: p.wip, st: p.st, loan: p.loan ? S.loans.find(l => l.id === p.loan).bal : 0 } : null });
      });
      o.starts = r;
    } else {
      // one day of work (adds its own state, so it comes last)
      const fm = co.fm;
      const L = fm.d41 && fm.d41.w === S.week ? fm.d41 : null;
      const log = { w: S.week - 1, days: {}, req: 0, took: 0, lost: 0, big: 0, tooBig: 0, used: 0, H: 0, Hw: 0, Dh: 0, rev: 0, cogs: 0, paid: 0, units: 0, fin: [0, 0, 0], names: [] };
      R41.projDay(co, bd, log, S.week - 1, 3);
      o.hw41 = fm.hw41; o.hvl41 = fm.hvl41; o.avgH41 = fm.avgH41; o.Dh = log.Dh; o.Hw = log.Hw; o.H = log.H;
    }
    out.cos[co.id] = o;
  });
  return JSON.stringify(out);
})()
