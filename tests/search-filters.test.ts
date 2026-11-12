// bun test tests/search-filters.test.ts
import { describe, expect, test } from "bun:test";
import {
  buildSearchFilterClause,
  hasSearchFilter,
  isStrongEntityMatch,
  normalizeSearchFilters,
  strongEntityTerms,
} from "../search-filters.ts";
import { weightedAverageFusion } from "../bge-mcp-ts/adaptive-features.ts";

describe("normalizeSearchFilters", () => {
  test("takes source from the body when filters has none", () => {
    expect(normalizeSearchFilters({}, "newsletters:nate-jones-substack").source).toBe("newsletters:nate-jones-substack");
  });
  test("filters.source wins over the body", () => {
    expect(normalizeSearchFilters({ source: "github" }, "notion").source).toBe("github");
  });
  test("blank or non-string source is dropped", () => {
    expect(normalizeSearchFilters({}, "  ").source).toBeUndefined();
    expect(normalizeSearchFilters({ source: 3 }, undefined).source).toBeUndefined();
    expect(normalizeSearchFilters(null, undefined)).toEqual({});
  });
  test("keeps date filters", () => {
    const f = normalizeSearchFilters({ date_range: { start: "2026-09-30" }, include_undated: true }, undefined);
    expect(f).toEqual({ date_range: { start: "2026-09-30" }, include_undated: true });
  });
});

describe("buildSearchFilterClause", () => {
  test("no filters gives no SQL and no params", () => {
    const params: any[] = ["x"];
    expect(buildSearchFilterClause({}, params)).toBe("");
    expect(params).toEqual(["x"]);
    expect(hasSearchFilter({})).toBe(false);
  });
  test("numbers params after the existing ones", () => {
    const params: any[] = ["patterns", 100];
    const sql = buildSearchFilterClause(
      { date_range: { start: "2026-09-30", end: "2026-10-02" }, source: "newsletters:nate-jones-substack" },
      params,
      "m",
    );
    expect(sql).toBe(
      " AND ((m.published_at >= $3::timestamptz AND m.published_at <= $4::timestamptz)) AND m.metadata->>'source' ILIKE $5",
    );
    expect(params).toEqual(["patterns", 100, "2026-09-30", "2026-10-02", "newsletters:nate-jones-substack%"]);
  });
  test("include_undated keeps undated rows inside the date clause only", () => {
    const params: any[] = [];
    const sql = buildSearchFilterClause({ date_range: { end: "2026-10-02" }, include_undated: true, source: "github" }, params);
    expect(sql).toBe(" AND ((m.published_at <= $1::timestamptz) OR m.published_at IS NULL) AND m.metadata->>'source' ILIKE $2");
  });
  test("source is a prefix match with LIKE wildcards escaped", () => {
    const params: any[] = [];
    buildSearchFilterClause({ source: "web:a_b%c\\" }, params);
    expect(params).toEqual(["web:a\\_b\\%c\\\\%"]);
  });
});

describe("strongEntityTerms", () => {
  const strong = (q: string, patterns: string[] = [], alias: string[] = []) => [...strongEntityTerms(q, patterns, alias)].sort();

  test("the incident query has no strong single words", () => {
    expect(strong("Personal software is here, and you can build yours this week")).toEqual([]);
  });
  test("multiword patterns and alias terms are strong", () => {
    expect(strong("how does regen ledger work", ["regen", "ledger", "regen ledger"])).toEqual(["regen ledger"]);
    expect(strong("what is bct", ["bct"], ["bct", "base carbon tonne"])).toEqual(["base carbon tonne", "bct"]);
  });
  test("acronyms, mixed case and mid-sentence capitals are strong", () => {
    expect(strong("what does KOI do")).toEqual(["koi"]);
    expect(strong("is OpenAI cheaper")).toEqual(["openai"]);
    expect(strong("notes from the Gregory call")).toEqual(["gregory"]);
  });
  test("a capital at the start of a sentence is not", () => {
    expect(strong("Software. Build it")).toEqual([]);
  });
  test("stopwords never count, even in capitals", () => {
    expect(strong("tell me what You think")).toEqual([]);
  });
});

describe("isStrongEntityMatch", () => {
  test("matches case-insensitively", () => {
    const terms = new Set(["koi"]);
    expect(isStrongEntityMatch(["KOI"], terms)).toBe(true);
    expect(isStrongEntityMatch(["Software", "Build"], terms)).toBe(false);
    expect(isStrongEntityMatch(null, terms)).toBe(false);
  });
});

describe("weightedAverageFusion entity bonus", () => {
  const vec = (rid: string, s: number) => ({ id: rid, rid, content: "", similarity: s, source: "vector" as const });
  const ent = (rid: string, s: number, strong: boolean) => ({
    id: rid, rid, content: "", similarity: s, source: "hybrid" as const,
    metadata: { entities_matched: ["x"], strong_entity_match: strong },
  });

  test("the incident: a weak entity-only match no longer outranks the post", () => {
    const fused = weightedAverageFusion(
      [vec("regen.newsletter:post#chunk0", 0.545)],
      [ent("regen.github:repo#chunk3", 1, false), ent("regen.github:other#chunk1", 1, false)],
      [],
    );
    expect(fused[0].id).toBe("regen.newsletter:post");
    expect(fused[0].score).toBeCloseTo(0.327, 3);
    expect(fused[1].score).toBeCloseTo(0.2, 3);
    expect(fused[1].metadata.entity_boost).toBe(0);
  });
  test("a strong entity-only match keeps the bonus", () => {
    const fused = weightedAverageFusion([], [ent("orn:doc:a#chunk0", 1, true)], []);
    expect(fused[0].score).toBeCloseTo(0.35, 3);
    expect(fused[0].metadata.entity_boost).toBe(0.15);
  });
  test("an entity match on a vector or keyword hit keeps the bonus, weak or not", () => {
    const fused = weightedAverageFusion(
      [vec("orn:doc:a#chunk0", 0.5)],
      [ent("orn:doc:a#chunk2", 0.5, false), ent("orn:doc:b#chunk0", 0.5, false)],
      [{ id: "orn:doc:b", rid: "orn:doc:b", content: "", similarity: 0.4, source: "keyword" as const }],
    );
    const a = fused.find((r) => r.id === "orn:doc:a")!;
    const b = fused.find((r) => r.id === "orn:doc:b")!;
    expect(a.score).toBeCloseTo(0.6 * 0.5 + 0.2 * 0.5 + 0.15, 3);
    expect(b.score).toBeCloseTo(0.2 * 0.5 + 0.2 * 0.4 + 0.15, 3);
  });
  test("two chunks of one entity-only doc: the stronger match counts, in either order", () => {
    const one = weightedAverageFusion([], [ent("orn:doc:a#chunk0", 0.4, false), ent("orn:doc:a#chunk5", 0.9, true)], []);
    const two = weightedAverageFusion([], [ent("orn:doc:a#chunk5", 0.9, true), ent("orn:doc:a#chunk0", 0.4, false)], []);
    expect(one[0].score).toBeCloseTo(0.2 * 0.9 + 0.15, 3);
    expect(two[0].score).toBeCloseTo(one[0].score, 6);
  });
});
