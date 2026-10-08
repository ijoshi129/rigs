// Dev helper: node scripts/shot.mjs <url> <out.png> [width] [height] [waitMs]
import puppeteer from "puppeteer-core";
const [url, out, w = "1100", h = "1000", waitMs = "9000"] = process.argv.slice(2);
const browser = await puppeteer.launch({ executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: true, args: ["--no-first-run"] });
const page = await browser.newPage();
await page.setViewport({ width: +w, height: +h, deviceScaleFactor: 2 });
page.on("pageerror", (e) => console.log("PAGEERROR", e.message));
page.on("console", (m) => { if (m.type() === "error") console.log("CONSOLE", m.text()); });
await page.goto(url, { waitUntil: "networkidle2", timeout: 30000 });
await new Promise((r) => setTimeout(r, +waitMs));
await page.screenshot({ path: out, fullPage: true });
await browser.close();
console.log("saved", out);
