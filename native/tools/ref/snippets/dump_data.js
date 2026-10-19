(() => {
  const fnKeys = [];
  const clean = (v, path) => {
    if (typeof v === 'function') { fnKeys.push(path); return undefined; }
    if (Array.isArray(v)) return v.map((x, i) => clean(x, path + '[' + i + ']'));
    if (v && typeof v === 'object') { const o = {}; for (const k of Object.keys(v)) { const c = clean(v[k], path + '.' + k); if (c !== undefined) o[k] = c; } return o; }
    if (typeof v === 'number' && !isFinite(v)) return null;
    return v;
  };
  const out = { CO_ORDER, CO: {}, BD: {}, BD_ORDER };
  for (const k of CO_ORDER) out.CO[k] = clean(CO[k], 'CO.' + k);
  for (const k of Object.keys(BD)) out.BD[k] = clean(BD[k], 'BD.' + k);
  out.fnKeys = fnKeys;
  return JSON.stringify(out);
})()
