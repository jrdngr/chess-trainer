/**
 * Writes spec/copy.json: the words the app shows, as written in its source.
 * Every JSX text and every string or template literal that reads as prose
 * (a capital letter or a space, and a letter), from src/screens,
 * src/components and src/model, by file, in source order. The native app
 * keeps its copy in step with this file.
 *
 *   npm run spec:copy           # write
 *   npm run spec:copy -- --check
 */
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import ts from 'typescript';

const ROOT = join(import.meta.dirname, '..');
const DIRS = ['src/screens', 'src/components', 'src/model'];
const OUT = join(ROOT, 'spec/copy.json');

function files(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return entry.name === 'seed' ? [] : files(path);
    return /\.tsx?$/.test(entry.name) && !/\.test\.tsx?$/.test(entry.name) ? [path] : [];
  });
}

/** Reads as words a person sees, rather than a key, a class name, a path or a SAN. */
function prose(text) {
  const t = text.replace(/\s+/g, ' ').trim();
  if (t.length < 2 || !/[a-z]/i.test(t)) return null;
  if (/^[a-z0-9_.:/#-]+$/.test(t)) return null; // keys, ids, css, paths
  if (/^var\(|^#[0-9a-f]{3,8}$|^\d|^[a-z-]+( [a-z-]+)*$/.test(t) && !/ /.test(t)) return null;
  if (/^[a-z][a-z0-9-]*( [a-z][a-z0-9-]*)+$/.test(t) && !/[A-Z]/.test(t) && t.split(' ').every((w) => w.includes('-') || w.length < 3 || /^(btn|row|col|ctx|sm|lg|ok|no|warn|mt|mb|gap)/.test(w))) return null; // class lists
  if (!/[A-Z]/.test(t) && !/ /.test(t)) return null;
  return t;
}

/** A template literal's text, with each hole written as {…}. */
function templateText(node, source) {
  if (ts.isNoSubstitutionTemplateLiteral(node)) return node.text;
  let out = node.head.text;
  for (const span of node.templateSpans) out += `{${span.expression.getText(source)}}` + span.literal.text;
  return out;
}

const out = {};
for (const path of DIRS.flatMap((dir) => files(join(ROOT, dir))).sort()) {
  const source = ts.createSourceFile(path, readFileSync(path, 'utf8'), ts.ScriptTarget.Latest, true, path.endsWith('x') ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
  const found = [];
  const visit = (node) => {
    // Imports, types and console output are not copy.
    if (ts.isImportDeclaration(node) || ts.isExportDeclaration(node) || ts.isTypeNode(node) || ts.isLiteralTypeNode?.(node)) return;
    if (ts.isCallExpression(node) && /^console\.|^import\.meta/.test(node.expression.getText(source))) return;
    let text = null;
    if (ts.isJsxText(node)) text = node.text;
    else if (ts.isStringLiteral(node)) {
      const parent = node.parent;
      // Object keys, property access, comparisons against a kind, and JSX attributes that are not shown are not copy.
      if (parent && ts.isPropertyAssignment(parent) && parent.name === node) return;
      if (parent && ts.isJsxAttribute(parent) && !/^(label|title|placeholder|aria-label|alt|text|hint|subtitle|aside)$/.test(parent.name.getText(source))) return;
      if (parent && ts.isBinaryExpression(parent) && /===|!==/.test(parent.operatorToken.getText(source))) return;
      if (parent && ts.isCaseClause(parent)) return;
      text = node.text;
    } else if (ts.isTemplateExpression(node) || ts.isNoSubstitutionTemplateLiteral(node)) {
      // Class names, styles and keys built from templates are not copy; nor is
      // a template whose own words are not (a unit, a separator).
      const attribute = ts.findAncestor(node, (n) => ts.isJsxAttribute(n) || ts.isStatement(n));
      const hidden = attribute && ts.isJsxAttribute(attribute) && !/^(label|title|placeholder|aria-label|alt|text|hint|subtitle|aside)$/.test(attribute.name.getText(source));
      const words = ts.isNoSubstitutionTemplateLiteral(node) ? node.text : [node.head.text, ...node.templateSpans.map((span) => span.literal.text)].join(' ');
      if (!hidden && prose(words)) text = templateText(node, source);
    }
    const shown = text === null ? null : prose(text);
    if (shown) found.push(shown);
    if (!ts.isTemplateExpression(node)) ts.forEachChild(node, visit);
    else node.templateSpans.forEach((span) => ts.forEachChild(span.expression, visit) || visit(span.expression));
  };
  visit(source);
  const unique = [...new Set(found)];
  if (unique.length) out[relative(ROOT, path).replace(/\\/g, '/')] = unique;
}

const text = JSON.stringify(out, null, 2) + '\n';
if (process.argv.includes('--check')) {
  let current = '';
  try {
    current = readFileSync(OUT, 'utf8');
  } catch {}
  if (current !== text) {
    console.error('spec/copy.json is out of date: run npm run spec:copy');
    process.exit(1);
  }
  console.log('spec/copy.json is current');
} else {
  writeFileSync(OUT, text);
  console.log(`wrote ${Object.values(out).reduce((n, list) => n + list.length, 0)} strings from ${Object.keys(out).length} files to spec/copy.json`);
}
