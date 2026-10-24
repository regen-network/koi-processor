"""Tracked config files must not hold the database credential; readers take it from the environment.

config/curator_config.yaml, config/quality_config.yaml, config/weekly_aggregator.json and
ecosystem.hybrid.config.js used to carry the eliza password inline. A deployment that put its own
value there was one ``git checkout``, ``stash`` or ``reset`` away from the committed one. These
tests pin the replacement: the files hold no credential, the weekly aggregator and the PM2
ecosystem read it from the environment or .env, and the cron wrappers export only the database
keys from .env.

All credentials below are fictional.
"""

import importlib.util
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parent.parent
FICTIONAL_DSN = "postgresql://fictional_role:fict1onal@db.example.invalid:5433/eliza"
FICTIONAL_PASSWORD = "fict1onal-pa:ss"
USERINFO = re.compile(r"://[^/@\s:]+:[^@\s]+@")
WRAPPERS = ["scripts/cron_daily_curator.sh", "scripts/cron_weekly_aggregator.sh"]


def test_tracked_configs_hold_no_database_credential():
    for name in ("config/curator_config.yaml", "config/quality_config.yaml"):
        assert "database_url" not in yaml.safe_load((ROOT / name).read_text()), name
    assert "password" not in json.loads((ROOT / "config/weekly_aggregator.json").read_text())["database"]
    for name in ("config/curator_config.yaml", "config/quality_config.yaml", "ecosystem.hybrid.config.js"):
        assert not USERINFO.search((ROOT / name).read_text()), f"{name} holds a URL with a password"


def _aggregator(monkeypatch, password):
    if password is None:
        monkeypatch.delenv("KOI_DB_PASSWORD", raising=False)
    else:
        monkeypatch.setenv("KOI_DB_PASSWORD", password)
    spec = importlib.util.spec_from_file_location("_envcfg_weekly_aggregator", ROOT / "src/content/weekly_aggregator.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    calls = []
    monkeypatch.setattr(module.psycopg2, "connect", lambda **kw: calls.append(kw) or object())
    return module.WeeklyAggregator(str(ROOT / "config/weekly_aggregator.json")), calls


def test_weekly_aggregator_takes_password_from_environment(monkeypatch):
    aggregator, calls = _aggregator(monkeypatch, FICTIONAL_PASSWORD)
    aggregator.connect_db()
    assert calls[0]["password"] == FICTIONAL_PASSWORD
    assert calls[0]["user"] and calls[0]["host"] and calls[0]["database"]


def test_weekly_aggregator_refuses_without_password(monkeypatch):
    aggregator, calls = _aggregator(monkeypatch, None)
    with pytest.raises(RuntimeError, match="KOI_DB_PASSWORD"):
        aggregator.connect_db()
    assert calls == []


def _ecosystem(tmp_path, env_text):
    shutil.copy(ROOT / "ecosystem.hybrid.config.js", tmp_path / "ecosystem.hybrid.config.js")
    (tmp_path / ".env").write_text(env_text)
    script = "console.log(JSON.stringify(require(process.argv[1]).apps[0].env))"
    return subprocess.run(["node", "-e", script, str(tmp_path / "ecosystem.hybrid.config.js")],
                          capture_output=True, text=True, env={"PATH": os.environ["PATH"]})


@pytest.mark.skipif(shutil.which("node") is None, reason="node not installed")
def test_ecosystem_reads_postgres_url_from_env_file(tmp_path):
    result = _ecosystem(tmp_path, f'OTHER=1\nPOSTGRES_URL="{FICTIONAL_DSN}"\n')
    assert result.returncode == 0, result.stderr
    env = json.loads(result.stdout)
    assert env["POSTGRES_URL"] == FICTIONAL_DSN
    assert env["ENABLE_GRAPHRAG_CONTEXT"] == "true"


@pytest.mark.skipif(shutil.which("node") is None, reason="node not installed")
def test_ecosystem_refuses_without_postgres_url(tmp_path):
    result = _ecosystem(tmp_path, "OTHER=1\n")
    assert result.returncode != 0
    assert "POSTGRES_URL is missing" in result.stderr


def _run_wrapper(tmp_path, wrapper, env_text):
    koi = tmp_path / "koi"
    shim = tmp_path / "shim"
    (koi / "venv/bin").mkdir(parents=True)
    shim.mkdir()
    (koi / ".env").write_text(env_text)
    (koi / "venv/bin/activate").write_text(f'export PATH="{shim}:$PATH"\n')
    record = tmp_path / "seen.json"
    # Stands in for the venv's python: records what the first Python step would see, then fails
    # so the wrapper stops before any later step.
    (shim / "python").write_text(
        "#!/bin/sh\n"
        f"{shutil.which('python3')} -c 'import json,os,sys; "
        "json.dump({k: os.environ.get(k) for k in (\"POSTGRES_URL\", \"KOI_DB_PASSWORD\", \"OPENAI_API_KEY\")}, "
        f"open(\"{record}\", \"w\"))'\nexit 1\n")
    (shim / "python").chmod(0o755)
    result = subprocess.run(["bash", str(ROOT / wrapper)], capture_output=True, text=True,
                            env={"PATH": "/usr/bin:/bin", "KOI_DIR": str(koi)})
    return result, (json.loads(record.read_text()) if record.exists() else None)


@pytest.mark.parametrize("wrapper", WRAPPERS)
def test_cron_wrapper_exports_only_database_keys(tmp_path, wrapper):
    env_text = (f'POSTGRES_URL="{FICTIONAL_DSN}"\nKOI_DB_PASSWORD={FICTIONAL_PASSWORD}\n'
                "OPENAI_API_KEY=fictional-not-for-this-step\n")
    result, seen = _run_wrapper(tmp_path, wrapper, env_text)
    assert seen is not None, result.stdout + result.stderr
    assert seen == {"POSTGRES_URL": FICTIONAL_DSN, "KOI_DB_PASSWORD": FICTIONAL_PASSWORD, "OPENAI_API_KEY": None}


@pytest.mark.parametrize("wrapper", WRAPPERS)
def test_cron_wrapper_refuses_without_postgres_url(tmp_path, wrapper):
    result, seen = _run_wrapper(tmp_path, wrapper, f"KOI_DB_PASSWORD={FICTIONAL_PASSWORD}\n")
    assert result.returncode == 1
    assert "POSTGRES_URL missing from .env" in result.stdout
    assert seen is None
