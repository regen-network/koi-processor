"""Private-repo ingest guard: the code-graph loaders must refuse the private
repos so their structure cannot enter regen_graph, which is served without
authentication via /api/koi/graph."""
import asyncio
import pathlib
import sys
import types

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src" / "core"))

from private_repos import PRIVATE_REPOS, is_private_repo, refuse_private_cli


def test_private_list_membership():
    for r in ["koi-processor", "revenue-hunter-cec", "regen-ai-core",
              "protocol-politicians", "regen-claude-config", "regen-demos"]:
        assert is_private_repo(r), r
    for r in ["regen-ledger", "regen-web", "koi-research", "regen-data-standards"]:
        assert not is_private_repo(r), r
    # case / whitespace / owner-prefix tolerant
    assert is_private_repo("KOI-Processor")
    assert is_private_repo("  koi-processor  ")
    assert is_private_repo("gaiaaiagent/koi-processor")
    assert not is_private_repo("")


def test_webhook_run_extraction_skips_private(monkeypatch, tmp_path):
    import api.github_webhook as wh

    def boom(*a, **k):
        raise AssertionError("subprocess.run called for a private repo")

    monkeypatch.setattr(wh.subprocess, "run", boom)
    wh.running_extractions.clear()
    # tmp_path exists, so only the private-repo guard can stop it before subprocess
    asyncio.run(wh.run_extraction("koi-processor", tmp_path))
    assert "koi-processor" not in wh.running_extractions


def test_webhook_run_extraction_allows_public(monkeypatch, tmp_path):
    import api.github_webhook as wh
    ran = {"git": False, "extract": False}

    def fake_run(cmd, *a, **k):
        if "pull" in cmd:
            ran["git"] = True
        else:
            ran["extract"] = True
        return types.SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(wh.subprocess, "run", fake_run)
    wh.running_extractions.clear()
    asyncio.run(wh.run_extraction("regen-ledger", tmp_path))
    assert ran["git"] is True  # public repo proceeds past the guard


def test_cli_guard_refuses_private():
    # refuse_private_cli is the exact guard load_to_staging.main() invokes.
    with pytest.raises(SystemExit) as e:
        refuse_private_cli("koi-processor", False)
    assert e.value.code == 3


def test_cli_guard_allows_public():
    assert refuse_private_cli("regen-ledger", False) is None


def test_cli_guard_override_allows_private():
    assert refuse_private_cli("koi-processor", True) is None
