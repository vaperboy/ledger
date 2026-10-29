(() => {
  // Who changes a company's awareness in the original, and by how much (sum of increases and decreases per calling function),
  // over 12 seeds, weeks 8-26. window.TRADE selects the trade (default courier).
  const t = window.TRADE || 'courier';
  const tally = {};
  for (const sd of Array.from({ length: 12 }, (_, i) => 1000 + i * 37)) {
    newGame({ seed: sd, country: 'UK', name: 'S' });
    S.cash += 5e7;
    const o = { name: 'X', form: 'AS', acc: S.pool.acc[0].id };
    const co = startCompany(t, o);
    injectCash(co, Math.round(setupEstimate(t, o).total * 1.6));
    setupAndOpen(co);
    S.dmode = 1;
    let v = co.aware;
    Object.defineProperty(co, 'aware', {
      get() { return v; },
      set(x) {
        if (S.week >= 8) {
          const st = (new Error().stack || '').split('\n').slice(2, 4).map(l => (l.match(/at (\S+)/) || [])[1]).join('<');
          const k = (x > v ? '+' : '-') + st;
          tally[k] = (tally[k] || 0) + (x - v);
        }
        v = x;
      },
      configurable: true
    });
    for (let g = 0; S.week < 26 && g < 26 * 7; g++) {
      dayStep();
      S.inbox.forEach(m => { if (m.status === 'open' && m.act && /^pay29/.test(m.act)) { ACTS[m.act](m, 0); m.status = 'done'; } });
    }
  }
  const r = {}; for (const k in tally) r[k] = Math.round(tally[k] * 10 / 12) / 10;
  return JSON.stringify(r, null, 0);
})()
