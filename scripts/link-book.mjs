/**
 * Add move links to an existing book without rebuilding it from games.
 *
 *   node scripts/link-book.mjs
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { linkBook } from './book-links.mjs';

const file = join(dirname(fileURLToPath(import.meta.url)), '..', 'src/model/book/book.json');
const book = linkBook(JSON.parse(readFileSync(file, 'utf8')));
writeFileSync(file, `${JSON.stringify(book)}\n`);
const links = book.positions.reduce((sum, [, , moves]) => sum + moves.filter((m) => m[4] >= 0).length, 0);
console.error(`linked ${links} moves across ${book.positions.length} positions`);
