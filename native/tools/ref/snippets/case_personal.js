(() => {
  const out = {};
  const co = S.cos[0];
  // exercise: a consumer loan, a company loan, a mortgage, sole-trader profit, salary, dividends, savings
  S.week = 16;             // a month end
  S.sav.bal = 50000;
  S.cash = 400000;
  S.tax.wage = 300000; S.tax.withheld = 40000; S.tax.ytdDiv = 150000; S.tax.gain = 20000; S.tax.shield = 30000;
  out.l1 = takeLoan('cons', 150000, 60);
  out.l2 = takeLoan('mort', 300000, 240);
  co.form = 'ENK'; co.bk.y = { rev: 2500000, cogs: 900000, wages: 600000, rent: 100000 };
  S.tax.hqDed = 20000;
  out.l3 = takeLoan('biz', 20000, 36, co, true);
  out.pre = serialize();
  const gs = () => ({ cash: S.cash, sav: S.sav.bal, credit: S.credit, loans: S.loans.map(l => [l.id, l.bal, l.pay, l.margin]), interest: S.stats.interest, log: S.log.slice(0, 6), tax: JSON.parse(JSON.stringify(S.tax)), coCash: co.cash, coInt: co.bk.y.int || 0 });
  personalMonth(); out.afterMonth = gs();
  S.week = 17; advTaxMonth(); out.afterAdv = gs();   // quarter? depends on month; recorded either way
  // move to a quarter month end for advance tax
  S.week = 21; S.tax.adv = 0; S.tax.withheld = 40000; advTaxMonth(); out.afterAdv2 = gs();
  out.est = personalTaxEstimate();
  out.nwBeforeYear = netWorth().total;
  yearEndPersonal(); out.afterYear = gs(); out.enkLoss = S.enkLoss; out.yearsStat = S.stats.years; out.taxPaid = S.stats.taxPaid;
  return JSON.stringify(out);
})()
