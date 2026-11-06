"""Device-code sign-in page must not reflect the raw `error` query value.

GET /api/koi/activate (src/services/auth_service.py: activate_page) renders an
error block from the `error` query parameter. It is served anonymously - nginx
exempts /api/koi/activate from the dashboard Basic-auth gate - so any part of the
query value echoed into the HTML is a reflected-input (cross-site-scripting)
vector. The page must render only the known, fixed error messages and never
interpolate the caller's value.

Offline note: auth_service imports PyJWT and declares a Form() route, neither of
which the runtime venv provides, so both are stubbed in sys.modules before import.
The GET handler under test uses neither; the stubs only let the module import.
"""
from __future__ import annotations

import asyncio
import pathlib
import sys
import types

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

sys.modules.setdefault("jwt", types.ModuleType("jwt"))
if "multipart" not in sys.modules:
    _mp = types.ModuleType("multipart")
    _mp.__version__ = "0-stub"  # FastAPI's Form() guard only checks this import
    _mp_sub = types.ModuleType("multipart.multipart")
    _mp_sub.parse_options_header = lambda *a, **k: (b"", {})
    _mp.multipart = _mp_sub
    sys.modules["multipart"] = _mp
    sys.modules["multipart.multipart"] = _mp_sub

from src.services.auth_service import activate_page  # noqa: E402


def _render(error):
    return str(asyncio.run(activate_page(error=error)))


def test_unknown_error_value_is_not_echoed():
    # A caller-controlled value must never reach the page, escaped or not.
    marker = '<b id="xss-marker">x</b>'
    html = _render(marker)
    assert marker not in html
    assert "xss-marker" not in html
    assert '<div class="error">' in html  # a generic error block still renders


def test_known_error_code_renders_its_message():
    assert "Invalid or expired code" in _render("invalid")


def test_no_error_renders_no_error_block():
    assert '<div class="error">' not in _render(None)
