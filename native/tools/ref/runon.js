// Load a save into the ORIGINAL game, run a snippet on it, print the result as JSON.
// usage: node runon.js <ledger.html> <save.json> <snippet.js>
const { chromium } = require('/opt/node-tools/node_modules/playwright');
const fs = require('fs');
(async () => {
  const [, , html, save, snippet] = process.argv;
  const saveText = fs.readFileSync(save, 'utf8');
  const code = fs.readFileSync(snippet, 'utf8');
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox', '--disable-gpu'] });
  const pg = await br.newPage({ viewport: { width: 390, height: 844 } });
  const errs = [];
  pg.on('pageerror', e => errs.push('PAGEERR ' + e.message));
  await pg.goto('file://' + html, { waitUntil: 'domcontentloaded' });
  await pg.waitForTimeout(800);
  const r = await pg.evaluate(([t, c]) => { if (!deserialize(t)) return 'LOAD FAILED'; return (0, eval)(c); }, [saveText, code]);
  process.stdout.write(typeof r === 'string' ? r : JSON.stringify(r));
  if (errs.length) console.error('\n' + errs.slice(0, 5).join('\n'));
  await br.close();
})();
