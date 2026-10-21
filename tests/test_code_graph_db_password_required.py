"""The code-graph scripts must not fall back to a default database password.

load_to_staging.py, community_detection.py and detect_flows.py used to read
``os.environ.get("KOI_DB_PASSWORD", <literal>)``, so a missing variable
silently used a password published in this repository. These tests pin the replacement behaviour: no
default, a refusal before any connection attempt, and the password passed to
asyncpg as a keyword so special characters survive.

All credentials below are fictional.
"""

import ast
import importlib.util
import sys
import types
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
SCRIPT_NAMES = ["load_to_staging", "community_detection", "detect_flows"]
FICTIONAL_PASSWORD = "fict1onal@pa:ss/w0rd"


def _load(name, monkeypatch, password):
    if password is None:
        monkeypatch.delenv("KOI_DB_PASSWORD", raising=False)
    else:
        monkeypatch.setenv("KOI_DB_PASSWORD", password)
    # The scripts import graph and parser libraries at module level; the
    # connection logic under test needs none of them.
    stub = types.ModuleType("tree_sitter_extractor")
    stub.TreeSitterExtractor = stub.CodeEntity = stub.CodeEdge = object
    monkeypatch.setitem(sys.modules, "tree_sitter_extractor", stub)
    for lib in ("igraph", "leidenalg"):
        if importlib.util.find_spec(lib) is None:
            fake = types.ModuleType(lib)
            fake.Graph = object  # used in module-level annotations
            monkeypatch.setitem(sys.modules, lib, fake)
    spec = importlib.util.spec_from_file_location(f"_pwtest_{name}", SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.mark.parametrize("name", SCRIPT_NAMES)
def test_source_has_no_password_default(name):
    tree = ast.parse((SCRIPTS / f"{name}.py").read_text())
    offenders = [
        node.lineno
        for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr in ("get", "getenv")
        and node.args
        and isinstance(node.args[0], ast.Constant)
        and node.args[0].value == "KOI_DB_PASSWORD"
        and (len(node.args) > 1 or node.keywords)
    ]
    assert offenders == [], f"{name}.py gives KOI_DB_PASSWORD a default at lines {offenders}"


@pytest.mark.parametrize("name", SCRIPT_NAMES)
@pytest.mark.parametrize("password", [None, ""])
def test_missing_password_refuses_to_connect(name, password, monkeypatch):
    module = _load(name, monkeypatch, password)
    assert not module.DB_CONFIG["password"]
    with pytest.raises(SystemExit) as exc:
        module._connect_kwargs()
    assert "KOI_DB_PASSWORD" in str(exc.value)


@pytest.mark.parametrize("name", SCRIPT_NAMES)
def test_password_passed_verbatim_as_keyword(name, monkeypatch):
    monkeypatch.setenv("KOI_DB_HOST", "db.example.invalid")
    monkeypatch.setenv("KOI_DB_USER", "fictional_role")
    module = _load(name, monkeypatch, FICTIONAL_PASSWORD)
    kwargs = module._connect_kwargs()
    assert kwargs["password"] == FICTIONAL_PASSWORD
    assert kwargs["user"] == "fictional_role"
    assert kwargs["host"] == "db.example.invalid"
    assert set(kwargs) == {"host", "port", "database", "user", "password"}


@pytest.mark.parametrize("name", SCRIPT_NAMES)
def test_no_connection_dsn_is_built(name):
    # The old code formatted the password into a postgresql:// URL, which breaks
    # on '@' or ':' and puts the secret in a string that is easy to log.
    source = (SCRIPTS / f"{name}.py").read_text()
    assert "DB_CONFIG['password']" not in source
    assert "asyncpg.connect(db_url)" not in source
