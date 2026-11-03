"""Content dashboard login: credentials from the environment, enforced by default.

Offline: each test imports src/content/content_dashboard.py fresh under its own environment
and uses Flask's test client. No database, no network (nothing here calls
get_db_connection).
"""

from __future__ import annotations

import importlib
import pathlib
import sys

import pytest
from werkzeug.security import generate_password_hash

REPO = pathlib.Path(__file__).resolve().parents[1]
MODULE = "src.content.content_dashboard"
USER = "dash-test-user"
PASSWORD = "correct horse battery staple"


def _load(monkeypatch, **env):
    for key in ("FLASK_SECRET_KEY", "DASHBOARD_USERNAME", "DASHBOARD_PASSWORD_HASH",
                "DASHBOARD_AUTH_DISABLED"):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setenv("DB_PASSWORD", "unused-in-these-tests")
    for key, value in env.items():
        monkeypatch.setenv(key, value)
    monkeypatch.chdir(REPO)  # load_dotenv() reads .env from the working directory
    monkeypatch.syspath_prepend(str(REPO))
    sys.modules.pop(MODULE, None)
    mod = importlib.import_module(MODULE)
    mod.app.config["TESTING"] = True
    # A protected probe route that touches no database.
    mod.app.add_url_rule("/_auth_probe", "auth_probe", mod.require_auth(lambda: "ok"))
    return mod


@pytest.fixture
def dash(monkeypatch):
    return _load(monkeypatch, FLASK_SECRET_KEY="test-secret",
                 DASHBOARD_USERNAME=USER,
                 DASHBOARD_PASSWORD_HASH=generate_password_hash(PASSWORD))


def _login(client, username, password, prefix=None):
    headers = {"X-Forwarded-Prefix": prefix} if prefix else {}
    return client.post("/login", data={"username": username, "password": password},
                       headers=headers)


def test_refuses_to_start_without_a_secret_key(monkeypatch):
    with pytest.raises(RuntimeError, match="FLASK_SECRET_KEY"):
        _load(monkeypatch)


def test_unauthenticated_request_redirects_to_login(dash):
    r = dash.app.test_client().get("/_auth_probe")
    assert r.status_code == 302 and r.headers["Location"].endswith("/login")


def test_redirect_and_form_keep_the_nginx_prefix(dash):
    c = dash.app.test_client()
    r = c.get("/_auth_probe", headers={"X-Forwarded-Prefix": "/digests"})
    assert r.status_code == 302 and r.headers["Location"].endswith("/digests/login")
    page = c.get("/login", headers={"X-Forwarded-Prefix": "/digests"}).get_data(as_text=True)
    assert 'action="/digests/login"' in page


def test_without_the_prefix_header_urls_are_unchanged(dash):
    page = dash.app.test_client().get("/login").get_data(as_text=True)
    assert 'action="/login"' in page


@pytest.mark.parametrize("username,password", [
    (USER, "wrong"), ("someone-else", PASSWORD), ("", ""), (USER, ""),
])
def test_wrong_credentials_are_rejected(dash, username, password):
    c = dash.app.test_client()
    r = _login(c, username, password)
    assert r.status_code == 200 and "Invalid credentials" in r.get_data(as_text=True)
    assert c.get("/_auth_probe").status_code == 302


def test_correct_credentials_log_in(dash):
    c = dash.app.test_client()
    r = _login(c, USER, PASSWORD, prefix="/digests")
    assert r.status_code == 302 and r.headers["Location"].endswith("/digests/")
    probe = c.get("/_auth_probe")
    assert probe.status_code == 200 and probe.get_data(as_text=True) == "ok"
    c.get("/logout")
    assert c.get("/_auth_probe").status_code == 302


def test_no_login_succeeds_without_configured_credentials(monkeypatch):
    mod = _load(monkeypatch, FLASK_SECRET_KEY="test-secret")
    c = mod.app.test_client()
    assert _login(c, "", "").status_code == 200
    assert _login(c, USER, PASSWORD).status_code == 200
    assert c.get("/_auth_probe").status_code == 302


def test_malformed_hash_fails_closed(monkeypatch):
    mod = _load(monkeypatch, FLASK_SECRET_KEY="test-secret", DASHBOARD_USERNAME=USER,
                DASHBOARD_PASSWORD_HASH="not-a-hash")
    c = mod.app.test_client()
    assert _login(c, USER, PASSWORD).status_code == 200
    assert c.get("/_auth_probe").status_code == 302


def test_auth_disabled_only_with_the_explicit_flag(monkeypatch):
    mod = _load(monkeypatch, FLASK_SECRET_KEY="test-secret", DASHBOARD_AUTH_DISABLED="1")
    assert mod.app.test_client().get("/_auth_probe").status_code == 200
    mod = _load(monkeypatch, FLASK_SECRET_KEY="test-secret", DASHBOARD_AUTH_DISABLED="true")
    assert mod.app.test_client().get("/_auth_probe").status_code == 302


def test_routes_outside_the_session_login_stay_outside_it(dash, monkeypatch):
    """These never used the session login (nginx serves /podcast and the weekly-digest API
    without basic auth; the digest API has its own bearer check). The change must not
    redirect them to /login."""
    def no_db(*args, **kwargs):
        raise RuntimeError("no database in these tests")
    monkeypatch.setattr(dash, "get_db_connection", no_db)
    c = dash.app.test_client()
    for method, path in (("GET", "/podcast"), ("GET", "/api/koi/weekly-digest"),
                         ("POST", "/api/dashboard/notify"), ("GET", "/login")):
        r = c.open(path, method=method, json={} if method == "POST" else None)
        assert not (r.status_code in (301, 302) and r.headers.get("Location", "").endswith("/login")), path


def test_no_hardcoded_login_or_default_secret_in_source():
    src = (REPO / "src" / "content" / "content_dashboard.py").read_text()
    assert "password == '" not in src and 'password == "' not in src
    assert "os.environ.get('FLASK_SECRET_KEY'," not in src
