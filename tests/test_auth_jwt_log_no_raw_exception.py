"""The JWT-validation warning logs the exception type, not the raw message (offline).

A raw exception message can carry attacker-controlled content (e.g. a newline in a
JWT 'kid'), which forges extra log lines (log injection). On the base commit the line
is `logger.warning(f"[Auth] JWT validation failed: {e}")`, so these assertions fail
there and pass here.
"""
from __future__ import annotations

import pathlib

REPO = pathlib.Path(__file__).resolve().parents[1]
SRC = (REPO / "src" / "services" / "auth_service.py").read_text()


def test_jwt_validation_warning_does_not_interpolate_the_raw_exception():
    assert 'f"[Auth] JWT validation failed: {e}"' not in SRC


def test_jwt_validation_warning_logs_the_exception_type():
    assert "[Auth] JWT validation failed: {type(e).__name__}" in SRC
