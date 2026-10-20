# koi-processor

## What this is

The Regen KOI processing service. It ingests content events from KOI sensors, stores documents and embeddings in PostgreSQL, extracts entities into a knowledge graph, serves hybrid search to agents and applications, and runs the Regen claims engine.

This repository is a Regen-scoped subset of `gaiaaiagent/koi-processor`. It contains the code that Regen Network's production KOI deployment runs.

## Services

| File | Role | Port | How production runs it |
|---|---|---|---|
| `koi-query-api.ts` | Hybrid search and query API (`/api/koi/*`, `/api/podcast/chat`), run under Bun | 8301 | PM2, via `ecosystem.hybrid.config.js` |
| `api/personal_ingest_api.py` | FastAPI app. Production exposes the claims engine (`/claims/`), entity lookup (`/entities`, `/entity-search`) and SeaTrees export (`/seatrees/`) through its reverse proxy | 8352 in production (uvicorn `--port`); `KOI_API_PORT` or 8351 when run directly | uvicorn |
| `api/pipeline_metadata_api.py` | Pipeline structure and component metadata, read from `koi-ontology.ttl` and `pipeline-metadata.ttl` | 8002 | systemd |
| `src/core/bge_server.py` | Embedding server | 8090 | systemd |
| `api/koi_content_api.py` | Content API over PostgreSQL | 8007 | systemd |
| `adaptive_extraction_api.py` | HTTP wrapper around `src/core/adaptive_extractor.py` | 8351 when run directly | systemd |
| `src/content/content_dashboard.py` | Content operations dashboard (daily and weekly curation, podcast) | 8400 | gunicorn under systemd |
| `src/core/koi_event_bridge_v2.py` | Event bridge: deduplication, chunking, embeddings | 8100 | systemd |
| `src/core/koi_event_bridge_semantic.py` | Event bridge with LLM extraction, knowledge graph and CAT receipts | 8004 | long-running process |
| `scripts/coordinator_to_eventbridge_forwarder.py` | Polls the KOI coordinator and forwards events to the event bridge. Imports `scripts/koi_envelope.py` | none | systemd |
| `src/core/koi_knowledge_mcp_server.py` | Knowledge MCP server (HTTP) | 8200 | long-running process |
| `src/core/koi_knowledge_mcp_stdio.py` | Knowledge MCP server (stdio), spawned by the MCP client | none | started by the client |
| `scripts/cron_daily_curator.sh` | Daily content curation | none | cron, `0 17 * * 1-5` |
| `scripts/cron_weekly_aggregator.sh` | Weekly digest and podcast generation | none | cron, `0 19 * * 5` |
| `scripts/cleanup_auth_requests.sql` | Deletes expired or used rows from `auth_requests` and expired or revoked rows from `session_tokens` | none | cron via `psql`, every 15 minutes |
| `monitoring/event_flood_monitor.sh` | Event flood alerting | none | systemd timer, every 5 minutes |
| `monitoring/production_monitor.sh` | Pipeline health checks | none | `systemd/koi-pipeline-monitor.timer`, every 5 minutes |
| `api/github_webhook.py` | GitHub push webhook that triggers code-graph extraction | 8360 | `systemd/koi-webhook.service` (installed but inactive) |
| `src/cat/coordinator_receipt_integration.py` | CAT receipt integration | none | imported by the KOI coordinator, which runs from a separate repository |

Only three unit files are included in `systemd/`. The other services above run under units, cron entries or process managers whose definitions are not part of this repository.

## Requirements

- Python 3 with the packages in `requirements.txt`
- gunicorn, for the content dashboard (not in `requirements.txt`)
- Bun, for `koi-query-api.ts` (dependencies in `package.json` and `bun.lock`)
- PostgreSQL with the `vector` (pgvector) extension, and the Apache AGE extension for the code graph (graph name `regen_graph`)
- Apache Jena Fuseki, used by both event bridges (via `src/core/provenance_to_rdf.py`) and the query API
- An OpenAI API key, used by `src/core/bge_server.py`
- The `regen` CLI, for anchoring claims on Regen Ledger
- PM2, if you run the query API from `ecosystem.hybrid.config.js`

## Configuration

Copy `.env.example` to `.env` and set your own values. Replace the `POSTGRES_URL` value with your own connection string, for example `postgresql://<user>:<password>@<host>:<port>/<database>`.

To export `.env` to a shell and its child processes:

```bash
set -a; source .env; set +a
```

Variables read by the code include:

| Variable | Read by | Purpose |
|---|---|---|
| `POSTGRES_URL` | `koi-query-api.ts`, `api/personal_ingest_api.py`, `adaptive_extraction_api.py`, both event bridges, `src/core/koi_knowledge_mcp_server.py`, the curation scripts in `src/content/` | PostgreSQL connection string |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` | `src/content/content_dashboard.py` | Database connection for the dashboard |
| `BGE_API_URL` | event bridges, MCP server | Embedding endpoint (default `http://localhost:8090/encode`) |
| `USE_ISOLATED_TABLES` | `src/core/koi_event_bridge_v2.py` | Write to `koi_memories` and `koi_embeddings` (default `true`) |
| `KG_EXTRACTION_ENABLED` | `src/core/koi_event_bridge_v2.py` | Knowledge graph extraction (code default `false`; `.env.example` sets `true`) |
| `OPENAI_API_KEY` | `src/core/bge_server.py`, `koi-query-api.ts` | Embeddings and chat |
| `KOI_INTERNAL_API_KEY` | `koi-query-api.ts` | Internal service authentication |
| `FUSEKI_URL`, `FUSEKI_DATASET` | `koi-query-api.ts`, `src/core/provenance_to_rdf.py` | SPARQL endpoint (defaults `http://localhost:3030`, `koi`) |
| `KOI_API_PORT` | `api/personal_ingest_api.py` | Listen port when run directly |
| `REGEN_CHAIN_ID`, `REGEN_RPC_URL`, `REGEN_REST_URL`, `REGEN_KEY_NAME`, `REGEN_CLI_PATH` | `api/ledger_anchor.py` | Claim anchoring (chain defaults to `regen-1`) |

Google OAuth setup for the auth endpoints is described in `config/README.md`.

## Database

The services share one PostgreSQL database. Schema changes are the SQL files in `migrations/`. There is no migration runner, so apply them with `psql`:

```bash
psql "$POSTGRES_URL" -f migrations/003_create_isolated_koi_tables.sql
```

Some migration numbers repeat (001, 006, 055) and the sequence has gaps. Read each file before applying it.

### Isolated KOI tables

The event bridge writes documents to `koi_memories` and their embeddings to `koi_embeddings`. Both tables are created by `migrations/003_create_isolated_koi_tables.sql`, shown below. Later migrations alter `koi_memories`: `004` adds `content_hash`, `published_at` and `published_confidence`, and `007` and `044` add a unique constraint on `rid`.

#### `koi_memories`

```sql
CREATE TABLE IF NOT EXISTS koi_memories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rid VARCHAR(500) NOT NULL,
    cid VARCHAR(500),
    version INTEGER DEFAULT 1,
    previous_version_id UUID REFERENCES koi_memories(id),
    event_type VARCHAR(20) NOT NULL CHECK (event_type IN ('NEW', 'UPDATE', 'FORGET')),
    source_sensor VARCHAR(200) NOT NULL,
    agent_id UUID,
    content JSONB NOT NULL,
    metadata JSONB DEFAULT '{}',
    superseded_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(rid, version)
);
```

#### `koi_embeddings`

```sql
CREATE TABLE IF NOT EXISTS koi_embeddings (
    id SERIAL PRIMARY KEY,
    memory_id UUID NOT NULL REFERENCES koi_memories(id) ON DELETE CASCADE,
    dim_384 vector(384),
    dim_512 vector(512),
    dim_768 vector(768),
    dim_1024 vector(1024),
    dim_1536 vector(1536),
    dim_3072 vector(3072),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(memory_id)
);
```

### Useful queries

```sql
-- Current documents
SELECT * FROM current_koi_memories;

-- Pipeline statistics
SELECT * FROM koi_pipeline_stats;
```

## Deployment

### Systemd

`systemd/` contains three unit files:

- `koi-webhook.service` runs `api/github_webhook.py` under uvicorn on port 8360.
- `koi-pipeline-monitor.service` runs `monitoring/production_monitor.sh` once.
- `koi-pipeline-monitor.timer` runs the monitor service every 5 minutes.

The two service units set `User`, `Group`, `WorkingDirectory`, `EnvironmentFile` and `ExecStart` for the production host. Edit them for yours before installing.

### Query API (Bun)

```bash
bun install
bun run start
```

`bun run start` runs `bun koi-query-api.ts`, which listens on port 8301.

### Query API (PM2)

`ecosystem.hybrid.config.js` defines the PM2 app `hybrid-rag-api`:

```bash
pm2 start ecosystem.hybrid.config.js
```

Its `interpreter`, `cwd` and `env` values are set for the production host. Edit them for yours before use.

## Claims engine

Lightweight, ledger-anchored impact claim system with Regen Ledger mainnet (regen-1) integration. The router is `api/routers/claims_router.py`, mounted by `api/personal_ingest_api.py`.

### Features

- Verification state machine: `self_reported → peer_reviewed → verified → ledger_anchored`
- Content-addressable RIDs (BLAKE2b-256 hash)
- Entity graph integration (claims as first-class KOI entities)
- AI-powered claim extraction from documents
- Live ledger anchoring via `regen` CLI with async 202 pending responses
- Reconciliation endpoint for blockchain drift detection

### Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| POST | /claims/ | Create claim |
| GET | /claims/{rid} | Get claim with evidence |
| GET | /claims/ | Search/filter claims |
| PATCH | /claims/{rid}/verify | Advance verification level |
| POST | /claims/{rid}/evidence | Attach evidence entity |
| POST | /claims/{rid}/anchor | Anchor on Regen Ledger (200 success or 202 pending) |
| POST | /claims/{rid}/reconcile | Check on-chain status of pending broadcast |

The router defines further routes, including attestations and proof packs. See `api/routers/claims_router.py` for the full list.

## Event bridge API

`src/core/koi_event_bridge_v2.py` listens on port 8100.

### Sending events

#### NEW event (first time content)

```bash
curl -X POST http://localhost:8100/process-koi-event \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "NEW",
    "rid": "sensor.website.example.com.page1",
    "source_node": "website_monitor",
    "timestamp": "2025-09-09T12:00:00Z",
    "bundle": {
      "rid": "sensor.website.example.com.page1",
      "manifest": {
        "rid": "sensor.website.example.com.page1",
        "timestamp": "2025-09-09T12:00:00Z",
        "content_hash": "<sha256 hex of the content>",
        "size_bytes": 40,
        "content_type": "text/plain",
        "metadata": {
          "title": "Example Page",
          "url": "https://example.com/page1"
        }
      },
      "contents": {
        "text": "This is the content to be processed..."
      }
    }
  }'
```

#### UPDATE event (content changed)

Send the same shape with `"event_type": "UPDATE"`, the new `contents` and the new `content_hash`. The bridge updates the existing row for the RID in place.

### Endpoints

#### `GET /` - Health check

Returns service status and configuration.

```json
{
  "service": "KOI Event Bridge v2",
  "status": "operational",
  "version": "2.0.0",
  "features": [...],
  "isolated_tables": true
}
```

`GET /health` returns a shorter status object.

#### `POST /process-koi-event` - Process event

Processes a KOI event with deduplication.

**Request body:**

```json
{
  "event_type": "NEW|UPDATE|FORGET",
  "rid": "string",
  "source_node": "string",
  "timestamp": "ISO 8601",
  "bundle": {
    "rid": "string",
    "manifest": {
      "rid": "string",
      "timestamp": "ISO 8601",
      "content_hash": "string",
      "size_bytes": 0,
      "content_type": "string",
      "version": "1.0",
      "metadata": {}
    },
    "contents": {}
  },
  "reason": "string, optional"
}
```

`bundle` may be omitted for `FORGET` events. Text is read from `contents.text`, `contents.content`, `contents.body`, `contents.description`, `contents.html`, or `contents.document.content`. Heartbeat, test and monitoring events are dropped by `src/core/koi_event_filter.py` and return `success: true` with `cid: "filtered"`.

**Response:**

```json
{
  "success": true,
  "rid": "string",
  "cid": "cid:sha256:<content_hash>",
  "chunks_created": 1,
  "embeddings_created": 1,
  "version": 1,
  "previous_version_id": null,
  "error": null
}
```

The status code is 200 on success and 500 on failure.

#### `GET /stats` - Pipeline statistics

Returns document, version, event and embedding counts from `koi_memories` and `koi_embeddings`.

### Embedding server API

`src/core/bge_server.py` listens on port 8090. It returns OpenAI `text-embedding-3-large` embeddings at 1024 dimensions and requires `OPENAI_API_KEY`.

#### `POST /encode` - Generate embedding

**Request** (`text` or `input`):

```json
{
  "text": "content to embed"
}
```

**Response:**

```json
{
  "embedding": [0.123, -0.456, ...],
  "dim": 1024
}
```

## Known gaps

- No test suite. `pytest.ini` is present but there are no tests.
- No Dockerfile.
- No migration runner. Apply `migrations/` by hand.
- The migrations do not create every column the event bridge writes (`is_private`, `access_source`).
- `api/pipeline_metadata_api.py` and `api/koi_content_api.py` hardcode their database connection and do not read `POSTGRES_URL`.
- The production checkout directory is hardcoded in several files, including `scripts/cron_daily_curator.sh`, `scripts/cron_weekly_aggregator.sh`, `api/pipeline_metadata_api.py`, the service units in `systemd/` and `ecosystem.hybrid.config.js`.

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE).
