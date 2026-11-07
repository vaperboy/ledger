// Builds the HTML replicas of the Home mockups and screenshots them (390x844, dark) with Playwright Chromium.
// Run:  node build.js   (from this folder). Output: ../png/{A,B,C}_{home,dayclose,weekreport}.png and the .html files next to this script.
// Colours, radii and type sizes mirror native/App/Ledger/Design/Theme.swift. These are replicas, NOT SwiftUI renders (no ImageRenderer on Linux).
const fs = require('fs'), path = require('path');
const { chromium } = require('playwright');

const CSS = `
:root{--page:#0F1011;--raised:#141516;--surface:#151617;--border:#2B2C2E;--bstrong:#3A3B3D;--divider:#242527;--ivory:#F1EBDD;--muted:#A19B8F;--faint:#8A857C;--dim:#75706A;--gold:#D6B889;--goldwash:rgba(214,184,137,.14);--gain:#7FC79B;--loss:#E58B78;--caution:#E0B064;--alert:#E5584B;}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:390px;height:844px;background:var(--page);overflow:hidden}
body{position:relative;font-family:Inter,-apple-system,sans-serif;color:var(--ivory);-webkit-font-smoothing:antialiased}
.serif{font-family:'Liberation Serif','Noto Serif','DejaVu Serif',Georgia,serif;font-weight:500}
.backdrop{position:absolute;inset:0;background:radial-gradient(circle at 50% 0,#1B1C1F 0,var(--page) 560px)}
.status{position:absolute;top:0;left:0;right:0;height:47px;display:flex;justify-content:space-between;align-items:flex-end;padding:0 30px 8px;font-size:15px;font-weight:600;z-index:5}
.scroll{position:absolute;top:47px;left:0;right:0;bottom:0;padding:12px 20px 0;overflow:hidden}
.caps{font-size:10.5px;font-weight:600;letter-spacing:1.6px;text-transform:uppercase;color:var(--gold)}
.card{background:var(--surface);border:1px solid var(--border);border-radius:14px;padding:14px 16px}
.hero{border-radius:16px}
.muted{color:var(--muted)}.faint{color:var(--faint)}.gain{color:var(--gain)}.loss{color:var(--loss)}
.gap{height:12px}
.btn{display:inline-flex;align-items:center;justify-content:center;border:1px solid var(--gold);border-radius:8px;color:var(--ivory);font-size:14px;font-weight:600;padding:9px 16px;background:transparent}
.btn.full{display:flex;width:100%;height:46px;font-size:16px}
.next{display:flex;align-items:center;justify-content:center;background:var(--gold);color:#0F1011;border-radius:999px;font-weight:600;font-size:16px;height:48px}
.link{color:var(--gold);font-size:14px;font-weight:600}
.pill{display:inline-block;font-size:11px;font-weight:600;color:var(--caution);border:1px solid rgba(224,176,100,.45);background:rgba(224,176,100,.1);border-radius:999px;padding:3px 9px;white-space:nowrap}
.row{display:flex;align-items:center;justify-content:space-between}
.hair{height:.5px;background:rgba(239,233,223,.09)}
/* guide card */
.guide h3{font-size:16px;font-weight:700;margin:6px 0 2px}.guide p{font-size:13.5px;color:var(--muted);line-height:1.35;margin-bottom:12px}
/* needs you */
.need{display:flex;justify-content:space-between;gap:10px;align-items:center}
.need b{font-size:14.5px;font-weight:600;display:block}.need span.s{font-size:12.5px;color:var(--muted);display:block;margin-top:2px}
/* strip */
.strip{display:flex;justify-content:space-between;align-items:center;padding:10px 14px;border:1px solid var(--border);border-radius:12px;background:var(--surface)}
.strip .f{display:flex;gap:12px;text-align:right}.strip .f div{font-size:10px;color:var(--faint)}.strip .f b{display:block;font-size:13px;font-weight:600;color:var(--ivory);font-variant-numeric:tabular-nums}
/* grid */
.grid{display:grid;grid-template-columns:repeat(4,1fr);row-gap:18px;column-gap:8px}
.app{text-align:center;position:relative}
.tile{width:62px;height:62px;margin:0 auto 6px;border-radius:15px;background:#17181A;border:1px solid #303134;display:flex;align-items:center;justify-content:center}
.tile svg{width:28px;height:28px;fill:none;stroke-width:1.5;stroke-linecap:round;stroke-linejoin:round}
.app span{font-size:11.5px;display:block;white-space:nowrap;overflow:hidden}
.bub{position:absolute;top:-5px;right:8px;min-width:18px;height:18px;border-radius:9px;background:var(--alert);color:#fff;font-size:11px;font-weight:700;display:flex;align-items:center;justify-content:center;padding:0 5px}
/* tab bar */
.tabbar{position:absolute;left:14px;right:14px;bottom:26px;height:58px;border-radius:999px;background:var(--raised);border:1px solid var(--border);box-shadow:0 4px 10px rgba(0,0,0,.35);display:flex;padding:0 6px;z-index:4}
.tab{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;font-size:10.5px;color:var(--muted);border-radius:999px;position:relative;margin:6px 0}
.tab svg{width:22px;height:22px;fill:none;stroke:var(--muted);stroke-width:1.5;stroke-linecap:round;stroke-linejoin:round}
.tab.on{background:var(--goldwash);color:var(--gold)}.tab.on svg{stroke:var(--gold)}
.tab .bub{top:-2px;right:10px;min-width:15px;height:15px;font-size:9.5px}
.homebar{position:absolute;bottom:8px;left:140px;width:110px;height:4px;border-radius:2px;background:rgba(241,235,221,.5);z-index:6}
/* segments */
.seg{display:flex;gap:5px}.seg i{flex:1;height:5px;border-radius:3px;background:rgba(239,233,223,.13)}.seg i.f{background:var(--gold)}.seg i.o{background:transparent;border:1px solid var(--gold)}
.seg.lg i{height:8px}
/* overlay */
.scrim{position:absolute;inset:0;background:rgba(0,0,0,.55);z-index:8}
.sheet{position:absolute;left:0;right:0;bottom:0;height:338px;z-index:9;background:var(--raised);border-radius:22px 22px 0 0;border-top:1px solid var(--bstrong);padding:22px 28px 40px;display:flex;flex-direction:column;align-items:center;text-align:center}
.sheet.amber{background:linear-gradient(rgba(224,176,100,.13),rgba(224,176,100,.13)),var(--raised);border-top-color:rgba(224,176,100,.5)}
.sheet .grab{width:38px;height:4px;border-radius:2px;background:var(--bstrong);margin-bottom:18px}
.sheet .big{font-size:34px;font-weight:700;margin:6px 0 10px;font-variant-numeric:tabular-nums}
.sheet .line{font-size:15px;color:var(--ivory);line-height:1.35;max-width:300px}
.sheet .seg{width:100%;margin-top:auto}
.sheet .tap{font-size:11px;color:var(--faint);margin-top:10px}
/* report */
.bars .b{margin:10px 0}.bars .b .l{display:flex;justify-content:space-between;font-size:13px;margin-bottom:5px}
.bars .t{height:12px;border-radius:6px;background:rgba(239,233,223,.06)}.bars .t i{display:block;height:12px;border-radius:6px}
.rec{display:flex;align-items:center;gap:8px;font-size:14px;color:var(--gold);font-weight:600}
`;

const G = {
  bank: 'M3 10l9-6 9 6M5 10v8M9.5 10v8M14.5 10v8M19 10v8M3 20h18',
  book: 'M5 4h11a3 3 0 013 3v13H8a3 3 0 01-3-3zM8 4v16',
  mail: 'M3 6h18v12H3zM3 7l9 6 9-6',
  news: 'M5 4h14v16H5zM8 8h8M8 12h8M8 16h5',
  sun: 'M12 8a4 4 0 100 8 4 4 0 000-8zM12 2v2M12 20v2M2 12h2M20 12h2',
  chart: 'M4 20V4M4 20h16M8 16v-5M12 16V8M16 16v-8',
  globe: 'M12 3a9 9 0 100 18 9 9 0 000-18zM3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18',
  gem: 'M6 4h12l3 5-9 11L3 9zM3 9h18',
  cup: 'M7 4h10v5a5 5 0 01-10 0zM12 14v4M8 20h8',
  cog: 'M12 9a3 3 0 100 6 3 3 0 000-6zM12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2',
  star: 'M12 3l2.7 5.6 6.1.8-4.5 4.2 1.1 6-5.4-3-5.4 3 1.1-6-4.5-4.2 6.1-.8z',
  bag: 'M5 8h14l-1 12H6zM9 8a3 3 0 016 0',
  shield: 'M12 3l8 3v6c0 5-3.5 8-8 9-4.500-1-8-4-8-9V6z',
  bed: 'M3 18V7M3 14h18v4M3 14V12a2 2 0 012-2h6a4 4 0 014 4',
  chip: 'M7 7h10v10H7zM10 3v4M14 3v4M10 17v4M14 17v4M3 10h4M3 14h4M17 10h4M17 14h4',
  tag: 'M3 12V4h8l10 10-8 8zM8 8h.01',
  users: 'M9 11a3 3 0 100-6 3 3 0 000 6zM3 20c0-3.500 2.500-6 6-6s6 2.500 6 6M17 11a2.500 2.500 0 100-5M18 14c2 .5 3 2.500 3 6',
  phone: 'M8 3h8a1 1 0 011 1v16a1 1 0 01-1 1H8a1 1 0 01-1-1V4a1 1 0 011-1zM11 18h2',
  home: 'M4 11l8-7 8 7v9H4zM10 20v-6h4v6',
  grid: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z',
  trophy: 'M8 4h8v5a4 4 0 01-8 0zM8 6H4v1a3 3 0 003 3M16 6h4v1a3 3 0 01-3 3M12 13v4M8 20h8',
};
const svg = (k, c, extra = '') => `<svg viewBox="0 0 24 24" style="stroke:${c};${extra}"><path d="${G[k]}"/></svg>`;

const APPS = [
  ['Bank', 'bank', '#86B4A0'], ['Accounting', 'book', '#A8B88A'], ['Inbox', 'mail', '#CF9A6A', 1], ['News', 'news', '#7F9BC4'],
  ['Weather', 'sun', '#93A9BD'], ['Stats', 'chart', '#9A94C4'], ['World', 'globe', '#78B0A8'], ['Luxury', 'gem', '#C48CB8'],
  ['Rich list', 'cup', '#D0A86F'], ['Market', 'tag', '#86B890'], ['Reviews', 'star', '#D2B97C'], ['Achievements', 'trophy', '#E0A458'],
  ['Settings', 'cog', '#A19B8F'], ['AirStay', 'bed', '#CF6A6A'], ['TechPro Store', 'chip', '#7FB088'], ['Atlas Insurance', 'shield', '#7F9FC8'],
  ['Marketplace', 'bag', '#4FA39B'],
];
const grid = () => `<div class="grid">${APPS.map(([t, g, c, b]) => `<div class="app">${b ? `<div class="bub">${b}</div>` : ''}<div class="tile">${svg(g, c)}</div><span>${t}</span></div>`).join('')}</div>`;

const tabbar = () => `<div class="tabbar">${[['Ventures', 'chart'], ['Group', 'users'], ['Home', 'home', 1], ['Pick tab', 'grid'], ['Phone', 'phone', 0, 2]]
  .map(([t, g, on, b]) => `<div class="tab ${on ? 'on' : ''}">${b ? `<div class="bub">${b}</div>` : ''}${svg(g, on ? '#D6B889' : '#A19B8F')}${t}</div>`).join('')}</div><div class="homebar"></div>`;

const status = () => `<div class="status"><span>9:41</span><span style="font-size:12px">5G &nbsp;100%</span></div>`;
const guide = () => `<div class="card guide"><div class="caps">Next goal · M3</div><h3>Hire your first worker</h3><p>Your café is busy enough that one person cannot keep up.</p><div class="btn">Find workers</div></div>`;
const needs = () => `<div class="card"><div class="caps" style="margin-bottom:10px">Needs you</div><div class="need"><div><b>A supplier wants cash up front</b><span class="s">Pay now or lose your 30-day terms.</span></div><span class="pill">4 days left</span></div><div class="hair" style="margin:12px 0 10px"></div><div class="row"><span class="link">Open in Inbox</span></div></div>`;
const strip = () => `<div class="strip"><div style="font-size:13px;color:var(--muted)">Tue · Week 7 · Day 3</div><div class="f"><div>Sales<b>41,300</b></div><div>Costs<b>34,400</b></div><div>Profit<b class="gain">+6,900</b></div></div></div>`;
const stripLink = `<div class="row" style="padding:8px 4px 0"><span style="font-size:11px;color:var(--faint)">Tap the strip to open the last week report</span><span class="link" style="font-size:12px">Last report</span></div>`;
const page = (inner, extra = '') => `<!doctype html><html><head><meta charset="utf-8"><style>${CSS}</style></head><body><div class="backdrop"></div>${status()}${inner}${extra}</body></html>`;

// ---------- Day close and week report parts ----------
const dayCloseSheet = (full = true) => `<div class="sheet amber"><div class="grab"></div><div class="muted" style="font-size:13px">Tue · Day 3</div><div class="big gain">+1,850 kr</div><div class="line">New in Inbox: A supplier wants cash up front</div><div class="tap">Tap to dismiss</div><div class="seg"><i class="f"></i><i class="f"></i><i class="f"></i><i></i><i></i><i></i><i class="o"></i></div></div>`;
const bars = () => `<div class="bars">${[['Sales', 96400, 'var(--gold)', '96,400'], ['Costs', 81100, '#6B665E', '81,100'], ['Profit', 15300, 'var(--gain)', '+15,300']]
  .map(([l, v, c, t]) => `<div class="b"><div class="l"><span class="muted">${l}</span><b style="font-variant-numeric:tabular-nums">${t} kr</b></div><div class="t"><i style="width:${(v / 96400 * 100).toFixed(1)}%;background:${c}"></i></div></div>`).join('')}</div>`;
const numberBlock = (size = 48) => `<div style="font-size:${size}px;font-weight:700;line-height:1.05" class="gain">+15,300 kr</div><div class="gain" style="font-size:17px;margin-top:4px">+11,200 kr vs last week</div>`;
const story = `<div class="serif" style="font-size:20px;line-height:1.3;margin:12px 0">Your best week yet.</div>`;
const rec = `<div class="rec">${svg('trophy', '#D6B889', 'width:18px;height:18px;fill:none;stroke-width:1.6')}Best week so far</div>`;
const footer = (bottom = 34) => `<div style="position:absolute;left:20px;right:20px;bottom:${bottom}px;text-align:center"><div class="link" style="margin-bottom:12px">Full report</div><div class="btn full">Continue</div></div>`;

// ---------- Variant A ----------
const A_home = () => page(`<div class="scroll">
  <div style="text-align:center"><div class="serif" style="font-size:52px;line-height:1">9:41</div><div style="font-size:12.5px;color:var(--muted);margin-top:4px">Tuesday 2 February 2027</div><div style="font-size:12px;color:var(--faint);margin-top:2px">Nordvik Café · Cash 184,200 kr</div></div>
  <div class="gap"></div>${strip()}<div style="height:12px"></div>${guide()}<div class="gap"></div>${needs()}<div style="height:18px"></div>${grid()}</div>${tabbar()}`);
const A_dayclose = () => page(`<div class="scroll"><div style="text-align:center"><div class="serif" style="font-size:52px;line-height:1">9:41</div><div style="font-size:12.5px;color:var(--muted);margin-top:4px">Tuesday 2 February 2027</div></div><div class="gap"></div>${strip()}<div class="gap"></div>${guide()}<div class="gap"></div>${needs()}</div>${tabbar()}<div class="scrim"></div>${dayCloseSheet()}`);
const A_week = () => page(`<div class="scroll" style="padding-top:20px"><div class="serif" style="font-size:34px">Week 7</div><div class="muted" style="font-size:14px;margin:2px 0 18px">Mon 8 – Sun 14 February 2027</div>${numberBlock()}${story}${bars()}<div class="gap"></div>${guide()}<div class="gap"></div>${rec}</div>${footer()}`);

// ---------- Variant B ----------
const B_home = () => page(`<div class="scroll" style="padding-top:8px">
  <div class="row" style="align-items:flex-end"><div><div class="caps">Home</div><div class="serif" style="font-size:28px;line-height:1.1;margin-top:2px">Nordvik Café</div></div><div style="text-align:right"><div style="font-size:10px;color:var(--faint)">Cash</div><div class="serif" style="font-size:22px">184,200 kr</div></div></div>
  <div class="gap"></div>${strip()}<div class="gap"></div>
  <div class="next">Next day</div><div style="height:12px"></div>
  ${guide()}<div class="gap"></div>${needs()}<div class="gap"></div>
  <div class="card"><div class="caps" style="margin-bottom:6px">This week so far</div><div class="row" style="margin:8px 0"><div><div style="font-size:10px;color:var(--faint)">Sales</div><b>41,300</b></div><div><div style="font-size:10px;color:var(--faint)">Costs</div><b>34,400</b></div><div style="text-align:right"><div style="font-size:10px;color:var(--faint)">Profit</div><b class="gain">+6,900</b></div></div><div class="serif muted" style="font-size:14px;line-height:1.35">Lunch sales are up on last week and the coffee margin holds.</div></div>
  <div class="gap"></div>
  <div class="card"><div class="row"><div><div class="caps">Company</div><div style="font-size:16px;font-weight:600;margin-top:3px">Nordvik Café</div><div class="muted" style="font-size:12.5px;margin-top:2px">Open · 2 staff · rating 4.3</div></div><div style="text-align:right"><div class="gain" style="font-weight:600">+6,900</div><div class="link" style="margin-top:6px;font-size:13px">Open company</div></div></div></div>
  <div class="gap"></div>
  <div class="card row"><div><div class="caps">Last report</div><div style="font-size:14px;margin-top:3px">Week 6 · <span class="gain">+4,100 kr</span></div></div><span class="link">View report</span></div>
  <div class="gap"></div><div class="card row"><div style="font-size:14px">Bank, News, Market and 14 more apps</div><span class="link">Open Phone</span></div>
</div>${tabbar()}`);
const B_week = () => page(`<div class="scroll" style="padding-top:20px"><div class="caps">Nordvik Café</div><div class="serif" style="font-size:34px;margin-top:2px">Week 7</div><div class="muted" style="font-size:14px;margin:2px 0 14px">Mon 8 – Sun 14 February 2027</div>
  <div class="card hero">${numberBlock()}${story.replace('margin:12px 0', 'margin:12px 0 0')}</div><div class="gap"></div>
  <div class="card">${bars()}</div><div class="gap"></div>${guide()}<div class="gap"></div><div class="card">${rec}</div></div>${footer()}`);

// ---------- Variant C ----------
const dashTop = (bottomEdge = true) => `<div style="position:absolute;top:47px;left:0;right:0;height:366px;padding:10px 20px 0;background:linear-gradient(#17181A,var(--page));border-bottom:1px solid var(--border);z-index:3">
  <div class="caps">Nordvik Café · Week 7</div>
  <div style="font-size:11px;color:var(--faint);margin-top:14px">Cash</div><div class="serif" style="font-size:44px;line-height:1.05">184,200 kr</div>
  <div class="row" style="margin-top:16px;align-items:flex-end"><div><div style="font-size:11px;color:var(--faint)">Profit this week</div><div class="gain" style="font-size:24px;font-weight:600">+6,900 kr</div></div><div style="text-align:right;font-size:12px" class="muted">Sales 41,300<br>Costs 34,400</div></div>
  <div style="margin-top:20px"><div class="row" style="font-size:11px;color:var(--faint);margin-bottom:6px"><span>Tue · Day 3 of 7</span><span>Report on day 7</span></div><div class="seg lg"><i class="f"></i><i class="f"></i><i class="f"></i><i></i><i></i><i></i><i class="o"></i></div></div>
  <div class="next" style="margin-top:22px">Next day</div>
  <div class="row" style="margin-top:12px"><span class="link" style="font-size:13px">Last report</span><span class="link" style="font-size:13px">Play to end of week</span></div></div>`;
const C_scroll = `<div style="position:absolute;top:413px;left:0;right:0;bottom:0;padding:14px 20px 0;overflow:hidden">${guide()}<div class="gap"></div>${needs()}<div style="height:18px"></div>${grid()}</div>`;
const C_home = () => page(dashTop() + C_scroll + tabbar());
const C_dayclose = () => page(dashTop() + C_scroll + tabbar() + `<div class="scrim" style="top:413px"></div>` + dayCloseSheet());
const C_week = () => page(`<div style="position:absolute;top:47px;left:0;right:0;height:250px;padding:18px 20px 0;border-bottom:1px solid var(--border);background:linear-gradient(#17181A,var(--page));z-index:3"><div class="serif" style="font-size:34px">Week 7</div><div class="muted" style="font-size:14px;margin:2px 0 14px">Mon 8 – Sun 14 February 2027</div>${numberBlock(44)}<div class="seg lg" style="margin-top:16px"><i class="f"></i><i class="f"></i><i class="f"></i><i class="f"></i><i class="f"></i><i class="f"></i><i class="f"></i></div></div>
  <div style="position:absolute;top:297px;left:0;right:0;bottom:130px;padding:6px 20px 0;overflow:hidden">${story}${bars()}<div class="gap"></div>${guide()}<div class="gap"></div>${rec}</div>${footer()}`);

// B day close: dim the real B home
const B_dayclose2 = () => B_home().replace('</body>', `<div class="scrim"></div>${dayCloseSheet()}</body>`);

const SCREENS = { A_home, A_dayclose, A_weekreport: A_week, B_home, B_dayclose: B_dayclose2, B_weekreport: B_week, C_home, C_dayclose, C_weekreport: C_week };

(async () => {
  const out = path.join(__dirname, '..', 'png');
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, colorScheme: 'dark' });
  for (const [name, fn] of Object.entries(SCREENS)) {
    const file = path.join(__dirname, name + '.html');
    fs.writeFileSync(file, fn());
    const p = await ctx.newPage();
    await p.goto('file://' + file);
    await p.screenshot({ path: path.join(out, name + '.png') });
    await p.close();
  }
  await browser.close();
})();
