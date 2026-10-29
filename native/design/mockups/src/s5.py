from common import *
# 5 · SKYLINE LUXE — closest to the sent concept: evening city header, greeting and initials, joined tiles with sparklines,
# rings for operations, bronze Next day. Colours are the concept's: walnut, ivory, gold, gain, loss.
BG="#090C0E"; PN="linear-gradient(180deg,#14171A,#101214)"; BD="rgba(249,247,241,.08)"; TX="#F9F7F1"; MU="#A9A49C"; FA="#6E6A64"
AC="#E3BA87"; GN="#6BD595"; RD="#E57460"; AM="#E9B65A"
CSS=f'''<style>
.s5{{font-family:Inter;color:{TX};font-size:13px}}
.s5 .row{{display:flex;align-items:center}}
.s5 .mu{{color:{MU}}} .s5 .fa{{color:{FA}}} .s5 .gn{{color:{GN}}} .s5 .rd{{color:{RD}}} .s5 .am{{color:{AM}}} .s5 .ac{{color:{AC}}}
.s5 .cap{{font:600 10px Inter;letter-spacing:.14em;text-transform:uppercase;color:{MU}}}
.s5 .pn{{background:{PN};border:1px solid {BD};border-radius:12px}}
.s5 .tiles{{display:flex;background:{PN};border:1px solid {BD};border-radius:12px;overflow:hidden}}
.s5 .tiles>div{{flex:1;padding:9px 11px}}
.s5 .tiles>div+div{{border-left:1px solid {BD}}}
.s5 .chip{{font:600 11px Inter;padding:3px 8px;border-radius:10px;white-space:nowrap}}
.s5 .tab{{position:absolute;left:0;right:0;bottom:0;height:84px;background:#07090A;border-top:1px solid {BD};display:flex;justify-content:space-around;padding-top:8px}}
.s5 .tab div{{display:flex;flex-direction:column;align-items:center;gap:3px;font:500 10px Inter;color:{FA};width:64px}}
.s5 .tab .on{{color:{AC}}}
.s5 .hi{{position:absolute;bottom:8px;left:50%;transform:translateX(-50%);width:134px;height:5px;border-radius:3px;background:{TX}}}
.s5 .next{{position:absolute;left:16px;right:16px;bottom:94px;height:50px;border-radius:14px;display:flex;align-items:center;justify-content:space-between;padding:0 16px;
  background:linear-gradient(180deg,#E8C597 0%,#C9935C 100%);color:#1D130A;box-shadow:0 10px 26px rgba(0,0,0,.6),inset 0 1px 0 rgba(255,255,255,.5)}}
</style>'''
def tabbar(on):
    items=[("home","Home"),("group","Group"),("money","Money"),("inbox","Inbox"),("phone","Phone")]
    return '<div class="tab">'+"".join(f'<div class="{"on" if k==on else ""}">{icon(k,22,sw=1.5)}<span>{t}</span></div>' for k,t in items)+'</div><div class="hi"></div>'
def nextday():
    return f'''<div class="next"><div><div style="font:700 15.5px Inter">Next day</div><div style="font:500 11px Inter;opacity:.7">Friday 10 Dec · {short(D["due30"])} due in the next 30 days</div></div>{icon("chev",20,"#1D130A",2.4)}</div>'''
def header(h, seed, inner):
    return f'''<div style="position:absolute;top:0;left:0;right:0;height:{h}px">{skyline(393,h,seed)}<div style="position:absolute;inset:0;background:linear-gradient(180deg,rgba(9,12,14,.55) 0%,rgba(9,12,14,0) 35%,rgba(9,12,14,.2) 70%,{BG} 100%)"></div></div>
<div style="position:relative">{status_bar(TX)}{inner}</div>'''
def hcol(h): return {"Thriving":GN,"Healthy":GN,"Tight":AM}.get(h,RD)
HSCORE = {"Thriving":.92,"Healthy":.72,"Tight":.4,"Struggling":.2}
def chip(t, col): return f'<span class="chip" style="color:{col};background:{col}1F">{t}</span>'

def dashboard():
    att = attention(1)[0]
    goods = [(c,i) for c in CO for i in c["insights"] if i["tone"]=="good"][:1]
    warns = [(c,i) for c,i in attention(4)[1:3]]
    bullets = goods + warns
    inner = f'''<div class="row" style="justify-content:space-between;padding:6px 18px 0">
 <div><div style="font-size:13px;color:#E9DFD0">Good evening,</div><div style="font:600 25px Inter;letter-spacing:-.4px">Alex Carter</div><div style="font-size:11.5px;color:#CDBFAE;margin-top:2px">Thu 9 Dec 2027 · Week {D["week"]} · Economy booming</div></div>
 <div style="width:44px;height:44px;border-radius:22px;border:1.5px solid {AC};display:flex;align-items:center;justify-content:center;font:600 15px Inter;color:{AC};background:rgba(9,12,14,.55)">AC</div></div>'''
    h = f'''{CSS}<div class="s5">{header(200,7,inner)}
<div style="padding:0 16px;position:relative;margin-top:58px">
 <div class="pn" style="padding:12px 14px 10px">
  <div class="row" style="justify-content:space-between"><span class="cap">Net worth</span><span class="fa" style="font-size:10.5px">30 days</span></div>
  <div class="row" style="justify-content:space-between;align-items:flex-end;margin-top:3px">
   <div><div class="num" style="font:600 32px Inter;letter-spacing:-.8px">{money(NW)}</div>
   <div class="row" style="gap:6px;margin-top:6px">{chip("▲ "+money(CH30)+" · 30d",GN)}{chip("▲ "+money(CH7)+" · 7d",GN)}{chip("Debt "+short(D["debt"]),RD)}</div></div>
  </div>
  <div style="margin-top:8px">{spark(nwd[-31:],329,46,AC,1.6,AC)}</div>
 </div>
 <div class="tiles" style="margin-top:8px">
 {"".join(f'<div><div class="cap" style="font-size:9px">{l}</div><div class="num" style="font:600 15.5px Inter;margin-top:3px">{short(v)}</div><div style="margin-top:5px;height:18px">{sp}</div></div>' for l,v,sp in [("Cash",D["personal"],f'<div class="fa" style="font-size:10.5px;padding-top:3px">Loan {short(D["debt"])}</div>'),("Invested",D["investments"],spark(D["invDaily"][-31:],90,18,RD,1.3)),("Companies",D["companies"],spark(COD[-31:],90,18,GN,1.3))])}
 </div>
 <div class="pn row" style="margin-top:8px;padding:10px 12px;gap:11px;border-color:{AM}40;background:linear-gradient(90deg,{AM}14,{AM}05)">
  <div style="color:{AM}">{icon("alert",18,AM,1.8)}</div>
  <div style="flex:1"><div style="font:600 12.5px Inter">{att[0]["name"]} needs attention</div><div class="mu" style="font-size:11.5px;line-height:1.35;margin-top:1px">Cash fell from £220k to £176k in three months while profit was only £3,943.</div></div>
  {icon("chev",15,MU,2)}</div>
 <div class="row" style="justify-content:space-between;margin-top:14px"><span class="cap">Insights</span><span class="ac" style="font-size:11.5px">All 9</span></div>
 {"".join(f'<div class="row" style="gap:10px;margin-top:8px;align-items:flex-start"><span style="width:6px;height:6px;border-radius:3px;margin-top:6px;flex:none;background:{GN if i["tone"]=="good" else AM}"></span><div style="flex:1;font-size:12.5px;line-height:1.38"><span style="font-weight:600">{c["name"].split()[0]}</span><span class="mu"> · {i["text"]}</span></div></div>' for c,i in bullets)}
</div>{nextday()}{tabbar("home")}</div>'''
    return phone(h, BG)

def group():
    inner = f'''<div class="row" style="justify-content:space-between;padding:4px 18px 0;align-items:flex-start">
 <div><div style="font:600 28px Inter;letter-spacing:-.5px">Group</div><div style="font-size:12px;color:#CDBFAE;margin-top:1px">{len(CO)} companies · {len(CITIES)} cities · {GROUP_STAFF} staff</div></div>
 <div style="width:38px;height:38px;border-radius:19px;border:1px solid {AC}88;display:flex;align-items:center;justify-content:center;background:rgba(9,12,14,.55);margin-top:4px">{icon("plus",18,AC,2)}</div></div>'''
    h = f'''{CSS}<div class="s5">{header(150,11,inner)}
<div style="padding:0 16px;position:relative;margin-top:30px">
 <div class="pn" style="padding:11px 14px 10px">
  <div class="row" style="justify-content:space-between"><span class="cap">Value of companies</span><span class="fa" style="font-size:10.5px">90 days</span></div>
  <div class="row" style="justify-content:space-between;align-items:flex-end;margin-top:3px">
   <div><div class="num" style="font:600 30px Inter;letter-spacing:-.8px">{money(GROUP_VALUE)}</div><div class="row" style="gap:6px;margin-top:5px">{chip("▲ "+short(GCH30)+" · 30d",GN)}{chip("Profit "+short(GROUP_PROFIT)+" · 12m",GN)}</div></div>
   <div style="margin-bottom:4px">{spark(COD[-91:],96,40,AC,1.5,AC)}</div></div>
 </div>
 <div class="tiles" style="margin-top:8px">
 {"".join(f'<div style="padding:8px 10px"><div class="cap" style="font-size:8.5px">{l}</div><div class="num" style="font:600 14px Inter;margin-top:3px;color:{col}">{v}</div></div>' for l,v,col in [("Cash",short(GROUP_CASH),TX),("Debt",short(GROUP_DEBT),RD),("Revenue",short(GROUP_REV),TX),("Margin",f"{GROUP_PROFIT/GROUP_REV*100:.1f}%",TX)])}
 </div>
 <div class="row" style="justify-content:space-between;margin-top:14px"><span class="cap">Companies</span><span class="ac row" style="font-size:11.5px;gap:4px">{icon("sort",13,AC,2)}Profit</span></div>
 <div class="pn" style="margin-top:7px;padding:0 10px">
  <div class="row fa" style="font:600 9px Inter;letter-spacing:.1em;text-transform:uppercase;height:26px;border-bottom:1px solid {BD}"><span style="flex:1;padding-left:34px">Company · health</span><span style="width:50px;text-align:right">Value</span><span style="width:58px;text-align:right">Profit 12m</span><span style="width:44px;text-align:right">Trend</span></div>
  {"".join(f'<div class="row" style="height:48px;{"border-top:1px solid "+BD if j else ""}"><div class="row" style="flex:1;gap:8px;min-width:0"><div style="position:relative;width:26px;height:26px;flex:none">{ring(HSCORE[c["health"]],26,hcol(c["health"]),"rgba(249,247,241,.09)",2.5)}<div style="position:absolute;inset:0;display:flex;align-items:center;justify-content:center">{icon(ticon(c),13,AC,1.9)}</div></div><div style="min-width:0"><div style="font:600 12.5px Inter;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{c["name"]}</div><div style="font-size:10.5px;white-space:nowrap"><span class="fa">{trade(c)} · </span><span style="color:{hcol(c["health"])}">{c["health"]}</span></div></div></div><span class="num" style="width:50px;text-align:right;font:500 12.5px Inter">{short(c["value"])}</span><span class="num" style="width:58px;text-align:right;font:600 12.5px Inter;color:{GN if c["profitTTM"]>=0 else RD}">{short(c["profitTTM"],True)}</span><div style="width:44px;display:flex;flex-direction:column;align-items:flex-end;gap:1px">{spark(c["revenueSeries"][-12:],38,14,GN if (c["growth"] or 0)>=0 else RD,1.3)}<span class="num" style="font-size:10px;color:{GN if (c["growth"] or 0)>=0 else RD}">{pct(c["growth"],d=0) if c["growth"] is not None else "new"}</span></div></div>' for j,c in enumerate(BY_PROFIT))}
 </div>
</div>{nextday()}{tabbar("group")}</div>'''
    return phone(h, BG)

def company():
    c = BAKERY
    links = {"operations":"Operations","staff":"Staff","marketing":"Marketing","finances":"Finances"}
    ins = [i for i in c["insights"] if "Competitors" not in i["text"]][:3]
    inner = f'''<div style="padding:2px 18px 0"><div class="row" style="gap:2px;font-size:14px;color:{AC}">{icon("back",17,AC,2)}Group</div>
 <div style="font:600 24px Inter;letter-spacing:-.4px;margin-top:22px;white-space:nowrap">{c["name"]}</div>
 <div class="row" style="gap:8px;margin-top:3px"><span style="font-size:12px;color:#CDBFAE">Bakery and pastry · Manchester · Ltd</span>{chip("Thriving",GN)}</div></div>'''
    rings = [(min(1,c["capacityUse"]),AM,f'{c["capacityUse"]*100:.0f}%',"Capacity"),(1/c["demandCoverage"],AM,f'{100/c["demandCoverage"]:.0f}%',"Demand met"),(c["awareness"]/100,AC,f'{c["awareness"]:.0f}',"Awareness"),(c["rating"]/5,GN,f'{c["rating"]:.1f}',"Rating")]
    h = f'''{CSS}<div class="s5">{header(160,23,inner)}
<div style="padding:0 16px;position:relative">
 <div class="row" style="gap:18px;margin-top:10px;font-size:13px;border-bottom:1px solid {BD}">{"".join(f'<span style="padding-bottom:7px;{"color:"+TX+";border-bottom:2px solid "+AC+";font-weight:600" if t=="Overview" else "color:"+FA}">{t}</span>' for t in ["Overview","Staff","Finances","Operations","Marketing"])}</div>
 <div class="tiles" style="margin-top:10px">
 {"".join(f'<div><div class="cap" style="font-size:9px">{l}</div><div class="num" style="font:600 16px Inter;margin-top:3px;color:{col}">{v}</div><div style="font-size:10.5px;margin-top:2px" class="{sc}">{s}</div></div>' for l,v,col,s,sc in [("Profit 12m",short(c["profitTTM"]),GN,f'{c["margin"]*100:.1f}% margin',"fa"),("Revenue 12m",short(c["revenueTTM"]),TX,f'▲ {c["growth"]*100:.0f}% vs 3 mo',"gn"),("Cash",short(c["cash"]),TX,f'{c["weeksOfCash"]:.0f} wks of costs',"fa")])}
 </div>
 <div class="pn" style="margin-top:8px;padding:10px 6px 8px">
  <div class="row" style="justify-content:space-between;padding:0 8px"><span class="cap">Operations · last week</span><span class="fa" style="font-size:10.5px">{c["served"]:,} served</span></div>
  <div class="row" style="justify-content:space-around;margin-top:8px">{"".join(f'<div style="display:flex;flex-direction:column;align-items:center;gap:4px">{ring(f,50,col,"rgba(249,247,241,.08)",4.5,lab,"Inter",12.5,TX)}<span class="mu" style="font-size:10.5px">{t}</span></div>' for f,col,lab,t in rings)}</div>
  <div class="row" style="gap:8px;margin:10px 8px 0;padding-top:9px;border-top:1px solid {BD}"><span class="am">{icon("gauge",15,AM,1.8)}</span><span style="flex:1;font-size:12px"><span class="mu">Bottleneck:</span> deck and rack ovens</span><span class="ac" style="font:600 12px Inter">Buy equipment ›</span></div>
 </div>
 <div class="row" style="justify-content:space-between;margin-top:12px"><span class="cap">Revenue & profit</span><span class="fa" style="font-size:10.5px"><span style="color:{AC}">●</span> Revenue &nbsp;<span style="color:{GN}">●</span> Profit</span></div>
 <div style="margin-top:6px">{linechart([c["revenueSeries"][-12:],c["profitSeries"][-12:]],361,74,[AC,GN],BD,FA,LAST12_INITIAL,fills=[AC,None],width=1.6)}</div>
 <div class="cap" style="margin-top:12px">Insights</div>
 {"".join(f'<div class="row" style="gap:10px;margin-top:7px;align-items:flex-start"><span style="width:6px;height:6px;border-radius:3px;margin-top:6px;flex:none;background:{GN if i["tone"]=="good" else AM}"></span><span style="flex:1;font-size:12.5px;line-height:1.38">{i["text"]}</span>{f"<span class=ac style=\"font-size:11.5px;white-space:nowrap\">{links[i["section"]]} ›</span>" if i["section"] else ""}</div>' for i in ins)}
</div>{tabbar("group")}</div>'''
    return phone(h, BG)
