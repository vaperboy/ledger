const { chromium } = require('/opt/node-tools/node_modules/playwright');
(async () => {
  const b = await chromium.launch();
  for (const f of process.argv.slice(2)) {
    const p = await b.newPage({ viewport: { width: 2400, height: 1200 }, deviceScaleFactor: 2 });
    await p.goto('file://' + f); await p.waitForTimeout(400);
    const el = await p.$('.sheet');
    await el.screenshot({ path: f.replace('.html', '.png') });
    await p.close();
  }
  await b.close();
})();
