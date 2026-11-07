"""Canonical list of GitHub repos whose code/content is private.

These repos must NOT be ingested into the code graph (`regen_graph`), which is
served without authentication via `/api/koi/graph` on :8301. Loading a private
repo there would expose its code structure anonymously, so both ingest paths
(`scripts/load_to_staging.py`, `api/github_webhook.py`) refuse these repos.

This list mirrors the per-repo ``"private": True`` flags in the GitHub sensor
(``gaiaaiagent/koi-sensors`` ``sensors/github/github_sensor.py``). The two repos
live in different codebases, so the list cannot be imported across them today;
keep the two copies in sync, and treat this as the canonical copy for
koi-processor's ingest paths.
"""

from __future__ import annotations

# Keep in sync with the sensor's "private": True repos.
PRIVATE_REPOS = frozenset({
    "koi-processor",
    "revenue-hunter-cec",
    "regen-ai-core",
    "protocol-politicians",
    "regen-claude-config",
    "regen-demos",
})

_PRIVATE_LOWER = frozenset(r.lower() for r in PRIVATE_REPOS)


def is_private_repo(repo_name: str) -> bool:
    """True if ``repo_name`` is a private repo that must not enter the code graph.

    Matching is case-insensitive and tolerant of surrounding whitespace. An
    ``owner/name`` form is reduced to its last path segment first.
    """
    name = (repo_name or "").strip().rstrip("/")
    if "/" in name:
        name = name.rsplit("/", 1)[-1]
    return name.lower() in _PRIVATE_LOWER


def refuse_private_cli(repo_name: str, allow_private: bool = False, *, log=None) -> None:
    """CLI ingest guard for ``scripts/load_to_staging.py``.

    Raises ``SystemExit(3)`` if ``repo_name`` is private and ``allow_private`` is
    false; otherwise returns ``None`` (the repo may be ingested). Kept dep-free so
    it is unit-testable without the loader's heavy imports.
    """
    if is_private_repo(repo_name) and not allow_private:
        msg = (
            f"Refusing to load private repo '{repo_name}' into the code graph: "
            f"regen_graph is served unauthenticated via /api/koi/graph. "
            f"Private repos: {sorted(PRIVATE_REPOS)}. "
            f"Pass --allow-private only if exposing its structure is intended."
        )
        if log is not None:
            log.error(msg)
        else:
            import sys as _sys
            print(msg, file=_sys.stderr)
        raise SystemExit(3)
