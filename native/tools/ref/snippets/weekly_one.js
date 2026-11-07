(() => {
  // One company, one seed, week by week: cash, inventory, VAT owed, payables, receivables, and the cumulative books. For tracing cash gaps
  // (compare with the native test testPrintWeeklyOne). Trade and seed are read from window.TRADE / window.SEED (default boutique, 1000).
  const t = window.TRADE || 'boutique', sd = window.SEED || 1000;
  newGame({ seed: sd, country: 'UK', name: 'S' });
  S.cash += 5e7;
  const o = { name: 'X', form: 'AS', acc: S.pool.acc[0].id };
  const co = startCompany(t, o);
  injectCash(co, Math.round(setupEstimate(t, o).total * 1.6));
  setupAndOpen(co);
  S.dmode = 1;
  const rows = [];
  let pw = S.week;
  const snap = () => ({ w: S.week, cash: Math.round(co.cash), inv: Math.round(co.inv || 0), vat: Math.round(co.vatAcc || 0), pay: Object.fromEntries(Object.entries(co.pay || {}).map(([k, v]) => [k, Math.round(v)])), recv: Math.round((co.recv || []).reduce((a, r) => a + r.a, 0)), bk: Object.fromEntries(Object.entries(co.bk.t).map(([k, v]) => [k, Math.round(v)])) });
  rows.push(snap());
  for (let g = 0; S.week < 26 && g < 26 * 7; g++) {
    dayStep();
    S.inbox.forEach(m => { if (m.status === 'open' && m.act && /^pay29/.test(m.act)) { ACTS[m.act](m, 0); m.status = 'done'; } });
    if (S.week !== pw) { pw = S.week; rows.push(snap()); }
  }
  return JSON.stringify(rows);
})()
