(() => {
  // What the original has after "fill in what is missing", seed 1000: size, money injected, money left, premises, staff pay, equipment.
  const out = {};
  for (const t of ['cafe', 'gym', 'restaurant', 'bakery', 'courier', 'barber', 'boutique', 'webdev']) {
    newGame({ seed: 1000, country: 'UK', name: 'S' });
    S.cash += 5e7;
    const o = { name: 'X', form: 'AS', acc: S.pool.acc[0].id };
    const co = startCompany(t, o);
    const est = setupEstimate(t, o);
    const inj = Math.round(est.total * 1.6);
    injectCash(co, inj);
    const before = co.cash;
    autoSetup(co, { force: 1 });
    const eq = {}; let eqc = 0; for (const k in co.eq) { eq[k] = Math.round(co.eq[k].cost || 0); eqc += eq[k]; }
    out[t] = { size: co.size, est: Object.fromEntries(Object.entries(est).map(([k, v]) => [k, typeof v === 'number' ? Math.round(v) : v])), inj, before: Math.round(before), after: Math.round(co.cash), spent: Math.round(before - co.cash), prem: co.prem && { m2: co.prem.m2, rent: Math.round(co.prem.rent), dep: Math.round(co.prem.dep || 0), kind: co.prem.kind }, staff: co.staff.map(s => s.role + ':' + Math.round(s.wage)), eqc, veh: co.veh.length, inv: Math.round(co.inv || 0), mgr: !!co.mgr, ohrs: co.ohrs };
  }
  return JSON.stringify(out, null, 1);
})()
