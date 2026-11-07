(() => {
  const out = [];
  for (const sd of [1000, 1037]) {
    newGame({ seed: sd, country: 'UK', name: 'S' });
    S.cash += 5e7;
    const o = { name: 'X', form: 'AS', acc: S.pool.acc[0].id };
    const co = startCompany('cafe', o);
    injectCash(co, Math.round(setupEstimate('cafe', o).total * 1.6));
    setupAndOpen(co);
    const rows = [];
    for (let w = 0; w < 26; w++) { nextWeek(); if (w % 5 == 0 || w == 25) rows.push([S.week, +co.aware.toFixed(1), co.aw23, +ratingOf(co).toFixed(2), Math.round(co.rep), Math.round(co.q), co.wOpen]); }
    out.push(rows);
  }
  return JSON.stringify(out);
})()
