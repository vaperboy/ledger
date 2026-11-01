(() => {
  newGame({ seed: 1, country: 'NO', name: 'G' });
  S.fxd = { UK: 1.07, US: 0.93, JP: 1.2, KR: 0.85, SE: 1.01 };
  const vals = [0, 0.4, 0.5, 7.3, 15, 99.5, 120, 480, 999, 1234, 4999, 5001, 12345, 49999, 98765, 123456, 349999, 1234567, 15000000, 987654321, 3.2e9, -7.3, -1234, -98765, -2.5e6];
  const out = { vals, fmt: {}, tax: {} };
  for (const k of CO_ORDER) {
    setCtx({ country: k });
    const c = CO[k];
    out.fmt[k] = {
      rate: fxr(c),
      money: vals.map(v => money(v)),
      plain: vals.map(v => money(v, true)),
      mshort: vals.map(v => mshort(v)),
      rl: vals.map(v => rl(v)),
      rnl100: vals.map(v => rnl(v, 100)),
      rnl1000: vals.map(v => rnl(v, 1000)),
      rnl25: vals.map(v => rnl(v, 25)),
      rlc: vals.map(v => rlc(v, k)),
      KC: vals.map(v => KC(v, k)),
      nice: vals.map(v => nicePrice(v))
    };
    const inc = [0, 50000, 200000, 450000, 800000, 1500000, 4000000, 2e7];
    out.tax[k] = { inc, self: inc.map(v => personalTax(v, 'self')), wage: inc.map(v => personalTax(v, 'wage')), div: inc.map(v => dividendTax(v, 50000)), wealth: inc.map(v => wealthTax(v * 10)), br: inc.map(v => bracketTax(v, c.income.brackets)) };
  }
  setCtx(null);
  out.annuity = [[1e6, 0.05, 60], [250000, 0.0375, 120], [9500 * 13.5, 0.0825, 60], [1e6, 0, 24], [123456, 0.12, 7]].map(a => [a, annuity(a[0], a[1], a[2])]);
  // calendar
  out.cal = [0, 1, 4, 5, 12, 13, 26, 52, 53, 100, 260].map(w => ({ w, d: dateStr(w), m: monthStr(w), mi: monthIdx(w), me: isMonthEnd(w), ye: isYearEnd(w), wd: (new Date(wDate(w).getTime()).getUTCDay() + 6) % 7 }));
  // rng
  S.rs = 123456789;
  out.rng = { seed: S.rs, z: Array.from({ length: 12 }, () => Z()), rint: Array.from({ length: 8 }, () => rint(3, 9)), gauss: Array.from({ length: 6 }, () => gauss()), pois: Array.from({ length: 8 }, (_, i) => pois(i * 4.5)), after: S.rs };
  S.rs = -77;
  out.rng2 = { seed: S.rs, z: Array.from({ length: 5 }, () => Z()), after: S.rs };
  S.rs = 5; out.shuffle = shuffle([1, 2, 3, 4, 5, 6, 7, 8]); out.shufAfter = S.rs;
  S.rs = 9; out.wpick = Array.from({ length: 10 }, () => wpick([{ w: 1, n: 'a' }, { w: 3, n: 'b' }, { w: 0, n: 'c' }, { w: 6, n: 'd' }]).n);
  return JSON.stringify(out);
})()
