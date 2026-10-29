from common import *
# 3 · WALNUT STUDY — a private study at night. Warm walnut light, Cormorant figures, brass rules, ledger lines with dotted leaders.
BG="radial-gradient(120% 60% at 70% 0%,#2A1E15 0%,#17110C 45%,#0C0907 100%)"
TX="#F3EADD"; MU="#B2A391"; FA="#7E7163"; BR="#C9A36B"; RG="#D7A88B"; GN="#A4C99A"; RD="#DD8A72"; AM="#E0B566"; HL="rgba(243,234,221,.10)"
CSS=f'''<style>
.s3{{font-family:Inter;color:{TX};font-size:13px}}
.s3 .row{{display:flex;align-items:center}}
.s3 .cg{{font-family:"Cormorant Garamond";font-weight:600;letter-spacing:-.2px;font-feature-settings:"lnum" 1,"tnum" 1}}
.s3 .mu{{color:{MU}}} .s3 .fa{{color:{FA}}} .s3 .gn{{color:{GN}}} .s3 .rd{{color:{RD}}} .s3 .am{{color:{AM}}} .s3 .br{{color:{BR}}}
.s3 .sc{{font:600 10px Inter;letter-spacing:.2em;text-transform:uppercase;color:{BR}}}
.s3 .hd{{display:flex;align-items:center;gap:10px;margin-top:16px}}
.s3 .hd .t{{font-family:"Cormorant Garamond";font-weight:600;font-size:19px;color:{TX};white-space:nowrap}}
.s3 .hd .r{{flex:1;height:1px;background:linear-gradient(90deg,{BR}88,{BR}11)}}
.s3 .hd .n{{font-size:11px;color:{FA};white-space:nowrap}}
.s3 .lead{{display:flex;align-items:baseline;gap:6px}}
.s3 .lead .d{{flex:1;border-bottom:1px dotted rgba(201,163,107,.35);transform:translateY(-3px)}}
.s3 .tab{{position:absolute;left:0;right:0;bottom:0;height:84px;background:linear-gradient(#0E0A07EE,#0A0705);border-top:1px solid rgba(201,163,107,.18);display:flex;justify-content:space-around;padding-top:8px}}
.s3 .tab div{{display:flex;flex-direction:column;align-items:center;gap:3px;font:500 10px Inter;color:{FA};width:64px}}
.s3 .tab .on{{color:{BR}}}
.s3 .hi{{position:absolute;bottom:8px;left:50%;transform:translateX(-50%);width:134px;height:5px;border-radius:3px;background:{TX}}}
.s3 .next{{position:absolute;left:50%;transform:translateX(-50%);bottom:96px;display:flex;align-items:center;gap:10px;padding:11px 22px;border-radius:24px;
  background:linear-gradient(180deg,#E4C691,#B98D52);color:#1E140B;font:600 14.5px Inter;box-shadow:0 8px 22px rgba(0,0,0,.55),inset 0 1px 0 rgba(255,255,255,.45);white-space:nowrap}}
.s3 .next span{{font-weight:500;opacity:.7;font-size:12.5px}}
</style>'''
def tabbar(on):
    items=[("home","Home"),("group","Group"),("money","Money"),("inbox","Inbox"),("phone","Phone")]
    return '<div class="tab">'+"".join(f'<div class="{"on" if k==on else ""}">{icon(k,22,sw=1.4)}<span>{t}</span></div>' for k,t in items)+'</div><div class="hi"></div>'
def nextday(): return f'<div class="next">Next day {icon("chev",14,"#1E140B",2.2)}<span>Fri 10 Dec</span></div>'
def head(t, n=""): return f'<div class="hd"><span class="t">{t}</span><span class="r"></span><span class="n">{n}</span></div>'
def lead(l, v, col=TX, fs=13.5):
    return f'<div class="lead" style="margin-top:7px"><span class="mu" style="font-size:12.5px;white-space:nowrap">{l}</span><span class="d"></span><span class="num" style="font-size:{fs}px;font-weight:500;color:{col};white-space:nowrap">{v}</span></div>'
def hcol(h): return {"Thriving":GN,"Healthy":GN,"Tight":AM}.get(h,RD)
ROMAN = ["i","ii","iii","iv"]

def dashboard():
    att = attention(3)
    w = nww[-53:]
    lo, hi = min(w), max(w)
    h = f'''{CSS}<div class="s3">{status_bar(TX)}
<div style="text-align:center;padding-top:4px"><div class="sc">Thursday 9 December 2027 · Week {D["week"]}</div>
 <div class="mu" style="font-size:12px;margin-top:10px">Net worth of Alex Carter</div>
 <div class="cg num" style="font-size:48px;line-height:1;margin-top:2px">{money(NW)}</div>
 <div style="font-size:12px;margin-top:5px"><span class="gn">{money(CH7,True)}</span><span class="mu"> this week</span><span class="fa"> &nbsp;·&nbsp; </span><span class="gn">{money(CH30,True)}</span><span class="mu"> in 30 days</span></div></div>
<div style="margin-top:10px;position:relative">{spark(w,393,64,RG,1.4,BR)}
 <div class="row fa" style="justify-content:space-between;padding:4px 20px 0;font-size:10px"><span>Dec 2026 · {short(w[0])}</span><span>low {short(lo)} · high {short(hi)}</span><span>today</span></div></div>
<div style="padding:0 20px">
 <div class="row" style="margin-top:12px;border-top:1px solid {HL};border-bottom:1px solid {HL};padding:9px 0">
 {"".join(f'<div style="flex:1;text-align:center;{"border-left:1px solid "+HL if i else ""}"><div class="fa" style="font-size:10px;letter-spacing:.08em;text-transform:uppercase">{l}</div><div class="cg num" style="font-size:19px;margin-top:1px;{"color:"+RD if v<0 else ""}">{short(v)}</div></div>' for i,(l,v) in enumerate([("Cash",D["personal"]),("Invested",D["investments"]),("Companies",D["companies"]),("Debt",-D["debt"])]))}
 </div>
 {head("Today's brief", f"{len(attention(9))} notes")}
 {"".join(f'<div class="row" style="gap:12px;margin-top:9px;align-items:flex-start"><span class="cg br" style="width:18px;font-size:17px;line-height:1;text-align:right">{ROMAN[k]}.</span><div style="flex:1"><div style="font-size:12.5px;line-height:1.38"><span style="color:{TX};font-weight:600">{c["name"]}</span><span class="mu"> — {i["text"]}</span></div></div><span class="br" style="margin-top:1px">{icon("chev",13,BR)}</span></div>' for k,(c,i) in enumerate(att))}
 {head("The companies", "profit, 12 months")}
 {"".join(f'<div class="lead" style="margin-top:7px"><span style="width:6px;height:6px;border-radius:3px;background:{hcol(c["health"])};flex:none;transform:translateY(-2px)"></span><span style="font-size:13px;white-space:nowrap">{c["name"]}</span><span class="d"></span><span class="num" style="font-size:13.5px;font-weight:500;color:{RD if c["profitTTM"]<0 else TX}">{short(c["profitTTM"])}</span></div>' for c in BY_PROFIT[:4])}
</div>
{nextday()}{tabbar("home")}</div>'''
    return phone(h, BG)

def donut(parts, size, colors, width, gap_col):
    r = (size - width) / 2; C = 2 * math.pi * r; tot = sum(parts); off = 0; out = []
    for v, col in zip(parts, colors):
        L = C * v / tot
        out.append(f'<circle cx="{size/2}" cy="{size/2}" r="{r}" fill="none" stroke="{col}" stroke-width="{width}" stroke-dasharray="{max(L-2,0.5):.1f} {C}" stroke-dashoffset="{-off:.1f}" transform="rotate(-90 {size/2} {size/2})"/>')
        off += L
    return f'<svg width="{size}" height="{size}" viewBox="0 0 {size} {size}">{"".join(out)}</svg>'

def group():
    byv = sorted(CO, key=lambda c: -c["value"])
    shades = ["#E2BE86","#C9A36B","#D7A88B","#A9845A","#8E6F4E","#6E5741"]
    h = f'''{CSS}<div class="s3">{status_bar(TX)}
<div style="padding:2px 20px 0">
 <div class="sc">Holdings · 9 Dec 2027</div>
 <div class="row" style="justify-content:space-between;align-items:baseline"><span class="cg" style="font-size:30px">The Group</span><span class="fa" style="font-size:11.5px">{len(CO)} companies · {GROUP_STAFF} staff</span></div>
 <div class="row" style="gap:16px;margin-top:10px">
  <div style="position:relative;width:124px;height:124px;flex:none">{donut([c["value"] for c in byv],124,shades,9,BG)}
   <div style="position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center"><div class="fa" style="font-size:9.5px;letter-spacing:.12em">VALUE</div><div class="cg num" style="font-size:24px;line-height:1.05">{short(GROUP_VALUE)}</div><div class="gn" style="font-size:10.5px">{short(GCH30,True)} · 30d</div></div></div>
  <div style="flex:1">{"".join(f'<div class="row" style="gap:7px;margin-top:{0 if not k else 5}px;font-size:11.5px"><span style="width:8px;height:8px;border-radius:2px;background:{shades[k]};flex:none"></span><span style="flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{c["name"].split()[0]} <span class="fa">{trade(c)}</span></span><span class="num mu">{c["value"]/GROUP_VALUE*100:.0f}%</span></div>' for k,c in enumerate(byv))}</div>
 </div>
 <div class="row" style="gap:22px;margin-top:8px;align-items:flex-start">
  <div style="flex:1">{lead("Revenue, 12 mo",short(GROUP_REV))}{lead("Profit, 12 mo",short(GROUP_PROFIT),GN)}{lead("Margin",f"{GROUP_PROFIT/GROUP_REV*100:.1f}%")}</div>
  <div style="flex:1">{lead("Cash held",short(GROUP_CASH))}{lead("Debt",short(GROUP_DEBT),RD)}{lead("Cities",str(len(CITIES)))}</div>
 </div>
 {head("By month", '<span style="color:'+RG+'">—</span> revenue &nbsp;<span style="color:'+GN+'">—</span> profit')}
 <div style="margin-top:8px">{linechart([G_REV,G_PROF],353,84,[RG,GN],HL,FA,LAST12_INITIAL)}</div>
 {head("The ledger", "sorted by profit")}
 <div class="row fa" style="font-size:9.5px;letter-spacing:.12em;text-transform:uppercase;margin-top:8px;padding-bottom:5px;border-bottom:1px solid {HL}"><span style="flex:1">Company</span><span style="width:58px;text-align:right">Value</span><span style="width:60px;text-align:right">Profit</span><span style="width:48px;text-align:right">Trend</span><span style="width:52px;text-align:right">State</span></div>
 {"".join(f'<div class="row" style="padding:6px 0;border-bottom:1px solid {HL}"><div style="flex:1;min-width:0"><div style="font-size:12.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{c["name"]}</div><div class="fa" style="font-size:10.5px">{trade(c)} · {c["city"]}</div></div><span class="cg num" style="width:58px;text-align:right;font-size:15px">{short(c["value"])}</span><span class="cg num" style="width:60px;text-align:right;font-size:15px;color:{RD if c["profitTTM"]<0 else TX}">{short(c["profitTTM"])}</span><span style="width:48px;display:flex;justify-content:flex-end">{spark(c["profitSeries"][-12:],38,16,GN if sum(c["profitSeries"][-3:])>=0 else RD,1.2)}</span><span style="width:52px;text-align:right;font-size:11px;color:{hcol(c["health"])}">{c["health"]}</span></div>' for c in BY_PROFIT)}
</div>{nextday()}{tabbar("group")}</div>'''
    return phone(h, BG)

def company():
    c = BAKERY
    tabs = ["Overview","Staff","Finances","Operations","Marketing"]
    links = {"operations":"Operations","staff":"Staff","marketing":"Marketing","finances":"Finances"}
    ins = [i for i in c["insights"] if "Competitors" not in i["text"]][:3]
    h = f'''{CSS}<div class="s3">{status_bar(TX)}
<div style="padding:2px 20px 0">
 <div class="row br" style="gap:2px;font-size:14px">{icon("back",17,BR)}The group</div>
 <div class="cg" style="font-size:27px;line-height:1.05;margin-top:8px;white-space:nowrap">{c["name"]}</div>
 <div style="font-size:12px;margin-top:3px"><span class="mu">Bakery and pastry · Manchester · Ltd</span><span class="fa"> · </span><span class="gn">Thriving</span></div>
 <div class="row" style="gap:16px;margin-top:12px;font-size:12.5px">{"".join(f'<span style="display:flex;flex-direction:column;align-items:center;gap:4px;{"color:"+TX if t=="Overview" else "color:"+FA}">{t}<span style="width:4px;height:4px;transform:rotate(45deg);background:{BR if t=="Overview" else "transparent"}"></span></span>' for t in tabs)}</div>
 <div class="row" style="margin-top:6px;border-top:1px solid {HL};padding-top:12px;align-items:flex-end;justify-content:space-between">
  <div><div class="mu" style="font-size:11.5px">Profit, last 12 months</div><div class="cg num" style="font-size:40px;line-height:1">{money(c["profitTTM"])}</div></div>
  <div style="text-align:right"><div class="gn" style="font-size:12px">Revenue {pct(c["growth"],d=0)} on 3 mo</div><div class="fa" style="font-size:11px;margin-top:2px">this month {short(c["monthProfit"])} profit</div></div></div>
 <div class="row" style="gap:22px;margin-top:6px;align-items:flex-start">
  <div style="flex:1">{lead("Revenue",short(c["revenueTTM"]))}{lead("Margin",f'{c["margin"]*100:.1f}%')}{lead("Value",short(c["value"]))}</div>
  <div style="flex:1">{lead("Cash",short(c["cash"]))}{lead("Costs / wk",short(c["weeklyCost"]))}{lead("Staff",str(c["staff"]))}</div>
 </div>
 {head("By month", '<span style="color:'+RG+'">—</span> revenue &nbsp;<span style="color:'+GN+'">—</span> profit')}
 <div style="margin-top:8px">{linechart([c["revenueSeries"][-12:],c["profitSeries"][-12:]],353,78,[RG,GN],HL,FA,LAST12_INITIAL)}</div>
 {head("Notes from the manager", f"{len(ins)}")}
 {"".join(f'<div class="row" style="gap:12px;margin-top:8px;align-items:flex-start"><span class="cg br" style="width:16px;font-size:17px;line-height:1;text-align:right">{ROMAN[k]}.</span><span style="flex:1;font-size:12.5px;line-height:1.38;color:{TX}">{i["text"]}</span>{f"<span class=br style=\"font-size:11.5px;white-space:nowrap\">{links[i["section"]]} ›</span>" if i["section"] else ""}</div>' for k,i in enumerate(ins))}
 {head("The bakehouse, last week")}
 <div class="row" style="gap:22px;align-items:flex-start">
  <div style="flex:1">{lead("Served",f'{c["served"]:,}')}{lead("Capacity used",f'{c["capacityUse"]*100:.0f}%',AM)}</div>
  <div style="flex:1">{lead("Demand met",f'{100/c["demandCoverage"]:.0f}%',AM)}{lead("Rating",f'{c["rating"]:.1f} / 5')}</div>
 </div>
</div>{tabbar("group")}</div>'''
    return phone(h, BG)
