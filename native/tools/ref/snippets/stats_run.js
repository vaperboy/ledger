(() => {
  const trades = ['cafe', 'barber', 'gym', 'restaurant', 'courier', 'boutique', 'webdev', 'bakery'];
  const SEED0 = 1000, STEP = 37; const seeds = Array.from({ length: 12 }, (_, i) => SEED0 + i * STEP);
  const out = {};
  for (const t of trades) {
    let rev = 0, cogs = 0, wages = 0, n = 0, cashEnd = 0, opened = 0, bust = 0;
    for (const sd of seeds) {
      newGame({ seed: sd, country: 'UK', name: 'S' });
      S.cash += 5e7;
      const o = { name: 'X', form: 'AS', acc: S.pool.acc[0].id };
      const co = startCompany(t, o);
      if (typeof co === 'string') continue;
      injectCash(co, Math.round(setupEstimate(t, o).total * 1.6));
      setupAndOpen(co);
      const w0 = S.week;
      for (let w = 0; w < 26; w++) nextWeek();
      if (co.st === 'bust') bust++;
      if (co.wOpen != null) opened++;
      // sum books over last 20 weeks from monthly history
      const h = co.hist.slice(-5);
      h.forEach(x => { rev += x.rev; n++; });
      cashEnd += co.cash;
    }
    out[t] = { revPerMonth: n ? rev / n : 0, cashEnd: cashEnd / seeds.length, bust, opened, months: n };
  }
  return JSON.stringify(out);
})()
