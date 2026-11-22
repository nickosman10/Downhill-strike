const { chromium } = require('playwright');
(async () => {
  const [lat, lon, heading, out] = process.argv.slice(2);
  const browser = await chromium.launch({ headless: false, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, locale: 'en-US' });
  const url = `https://www.google.com/maps/@${lat},${lon},3a,90y,${heading}h,88t/data=!3m1!1e1`;
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForTimeout(20000);
  await page.screenshot({ path: out });
  const gl = await page.evaluate(() => { const c = document.createElement('canvas'); return !!(c.getContext('webgl') || c.getContext('webgl2')); });
  console.log('webgl', gl, 'url', page.url().slice(0, 120));
  await browser.close();
})();
