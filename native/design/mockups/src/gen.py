import sys; sys.path.insert(0, __file__.rsplit('/',1)[0])
from common import *
import s1, s2, s3, s4, s5
S = [(s1,"Ivory Ledger","Editorial private banking. Flat sections split by hairlines, serif figures, champagne small caps. No cards."),
     (s2,"Command Grid","Football Manager density. Tiled panels with header bars, zebra tables, coloured attribute numbers, Continue at the top."),
     (s3,"Walnut Study","A private study at night. Warm walnut light, Cormorant figures, brass rules, ledger lines with dotted leaders."),
     (s4,"Glass Native","iOS 26. Large titles and compact inset lists. Liquid Glass only on what floats: tab bar, Next day, segmented controls, round buttons."),
     (s5,"Skyline Luxe","Closest to your concept. Evening skyline header, joined tiles with sparklines, rings for operations, bronze Next day.")]
SUB = "Live data from a 430-day demo game (UK, 6 companies) · iPhone 16 Pro, 393 × 852 pt"
D_ = __file__.rsplit('/',1)[0]
for fn, title, f in [("A_dashboard","Dashboard — 5 directions","dashboard"),("B_group","Group — 5 directions","group"),("C_company","Company management — 5 directions","company")]:
    open(f"{D_}/{fn}.html","w").write(sheet(title, SUB, [(getattr(m,f)(),t,d) for m,t,d in S]))
