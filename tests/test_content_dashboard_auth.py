"""Content dashboard login: credentials from the environment, enforced by default.

Offline: each test imports src/content/content_dashboard.py fresh under its own environment
(with python-dotenv's load_dotenv stubbed, so no .env file is read) and uses Flask's test
client. No database and no network: get_db_connection is replaced where a route could
reach it.
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

# Endpoints that never used the session login. nginx serves the podcast pages and the
# weekly-digest API without basic auth (the API has its own bearer check); notify is the
# internal update hook; login and logout must stay reachable.
OPEN_ENDPOINTS = {
    "static", "login", "logout", "notify_update", "podcast_map", "podcast_map_webgpu",
    "podcast_audio", "serve_podcast_audio", "koi_weekly_digest", "koi_weekly_digest_notebooklm",
}


def _load(monkeypatch, **env):
    import dotenv
    monkeypatch.setattr(dotenv, "load_dotenv", lambda *a, **k: False)
    for key in ("FLASK_SECRET_KEY", "DASHBOARD_USERNAME", "DASHBOARD_PASSWORD_HASH",
                "DASHBOARD_AUTH_DISABLED", "DASHBOARD_COOKIE_SECURE", "DASHBOARD_URL_PREFIX"):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setenv("DB_PASSWORD", "unused-in-these-tests")
    for key, value in env.items():
        monkeypatch.setenv(key, value)
    monkeypatch.chdir(REPO)
    monkeypatch.syspath_prepend(str(REPO))
    sys.modules.pop(MODULE, None)
    mod = importlib.import_module(MODULE)
    mod.app.config["TESTING"] = True

    def no_db(*args, **kwargs):
        raise RuntimeError("no database in these tests")
    monkeypatch.setattr(mod, "get_db_connection", no_db)
    # A protected probe route that touches no database.
    mod.app.add_url_rule("/_auth_probe", "auth_probe", mod.require_auth(lambda: "ok"))
    return mod


BASE_ENV = dict(FLASK_SECRET_KEY="test-secret", DASHBOARD_USERNAME=USER,
                DASHBOARD_COOKIE_SECURE="0")


@pytest.fixture
def dash(monkeypatch):
    return _load(monkeypatch, DASHBOARD_PASSWORD_HASH=generate_password_hash(PASSWORD), **BASE_ENV)


def _login(client, username, password, prefix=None):
    headers = {"X-Forwarded-Prefix": prefix} if prefix else {}
    return client.post("/login", data={"username": username, "password": password},
                       headers=headers)


def _redirects_to_login(response):
    return response.status_code == 302 and response.headers["Location"].endswith("/login")


def test_refuses_to_start_without_a_secret_key(monkeypatch):
    with pytest.raises(RuntimeError, match="FLASK_SECRET_KEY"):
        _load(monkeypatch)


def test_unauthenticated_request_redirects_to_login(dash):
    assert _redirects_to_login(dash.app.test_client().get("/_auth_probe"))


def test_every_route_outside_the_allowlist_needs_the_login(dash):
    c = dash.app.test_client()
    checked = 0
    with dash.app.test_request_context():
        targets = []
        for rule in dash.app.url_map.iter_rules():
            if rule.endpoint in OPEN_ENDPOINTS:
                continue
            url = dash.url_for(rule.endpoint, **{a: "1" for a in rule.arguments})
            methods = sorted(rule.methods - {"HEAD", "OPTIONS"})
            targets.append((rule.endpoint, "GET" if "GET" in methods else methods[0], url))
    for endpoint, method, url in targets:
        r = c.open(url, method=method, json={} if method != "GET" else None)
        assert _redirects_to_login(r), f"{endpoint} {method} {url} -> {r.status_code}"
        checked += 1
    assert checked >= 25  # the dashboard has about 27 protected routes plus the probe


def test_redirect_and_form_keep_the_nginx_prefix(dash):
    c = dash.app.test_client()
    r = c.get("/_auth_probe", headers={"X-Forwarded-Prefix": "/digests"})
    assert r.status_code == 302 and r.headers["Location"].endswith("/digests/login")
    page = c.get("/login", headers={"X-Forwarded-Prefix": "/digests"}).get_data(as_text=True)
    assert 'action="/digests/login"' in page


@pytest.mark.parametrize("sent", ["//evil.example", "https://evil.example", "/other",
                                  "/a,/digests", "/digests/extra"])
def test_only_the_configured_prefix_is_honoured(dash, sent):
    c = dash.app.test_client()
    r = c.get("/_auth_probe", headers={"X-Forwarded-Prefix": sent})
    assert r.status_code == 302 and r.headers["Location"] == "/login"
    page = c.get("/login", headers={"X-Forwarded-Prefix": sent}).get_data(as_text=True)
    assert 'action="/login"' in page


def test_without_the_prefix_header_urls_are_unchanged(dash):
    page = dash.app.test_client().get("/login").get_data(as_text=True)
    assert 'action="/login"' in page


@pytest.mark.parametrize("username,password", [
    (USER, "wrong"), ("someone-else", PASSWORD), ("", ""), (USER, ""), (USER, PASSWORD + "\n"),
])
def test_wrong_credentials_are_rejected(dash, username, password):
    c = dash.app.test_client()
    r = _login(c, username, password)
    assert r.status_code == 200 and "Invalid credentials" in r.get_data(as_text=True)
    assert _redirects_to_login(c.get("/_auth_probe"))


def test_correct_credentials_log_in_and_logout_ends_the_session(dash):
    c = dash.app.test_client()
    with c.session_transaction() as s:
        s["planted"] = "before-login"
    r = _login(c, USER, PASSWORD, prefix="/digests")
    assert r.status_code == 302 and r.headers["Location"].endswith("/digests/")
    with c.session_transaction() as s:
        assert "planted" not in s and s.get("user") == USER and s.get("auth")
    probe = c.get("/_auth_probe")
    assert probe.status_code == 200 and probe.get_data(as_text=True) == "ok"
    out = c.get("/logout", headers={"X-Forwarded-Prefix": "/digests"})
    assert out.status_code == 302 and out.headers["Location"].endswith("/digests/login")
    assert _redirects_to_login(c.get("/_auth_probe"))


def test_changing_the_password_ends_existing_sessions(dash, monkeypatch):
    c = dash.app.test_client()
    assert _login(c, USER, PASSWORD).status_code == 302
    assert c.get("/_auth_probe").status_code == 200
    monkeypatch.setattr(dash, "DASHBOARD_PASSWORD_HASH", generate_password_hash("a new one"))
    assert _redirects_to_login(c.get("/_auth_probe"))


def test_session_cookie_flags(monkeypatch):
    env = dict(BASE_ENV)
    env.pop("DASHBOARD_COOKIE_SECURE")
    mod = _load(monkeypatch, DASHBOARD_PASSWORD_HASH=generate_password_hash(PASSWORD), **env)
    r = _login(mod.app.test_client(), USER, PASSWORD)
    cookie = r.headers["Set-Cookie"]
    assert cookie.startswith("digests_session=") and "Secure" in cookie and "SameSite=Lax" in cookie
    assert "HttpOnly" in cookie


def test_socketio_connect_needs_the_login(dash):
    c = dash.app.test_client()
    anonymous = dash.socketio.test_client(dash.app, flask_test_client=c)
    assert not anonymous.is_connected()
    assert _login(c, USER, PASSWORD).status_code == 302
    logged_in = dash.socketio.test_client(dash.app, flask_test_client=c)
    assert logged_in.is_connected()
    logged_in.disconnect()


def test_no_login_succeeds_without_configured_credentials(monkeypatch):
    mod = _load(monkeypatch, FLASK_SECRET_KEY="test-secret", DASHBOARD_COOKIE_SECURE="0")
    c = mod.app.test_client()
    assert _login(c, "", "").status_code == 200
    assert _login(c, USER, PASSWORD).status_code == 200
    assert _redirects_to_login(c.get("/_auth_probe"))


@pytest.mark.parametrize("bad_hash", ["not-a-hash", "foo$bar$baz", "scrypt:abc$s$h", "$$"])
def test_malformed_hash_fails_closed(monkeypatch, bad_hash):
    mod = _load(monkeypatch, DASHBOARD_PASSWORD_HASH=bad_hash, **BASE_ENV)
    c = mod.app.test_client()
    assert _login(c, USER, PASSWORD).status_code == 200
    assert _redirects_to_login(c.get("/_auth_probe"))


def test_auth_disabled_only_with_the_explicit_flag(monkeypatch):
    mod = _load(monkeypatch, FLASK_SECRET_KEY="test-secret", DASHBOARD_AUTH_DISABLED="1")
    assert mod.app.test_client().get("/_auth_probe").status_code == 200
    mod = _load(monkeypatch, FLASK_SECRET_KEY="test-secret", DASHBOARD_AUTH_DISABLED="true")
    assert _redirects_to_login(mod.app.test_client().get("/_auth_probe"))


def test_routes_outside_the_session_login_stay_outside_it(dash):
    c = dash.app.test_client()
    for method, path in (("GET", "/podcast"), ("GET", "/api/koi/weekly-digest"),
                         ("POST", "/api/dashboard/notify"), ("GET", "/login")):
        r = c.open(path, method=method, json={} if method == "POST" else None)
        assert not _redirects_to_login(r), path


def test_no_hardcoded_login_or_default_secret_in_source():
    src = (REPO / "src" / "content" / "content_dashboard.py").read_text()
    assert "password == '" not in src and 'password == "' not in src
    assert "os.environ.get('FLASK_SECRET_KEY'," not in src
    assert "dev-secret-key" not in (REPO / "config" / "dashboard_config.yaml").read_text()


def test_alert_fields_are_escaped_in_the_dashboard_script():
    js = (REPO / "static" / "dashboard.v5.js").read_text()
    for raw in ("${alert.message}", "${alert.alert_type}", "${alert.severity || 'info'}"):
        assert raw not in js, raw
    assert "escapeHtml(alert.message)" in js and "escapeHtml(alert.alert_type)" in js
