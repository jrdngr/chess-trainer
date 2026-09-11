/**
 * Turn the Vite build into a page the Artifact tool can publish.
 *
 * The artifact host wraps the file in its own <!doctype>/<head>/<body>, so the
 * page we hand it must be bare content. CSS is inlined (small, and it avoids
 * any question about same-origin stylesheet loading in the sandbox); the app
 * bundle and the Stockfish worker stay as supporting files, since a worker
 * needs a real URL either way.
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

const page = `<title>Repertoire Trainer</title>
<style>
${css}
</style>
<div id="root"></div>
<script type="module" src="${clean(jsSrc)}"></script>
`;

mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'index.html'), page);

const files = {
  [clean(jsSrc)]: clean(jsSrc),
  'engine/stockfish.js': 'engine/stockfish.js',
};

writeFileSync(join(outDir, 'files.json'), `${JSON.stringify({ root: 'dist', files }, null, 2)}\n`);

const kb = (n) => `${(n / 1024).toFixed(0)} kB`;
console.log(`page   dist-artifact/index.html  ${kb(page.length)}`);
for (const [published, source] of Object.entries(files)) {
  console.log(`file   ${published.padEnd(24)} ${kb(readFileSync(join(dist, source)).length)}`);
}
