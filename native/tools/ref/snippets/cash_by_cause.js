(() => {
  // Where does the company's cash go? Tallies every cash movement of the company by the function that caused it (second stack frame),
  // for one seed (default 1000) of one trade, 26 weeks, day mode. Set TRADE / SEED before evaluating, e.g. via the wrapper in ev.js -e.
  const t = window.TRADE || 'boutique', sd = window.SEED || 1000;
  newGame({ seed: sd, country: 'UK', name: 'S' });
  S.cash += 5e7;
  const o = { name: 'X', form: 'AS', acc: S.pool.acc[0].id };
  const co = startCompany(t, o);
  injectCash(co, Math.round(setupEstimate(t, o).total * 1.6));
  setupAndOpen(co);
  S.dmode = 1;
  const tally = {};
  const orig = window.cashRaw;
  window.cashRaw = function (h, amt) {
    if (h === co) {
      const st = (new Error().stack || '').split('\n').slice(2, 6).map(l => (l.match(/at (\S+)/) || [])[1]).filter(Boolean);
      const k = st.filter(x => !/^(moveCash|payCoCore|payCo|coIn|Object\.|eval)/.test(x))[0] || st[0] || '?';
      tally[k] = (tally[k] || 0) + amt;
    }
    return orig.apply(this, arguments);
  };
  const c0 = co.cash;
  for (let g = 0; S.week < 26 && g < 26 * 7; g++) {
    dayStep();
    S.inbox.forEach(m => { if (m.status === 'open' && m.act && /^pay29/.test(m.act)) { ACTS[m.act](m, 0); m.status = 'done'; } });
  }
  window.cashRaw = orig;
  const r = {}; for (const k in tally) r[k] = Math.round(tally[k]);
  return JSON.stringify({ start: Math.round(c0), end: Math.round(co.cash), tally: r, books: co.bk.t });
})()
