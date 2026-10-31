import { buildBookIndex } from './book';
import type { ReferenceIndex } from './reference';

let cached: ReferenceIndex | null = null;

/** Built on first use, then reused — the book is a few megabytes of JSON. */
export function referenceIndex(): ReferenceIndex {
  if (!cached) cached = buildBookIndex();
  return cached;
}
