(() => {
  const trades = ['cafe', 'gym', 'restaurant', 'bakery'];
  const seeds = Array.from({ length: 12 }, (_, i) => 1000 + i * 37);
  const out = {};
  for (const t of trades) {
    const acc = { D: 0, cap: 0, units: 0, rev: 0, staff: 0, n: 0, rep: 0, q: 0, aware: 0 };
    for (const sd of seeds) {
      newGame({ seed: sd, country: 'UK', name: 'S' });
      S.cash += 5e7;
      const o = { name: 'X', form: 'AS', acc: S.pool.acc[0].id };
      const co = startCompany(t, o);
      injectCash(co, Math.round(setupEstimate(t, o).total * 1.6));
      setupAndOpen(co);
      for (let w = 0; w < 26; w++) {
        nextWeek();
        if (w >= 12 && co.lastW) { acc.D += co.lastW.D; acc.cap += co.lastW.cap; acc.units += co.lastW.units; acc.rev += co.lastW.rev; acc.staff += co.staff.length; acc.rep += co.rep; acc.q += co.q; acc.aware += co.aware; acc.n++; }
      }
    }
    for (const k in acc) if (k !== 'n') acc[k] = +(acc[k] / acc.n).toFixed(1);
    out[t] = acc;
  }
  return JSON.stringify(out);
})()
