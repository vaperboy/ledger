(() => {
  // Per-week averages over 12 seeds (day mode, as stats_run_day.js): demand, capacity, units, revenue, awareness, reputation,
  // quality, staff, cash, plus the books by category at week 26. Compare with the native test testPrintWeekTrace.
  const trades = ['gym', 'bakery', 'restaurant', 'cafe', 'courier', 'barber', 'boutique', 'webdev'];
  const seeds = Array.from({ length: 12 }, (_, i) => 1000 + i * 37);
  const out = {};
  for (const t of trades) {
    const W = Array.from({ length: 26 }, () => ({ D: 0, cap: 0, units: 0, rev: 0, cogs: 0, aware: 0, rep: 0, q: 0, staff: 0, cash: 0, n: 0 }));
    const books = {}; let nb = 0, inv = 0, openW = 0, no = 0;
    for (const sd of seeds) {
      newGame({ seed: sd, country: 'UK', name: 'S' });
      S.cash += 5e7;
      const o = { name: 'X', form: 'AS', acc: S.pool.acc[0].id };
      const co = startCompany(t, o);
      injectCash(co, Math.round(setupEstimate(t, o).total * 1.6));
      setupAndOpen(co);
      S.dmode = 1;
      let pw = S.week;
      for (let g = 0; S.week < 26 && g < 26 * 7; g++) {
        dayStep();
        S.inbox.forEach(m => { if (m.status === 'open' && m.act && /^pay29/.test(m.act)) { ACTS[m.act](m, 0); m.status = 'done'; } });
        if (S.week !== pw) {
          pw = S.week;
          const w = W[S.week - 1], lw = co.lastW || {};
          w.D += lw.D || 0; w.cap += lw.cap || 0; w.units += lw.units || 0; w.rev += lw.rev || 0; w.cogs += lw.cogs || 0;
          w.aware += co.aware; w.rep += co.rep; w.q += co.q; w.staff += co.staff.length; w.cash += co.cash; w.n++;
        }
      }
      for (const k in co.bk.t) books[k] = (books[k] || 0) + co.bk.t[k];
      nb++; inv += co.inv || 0; if (co.wOpen != null) { openW += co.wOpen; no++; }
    }
    for (const k in books) books[k] = Math.round(books[k] / nb);
    out[t] = { weeks: W.map(w => { const r = {}; for (const k in w) if (k !== 'n') r[k] = Math.round(w[k] / Math.max(1, w.n)); return r; }), books, inv: Math.round(inv / nb), openWeek: no ? openW / no : null };
  }
  return JSON.stringify(out);
})()
