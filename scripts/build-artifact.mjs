/**
 * Turn the Vite build into a page the Artifact tool can publish.
 *
 * The artifact host wraps the file in its own <!doctype>/<head>/<body>, so the
 * page we hand it must be bare content.
 *
 * CSS and the app bundle are both inlined. Inlining the bundle is deliberate:
 * it means the app boots even if relative supporting-file URLs resolve oddly
 * against whatever path the sandbox serves the page from. The Stockfish worker
 * has to stay a real file — a worker needs a URL — and that is the one piece
 * that degrades gracefully on its own if it cannot load.
 */
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');
const outDir = join(root, 'dist-artifact');

if (!existsSync(join(dist, 'index.html'))) {
  console.error('No dist/index.html — run `npm run build` first.');
  process.exit(1);
}

const html = readFileSync(join(dist, 'index.html'), 'utf8');

const cssHref = /<link[^>]+href="([^"]+\.css)"/.exec(html)?.[1];
const jsSrc = /<script[^>]+src="([^"]+\.js)"/.exec(html)?.[1];
if (!cssHref || !jsSrc) {
  console.error('Could not find the built CSS/JS references in dist/index.html');
  process.exit(1);
}

const clean = (p) => p.replace(/^\.?\//, '');
const css = readFileSync(join(dist, clean(cssHref)), 'utf8');
const js = readFileSync(join(dist, clean(jsSrc)), 'utf8');

// A literal </script> anywhere in the bundle would close the tag early.
if (/<\/script/i.test(js) || /<\/style/i.test(css)) {
  console.error('Built assets contain a closing tag sequence; cannot inline them safely.');
  process.exit(1);
}

const page = `<title>Repertoire Trainer</title>
<style>
${css}
</style>
<div id="root"></div>
<script type="module">
${js}
</script>
`;

mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'index.html'), page);

const files = {
  'engine/stockfish.js': 'engine/stockfish.js',
};

writeFileSync(join(outDir, 'files.json'), `${JSON.stringify({ root: 'dist', files }, null, 2)}\n`);

const kb = (n) => `${(n / 1024).toFixed(0)} kB`;
console.log(`page   dist-artifact/index.html  ${kb(page.length)}`);
for (const [published, source] of Object.entries(files)) {
  console.log(`file   ${published.padEnd(24)} ${kb(readFileSync(join(dist, source)).length)}`);
}
