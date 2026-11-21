"""The provenance endpoint hides private documents from anonymous callers (offline).

Exercises api/pipeline_metadata_api.py::get_document_provenance with a fake asyncpg
connection, so no database and no network are touched.

The handler gates anonymous access twice, both through _provenance_touches_private_doc:
a fast pre-fetch check on the requested RID, and an authoritative post-fetch check over
every RID in the receipts chain (derivative RIDs such as embedding:<rid>:<model> trace
back to the private document through input_rid). The fake connection models that privacy
query over a fake koi_memories (private_rids) + koi_memory_chunks (chunk_to_doc).

NEGATIVE CONTROL: on the base commit get_document_provenance has no `user_email`
parameter and no gate, so _call raises TypeError and none of the privacy assertions can
pass; with the fix they pass. The post-fetch case (embedding derivative RID) additionally
fails on any version lacking the chain-wide check. The SQL itself is verified read-only
against the live database before the edge 403 is lifted.
"""
from __future__ import annotations

import asyncio
import importlib
import pathlib
import sys

import pytest

REPO = pathlib.Path(__file__).resolve().parents[1]
API_DIR = REPO / "api"

DOC_RID = "orn:regen.document:github/acme/secret-repo"
PUB_DOC_RID = "orn:regen.document:notion/public-page"
CHUNK_RID = f"{DOC_RID}:chunk_0"        # koi_memory_chunks form (isolated tables, default)
HASH_CHUNK_RID = f"{DOC_RID}#chunk3"    # koi_memories legacy chunk form
EMBEDDING_RID = f"embedding:{DOC_RID}#chunk0:bge-large-en-v1.5"  # derivative receipt output
MISSING_RID = "orn:regen.document:github/acme/does-not-exist"


def _receipt(**over):
    base = {
        "receipt_id": "r1", "transformation_type": "sensor_collection", "input_rid": None,
        "output_rid": DOC_RID, "source_sensor": "github", "event_type": "NEW",
        "chunks_created": 0, "embeddings_created": 0, "entities_extracted": 0,
        "processor_name": "koi-sensor", "created_at": None, "metadata": None,
    }
    base.update(over)
    return base


RECEIPT = _receipt()
DOC = {"id": DOC_RID, "title": "SECRET TITLE", "source_sensor": "github",
       "created_at": None, "content_hash": "deadbeef"}


class FakeConn:
    """asyncpg stand-in. fetchval models _provenance_touches_private_doc's query over
    a fake koi_memories (private_rids) + koi_memory_chunks (chunk_to_doc), given the
    handler's (exact_rids, bases) arguments."""

    def __init__(self, *, private_rids=(), chunk_to_doc=None, receipts=None, doc=None):
        self.private_rids = set(private_rids)
        self.chunk_to_doc = dict(chunk_to_doc or {})
        self._receipts = list(receipts or [])
        self._doc = doc
        self.calls = []
        self.fetchval_calls = []

    async def fetchval(self, query, *args):
        self.calls.append("fetchval")
        exact, bases = set(args[0]), set(args[1])
        self.fetchval_calls.append((exact, bases))
        matched = set(exact)
        for chunk_rid, doc_rid in self.chunk_to_doc.items():
            if chunk_rid in exact:
                matched.add(doc_rid)
        for p in self.private_rids:
            if any(p.startswith(b + "#chunk") for b in bases):
                matched.add(p)
        return True if (matched & self.private_rids) else None

    async def fetch(self, query, *args):
        self.calls.append("fetch")
        return list(self._receipts)

    async def fetchrow(self, query, *args):
        self.calls.append("fetchrow")
        return self._doc if "content_hash" in query else None

    async def close(self):
        self.calls.append("close")


@pytest.fixture
def pm(monkeypatch):
    monkeypatch.setenv("POSTGRES_URL", "postgresql://u:p@localhost:5432/db")  # mocked; never dialed
    monkeypatch.syspath_prepend(str(API_DIR))
    sys.modules.pop("pipeline_metadata_api", None)
    return importlib.import_module("pipeline_metadata_api")


def _call(pm, monkeypatch, *, rid, user_email, conn):
    import asyncpg

    async def _connect(*args, **kwargs):
        return conn

    monkeypatch.setattr(asyncpg, "connect", _connect)
    return asyncio.run(pm.get_document_provenance(rid=rid, user_email=user_email))


def _assert_hidden_shape(result):
    assert result["found"] is False
    assert result["document"] == {"source_url": None}
    assert "title" not in result["document"]
    assert result["timeline"] == []
    assert result["provenance"]["transformation_count"] == 0
    assert result["provenance"]["sensed_by"] == []


def _assert_hidden_before_fetch(result, conn):
    _assert_hidden_shape(result)
    # The fast pre-fetch gate returned before any leaking query ran.
    assert "fetch" not in conn.calls and "fetchrow" not in conn.calls


# --- direct requests: blocked by the fast pre-fetch gate --------------------------

def test_anonymous_private_document_looks_missing(pm, monkeypatch):
    conn = FakeConn(private_rids={DOC_RID}, receipts=[RECEIPT], doc=DOC)
    _assert_hidden_before_fetch(_call(pm, monkeypatch, rid=DOC_RID, user_email=None, conn=conn), conn)


def test_anonymous_private_chunk_isolated_form_looks_missing(pm, monkeypatch):
    # "<doc>:chunk_N" lives only in koi_memory_chunks; resolved via document_rid.
    conn = FakeConn(private_rids={DOC_RID}, chunk_to_doc={CHUNK_RID: DOC_RID},
                    receipts=[RECEIPT], doc=DOC)
    _assert_hidden_before_fetch(_call(pm, monkeypatch, rid=CHUNK_RID, user_email=None, conn=conn), conn)
    exact, bases = conn.fetchval_calls[0]
    assert CHUNK_RID in exact and DOC_RID in bases


def test_anonymous_private_chunk_hash_form_looks_missing(pm, monkeypatch):
    conn = FakeConn(private_rids={HASH_CHUNK_RID}, receipts=[RECEIPT], doc=DOC)
    _assert_hidden_before_fetch(_call(pm, monkeypatch, rid=HASH_CHUNK_RID, user_email=None, conn=conn), conn)


def test_anonymous_content_prefixed_private_rid_looks_missing(pm, monkeypatch):
    conn = FakeConn(private_rids={DOC_RID}, receipts=[RECEIPT], doc=DOC)
    _assert_hidden_before_fetch(
        _call(pm, monkeypatch, rid=f"content:{DOC_RID}", user_email=None, conn=conn), conn)


def test_anonymous_private_rid_with_non_chunk_hash_suffix_looks_missing(pm, monkeypatch):
    conn = FakeConn(private_rids={DOC_RID}, receipts=[RECEIPT], doc=DOC)
    _assert_hidden_before_fetch(
        _call(pm, monkeypatch, rid=f"{DOC_RID}#x", user_email=None, conn=conn), conn)


def test_anonymous_embedded_content_prefix_private_rid_looks_missing(pm, monkeypatch):
    embedded = "content:orn:regen.document:content:github/acme/secret-repo"
    conn = FakeConn(private_rids={DOC_RID}, receipts=[RECEIPT], doc=DOC)
    _assert_hidden_before_fetch(
        _call(pm, monkeypatch, rid=embedded, user_email=None, conn=conn), conn)


# --- derivative request: caught only by the post-fetch chain-wide gate ------------

def test_anonymous_derivative_embedding_rid_looks_missing(pm, monkeypatch):
    # The request RID is not itself a document/chunk, so the pre-fetch gate lets it
    # through; the receipts chain reaches the private document via input_rid, and the
    # post-fetch gate must hide the whole response.
    emb_receipt = _receipt(receipt_id="emb", transformation_type="memory_to_bge_embedding",
                           input_rid=f"{DOC_RID}#chunk0", output_rid=EMBEDDING_RID)
    conn = FakeConn(private_rids={DOC_RID}, receipts=[emb_receipt], doc=None)
    result = _call(pm, monkeypatch, rid=EMBEDDING_RID, user_email=None, conn=conn)
    _assert_hidden_shape(result)
    assert "fetch" in conn.calls  # it reached the receipts chain, then hid the result


# --- served paths -----------------------------------------------------------------

def test_anonymous_public_document_is_served(pm, monkeypatch):
    conn = FakeConn(private_rids=set(), receipts=[RECEIPT], doc=DOC)
    result = _call(pm, monkeypatch, rid=PUB_DOC_RID, user_email=None, conn=conn)
    assert result["found"] is True
    assert result["document"]["title"] == "SECRET TITLE"
    assert result["provenance"]["transformation_count"] == 1


def test_authenticated_caller_sees_private_provenance(pm, monkeypatch):
    conn = FakeConn(private_rids={DOC_RID}, receipts=[RECEIPT], doc=DOC)
    result = _call(pm, monkeypatch, rid=DOC_RID, user_email="curator@regen.network", conn=conn)
    assert result["found"] is True
    assert result["document"]["title"] == "SECRET TITLE"
    assert "fetchval" not in conn.calls  # both gates skipped for a curator


def test_missing_rid_still_reports_not_found(pm, monkeypatch):
    conn = FakeConn(private_rids=set(), receipts=[], doc=None)
    result = _call(pm, monkeypatch, rid=MISSING_RID, user_email=None, conn=conn)
    assert result["found"] is False
    assert result["timeline"] == []
    assert result["provenance"]["transformation_count"] == 0
