(() => {
  let kept = 0, n = 0, quits = 0, notes = {};
  for (let sd = 1; sd <= 30; sd++) {
    newGame({ seed: sd * 13, country: 'UK', name: 'S' });
    S.cash += 5e7;
    const o = { name: 'X', form: 'AS', acc: S.pool.acc[0].id };
    const co = startCompany('cafe', o);
    injectCash(co, Math.round(setupEstimate('cafe', o).total * 1.6));
    setupAndOpen(co);
    for (let w = 0; w < 26; w++) nextWeek();
    n++; if (co.staff.length) kept++;
    S.rep && S.rep.ev && S.rep.ev.forEach(e => { if (/notice|left|quit/.test(e.t)) quits++; });
  }
  return JSON.stringify({ kept, n });
})()
