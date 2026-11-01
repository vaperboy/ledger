(() => {
  newGame({ seed: 777, country: 'UK', name: 'Parts' });
  S.cash += 5e8;
  const types = ['cafe', 'barber', 'boutique', 'webdev', 'bakery', 'taxi', 'gym', 'cleaning', 'courier', 'hotel', 'hardware', 'foodtruck', 'physio', 'brewery', 'restaurant', 'grocery', 'kiosk', 'pets', 'carclean', 'tutor', 'factory', 'trucking', 'nightclub', 'photo', 'handy'];
  const ids = [];
  types.forEach((t, i) => {
    try {
      const o = { name: 'P' + t, form: i % 2 ? 'AS' : 'ENK', acc: S.pool.acc[0].id };
      const co = startCompany(t, o);
      if (typeof co === 'string') return;
      injectCash(co, Math.round(setupEstimate(t, o).total * 2));
      setupAndOpen(co);
      co.staff.forEach(s => onbItems(s.role).forEach(it => { s.onb = s.onb || {}; s.onb[it[0]] = 1; }));
      ids.push(co.id);
    } catch (e) { }
  });
  for (let w = 0; w < 10; w++) nextWeek();
  const out = { save: serialize(), cos: {} };
  S.cos.forEach(co => {
    if (co.st !== 'open') return;
    const bd = BD[co.type];
    const dm = demand(co, bd), cp = capacity(co, bd);
    out.cos[co.id] = { type: co.type, D: dm.D, parts: dm.parts, cap: cp.cap, cparts: cp.parts.map(p => ({ k: p.k, have: p.have, cap: p.cap, capPer: p.capPer, need: p.need })), bot: cp.bot && cp.bot.k, owner: cp.owner, price: ticketEff(co, bd), priceMult: ticketMult(co, bd), vat: vatRate(co), qt: qualityTarget(co, bd, 0.6), repMult: repMult(co), mkt: mktMult(co), pDem: priceDem(co, bd), rivalMult: rivalMult(co, bd), knobD: knobFx(co, 'd'), knobK: knobFx(co, 'k'), knobT: knobFx(co, 't'), reach: reachOf(co).mult, own: ownShare(co), season: seasOf(bd) };
  });
  return JSON.stringify(out);
})()
