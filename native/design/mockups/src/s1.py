from common import *
# 1 · IVORY LEDGER — editorial private banking. Flat sections divided by hairlines, serif figures, no cards.
BG="#111315"; TX="#EFE9DF"; MU="#9D978E"; FA="#6C6862"; HL="rgba(239,233,223,.09)"; AC="#CFB185"; GN="#86C79D"; RD="#DC8770"; AM="#D9AE62"
CSS=f'''<style>
.s1{{font-family:Inter;color:{TX}}}
.s1 .cap{{font:600 10.5px Inter;letter-spacing:.16em;text-transform:uppercase;color:{AC}}}
.s1 .serif{{font-family:Newsreader;font-weight:500;letter-spacing:-.3px}}
.s1 .mu{{color:{MU}}} .s1 .fa{{color:{FA}}} .s1 .gn{{color:{GN}}} .s1 .rd{{color:{RD}}} .s1 .am{{color:{AM}}}
.s1 .hl{{border-top:1px solid {HL}}}
.s1 .row{{display:flex;align-items:center}}
.s1 .tab{{position:absolute;left:0;right:0;bottom:0;height:84px;background:#0D0F11;border-top:1px solid {HL};display:flex;justify-content:space-around;padding-top:8px}}
.s1 .tab div{{display:flex;flex-direction:column;align-items:center;gap:3px;font:500 10px Inter;color:{FA};width:64px}}
.s1 .tab .on{{color:{AC}}}
.s1 .hi{{position:absolute;bottom:8px;left:50%;transform:translateX(-50%);width:134px;height:5px;border-radius:3px;background:#EFE9DF}}
</style>'''
def tabbar(on):
    items=[("home","Home"),("group","Group"),("money","Money"),("inbox","Inbox"),("phone","Phone")]
    return '<div class="tab">'+"".join(f'<div class="{"on" if k==on else ""}">{icon(k,22,sw=1.5)}<span>{t}</span></div>' for k,t in items)+'</div><div class="hi"></div>'

def dashboard():
    att = attention(2)
    cos = BY_PROFIT[:4]
    h = f'''{CSS}<div class="s1">{status_bar(TX)}
<div style="padding:6px 22px 0">
 <div class="row" style="justify-content:space-between"><span class="fa" style="font-size:12px">Thursday 9 December 2027 · Week {D["week"]}</span><span class="mu" style="font-size:12px">{D["flag"]} United Kingdom</span></div>
 <div class="serif" style="font-size:25px;margin-top:4px">Alex Carter</div>
 <div class="row" style="justify-content:space-between;margin-top:14px"><span class="cap">Net worth</span><span class="fa" style="font-size:11px;letter-spacing:.04em">1W &nbsp;1M &nbsp;<span style="color:{TX};border-bottom:1px solid {AC};padding-bottom:1px">1Y</span>&nbsp; ALL</span></div>
 <div class="row" style="align-items:baseline;gap:10px;margin-top:4px"><span class="serif num" style="font-size:40px;line-height:1.05">{money(NW)}</span></div>
 <div style="font-size:12.5px;margin-top:4px"><span class="gn">{money(CH7,True)}</span><span class="mu"> this week · </span><span class="gn">{money(CH30,True)}</span><span class="mu"> in 30 days</span></div>
 <div style="margin-top:10px">{spark(nww[-52:],349,62,AC,1.4,AC)}</div>
 <div class="row hl" style="margin-top:12px;padding-top:12px">
  {"".join(f'<div style="flex:1;{"border-left:1px solid "+HL+";padding-left:10px" if i else ""}"><div class="fa" style="font-size:10.5px">{l}</div><div class="num" style="font-size:15px;font-weight:600;margin-top:2px;{"color:"+RD if v<0 else ""}">{short(v)}</div></div>' for i,(l,v) in enumerate([("Cash",D["personal"]),("Invested",D["investments"]),("Companies",D["companies"]),("Debt",-D["debt"])]))}
 </div>
 <div class="hl" style="margin-top:14px;padding-top:12px"><div class="row" style="justify-content:space-between"><span class="cap">Needs your attention</span><span class="fa" style="font-size:11px">{len(attention(9))} findings</span></div>
 {"".join(f'<div class="row" style="gap:12px;margin-top:10px;align-items:flex-start"><div style="margin-top:2px;color:{AM if i["tone"]=="warn" else RD}">{icon("alert",15)}</div><div style="flex:1"><div class="fa" style="font-size:10.5px;letter-spacing:.06em;text-transform:uppercase">{c["name"]}</div><div style="font-size:13px;line-height:1.35;margin-top:1px">{i["text"]}</div></div><div class="fa" style="margin-top:12px">{icon("chev",14)}</div></div>' for c,i in att)}
 </div>
 <div class="hl" style="margin-top:12px;padding-top:12px"><div class="row" style="justify-content:space-between"><span class="cap">Companies</span><span class="fa" style="font-size:10.5px">Profit 12 mo &nbsp;&nbsp; Cash</span></div>
 {"".join(f'<div class="row" style="margin-top:9px;font-size:13.5px"><span style="width:6px;height:6px;border-radius:3px;background:{GN if c["health"] in ("Thriving","Healthy") else AM};margin-right:10px"></span><span style="flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{c["name"]}<span class="fa" style="font-size:11.5px"> · {trade(c)}</span></span><span class="num {"rd" if c["profitTTM"]<0 else ""}" style="width:70px;text-align:right">{short(c["profitTTM"])}</span><span class="num mu" style="width:62px;text-align:right">{short(c["cash"])}</span></div>' for c in cos)}
 <div style="font-size:12px;color:{AC};margin-top:8px">All 6 companies →</div></div>
</div>
<div style="position:absolute;left:22px;right:22px;bottom:96px" class="row">
 <div style="flex:1"><div class="fa" style="font-size:10.5px">Thursday · day 4 of 7</div><div class="row" style="gap:4px;margin-top:5px">{"".join(f'<span style="width:22px;height:3px;border-radius:2px;background:{AC if d<4 else HL}"></span>' for d in range(7))}</div></div>
 <div style="background:{AC};color:#17130E;font:600 15px Inter;padding:13px 26px;border-radius:24px" class="row">Next day&nbsp;&nbsp;{icon("chev",15,"#17130E",2)}</div>
</div>
{tabbar("home")}</div>'''
    return phone(h, BG)

def group():
    rows = BY_PROFIT
    tot = sum(c['value'] for c in rows)
    shades = ["#CFB185","#B8996D","#9F8259","#866C48","#6E5839","#57462E"]
    alloc = "".join(f'<div style="flex:{c["value"]/tot:.4f};background:{shades[i]};height:6px"></div>' for i,c in enumerate(sorted(rows,key=lambda c:-c["value"])))
    h = f'''{CSS}<div class="s1">{status_bar(TX)}
<div style="padding:4px 22px 0">
 <div class="row" style="justify-content:space-between;align-items:baseline"><span class="serif" style="font-size:28px">Group</span><span class="fa" style="font-size:12px">{len(CO)} companies · {len(CITIES)} cities · {GROUP_STAFF} staff</span></div>
 <div class="cap" style="margin-top:14px">Value of holdings</div>
 <div class="row" style="align-items:baseline;justify-content:space-between;margin-top:3px"><span class="serif num" style="font-size:36px">{money(GROUP_VALUE)}</span><span class="gn" style="font-size:12.5px">{money(GCH30,True)} · 30 d</span></div>
 <div class="row" style="gap:2px;margin-top:12px;border-radius:3px;overflow:hidden">{alloc}</div>
 <div class="row hl" style="margin-top:14px;padding-top:11px">
 {"".join(f'<div style="flex:1;{"border-left:1px solid "+HL+";padding-left:10px" if i%3 else ""}"><div class="fa" style="font-size:10.5px">{l}</div><div class="num" style="font-size:15px;font-weight:600;margin-top:2px;{c}">{v}</div></div>' for i,(l,v,c) in enumerate([("Revenue 12 mo",short(GROUP_REV),""),("Profit 12 mo",short(GROUP_PROFIT),"color:"+GN),("Margin",f"{GROUP_PROFIT/GROUP_REV*100:.1f}%","")]))}
 </div>
 <div class="row" style="margin-top:10px">
 {"".join(f'<div style="flex:1;{"border-left:1px solid "+HL+";padding-left:10px" if i%3 else ""}"><div class="fa" style="font-size:10.5px">{l}</div><div class="num" style="font-size:15px;font-weight:600;margin-top:2px">{v}</div></div>' for i,(l,v) in enumerate([("Cash in companies",short(GROUP_CASH)),("Debt",short(GROUP_DEBT)),("Staff",str(GROUP_STAFF))]))}
 </div>
 <div class="hl" style="margin-top:14px;padding-top:12px"><div class="row" style="justify-content:space-between"><span class="cap">Revenue and profit by month</span><span class="fa" style="font-size:10.5px"><span style="color:{AC}">—</span> Revenue &nbsp;<span style="color:{GN}">—</span> Profit</span></div>
 <div style="margin-top:8px">{linechart([G_REV,G_PROF],349,92,[AC,GN],HL,FA,LAST12_INITIAL)}</div></div>
 <div class="hl" style="margin-top:12px;padding-top:10px">
  <div class="row fa" style="font-size:10px;letter-spacing:.1em;text-transform:uppercase"><span style="flex:1">Company · sorted by profit</span><span style="width:64px;text-align:right">Value</span><span style="width:66px;text-align:right">Profit</span><span style="width:52px;text-align:right">Rev. 12m</span></div>
  {"".join(f'<div class="row" style="padding:9px 0;{"border-top:1px solid "+HL if j else ""};margin-top:{6 if not j else 0}px"><div style="flex:1;min-width:0"><div style="font-size:13.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{c["name"]}</div><div style="font-size:11px;margin-top:1px"><span class="fa">{trade(c)} · {c["city"]} · </span><span style="color:{GN if c["health"] in ("Thriving","Healthy") else AM}">{c["health"]}</span></div></div><span class="num" style="width:64px;text-align:right;font-size:13.5px">{short(c["value"])}</span><span class="num" style="width:66px;text-align:right;font-size:13.5px;color:{RD if c["profitTTM"]<0 else TX}">{short(c["profitTTM"])}</span><span style="width:52px;display:flex;justify-content:flex-end">{spark(c["revenueSeries"][-12:],44,18,GN if (c["growth"] or 0)>=0 else RD,1.3)}</span></div>' for j,c in enumerate(rows))}
 </div>
</div>{tabbar("group")}</div>'''
    return phone(h, BG)

def company():
    c = BAKERY
    tabs = ["Overview","Staff","Finances","Operations","Marketing"]
    links = {"operations":"Operations","staff":"Staff","marketing":"Marketing","finances":"Finances"}
    ins = [i for i in c["insights"] if "Competitors" not in i["text"]][:3]
    h = f'''{CSS}<div class="s1">{status_bar(TX)}
<div style="padding:2px 22px 0">
 <div class="row" style="justify-content:space-between;color:{AC};font-size:15px"><span class="row" style="gap:2px">{icon("back",18,AC)}Group</span>{icon("more",20,MU)}</div>
 <div class="serif" style="font-size:26px;margin-top:8px;line-height:1.1">{c["name"]}</div>
 <div style="font-size:12px;margin-top:3px"><span class="mu">Bakery · Manchester · Ltd · </span><span class="gn">● Thriving</span></div>
 <div class="row" style="gap:18px;margin-top:14px;font-size:13.5px;border-bottom:1px solid {HL}">{"".join(f'<span style="padding-bottom:8px;{"color:"+TX+";border-bottom:1.5px solid "+AC if t=="Overview" else "color:"+FA}">{t}</span>' for t in tabs)}</div>
 <div class="row" style="margin-top:14px;align-items:flex-end;justify-content:space-between"><div><div class="cap">Profit · 12 months</div><div class="serif num" style="font-size:34px;margin-top:2px">{money(c["profitTTM"])}</div></div><div style="text-align:right;font-size:12px"><div class="mu">Margin <span style="color:{TX}">{c["margin"]*100:.1f}%</span></div><div class="mu" style="margin-top:2px">Revenue <span style="color:{TX}">{short(c["revenueTTM"])}</span> <span class="gn">{pct(c["growth"],d=0)}</span></div></div></div>
 <div class="row hl" style="margin-top:12px;padding-top:10px">
 {"".join(f'<div style="flex:1;{"border-left:1px solid "+HL+";padding-left:10px" if i else ""}"><div class="fa" style="font-size:10.5px">{l}</div><div class="num" style="font-size:14.5px;font-weight:600;margin-top:2px">{v}</div><div class="fa" style="font-size:10px;margin-top:1px">{s}</div></div>' for i,(l,v,s) in enumerate([("Cash",short(c["cash"]),f'{c["weeksOfCash"]:.0f} wks of costs'),("Value",short(c["value"]),"book + goodwill"),("Costs / week",short(c["weeklyCost"]),f'{c["staff"]} staff')]))}
 </div>
 <div class="hl" style="margin-top:12px;padding-top:10px"><div class="row" style="justify-content:space-between"><span class="cap">By month</span><span class="fa" style="font-size:10.5px"><span style="color:{AC}">—</span> Revenue &nbsp;<span style="color:{GN}">—</span> Profit</span></div>
 <div style="margin-top:6px">{linechart([c["revenueSeries"][-12:],c["profitSeries"][-12:]],349,84,[AC,GN],HL,FA,LAST12_INITIAL)}</div></div>
 <div class="hl" style="margin-top:12px;padding-top:10px"><span class="cap">What is going on</span>
 {"".join(f'<div class="row" style="gap:10px;margin-top:9px;align-items:flex-start"><span style="margin-top:2px;color:{GN if i["tone"]=="good" else AM}">{icon("check" if i["tone"]=="good" else "alert",14)}</span><span style="flex:1;font-size:13px;line-height:1.35">{i["text"].replace("2751","2,751")}</span>{f"<span style=\"font-size:11.5px;color:{AC};white-space:nowrap;margin-top:1px\">{links[i["section"]]} →</span>" if i["section"] else ""}</div>' for i in ins)}
 </div>
 <div class="hl" style="margin-top:12px;padding-top:10px"><div class="row" style="justify-content:space-between"><span class="cap">Last week</span><span class="fa" style="font-size:11px">{c["served"]:,.0f} served of {c["capacity"]:,.0f} possible</span></div>
 {"".join(f'<div class="row" style="gap:10px;margin-top:8px;font-size:12px"><span class="mu" style="width:96px">{l}</span><div style="flex:1;height:4px;background:{HL};border-radius:2px"><div style="width:{min(1,v)*100:.0f}%;height:4px;border-radius:2px;background:{col}"></div></div><span class="num" style="width:38px;text-align:right">{v*100:.0f}%</span></div>' for l,v,col in [("Capacity used",c["capacityUse"],AM),("Demand met",1/c["demandCoverage"],AM),("Awareness",c["awareness"]/100,AC)])}
 <div class="fa" style="font-size:11.5px;margin-top:7px">Limited by <span style="color:{TX}">deck and rack ovens</span> · turning customers away</div></div>
</div>{tabbar("group")}</div>'''
    return phone(h, BG)
