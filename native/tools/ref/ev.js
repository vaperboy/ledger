// Run a JS snippet inside the ORIGINAL Ledger game (headless Chromium) and print the result as JSON.
// usage: node ev.js <path/to/ledger.html> <snippet.js | -e "expression">
const { chromium } = require('/opt/node-tools/node_modules/playwright');
const fs = require('fs');
(async () => {
  const [, , html, a, b] = process.argv;
  const code = a === '-e' ? b : fs.readFileSync(a, 'utf8');
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox', '--disable-gpu'] });
  const pg = await br.newPage({ viewport: { width: 390, height: 844 } });
  const errs = [];
  pg.on('pageerror', e => errs.push('PAGEERR ' + e.message));
  await pg.goto('file://' + html, { waitUntil: 'domcontentloaded' });
  await pg.waitForTimeout(800);
  const r = await pg.evaluate(code);
  process.stdout.write(typeof r === 'string' ? r : JSON.stringify(r, null, 1));
  if (errs.length) console.error('\n' + errs.slice(0, 5).join('\n'));
  await br.close();
})();
