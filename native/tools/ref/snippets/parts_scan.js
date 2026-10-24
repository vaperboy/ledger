(() => {
  newGame({ seed: 777, country: 'UK', name: 'Parts' });
  S.cash += 5e8;
  const types = ['cafe', 'barber', 'boutique', 'webdev', 'bakery', 'taxi', 'gym', 'plumber', 'hotel', 'hardware', 'cleaning', 'courier', 'resrent', 'insco', 'foodtruck', 'physio', 'brewery'];
  const out = {};
  types.forEach((t, i) => {
    try {
      const o = { name: 'P' + t, form: 'AS', acc: S.pool.acc[0].id };
      const co = startCompany(t, o);
      if (typeof co === 'string') { out[t] = 'START ' + co; return; }
      injectCash(co, Math.round(setupEstimate(t, o).total * 2));
      setupAndOpen(co);
      co.staff.forEach(s => onbItems(s.role).forEach(it => { s.onb = s.onb || {}; s.onb[it[0]] = 1; }));
      for (let w = 0; w < 6; w++) nextWeek();
      const dm = demand(co, BD[t]), cp = capacity(co, BD[t]);
      out[t] = { st: co.st, D: dm.D, parts: dm.parts, cap: cp.cap, bot: cp.bot && cp.bot.label, cparts: cp.parts.map(p => [p.k, +p.have.toFixed(2), +p.cap.toFixed(1)]), price: ticketEff(co, BD[t]), lw: co.lastW };
    } catch (e) { out[t] = 'ERR ' + e.message; }
  });
  return JSON.stringify(out);
})()
