(() => {
  newGame({ seed: 12345, country: 'UK', name: 'Test Player' });
  S.cash += 300000000;
  const o = { name: 'Test Cafe', form: 'AS', acc: S.pool.acc[0].id };
  const co = startCompany('cafe', o);
  if (typeof co === 'string') return 'START ' + co;
  injectCash(co, Math.round(setupEstimate('cafe', o).total * 1.6));
  setupAndOpen(co);
  const out = { start: serialize(), weeks: [] };
  for (let w = 0; w < 12; w++) {
    nextWeek();
    const lw = co.lastW || {};
    out.weeks.push({ w: S.week, rs: S.rs, cash: co.cash, me: S.cash, rev: lw.rev, units: lw.units, D: lw.D, cap: lw.cap, cogs: lw.cogs, rep: co.rep, aware: co.aware, st: co.st });
  }
  out.end = serialize();
  return JSON.stringify(out);
})()
