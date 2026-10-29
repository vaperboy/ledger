(() => {
  const out = {};
  out.version = VERSION;
  out.countries = CO_ORDER.map(k => [k, CO[k].name, CO[k].cur]);
  out.trades = Object.values(BD).map(b => [b.id, b.n, b.fam, b.cat, b.ticket, (b.eq || []).length, (b.std || []).length, (b.knobs || []).length]);
  out.screens = Object.keys(UI.V).sort();
  out.actions = Object.keys(UI.ACT).sort();
  out.companyTabs = (typeof CT !== "undefined" ? Object.keys(CT).sort() : []);
  out.pipelines = {};
  Object.keys(PIPES).forEach(k => { out.pipelines[k] = PIPES[k].map(s => s.order + ' ' + s.id); });
  try { out.events = Object.keys(EV).length; out.eventIds = Object.keys(EV).slice(0, 400); } catch (e) { out.events = 'ERR'; }
  try { out.famEv = Object.keys(FAM_EV).length; } catch (e) { }
  try { out.docs = Object.keys(DOCS); } catch (e) { }
  try { out.roles = Object.keys(ROLES); } catch (e) { }
  try { out.channels = Object.keys(CH).map(k => [k, CH[k].n || CH[k].name]); } catch (e) { }
  try { out.stocks = STOCK_DEF.length; out.crypto = CRYPTO_DEF.length; out.funds = Object.keys(FUNDS); } catch (e) { }
  try { out.ach = Object.keys(window.R28 || {}).length; } catch (e) { }
  return JSON.stringify(out);
})()
