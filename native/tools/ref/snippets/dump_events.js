(() => {
  const out = { events: {}, fnForms: [], specials: Object.keys(SPEC), fam: {}, keys: {} };
  const seenKeys = {};
  const ser = (v, path) => {
    if (typeof v === 'function') { const s = v.toString(); out.fnForms.push(path + ' :: ' + s); return { $fn: s }; }
    if (Array.isArray(v)) return v.map((x, i) => ser(x, path + '[' + i + ']'));
    if (v && typeof v === 'object') { const o = {}; for (const k in v) { seenKeys[k] = 1; o[k] = ser(v[k], path + '.' + k); } return o; }
    return v;
  };
  Object.keys(EV).forEach(id => { out.events[id] = ser(EV[id], id); });
  out.keys = Object.keys(seenKeys);
  try { out.famEv = ser(FAM_EV, 'FAM_EV'); } catch (e) { }
  return JSON.stringify(out);
})()
