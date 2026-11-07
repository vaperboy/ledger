(() => {
  const out = {};
  for (const t of ['cafe', 'gym', 'restaurant']) {
    newGame({ seed: 1000, country: 'UK', name: 'S' });
    S.cash += 5e7;
    const o = { name: 'X', form: 'AS', acc: S.pool.acc[0].id };
    const co = startCompany(t, o);
    const c0 = Math.round(setupEstimate(t, o).total * 1.6);
    injectCash(co, c0);
    setupAndOpen(co);
    const cashAfterSetup = co.cash;
    for (let w = 0; w < 26; w++) nextWeek();
    const b = {}; for (const k in co.bk.t) b[k] = Math.round(co.bk.t[k]);
    out[t] = { injected: c0, cashAfterSetup: Math.round(cashAfterSetup), cashEnd: Math.round(co.cash), books: b, staff: co.staff.length, inv: Math.round(co.inv || 0), pay: Object.keys(co.pay || {}).length };
  }
  return JSON.stringify(out);
})()
