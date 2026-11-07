(() => {
  const fnKeys = [];
  const clean = (v, path) => {
    if (typeof v === 'function') { fnKeys.push(path); return undefined; }
    if (Array.isArray(v)) return v.map((x, i) => clean(x, path + '[' + i + ']'));
    if (v && typeof v === 'object') { const o = {}; for (const k of Object.keys(v)) { const c = clean(v[k], path + '.' + k); if (c !== undefined) o[k] = c; } return o; }
    if (typeof v === 'number' && !isFinite(v)) return null;
    return v;
  };
  const preCalib = {};
  Object.keys(BD).forEach(k => { preCalib[k] = !!BD[k]._c; });
  const trades = {};
  Object.keys(BD).forEach(k => { calib(BD[k]); });
  Object.keys(BD).forEach(k => { trades[k] = clean(BD[k], 'BD.' + k); });
  const tables = {};
  ['ROLES','PREM','VEH','SEAS','DOCS','SALES_ROLES','FIT','PL_TIERS','PL_TIERS_B','MGR_TYPES','INS_PRODS','TENURE_Y','TIERS','CAT_TIER','PRICE_PM','PRICE_NAMES','SENS','DK','FULL_H','HCAP','OFFICE_T','HQ_ROLES','FAM_NOUN','EXPRO'].forEach(n => { try { tables[n] = clean(eval(n), n); } catch (e) { tables[n] = 'ERR ' + e.message; } });
  return JSON.stringify({ trades, order: BD_ORDER, tables, fnKeys, preCalib });
})()
