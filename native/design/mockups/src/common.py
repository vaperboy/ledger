import json, math, random
D = json.load(open(__file__.replace('common.py', 'data.json')))
import re as _re
def _tidy(s):
    s = _re.sub(r'(\d)\u00a0(\d{3})', r'\1,\2', s)
    s = _re.sub(r'(\d)\u00a0([kM])\b', r'\1\2', s)
    s = _re.sub(r'(\d) ([kM])\b', r'\1\2', s)
    return s.replace('2751', '2,751')
for _c in D['companyList']:
    for _i in _c['insights']: _i['text'] = _tidy(_i['text'])

def money(v, sign=False):
    s = f"£{abs(v):,.0f}"
    if v < 0: return "−" + s
    return ("+" + s) if sign and v > 0 else s

def short(v, sign=False):
    a = abs(v)
    if a >= 1e6: s = f"£{a/1e6:.2f}M"
    elif a >= 1e5: s = f"£{a/1e3:.0f}k"
    elif a >= 1e4: s = f"£{a/1e3:.1f}k"
    else: s = f"£{a:,.0f}"
    if v < 0: return "−" + s
    return ("+" + s) if sign and v > 0 else s

def pct(v, sign=True, d=1):
    s = f"{abs(v)*100:.{d}f}%"
    if v < 0: return "−" + s
    return ("+" + s) if sign and v > 0 else s

# ---------- data derived ----------
CO = D['companyList']
NW = D['netWorth']
nwd = [x for x in D['nwDaily'] if x > 0]
nww = [x for x in D['nwWeekly'] if x > 0]
CH7 = nwd[-1] - nwd[-8]; CH7P = CH7 / nwd[-8]
CH30 = nwd[-1] - nwd[-31]; CH30P = CH30 / nwd[-31]
COD = D['coDaily']
GROUP_VALUE = sum(c['value'] for c in CO)
GROUP_REV = sum(c['revenueTTM'] for c in CO)
GROUP_PROFIT = sum(c['profitTTM'] for c in CO)
GROUP_CASH = sum(max(0, c['cash']) for c in CO)
GROUP_DEBT = sum(c['debt'] for c in CO)
GROUP_STAFF = sum(c['staff'] for c in CO)
CITIES = sorted(set(c['city'] for c in CO))
GCH30 = COD[-1] - COD[-31]

def aligned_sum(key, n=12):
    out = [0.0] * n
    for c in CO:
        s = c[key][-n:]
        for i, v in enumerate(s): out[n - len(s) + i] += v
    return out
G_REV = aligned_sum('revenueSeries'); G_PROF = aligned_sum('profitSeries')
MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
# last closed month is November 2027 (date 9 Dec 2027)
LAST12 = [MONTHS[(10 - 11 + i) % 12] for i in range(12)]
LAST12_INITIAL = [m[0] for m in LAST12]

BAKERY = next(c for c in CO if c['trade'].startswith('Bakery'))
BY_PROFIT = sorted(CO, key=lambda c: -c['profitTTM'])
SHORT_TRADE = {'Accounting firm': 'Accounting', 'Café': 'Café', 'Gym': 'Gym', 'Car rental': 'Car rental', 'Bakery and pastry': 'Bakery', 'Software and web agency': 'Software'}
def trade(c): return SHORT_TRADE.get(c['trade'], c['trade'])

# Needs attention: the most serious real findings across the group
def attention(n=3):
    rank = {'bad': 0, 'warn': 1, 'neutral': 2, 'good': 3}
    items = []
    for c in CO:
        for i in c['insights']:
            if 'paperwork' in i['text']: continue
            if 'Competitors' in i['text']: continue
            items.append((rank[i['tone']], c, i))
    items.sort(key=lambda x: x[0])
    return [(c, i) for _, c, i in items[:n]]

# ---------- svg helpers ----------
def scale(vals, h, pad=0.1, lo=None, hi=None):
    lo = min(vals) if lo is None else lo; hi = max(vals) if hi is None else hi
    span = (hi - lo) or 1
    return [h - ((v - lo) / span) * h * (1 - 2 * pad) - h * pad for v in vals]

def spark(vals, w, h, color, width=1.5, fill=None, smooth=True):
    if len(vals) < 2: return f'<svg width="{w}" height="{h}"></svg>'
    ys = scale(vals, h)
    xs = [i * w / (len(vals) - 1) for i in range(len(vals))]
    d = f"M{xs[0]:.1f},{ys[0]:.1f}" + "".join(f" L{x:.1f},{y:.1f}" for x, y in zip(xs[1:], ys[1:]))
    area = ""
    if fill:
        gid = f"g{random.randint(0, 10**9)}"
        area = (f'<defs><linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{fill}" stop-opacity=".28"/>'
                f'<stop offset="1" stop-color="{fill}" stop-opacity="0"/></linearGradient></defs>'
                f'<path d="{d} L{w},{h} L0,{h} Z" fill="url(#{gid})"/>')
    return f'<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" style="display:block;overflow:visible">{area}<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"/></svg>'

def bars(vals, w, h, pos, neg, gap=3, radius=1.5, zero_line=None):
    n = len(vals); bw = (w - gap * (n - 1)) / n
    hi = max(max(vals), 0); lo = min(min(vals), 0); span = (hi - lo) or 1
    z = h * hi / span
    out = []
    for i, v in enumerate(vals):
        bh = abs(v) / span * h
        y = z - bh if v >= 0 else z
        out.append(f'<rect x="{i*(bw+gap):.1f}" y="{y:.1f}" width="{bw:.1f}" height="{max(bh,1):.1f}" rx="{radius}" fill="{pos if v>=0 else neg}"/>')
    zl = f'<line x1="0" x2="{w}" y1="{z:.1f}" y2="{z:.1f}" stroke="{zero_line}" stroke-width="1"/>' if zero_line else ""
    return f'<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" style="display:block">{zl}{"".join(out)}</svg>'

def ring(frac, size, color, track, width=4, label="", font="inherit", fs=13, fc="#fff"):
    r = (size - width) / 2; c = 2 * math.pi * r; f = max(0, min(1, frac))
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 {size} {size}"><circle cx="{size/2}" cy="{size/2}" r="{r}" fill="none" stroke="{track}" stroke-width="{width}"/>'
            f'<circle cx="{size/2}" cy="{size/2}" r="{r}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round" stroke-dasharray="{c*f:.1f} {c}" transform="rotate(-90 {size/2} {size/2})"/>'
            f'<text x="50%" y="50%" text-anchor="middle" dominant-baseline="central" font-family="{font}" font-size="{fs}" font-weight="600" fill="{fc}">{label}</text></svg>')

def linechart(series, w, h, colors, grid, label_color, labels=None, ylabels=True, fmt=short, font="Inter", fills=None, width=1.8, dots=False, zero=True):
    allv = [v for s in series for v in s]
    lo, hi = min(allv + ([0] if zero else [])), max(allv)
    span = hi - lo or 1; lo -= span * 0.08; hi += span * 0.08
    pl, pr, pt, pb = 0, (40 if ylabels else 0), 6, (16 if labels else 2)
    W, H = w - pl - pr, h - pt - pb
    def Y(v): return pt + H - (v - lo) / (hi - lo) * H
    out = []
    for k in range(4):
        v = lo + (hi - lo) * k / 3
        y = Y(v)
        out.append(f'<line x1="0" x2="{W}" y1="{y:.1f}" y2="{y:.1f}" stroke="{grid}" stroke-width="1"/>')
        if ylabels: out.append(f'<text x="{W+6}" y="{y+3.5:.1f}" font-family="{font}" font-size="9.5" fill="{label_color}">{fmt(v)}</text>')
    if lo < 0 < hi: out.append(f'<line x1="0" x2="{W}" y1="{Y(0):.1f}" y2="{Y(0):.1f}" stroke="{label_color}" stroke-opacity=".5" stroke-width="1" stroke-dasharray="2 3"/>')
    for si, s in enumerate(series):
        n = len(s); xs = [W * (i + (12 - n)) / 11 for i in range(n)] if n <= 12 else [W * i / (n - 1) for i in range(n)]
        d = "M" + " L".join(f"{x:.1f},{Y(v):.1f}" for x, v in zip(xs, s))
        if fills and fills[si]:
            gid = f"lc{random.randint(0, 10**9)}"
            out.insert(0, f'<defs><linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{fills[si]}" stop-opacity=".25"/><stop offset="1" stop-color="{fills[si]}" stop-opacity="0"/></linearGradient></defs>')
            out.append(f'<path d="{d} L{xs[-1]:.1f},{pt+H} L{xs[0]:.1f},{pt+H} Z" fill="url(#{gid})"/>')
        out.append(f'<path d="{d}" fill="none" stroke="{colors[si]}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"/>')
        if dots:
            for x, v in zip(xs, s): out.append(f'<circle cx="{x:.1f}" cy="{Y(v):.1f}" r="2" fill="{colors[si]}"/>')
    if labels:
        for i, l in enumerate(labels):
            out.append(f'<text x="{W*i/(len(labels)-1):.1f}" y="{h-3}" text-anchor="middle" font-family="{font}" font-size="9" fill="{label_color}">{l}</text>')
    return f'<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" style="display:block;overflow:visible">{"".join(out)}</svg>'

ICONS = {
 'home': '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z"/>',
 'group': '<path d="M3 21h18M5 21V6a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v15M15 10h3a1 1 0 0 1 1 1v10M8 9h3M8 13h3M8 17h3"/>',
 'money': '<rect x="2.5" y="6" width="19" height="12" rx="2"/><circle cx="12" cy="12" r="2.8"/><path d="M6 9.5v5M18 9.5v5"/>',
 'inbox': '<path d="M3 13h5l1.5 3h5L16 13h5"/><path d="M5.5 5h13l2.5 8v6a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-6z"/>',
 'phone': '<rect x="6.5" y="2.5" width="11" height="19" rx="2.5"/><path d="M11 18.5h2"/>',
 'chev': '<path d="M9 6l6 6-6 6"/>', 'back': '<path d="M15 5l-7 7 7 7"/>',
 'alert': '<path d="M12 3.5 2.5 20h19z"/><path d="M12 10v4.5M12 17.2v.3"/>',
 'up': '<path d="M7 17 17 7M9 7h8v8"/>', 'down': '<path d="M7 7l10 10M17 9v8H9"/>',
 'users': '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.3a3.5 3.5 0 0 1 0 7M17.5 14.2a6 6 0 0 1 4 5.8"/>',
 'tag': '<path d="M3 12V4a1 1 0 0 1 1-1h8l9 9-9 9z"/><circle cx="7.5" cy="7.5" r="1.4"/>',
 'mega': '<path d="M3 10v4a1 1 0 0 0 1 1h3l7 4V5L7 9H4a1 1 0 0 0-1 1z"/><path d="M18 9a4 4 0 0 1 0 6"/>',
 'tool': '<path d="M14.5 6.5a4 4 0 0 0 5 5l-9 9a2.1 2.1 0 0 1-3-3z"/><path d="M14.5 6.5 17 4l3 3-2.5 2.5"/>',
 'transfer': '<path d="M4 8h15l-3.5-3.5M20 16H5l3.5 3.5"/>',
 'bulb': '<path d="M9 18h6M10 21h4M12 3a6 6 0 0 0-4 10.5c.8.8 1 1.6 1 2.5h6c0-.9.2-1.7 1-2.5A6 6 0 0 0 12 3z"/>',
 'cal': '<rect x="3.5" y="5" width="17" height="16" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
 'flame': '<path d="M12 3c3 4 5.5 6.5 5.5 10.5a5.5 5.5 0 0 1-11 0c0-2.2 1-3.8 2.2-5.2.2 2 1.2 3.2 2.3 3.2 0-3.2-.8-5.5 1-8.5z"/>',
 'plus': '<path d="M12 5v14M5 12h14"/>', 'sort': '<path d="M7 4v16M4 7l3-3 3 3M17 20V4M14 17l3 3 3-3"/>',
 'sparkle': '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/>',
 'clock': '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>', 'more': '<circle cx="5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="19" cy="12" r="1.3"/>',
 'gauge': '<path d="M4 17a8 8 0 1 1 16 0"/><path d="M12 17l4-5"/>', 'check': '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
 'shop': '<path d="M4 9h16l-1.2-4.5a1 1 0 0 0-1-.7H6.2a1 1 0 0 0-1 .7zM5 9v11h14V9M9.5 20v-6h5v6"/>',
 'cup': '<path d="M4 8h12v5a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5z"/><path d="M16 9h1.5a2.5 2.5 0 0 1 0 5H16"/><path d="M8 3.5v2M12 3.5v2"/>',
 'cake': '<path d="M4 20h16v-7a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2z"/><path d="M4 15c2 1.3 4 1.3 5.3 0 1.4 1.3 3.4 1.3 4.7 0 1.3 1.3 3.3 1.3 6 0"/><path d="M12 11V7.5"/><path d="M12 3.5c.9.9.9 2.2 0 3"/>',
 'car': '<path d="M3 13l2-6h14l2 6v5H3z"/><path d="M3 13h18"/><path d="M6.5 16h1M16.5 16h1"/>',
 'dumbbell': '<path d="M6.5 7v10M3.5 9.5v5M17.5 7v10M20.5 9.5v5M6.5 12h11"/>',
 'laptop': '<rect x="5" y="5" width="14" height="10" rx="1.5"/><path d="M2.5 19h19"/>',
 'ledger': '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 8h6M9 12h6M9 16h3.5"/>',
}
TRADE_ICON = {'Accounting firm': 'ledger', 'Café': 'cup', 'Gym': 'dumbbell', 'Car rental': 'car', 'Bakery and pastry': 'cake', 'Software and web agency': 'laptop'}
def ticon(c): return TRADE_ICON.get(c['trade'], 'shop')
def icon(name, size=18, color="currentColor", sw=1.6):
    return f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{color}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" style="display:block;flex:none">{ICONS[name]}</svg>'

def status_bar(color="#fff"):
    return f'''<div class="sb" style="display:flex;justify-content:space-between;align-items:center;height:47px;padding:0 30px 0 36px;color:{color};font:600 16px Inter">
<span style="letter-spacing:-.2px">9:41</span><span style="display:flex;gap:6px;align-items:center">
<svg width="18" height="11" viewBox="0 0 18 11"><rect x="0" y="7" width="3" height="4" rx=".7" fill="{color}"/><rect x="5" y="5" width="3" height="6" rx=".7" fill="{color}"/><rect x="10" y="2.5" width="3" height="8.5" rx=".7" fill="{color}"/><rect x="15" y="0" width="3" height="11" rx=".7" fill="{color}"/></svg>
<svg width="16" height="11" viewBox="0 0 16 11"><path d="M8 2.2c2.3 0 4.4.9 6 2.4l1.1-1.2A10 10 0 0 0 8 .6 10 10 0 0 0 .9 3.4L2 4.6a8.4 8.4 0 0 1 6-2.4zm0 3.3c1.4 0 2.7.5 3.7 1.4l1.1-1.2A7 7 0 0 0 8 3.9a7 7 0 0 0-4.8 1.8l1.1 1.2c1-.9 2.3-1.4 3.7-1.4zM8 8.8 10.2 6.5a3.2 3.2 0 0 0-4.4 0z" fill="{color}"/></svg>
<svg width="26" height="12" viewBox="0 0 26 12"><rect x=".5" y=".5" width="22" height="11" rx="3.2" fill="none" stroke="{color}" stroke-opacity=".4"/><rect x="2" y="2" width="19" height="8" rx="2" fill="{color}"/><path d="M24 4v4c.8-.3 1.3-1 1.3-2s-.5-1.7-1.3-2z" fill="{color}" fill-opacity=".4"/></svg></span></div>'''

def skyline(w, h, seed=7, glow="#C8905A"):
    rnd = random.Random(seed); out = []
    x = 0
    while x < w:
        bw = rnd.randint(14, 38); bh = rnd.randint(int(h * .25), int(h * .92))
        if rnd.random() < .12: bh = int(h * rnd.uniform(.9, 1.0))
        shade = rnd.choice(["#100D0B", "#130F0C", "#0E0B09", "#16110D"])
        out.append(f'<rect x="{x}" y="{h-bh}" width="{bw}" height="{bh}" fill="{shade}"/>')
        for wy in range(h - bh + 6, h - 4, 5):
            for wx in range(x + 3, x + bw - 3, 4):
                if rnd.random() < .16:
                    op = rnd.uniform(.25, .9)
                    out.append(f'<rect x="{wx}" y="{wy}" width="1.6" height="2" fill="{glow}" opacity="{op:.2f}"/>')
        x += bw + rnd.randint(-2, 2)
    return f'''<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" preserveAspectRatio="none" style="display:block">
<defs><linearGradient id="sky{seed}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0B0A0A"/><stop offset=".55" stop-color="#2A1C12"/><stop offset="1" stop-color="#6B4428"/></linearGradient>
<radialGradient id="sun{seed}" cx=".62" cy="1" r=".7"><stop offset="0" stop-color="#E0A060" stop-opacity=".55"/><stop offset="1" stop-color="#E0A060" stop-opacity="0"/></radialGradient></defs>
<rect width="{w}" height="{h}" fill="url(#sky{seed})"/><rect width="{w}" height="{h}" fill="url(#sun{seed})"/>{"".join(out)}</svg>'''

def phone(inner, bg, extra_style=""):
    return f'<div class="device"><div class="screen" style="background:{bg};{extra_style}">{inner}</div><div class="island"></div></div>'

SHEET_CSS = '''
@import url("fonts.css");
*{box-sizing:border-box;margin:0;padding:0}
body{background:#1F1F21;font-family:Inter, sans-serif;-webkit-font-smoothing:antialiased;color:#eee;font-feature-settings:"tnum" 1,"cv11" 1}
.sheet{padding:56px 60px 64px}
.sheet h1{font:600 30px "Inter Display",Inter;letter-spacing:-.4px;color:#F3EFE8}
.sheet .sub{font:400 15px Inter;color:#A39E96;margin-top:6px;max-width:1300px}
.sheetrow{display:flex;gap:46px;margin-top:40px;align-items:flex-start}
.col{width:393px;flex:none}
.s1 *, .s2 *, .s3 *, .s4 *, .s5 *{min-width:0}
.label{margin-top:22px}
.label .n{font:600 13px Inter;letter-spacing:.14em;text-transform:uppercase;color:#D2B58C}
.label .t{font:600 19px Inter;color:#F3EFE8;margin-top:4px}
.label .d{font:400 13.5px/1.45 Inter;color:#A39E96;margin-top:6px}
.device{position:relative;width:393px;height:852px;border-radius:56px;padding:0;box-shadow:0 0 0 11px #0A0A0B,0 0 0 12.5px #3A3633,0 30px 60px rgba(0,0,0,.55)}
.screen{position:relative;width:393px;height:852px;border-radius:56px;overflow:hidden}
.island{position:absolute;top:11px;left:50%;transform:translateX(-50%);width:124px;height:36px;border-radius:20px;background:#000}
.num{font-feature-settings:"tnum" 1}
'''

def sheet(title, sub, cols):
    body = "".join(f'<div class="col">{c[0]}<div class="label"><div class="n">Option {i+1}</div><div class="t">{c[1]}</div><div class="d">{c[2]}</div></div></div>' for i, c in enumerate(cols))
    return f'<!doctype html><html><head><meta charset="utf-8"><style>{SHEET_CSS}</style></head><body><div class="sheet"><h1>{title}</h1><div class="sub">{sub}</div><div class="sheetrow">{body}</div></div></body></html>'
