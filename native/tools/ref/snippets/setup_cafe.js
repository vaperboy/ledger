(() => {
  const out = {};
  for (const t of ['cafe', 'gym']) {
    newGame({ seed: 1000, country: 'UK', name: 'S' });
    S.cash += 5e7;
    const o = { name: 'X', form: 'AS', acc: S.pool.acc[0].id };
    const co = startCompany(t, o);
    const est = setupEstimate(t, o);
    const c0 = Math.round(est.total * 1.6);
    injectCash(co, c0);
    const cashBefore = co.cash;
    const log = autoSetup(co, { force: 1 });
    out[t] = { est, injected: c0, cashBefore: Math.round(cashBefore), cashAfter: Math.round(co.cash), log, size: co.size, eq: JSON.stringify(co.eq), veh: co.veh.length, prem: JSON.stringify(co.prem), docs: Object.keys(co.docs || {}).join(',') };
  }
  return JSON.stringify(out);
})()
