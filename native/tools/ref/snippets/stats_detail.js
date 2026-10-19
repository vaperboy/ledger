(() => {
  const out = {};
  for (const t of ['restaurant', 'courier', 'barber', 'cafe']) {
    const rows = [];
    for (const sd of [1000, 1037, 1074, 1111]) {
      newGame({ seed: sd, country: 'UK', name: 'S' });
      S.cash += 5e7;
      const o = { name: 'X', form: 'AS', acc: S.pool.acc[0].id };
      const co = startCompany(t, o);
      injectCash(co, Math.round(setupEstimate(t, o).total * 1.6));
      setupAndOpen(co);
      for (let w = 0; w < 26; w++) nextWeek();
      const lw = co.lastW;
      rows.push({ D: Math.round(lw.D), cap: Math.round(lw.cap), units: Math.round(lw.units), rev: lw.rev, staff: co.staff.map(s => s.role).join(','), aware: Math.round(co.aware), rep: Math.round(co.rep), q: Math.round(co.q), size: co.size, eq: Object.keys(co.eq).join(','), veh: co.veh.length, bot: co.dbg && co.dbg.bot });
    }
    out[t] = rows;
  }
  return JSON.stringify(out, null, 0);
})()
