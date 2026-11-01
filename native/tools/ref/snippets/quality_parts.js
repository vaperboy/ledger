(() => {
  // The parts of the quality target for several seeds at week 20: staff skill, owner skill, equipment condition, knobs, maintenance.
  // Compare with the native test testPrintQualityParts.
  const t = window.TRADE || 'gym';
  const out = [];
  for (const sd of [1000, 1037, 1074, 1111]) {
    newGame({ seed: sd, country: 'UK', name: 'S' });
    S.cash += 5e7;
    const o = { name: 'X', form: 'AS', acc: S.pool.acc[0].id };
    const co = startCompany(t, o);
    injectCash(co, Math.round(setupEstimate(t, o).total * 1.6));
    setupAndOpen(co);
    S.dmode = 1;
    for (let g = 0; S.week < 20 && g < 26 * 7; g++) {
      dayStep();
      S.inbox.forEach(m => { if (m.status === 'open' && m.act && /^pay29/.test(m.act)) { ACTS[m.act](m, 0); m.status = 'done'; } });
    }
    const bd = BD[co.type];
    const sk = co.staff.map(s => Math.round(staffSkill(s) * 10) / 10);
    const eq = bd.eq.filter(e => e.fl.indexOf('q') >= 0).map(e => [e.id, +(eqCondOf(co, e)).toFixed(3), eqN(co, e)]);
    out.push({ sd, week: S.week, q: +co.q.toFixed(1), rep: +co.rep.toFixed(1), oskill: +co.oskill.toFixed(1), ohrs: co.ohrs, maint: co.maint, sk, eq, qt: +qualityTarget(co, bd, 0.7).toFixed(1), knobQ: +knobFx(co, 'q', 'sum').toFixed(2), goodsQ: goodsEff(co).q, staff: co.staff.length });
  }
  return JSON.stringify(out);
})()
