from common import *
# 2 · COMMAND GRID — Football Manager. Tight tiled panels with header bars, tables, attribute-style numbers, "Continue" at the top.
BG="#0B0E11"; PN="#12161A"; PH="#161B20"; BD="#1F262D"; TX="#E7EAEC"; MU="#8E979F"; FA="#5E676F"; AC="#CFA86C"; GN="#5CC58C"; RD="#E36F5E"; AM="#E2B04A"
CSS=f'''<style>
.s2{{font-family:Inter;color:{TX};font-size:12.5px}}
.s2 .row{{display:flex;align-items:center}}
.s2 .pn{{background:{PN};border:1px solid {BD};border-radius:5px;margin-top:6px;overflow:hidden}}
.s2 .ph{{display:flex;justify-content:space-between;align-items:center;height:25px;padding:0 10px;background:{PH};border-bottom:1px solid {BD};font:600 9.5px Inter;letter-spacing:.12em;text-transform:uppercase;color:{MU}}}
.s2 .ph span:last-child{{letter-spacing:.02em;text-transform:none;font-weight:500;color:{FA}}}
.s2 .mu{{color:{MU}}} .s2 .fa{{color:{FA}}} .s2 .gn{{color:{GN}}} .s2 .rd{{color:{RD}}} .s2 .am{{color:{AM}}}
.s2 table{{width:100%;border-collapse:collapse}}
.s2 td,.s2 th{{padding:0 8px;height:27px;white-space:nowrap}}
.s2 th{{font:600 9px Inter;letter-spacing:.1em;text-transform:uppercase;color:{FA};text-align:right;height:22px}}
.s2 th:first-child,.s2 td:first-child{{text-align:left}}
.s2 td{{text-align:right;font-feature-settings:"tnum" 1}}
.s2 tbody tr:nth-child(odd){{background:rgba(255,255,255,.022)}}
.s2 .tab{{position:absolute;left:0;right:0;bottom:0;height:80px;background:#090B0D;border-top:1px solid {BD};display:flex;justify-content:space-around;padding-top:7px}}
.s2 .tab div{{display:flex;flex-direction:column;align-items:center;gap:2px;font:500 9.5px Inter;color:{FA};width:64px}}
.s2 .tab .on{{color:{AC}}}
.s2 .hi{{position:absolute;bottom:8px;left:50%;transform:translateX(-50%);width:134px;height:5px;border-radius:3px;background:#E7EAEC}}
.s2 .cont{{background:{AC};color:#14100A;font:700 12px Inter;padding:7px 12px 7px 14px;border-radius:4px;display:flex;align-items:center;gap:4px;letter-spacing:.02em}}
</style>'''
def tabbar(on):
    items=[("home","Home"),("group","Group"),("money","Money"),("inbox","Inbox"),("phone","Phone")]
    return '<div class="tab">'+"".join(f'<div class="{"on" if k==on else ""}">{icon(k,20,sw=1.5)}<span>{t}</span></div>' for k,t in items)+'</div><div class="hi"></div>'
def context(title, sub):
    return f'''<div class="row" style="justify-content:space-between;padding:2px 12px 4px"><div><div style="font:700 17px Inter;letter-spacing:-.2px">{title}</div><div class="fa" style="font-size:10.5px;margin-top:1px">{sub}</div></div>
<div style="text-align:right"><div class="cont">CONTINUE {icon("chev",12,"#14100A",2.4)}</div><div class="fa" style="font-size:9.5px;margin-top:3px">Thu · day 4 of 7</div></div></div>'''
def hbar(v, col, w=40):
    return f'<div style="width:{w}px;height:4px;background:{BD};border-radius:2px;display:inline-block;vertical-align:middle"><div style="width:{max(2,min(1,v)*w):.0f}px;height:4px;border-radius:2px;background:{col}"></div></div>'
def health_cell(h):
    col = {"Thriving":GN,"Healthy":GN,"Tight":AM,"Struggling":RD}.get(h,MU)
    n = {"Thriving":5,"Healthy":4,"Tight":2,"Struggling":1}.get(h,3)
    return '<span style="display:inline-flex;gap:2px;vertical-align:middle">'+"".join(f'<span style="width:5px;height:9px;border-radius:1px;background:{col if i<n else BD}"></span>' for i in range(5))+'</span>'

def dashboard():
    att = attention(3)
    tot = D["assets"]
    h = f'''{CSS}<div class="s2">{status_bar(TX)}{context("Alex Carter", f"Thursday 9 Dec 2027 · Week {D['week']} · Economy: boom · Base rate 3.75%")}
<div style="padding:0 8px">
 <div class="pn"><div class="ph"><span>Net worth</span><span>Last 13 weeks</span></div>
  <div class="row" style="padding:8px 10px 2px;align-items:flex-end;justify-content:space-between">
   <div><div style="font:700 26px Inter;letter-spacing:-.5px" class="num">{money(NW)}</div></div>
   <table style="width:auto"><tr><td class="fa" style="height:16px;padding:0 6px">Week</td><td class="gn" style="height:16px;padding:0">{money(CH7,True)}</td></tr><tr><td class="fa" style="height:16px;padding:0 6px">30 days</td><td class="gn" style="height:16px;padding:0">{money(CH30,True)}</td></tr></table>
  </div>
  <div style="padding:2px 10px 8px">{linechart([nwd[-91:]],335,58,[AC],BD,FA,None,True,fills=[AC],width=1.4,zero=False)}</div>
  <table style="border-top:1px solid {BD}"><thead><tr><th>Holding</th><th>Value</th><th>Share</th><th>Week</th></tr></thead><tbody>
  {"".join(f'<tr><td>{l}</td><td style="{"color:"+RD if v<0 else ""}">{money(v)}</td><td>{hbar(abs(v)/tot,AC,46)} <span class="fa" style="display:inline-block;width:30px">{abs(v)/tot*100:.0f}%</span></td><td class="{"gn" if c>0 else "rd" if c<0 else "fa"}">{short(c,True) if c else "–"}</td></tr>' for l,v,c in [("Cash",D["personal"],D["cashDaily"][-1]-D["cashDaily"][-8]),("Investments",D["investments"],D["invDaily"][-1]-D["invDaily"][-8]),("Companies",D["companies"],COD[-1]-COD[-8]),("Debt",-D["debt"],0)])}
  </tbody></table></div>
 <div class="pn"><div class="ph"><span>Assistant report</span><span>{len(attention(9))} items</span></div>
  {"".join(f'<div class="row" style="padding:7px 10px;gap:9px;{"border-top:1px solid "+BD if j else ""}"><span style="width:3px;align-self:stretch;border-radius:2px;background:{AM if i["tone"]=="warn" else RD if i["tone"]=="bad" else GN}"></span><div style="flex:1"><div style="font-weight:600;font-size:11.5px">{c["name"]}</div><div class="mu" style="font-size:11.5px;line-height:1.3;margin-top:1px">{i["text"]}</div></div><span style="color:{AC};font-size:11px;white-space:nowrap">{(i["section"] or "View").capitalize()} ›</span></div>' for j,(c,i) in enumerate(att))}
 </div>
 <div class="pn"><div class="ph"><span>Companies</span><span>6 · sorted by profit</span></div>
  <table><thead><tr><th>Company</th><th>Health</th><th>Profit 12m</th><th>Cash</th></tr></thead><tbody>
  {"".join(f'<tr><td style="max-width:150px;overflow:hidden;text-overflow:ellipsis">{c["name"]}</td><td>{health_cell(c["health"])}</td><td class="{"rd" if c["profitTTM"]<0 else ""}">{short(c["profitTTM"])}</td><td class="mu">{short(c["cash"])}</td></tr>' for c in BY_PROFIT)}
  </tbody></table></div>
</div>{tabbar("home")}</div>'''
    return phone(h, BG)

def group():
    rows = BY_PROFIT
    mx = max(abs(c["profitTTM"]) for c in rows)
    h = f'''{CSS}<div class="s2">{status_bar(TX)}{context("Group", f"{len(CO)} companies · {len(CITIES)} cities · {GROUP_STAFF} staff")}
<div style="padding:0 8px">
 <div class="pn"><div class="ph"><span>Portfolio</span><span>12 months</span></div>
  <div style="display:grid;grid-template-columns:repeat(3,1fr)">
  {"".join(f'<div style="padding:7px 10px;{"border-left:1px solid "+BD if i%3 else ""};{"border-top:1px solid "+BD if i>2 else ""}"><div class="fa" style="font-size:9.5px;text-transform:uppercase;letter-spacing:.08em">{l}</div><div class="num" style="font:700 15px Inter;margin-top:2px;{c}">{v}</div></div>' for i,(l,v,c) in enumerate([("Value",short(GROUP_VALUE),""),("Revenue",short(GROUP_REV),""),("Profit",short(GROUP_PROFIT),"color:"+GN),("Cash",short(GROUP_CASH),""),("Debt",short(GROUP_DEBT),""),("Margin",f"{GROUP_PROFIT/GROUP_REV*100:.1f}%","")]))}
  </div></div>
 <div class="pn"><div class="ph"><span>Companies</span><span>Tap a column to sort</span></div>
  <table><thead><tr><th>Company</th><th>Value</th><th style="color:{AC}">Profit ▾</th><th>Margin</th><th>Rev</th></tr></thead><tbody>
  {"".join(f'<tr style="height:38px"><td style="height:38px;border-left:2px solid {GN if c["health"] in ("Thriving","Healthy") else AM}"><div style="font-weight:600;font-size:12px;max-width:118px;overflow:hidden;text-overflow:ellipsis">{c["name"]}</div><div class="fa" style="font-size:10px">{trade(c)} · {c["city"][:3].upper()}</div></td><td>{short(c["value"])}</td><td class="{"rd" if c["profitTTM"]<0 else "gn"}">{short(c["profitTTM"])}</td><td class="mu">{c["margin"]*100:.0f}%</td><td>{spark(c["revenueSeries"][-12:],34,14,GN if (c["growth"] or 0)>=0 else RD,1.2)}</td></tr>' for c in rows)}
  </tbody></table></div>
 <div class="pn"><div class="ph"><span>Profit by company</span><span>12 months</span></div>
  <div style="padding:6px 10px 8px">
  {"".join(f'<div class="row" style="height:19px;font-size:11px"><span class="mu" style="width:96px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">{c["name"].split()[0]}</span><div style="flex:1;position:relative;height:9px"><div style="position:absolute;left:50%;top:-4px;bottom:-4px;width:1px;background:{BD}"></div><div style="position:absolute;top:0;height:9px;border-radius:1px;background:{GN if c["profitTTM"]>=0 else RD};{"left:50%" if c["profitTTM"]>=0 else "right:50%"};width:{abs(c["profitTTM"])/mx*50:.1f}%"></div></div><span class="num" style="width:50px;text-align:right;{"color:"+RD if c["profitTTM"]<0 else ""}">{short(c["profitTTM"])}</span></div>' for c in rows)}
  </div></div>
</div>{tabbar("group")}</div>'''
    return phone(h, BG)

def attr(v, lo, hi):
    # Football Manager attribute colouring
    f = (v - lo) / (hi - lo)
    return GN if f > .66 else AC if f > .4 else AM if f > .2 else RD

def company():
    c = BAKERY
    tabs = ["Overview","Staff","Finances","Operations","Marketing"]
    ins = [i for i in c["insights"] if "Competitors" not in i["text"]][:3]
    h = f'''{CSS}<div class="s2">{status_bar(TX)}
<div class="row" style="justify-content:space-between;padding:2px 12px 0"><span class="fa" style="font-size:10.5px">Group › Bakery</span><div class="cont">CONTINUE {icon("chev",12,"#14100A",2.4)}</div></div>
<div style="padding:4px 12px 0"><div class="row" style="justify-content:space-between"><span style="font:700 18px Inter;letter-spacing:-.3px">{c["name"]}</span><span style="font:600 10px Inter;color:{GN};border:1px solid {GN}55;padding:2px 6px;border-radius:3px">THRIVING</span></div>
<div class="fa" style="font-size:10.5px;margin-top:1px">Bakery and pastry · Manchester · Limited company · 4 staff</div></div>
<div class="row" style="margin:8px 8px 0;border:1px solid {BD};border-radius:4px;overflow:hidden">{"".join(f'<span style="flex:1;text-align:center;padding:6px 0;font:600 10.5px Inter;{"background:"+PH+";color:"+AC+";box-shadow:inset 0 -2px 0 "+AC if t=="Overview" else "color:"+FA}">{t}</span>' for t in tabs)}</div>
<div style="padding:0 8px">
 <div class="pn"><div class="ph"><span>Key figures</span><span>12 months</span></div>
  <div style="display:grid;grid-template-columns:repeat(3,1fr)">
  {"".join(f'<div style="padding:6px 10px;{"border-left:1px solid "+BD if i%3 else ""};{"border-top:1px solid "+BD if i>2 else ""}"><div class="fa" style="font-size:9.5px;text-transform:uppercase;letter-spacing:.08em">{l}</div><div class="num" style="font:700 14.5px Inter;margin-top:1px">{v}</div><div style="font-size:9.5px;margin-top:1px;color:{sc}">{s}</div></div>' for i,(l,v,s,sc) in enumerate([("Profit",short(c["profitTTM"]),f'{c["margin"]*100:.1f}% margin',MU),("Revenue",short(c["revenueTTM"]),f'{pct(c["growth"],d=0)} vs 3 mo',GN),("Value",short(c["value"]),"book + goodwill",FA),("Cash",short(c["cash"]),f'{c["weeksOfCash"]:.0f} weeks of costs',FA),("Debt",short(c["debt"]),"payables + loans",FA),("Costs / wk",short(c["weeklyCost"]),"4 staff",FA)]))}
  </div></div>
 <div class="pn"><div class="ph"><span>Results by month</span><span><span style="color:{AC}">■</span> revenue &nbsp;<span style="color:{GN}">■</span> profit</span></div>
  <div style="padding:6px 10px 4px">{linechart([c["revenueSeries"][-12:],c["profitSeries"][-12:]],335,70,[AC,GN],BD,FA,LAST12_INITIAL,dots=True,width=1.4)}</div></div>
 <div class="row" style="gap:6px;align-items:stretch">
  <div class="pn" style="flex:1"><div class="ph"><span>Operations</span><span>last week</span></div>
   <table><tbody>{"".join(f'<tr><td class="mu">{l}</td><td style="color:{col};font-weight:700">{v}</td></tr>' for l,v,col in [("Capacity used",f'{c["capacityUse"]*100:.0f}%',AM),("Demand met",f'{100/c["demandCoverage"]:.0f}%',RD),("Rating",f'{c["rating"]:.1f}',attr(c["rating"],1,5)),("Reputation",f'{c["reputation"]:.0f}',attr(c["reputation"],0,100)),("Awareness",f'{c["awareness"]:.0f}',attr(c["awareness"],0,100))])}</tbody></table>
   <div class="fa" style="font-size:10px;padding:4px 8px 6px;border-top:1px solid {BD}">Bottleneck: <span style="color:{TX}">deck and rack ovens</span></div></div>
  <div class="pn" style="flex:1.25"><div class="ph"><span>Assistant</span><span>{len(ins)}</span></div>
   {"".join(f'<div style="padding:6px 8px;{"border-top:1px solid "+BD if j else ""}"><div class="row" style="gap:6px;align-items:flex-start"><span style="width:3px;height:26px;border-radius:2px;background:{GN if i["tone"]=="good" else AM}"></span><span style="font-size:10.5px;line-height:1.3;flex:1">{i["text"][:86]}{"…" if len(i["text"])>86 else ""}</span></div>{f"<div style=\"color:{AC};font-size:10px;margin:3px 0 0 9px\">Go to {i["section"]} ›</div>" if i["section"] else ""}</div>' for j,i in enumerate(ins))}
  </div>
 </div>
</div>{tabbar("group")}</div>'''
    return phone(h, BG)
