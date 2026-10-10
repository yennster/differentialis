// Regenerates the website's social card (site/assets/og.jpg) from card.html.
//
//   node tools/og-card/render.mjs
//
// Renders card.html at 1200×630 with 2× device pixels in headless Google Chrome (over the DevTools
// protocol, so fonts finish loading first), then downsamples to a 1200×630 JPEG with `sips`.
// diff-light.webp is a crop of a real Differentialis window; recapture it when the UI changes.
import { spawn, execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

setTimeout(() => { console.error("Timed out rendering the card."); process.exit(2); }, 90000);

const here = dirname(fileURLToPath(import.meta.url));
const work = mkdtempSync(join(tmpdir(), "og-card-"));
const output = resolve(here, "../../site/assets/og.jpg");
const port = 9335;

const chrome = spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", [
  "--headless=new", "--disable-gpu", "--hide-scrollbars", `--remote-debugging-port=${port}`,
  `--user-data-dir=${join(work, "profile")}`, "--allow-file-access-from-files", "about:blank",
], { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let target;
for (let i = 0; i < 50 && !target; i++) {
  await sleep(200);
  try { target = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find((t) => t.type === "page"); } catch {}
}
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener("open", r));
let id = 0;
const pending = new Map();
ws.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) { pending.get(message.id)(message.result); pending.delete(message.id); }
});
const send = (method, params = {}) => new Promise((r) => {
  const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params }));
});

await send("Emulation.setDeviceMetricsOverride", { width: 1200, height: 630, deviceScaleFactor: 2, mobile: false });
await send("Page.enable");
await send("Page.navigate", { url: pathToFileURL(join(here, "card.html")).href });
await sleep(1500);
await send("Runtime.evaluate", { expression: "document.fonts.ready.then(() => true)", awaitPromise: true });
await sleep(500);
const shot = await send("Page.captureScreenshot", { format: "png" });
const png = join(work, "card@2x.png");
writeFileSync(png, Buffer.from(shot.data, "base64"));
ws.close();
chrome.kill();

execFileSync("sips", ["-s", "format", "jpeg", "-s", "formatOptions", "90", "-Z", "1200", png, "--out", output], { stdio: "ignore" });
console.log(`Wrote ${output}`);
process.exit(0);
