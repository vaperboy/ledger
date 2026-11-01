from common import *
# 4 · GLASS NATIVE — iOS 26. Black page, large titles, compact inset lists; Liquid Glass only on what floats:
# the capsule tab bar, its Next day accessory, segmented controls, round buttons.
BG="#000"; GR="#141416"; TX="#F5F5F7"; MU="#98989F"; FA="#636366"; SEP="rgba(84,84,88,.42)"; AC="#D9B98A"; GN="#5FCB86"; RD="#F0705E"; AM="#F2B54B"; BL="#7FA8E0"
CSS=f'''<style>
.s4{{font-family:Inter;color:{TX};font-size:15px;letter-spacing:-.15px}}
.s4 .row{{display:flex;align-items:center}}
.s4 .mu{{color:{MU}}} .s4 .fa{{color:{FA}}} .s4 .gn{{color:{GN}}} .s4 .rd{{color:{RD}}} .s4 .am{{color:{AM}}}
.s4 .lt{{font:700 32px "Inter Display",Inter;letter-spacing:-.6px}}
.s4 .big{{font:600 34px "Inter Display",Inter;letter-spacing:-.8px;font-feature-settings:"tnum" 1}}
.s4 .sh{{font:700 19px "Inter Display",Inter;letter-spacing:-.3px;display:flex;align-items:center;gap:4px;margin:18px 0 8px}}
.s4 .grp{{background:{GR};border-radius:13px;overflow:hidden}}
.s4 .li{{display:flex;align-items:center;gap:12px;padding:0 14px;min-height:46px}}
.s4 .li+.li .bd, .s4 .li+.li.sepfull{{border-top:.5px solid {SEP}}}
.s4 .bd{{flex:1;display:flex;align-items:center;align-self:stretch;gap:8px;min-width:0}}
.s4 .sq{{width:30px;height:30px;border-radius:8px;display:flex;align-items:center;justify-content:center;flex:none}}
.s4 .glass{{background:rgba(44,44,50,.52);backdrop-filter:blur(20px) saturate(180%);-webkit-backdrop-filter:blur(20px) saturate(180%);
  border:.5px solid rgba(255,255,255,.16);box-shadow:inset 0 1px 0 rgba(255,255,255,.30),inset 0 -.5px 0 rgba(255,255,255,.10),0 10px 28px rgba(0,0,0,.55)}}
.s4 .seg{{display:flex;padding:3px;border-radius:20px;gap:2px}}
.s4 .seg span{{flex:1;text-align:center;font:600 13px Inter;color:{MU};padding:6px 0;border-radius:16px}}
.s4 .seg .on{{background:rgba(255,255,255,.16);color:{TX};box-shadow:inset 0 .5px 0 rgba(255,255,255,.35)}}
.s4 .cb{{width:38px;height:38px;border-radius:19px;display:flex;align-items:center;justify-content:center}}
.s4 .badge{{font:600 13px Inter;padding:3px 7px;border-radius:7px;min-width:66px;text-align:right;font-feature-settings:"tnum" 1}}
.s4 .tab{{position:absolute;left:14px;right:14px;bottom:24px;height:62px;border-radius:31px;display:flex;align-items:center;justify-content:space-around;padding:0 4px}}
.s4 .tab div{{display:flex;flex-direction:column;align-items:center;gap:2px;font:600 10px Inter;color:{TX};width:66px;padding:6px 0;border-radius:24px}}
.s4 .tab .on{{color:{AC};background:rgba(255,255,255,.12)}}
.s4 .acc{{position:absolute;left:14px;right:14px;bottom:94px;height:50px;border-radius:25px;display:flex;align-items:center;padding:0 6px 0 18px;gap:12px}}
.s4 .hi{{position:absolute;bottom:8px;left:50%;transform:translateX(-50%);width:134px;height:5px;border-radius:3px;background:#fff}}
</style>'''
def tabbar(on):
    items=[("home","Home"),("group","Group"),("money","Money"),("inbox","Inbox"),("phone","Phone")]
    tabs = '<div class="tab glass">'+"".join(f'<div class="{"on" if k==on else ""}">{icon(k,22,sw=1.7)}<span>{t}</span></div>' for k,t in items)+'</div>'
    acc = f'''<div class="acc glass"><div style="flex:1"><div style="font:600 13.5px Inter">Thursday 9 Dec</div><div class="row" style="gap:3px;margin-top:4px">{"".join(f'<span style="width:14px;height:3px;border-radius:2px;background:{AC if d<4 else "rgba(255,255,255,.18)"}"></span>' for d in range(7))}<span class="mu" style="font-size:11px;margin-left:6px">Day 4 of 7</span></div></div>
<div class="row" style="gap:6px;background:{AC};color:#18120A;font:600 14.5px Inter;padding:9px 16px;border-radius:20px;box-shadow:inset 0 1px 0 rgba(255,255,255,.5)">Next day {icon("chev",14,"#18120A",2.4)}</div></div>'''
    fade = '<div style="position:absolute;left:0;right:0;bottom:0;height:200px;background:linear-gradient(rgba(0,0,0,0),rgba(0,0,0,.82) 60%)"></div>'
    return fade + acc + tabs + '<div class="hi"></div>'
def sq(name, col, size=17): return f'<div class="sq" style="background:{col}2E">{icon(name,size,col,1.9)}</div>'
def hcol(h): return {"Thriving":GN,"Healthy":GN,"Tight":AM}.get(h,RD)
def badge(v): return f'<span class="badge" style="background:{(GN if v>=0 else RD)}26;color:{GN if v>=0 else RD}">{short(v,True)}</span>'
TCOL = {"ledger":BL,"cup":"#C9A27C","dumbbell":"#E58A6B","car":"#8FB7A6","cake":AC,"laptop":"#A99BE0"}

def dashboard():
    att = attention(3)
    w = nwd[-31:]
    h = f'''{CSS}<div class="s4">{status_bar(TX)}
<div style="padding:4px 18px 0">
 <div class="row" style="justify-content:space-between"><div><div class="mu" style="font:600 13px Inter;letter-spacing:.02em">THURSDAY 9 DECEMBER · WEEK {D["week"]}</div><div class="lt" style="margin-top:2px">Summary</div></div>
  <div class="cb glass" style="font:600 14px Inter;color:{AC}">AC</div></div>
 <div style="margin-top:12px"><div class="mu" style="font:500 14px Inter">Net Worth</div><div class="big" style="margin-top:1px">{money(NW)}</div>
  <div style="font:600 14px Inter;margin-top:2px"><span class="gn">▲ {money(CH30)} ({CH30P*100:.2f}%)</span><span class="mu" style="font-weight:500"> Past month</span></div></div>
 <div class="seg glass" style="margin-top:12px">{"".join(f'<span class="{"on" if t=="1M" else ""}">{t}</span>' for t in ["1W","1M","3M","1Y","All"])}</div>
 <div style="margin-top:12px">{linechart([w],357,96,[GN],"rgba(255,255,255,.07)",FA,None,True,fills=[GN],width=2,zero=False)}</div>
 <div class="grp" style="margin-top:12px">
 {"".join(f'<div class="li">{sq(ic,col)}<div class="bd"><span style="flex:1">{l}</span><span class="mu num" style="font-size:13px">{sh}</span><span class="num" style="width:96px;text-align:right;{"color:"+RD if v<0 else ""}">{money(v)}</span>{icon("chev",13,FA,2.2)}</div></div>' for ic,col,l,v,sh in [("money",GN,"Cash",D["personal"],""),("up",BL,"Investments",D["investments"],f'{D["investments"]/D["assets"]*100:.0f}%'),("group",AC,"Companies",D["companies"],f'{D["companies"]/D["assets"]*100:.0f}%'),("down",RD,"Debt",-D["debt"],"")])}
 </div>
 <div class="sh">Needs Attention {icon("chev",15,FA,2.4)}</div>
 <div class="grp">{"".join(f'<div class="li" style="padding-top:10px;padding-bottom:10px;align-items:flex-start">{sq("alert",AM if i["tone"]=="warn" else RD,16)}<div class="bd" style="flex-direction:column;align-items:stretch;gap:2px"><span style="font:600 14.5px Inter">{c["name"]}</span><span class="mu" style="font-size:13px;line-height:1.35">{i["text"]}</span></div></div>' for c,i in att[:2])}</div>
</div>{tabbar("home")}</div>'''
    return phone(h, BG)

def group():
    w = COD[-91:]
    h = f'''{CSS}<div class="s4">{status_bar(TX)}
<div style="padding:4px 18px 0">
 <div class="row" style="justify-content:space-between"><div class="lt">Group</div><div class="row" style="gap:10px"><div class="cb glass">{icon("sort",18,TX,1.9)}</div><div class="cb glass">{icon("plus",19,TX,2)}</div></div></div>
 <div class="mu" style="font-size:13.5px;margin-top:1px">{len(CO)} companies · {len(CITIES)} cities · {GROUP_STAFF} staff</div>
 <div class="row" style="margin-top:12px;justify-content:space-between;align-items:flex-end">
  <div><div class="mu" style="font:500 14px Inter">Total Value</div><div class="big" style="margin-top:1px">{money(GROUP_VALUE)}</div><div style="font:600 14px Inter;margin-top:2px"><span class="gn">▲ {short(GCH30)}</span><span class="mu" style="font-weight:500"> Past month</span></div></div>
  <div style="margin-bottom:6px">{spark(w,110,46,GN,1.8,GN)}</div></div>
 <div class="grp row" style="margin-top:14px;padding:10px 0">
 {"".join(f'<div style="flex:1;padding:0 12px;{"border-left:.5px solid "+SEP if i else ""}"><div class="mu" style="font-size:11.5px">{l}</div><div class="num" style="font:600 16px Inter;margin-top:2px;color:{col}">{v}</div></div>' for i,(l,v,col) in enumerate([("Profit 12M",short(GROUP_PROFIT),GN),("Revenue 12M",short(GROUP_REV),TX),("Cash",short(GROUP_CASH),TX),("Debt",short(GROUP_DEBT),RD)]))}
 </div>
 <div class="seg glass" style="margin-top:14px">{"".join(f'<span class="{"on" if t=="Profit" else ""}">{t}</span>' for t in ["Profit","Value","Growth","Health"])}</div>
 <div class="grp" style="margin-top:12px">
 {"".join(f'<div class="li" style="min-height:58px">{sq(ticon(c),TCOL[ticon(c)],18)}<div class="bd"><div style="flex:1;min-width:0"><div style="font:600 15px Inter;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{c["name"]}</div><div style="font-size:12.5px;margin-top:1px"><span class="mu">{trade(c)} · </span><span style="color:{hcol(c["health"])}">{c["health"]}</span></div></div>{spark(c["revenueSeries"][-12:],40,22,GN if (c["growth"] or 0)>=0 else RD,1.5)}<div style="text-align:right;margin-left:6px"><div class="num" style="font:500 14.5px Inter">{short(c["value"])}</div><div style="margin-top:3px">{badge(c["profitTTM"])}</div></div></div></div>' for c in BY_PROFIT)}
 </div>
</div>{tabbar("group")}</div>'''
    return phone(h, BG)

def company():
    c = BAKERY
    links = {"operations":"Operations","staff":"Staff","marketing":"Marketing","finances":"Finances"}
    ins = [i for i in c["insights"] if "Competitors" not in i["text"]][:3]
    acts = [("users","Hire"),("tag","Prices"),("mega","Campaign"),("tool","Equipment"),("transfer","Transfer")]
    figs = [("Profit 12M",short(c["profitTTM"]),GN),("Revenue 12M",short(c["revenueTTM"]),TX),("Margin",f'{c["margin"]*100:.1f}%',TX),
            ("Cash",short(c["cash"]),TX),("Value",short(c["value"]),TX),("Costs / week",money(c["weeklyCost"]),TX)]
    h = f'''{CSS}<div class="s4">{status_bar(TX)}
<div style="padding:2px 18px 0">
 <div class="row" style="justify-content:space-between"><div class="cb glass">{icon("back",19,TX,2.2)}</div><div class="cb glass">{icon("more",19,TX,2)}</div></div>
 <div style="font:700 27px 'Inter Display',Inter;letter-spacing:-.5px;margin-top:10px;white-space:nowrap">{c["name"]}</div>
 <div class="row" style="gap:8px;margin-top:3px"><span class="mu" style="font-size:13.5px">Bakery · Manchester · Ltd</span><span style="font:600 11.5px Inter;color:{GN};background:{GN}22;padding:2px 8px;border-radius:9px">Thriving</span></div>
 <div class="seg glass" style="margin-top:12px">{"".join(f'<span style="font-size:12px" class="{"on" if t=="Overview" else ""}">{t}</span>' for t in ["Overview","Staff","Finances","Operations","Marketing"])}</div>
 <div class="row" style="justify-content:space-between;margin-top:14px">{"".join(f'<div style="display:flex;flex-direction:column;align-items:center;gap:5px;width:62px"><div class="cb glass" style="width:50px;height:50px;border-radius:25px">{icon(i,21,AC,1.8)}</div><span style="font:500 11.5px Inter;color:{MU}">{t}</span></div>' for i,t in acts)}</div>
 <div class="grp" style="margin-top:14px;display:grid;grid-template-columns:1fr 1fr 1fr">
 {"".join(f'<div style="padding:9px 12px;{"border-left:.5px solid "+SEP if k%3 else ""};{"border-top:.5px solid "+SEP if k>2 else ""}"><div class="mu" style="font-size:11.5px">{l}</div><div class="num" style="font:600 16px Inter;margin-top:2px;color:{col}">{v}</div></div>' for k,(l,v,col) in enumerate(figs))}
 </div>
 <div class="sh" style="justify-content:space-between">Revenue & Profit<span class="mu" style="font:500 12px Inter"><span style="color:{AC}">●</span> Revenue &nbsp;<span style="color:{GN}">●</span> Profit</span></div>
 <div>{linechart([c["revenueSeries"][-12:],c["profitSeries"][-12:]],357,82,[AC,GN],"rgba(255,255,255,.07)",FA,LAST12_INITIAL,width=2)}</div>
 <div class="sh">From Your Manager</div>
 <div class="grp">{"".join(f'<div class="li" style="padding-top:9px;padding-bottom:9px;align-items:flex-start">{sq("check" if i["tone"]=="good" else "alert",GN if i["tone"]=="good" else AM,16)}<div class="bd" style="align-items:flex-start"><span style="flex:1;font-size:13.5px;line-height:1.35">{i["text"]}</span>{f"<span style=\"font:500 13px Inter;color:{AC};white-space:nowrap\">{links[i["section"]]}</span>" if i["section"] else ""}</div></div>' for i in ins)}</div>
</div>{tabbar("group")}</div>'''
    return phone(h, BG)
