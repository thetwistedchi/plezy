// Builds assets/browser/ubo-resources.json (scriptlets and redirect resources
// for the browser's ad blocker) from a uBlock Origin checkout:
//   git clone --depth 1 https://github.com/gorhill/uBlock.git
//   node tool/generate_ubo_resources.mjs path/to/uBlock assets/browser/ubo-resources.json
// Then bump AdblockManager._resourcesVersion.
import fs from 'node:fs';
import path from 'node:path';
const root = process.argv[2];
const { builtinScriptlets } = await import(path.join(root, 'src/js/resources/scriptlets.js'));
const redirects = (await import(path.join(root, 'src/js/redirect-resources.js'))).default;
const out = [];
const b64 = s => Buffer.from(s).toString('base64');
let trusted = 0;
for (const s of builtinScriptlets) {
  const isFn = s.name.endsWith('.fn');
  const r = {
    name: s.name,
    aliases: s.aliases || [],
    kind: { mime: isFn ? 'fn/javascript' : 'application/javascript' },
    content: b64(s.fn.toString()),
  };
  if (s.dependencies && s.dependencies.length) r.dependencies = s.dependencies;
  if (s.requiresTrust) { r.permission = 1; trusted++; }
  out.push(r);
}
const mimeOf = f => ({gif:'image/gif',png:'image/png',js:'application/javascript',html:'text/html',txt:'text/plain',mp3:'audio/mp3',mp4:'video/mp4',xml:'text/xml',css:'text/css',json:'application/json'})[f.split('.').pop()] || 'application/octet-stream';
for (const [name, details] of redirects) {
  const file = path.join(root, 'src/web_accessible_resources', name);
  if (!fs.existsSync(file)) continue;
  const aliases = details.alias ? (Array.isArray(details.alias) ? details.alias : [details.alias]) : [];
  out.push({ name, aliases, kind: { mime: mimeOf(name) }, content: fs.readFileSync(file).toString('base64') });
}
fs.writeFileSync(process.argv[3], JSON.stringify(out));
console.log('scriptlets', builtinScriptlets.length, 'trusted', trusted, 'total', out.length);
