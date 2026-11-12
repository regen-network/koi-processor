/**
 * Search filters and entity-match strength for /api/koi/query.
 *
 * Every candidate path (semantic, keyword, entity) applies the same filter
 * clause, so a source or date filter can't be bypassed by one of them.
 * Pure functions, so they can be tested without a database.
 */

export interface SearchFilters {
  date_range?: { start?: string; end?: string };
  include_undated?: boolean;
  source?: string;
}

/** Copy `filters`, taking `source` from the request body when it isn't in
 * `filters`. regen-koi-mcp sends `source` as a top-level body field. */
export function normalizeSearchFilters(filters: any, bodySource?: unknown): SearchFilters {
  const out: SearchFilters = { ...(filters && typeof filters === 'object' ? filters : {}) };
  const raw = out.source ?? bodySource;
  const source = typeof raw === 'string' ? raw.trim() : '';
  if (source) out.source = source;
  else delete out.source;
  return out;
}

/** SQL for the source and date filters, starting with " AND ", or "" when no
 * filter is set. Pushes its values onto `params` and refers to them by
 * position. `source` is a case-insensitive prefix match on metadata.source,
 * as regen-koi-mcp documents it: "discourse" matches
 * "discourse:forum.regen.network". */
export function buildSearchFilterClause(filters: SearchFilters | undefined, params: any[], alias: string = 'm'): string {
  const clauses: string[] = [];
  const dateClauses: string[] = [];
  if (filters?.date_range?.start) {
    params.push(filters.date_range.start);
    dateClauses.push(`${alias}.published_at >= $${params.length}::timestamptz`);
  }
  if (filters?.date_range?.end) {
    params.push(filters.date_range.end);
    dateClauses.push(`${alias}.published_at <= $${params.length}::timestamptz`);
  }
  if (dateClauses.length) {
    const undated = filters?.include_undated ? ` OR ${alias}.published_at IS NULL` : '';
    clauses.push(`((${dateClauses.join(' AND ')})${undated})`);
  }
  if (filters?.source) {
    params.push(filters.source.replace(/[\\%_]/g, (c) => `\\${c}`) + '%');
    clauses.push(`${alias}.metadata->>'source' ILIKE $${params.length}`);
  }
  return clauses.length ? ` AND ${clauses.join(' AND ')}` : '';
}

export function hasSearchFilter(filters: SearchFilters | undefined): boolean {
  return Boolean(filters?.source || filters?.date_range?.start || filters?.date_range?.end);
}

// English function words. They never seed an entity match on their own:
// extraction has produced entities literally named "You" or "This".
export const STOPWORDS = new Set([
  'a', 'about', 'after', 'all', 'also', 'am', 'an', 'and', 'any', 'are', 'as', 'at', 'be', 'been',
  'before', 'being', 'both', 'but', 'by', 'can', 'could', 'did', 'do', 'does', 'doing', 'done',
  'each', 'even', 'every', 'few', 'for', 'from', 'get', 'gets', 'got', 'had', 'has', 'have',
  'having', 'he', 'her', 'here', 'hers', 'him', 'his', 'how', 'i', 'if', 'in', 'into', 'is', 'it',
  'its', 'just', 'like', 'make', 'makes', 'many', 'may', 'me', 'might', 'more', 'most', 'much',
  'must', 'my', 'new', 'no', 'not', 'now', 'of', 'off', 'on', 'once', 'one', 'only', 'or',
  'other', 'our', 'ours', 'out', 'over', 'own', 'same', 'say', 'says', 'she', 'should', 'so',
  'some', 'such', 'than', 'that', 'the', 'their', 'theirs', 'them', 'then', 'there', 'these',
  'they', 'this', 'those', 'through', 'to', 'too', 'under', 'until', 'up', 'us', 'use', 'used',
  'very', 'was', 'way', 'we', 'well', 'were', 'what', 'when', 'where', 'which', 'while', 'who',
  'whom', 'why', 'will', 'with', 'would', 'yes', 'yet', 'you', 'your', 'yours', 'yourself',
]);

/**
 * Query terms whose entity matches count as strong. An entity-only candidate
 * (one the vector and keyword legs did not return) gets the fusion entity
 * bonus only when it matched one of these:
 *   - a multiword phrase from the query ("regen ledger")
 *   - a term with a canonical alias, or its canonical name ("bct" and
 *     "base carbon tonne")
 *   - a word written as a name in the query: all caps ("KOI"), mixed case
 *     ("OpenAI"), or capitalized anywhere but the start of a sentence
 * A single common word ("software", "build") is not strong on its own, which
 * keeps it from outranking real matches.
 */
export function strongEntityTerms(query: string, patterns: string[], aliasTerms: string[]): Set<string> {
  const strong = new Set<string>();
  for (const p of patterns) if (p.includes(' ')) strong.add(p.toLowerCase());
  for (const a of aliasTerms) strong.add(a.toLowerCase());
  const tokens = query.match(/[A-Za-z0-9][\w'-]*|[.!?]/g) || [];
  let sentenceStart = true;
  for (const t of tokens) {
    if (/^[.!?]$/.test(t)) { sentenceStart = true; continue; }
    const word = t.replace(/[^\w-]/g, '');
    const lower = word.toLowerCase();
    if (word.length >= 2 && !STOPWORDS.has(lower)) {
      const acronym = word.length >= 2 && /^[A-Z0-9-]+$/.test(word) && /[A-Z]/.test(word);
      const mixed = /[a-z]/.test(word) && /[A-Z]/.test(word.slice(1));
      const capitalized = /^[A-Z][a-z]/.test(word) && !sentenceStart;
      if (acronym || mixed || capitalized) strong.add(lower);
    }
    sentenceStart = false;
  }
  return strong;
}

export function isStrongEntityMatch(entitiesMatched: string[] | null | undefined, strongTerms: Set<string>): boolean {
  return (entitiesMatched || []).some((e) => strongTerms.has(String(e).toLowerCase()));
}
