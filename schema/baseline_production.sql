-- KOI production schema baseline (koi-processor)
--
-- Schema-only snapshot of the 37 KOI tables the code in this repository queries,
-- taken from the Regen production KOI database (PostgreSQL 15) on 2026-10-22.
-- No data. Apply to an empty database to get the schema production runs:
--
--   psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 -f schema/baseline_production.sql
--
-- The files in migrations/ are the historical change log and do not replay
-- cleanly from an empty database. Use this file for new installs.
--
-- Not included: the ElizaOS tables (memories, embeddings, entities, cache) that
-- the event bridge and knowledge MCP server read. ElizaOS creates them.

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

SET search_path = public;

-- Trigger functions
CREATE OR REPLACE FUNCTION public.koi_memories_content_tsv_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.content_tsv := 
    setweight(to_tsvector('english', COALESCE(NEW.content->>'text', '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(NEW.metadata->>'title', '')), 'B') ||
    setweight(to_tsvector('english', COALESCE(NEW.metadata->>'description', '')), 'C');
  RETURN NEW;
END
$function$
;
CREATE OR REPLACE FUNCTION public.update_anchored_metadata_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.update_user_profiles_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$
;

--
-- PostgreSQL database dump
--


-- Dumped from database version 15.15 (Debian 15.15-1.pgdg12+1)
-- Dumped by pg_dump version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: allowed_predicates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.allowed_predicates (
    predicate text NOT NULL,
    description text,
    subject_types text[],
    object_types text[]
);


--
-- Name: anchored_metadata_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.anchored_metadata_records (
    id integer NOT NULL,
    iri text NOT NULL,
    resolver_url text NOT NULL,
    resolved_at timestamp with time zone DEFAULT now() NOT NULL,
    content_hash text NOT NULL,
    payload_size_bytes integer,
    payload_jsonb jsonb NOT NULL,
    http_status integer,
    resolution_time_ms integer,
    last_refresh_at timestamp with time zone,
    refresh_count integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: anchored_metadata_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.anchored_metadata_records_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: anchored_metadata_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.anchored_metadata_records_id_seq OWNED BY public.anchored_metadata_records.id;


--
-- Name: approval_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_history (
    history_id uuid DEFAULT gen_random_uuid() NOT NULL,
    review_id uuid,
    previous_status character varying(50),
    new_status character varying(50),
    changed_by character varying(100),
    notes text,
    changed_at timestamp with time zone DEFAULT now()
);


--
-- Name: auth_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_requests (
    id integer NOT NULL,
    device_code character varying(64) NOT NULL,
    user_email character varying(255),
    status character varying(20) DEFAULT 'pending'::character varying,
    session_token_hash character varying(64),
    created_at timestamp with time zone DEFAULT now(),
    expires_at timestamp with time zone DEFAULT (now() + '00:10:00'::interval),
    authenticated_at timestamp with time zone,
    used_at timestamp with time zone,
    session_token character varying(64),
    user_code character varying(12),
    state_id character varying(64),
    callback_url text
);


--
-- Name: auth_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_requests_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_requests_id_seq OWNED BY public.auth_requests.id;


--
-- Name: canonical_source_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.canonical_source_mappings (
    id integer NOT NULL,
    entity_uri text NOT NULL,
    entity_text text NOT NULL,
    source_type character varying(50) NOT NULL,
    source_url text NOT NULL,
    is_canonical boolean DEFAULT false,
    priority integer DEFAULT 0,
    notes text,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: canonical_source_mappings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.canonical_source_mappings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: canonical_source_mappings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.canonical_source_mappings_id_seq OWNED BY public.canonical_source_mappings.id;


--
-- Name: cat_receipts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cat_receipts (
    rid text NOT NULL,
    type text NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    parent_rid text,
    content_cid text,
    transformation jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: claim_attestations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.claim_attestations (
    id integer NOT NULL,
    attestation_rid text NOT NULL,
    claim_rid text NOT NULL,
    reviewer_uri text NOT NULL,
    verdict text DEFAULT 'pending'::text NOT NULL,
    rationale text,
    evidence_uris text[],
    content_hash text,
    ledger_iri text,
    attest_tx_hash text,
    attest_timestamp timestamp with time zone,
    attestor_address text,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT claim_attestations_verdict_check CHECK ((verdict = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'needs_info'::text])))
);


--
-- Name: claim_attestations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.claim_attestations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: claim_attestations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.claim_attestations_id_seq OWNED BY public.claim_attestations.id;


--
-- Name: claim_state_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.claim_state_log (
    id integer NOT NULL,
    claim_rid text NOT NULL,
    from_state text,
    to_state text NOT NULL,
    actor text,
    reason text,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: claim_state_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.claim_state_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: claim_state_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.claim_state_log_id_seq OWNED BY public.claim_state_log.id;


--
-- Name: claims; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.claims (
    id integer NOT NULL,
    claim_rid text NOT NULL,
    entity_uri text,
    claimant_uri text NOT NULL,
    statement text NOT NULL,
    claim_type text DEFAULT 'ecological'::text NOT NULL,
    verification text DEFAULT 'self_reported'::text NOT NULL,
    source_document text,
    ai_confidence double precision,
    content_hash text,
    ledger_iri text,
    ledger_timestamp timestamp with time zone,
    supersedes_rid text,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_by text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    tx_hash text,
    operator_uri text,
    data_iri text,
    credit_class_id text
);


--
-- Name: claims_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.claims_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: claims_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.claims_id_seq OWNED BY public.claims.id;


--
-- Name: koi_transformation_receipts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.koi_transformation_receipts (
    receipt_id character varying(64) NOT NULL,
    transformation_type character varying(100),
    input_rid character varying(255),
    input_cid character varying(255),
    output_rid character varying(255),
    output_cid character varying(255),
    processor_name character varying(100),
    processor_version character varying(50),
    chunks_created integer DEFAULT 0,
    embeddings_created integer DEFAULT 0,
    entities_extracted integer DEFAULT 0,
    source_sensor character varying(100),
    event_type character varying(50),
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    processing_duration_ms integer,
    jena_activity_uri character varying,
    jena_receipt_uri character varying,
    input_artifact_uri character varying,
    output_artifact_uri character varying,
    stored_in_graph character varying,
    parent_receipt_id character varying
);


--
-- Name: koi_embeddings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.koi_embeddings (
    id integer NOT NULL,
    memory_id uuid NOT NULL,
    dim_384 public.vector(384),
    dim_512 public.vector(512),
    dim_768 public.vector(768),
    dim_1024 public.vector(1024),
    dim_1536 public.vector(1536),
    dim_3072 public.vector(3072),
    created_at timestamp with time zone DEFAULT now(),
    jena_uri character varying,
    jena_embedding_uri character varying
);


--
-- Name: koi_memories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.koi_memories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    rid character varying(500) NOT NULL,
    cid character varying(500),
    version integer DEFAULT 1,
    previous_version_id uuid,
    event_type character varying(20) NOT NULL,
    source_sensor character varying(200) NOT NULL,
    agent_id uuid,
    content jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    superseded_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    published_at timestamp with time zone,
    published_confidence double precision DEFAULT 1.0,
    content_hash character varying(64),
    last_seen_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    source_content_rid character varying,
    is_chunk boolean DEFAULT false,
    parent_document_rid character varying,
    jena_uri character varying,
    jena_graph character varying,
    jena_sync_status character varying DEFAULT 'pending'::character varying,
    jena_synced_at timestamp without time zone,
    content_tsv tsvector,
    is_private boolean DEFAULT false,
    access_source character varying(100),
    CONSTRAINT koi_memories_event_type_check CHECK (((event_type)::text = ANY (ARRAY[('NEW'::character varying)::text, ('UPDATE'::character varying)::text, ('FORGET'::character varying)::text]))),
    CONSTRAINT koi_memories_published_confidence_check CHECK (((published_confidence >= (0)::double precision) AND (published_confidence <= (1)::double precision)))
);


--
-- Name: derivation_allowlist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.derivation_allowlist (
    id integer NOT NULL,
    metric_id text NOT NULL,
    metric_label text NOT NULL,
    json_pointer text NOT NULL,
    unit_pointer text,
    expected_unit text,
    value_type text DEFAULT 'numeric'::text NOT NULL,
    min_value numeric,
    max_value numeric,
    is_active boolean DEFAULT true,
    requires_review boolean DEFAULT false,
    description text,
    data_source text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text
);


--
-- Name: derivation_allowlist_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.derivation_allowlist_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: derivation_allowlist_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.derivation_allowlist_id_seq OWNED BY public.derivation_allowlist.id;


--
-- Name: metadata_derivations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metadata_derivations (
    id integer NOT NULL,
    metadata_record_id integer NOT NULL,
    metric_id text NOT NULL,
    json_pointer text NOT NULL,
    numeric_value numeric,
    string_value text,
    unit text,
    raw_value text,
    unit_source text,
    normalized_to text,
    conversion_factor numeric,
    is_valid boolean DEFAULT true,
    validation_errors jsonb,
    derived_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: document_entity_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_entity_links (
    id integer NOT NULL,
    document_rid text NOT NULL,
    entity_uri text NOT NULL,
    mention_count integer DEFAULT 1,
    context text,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: document_entity_links_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.document_entity_links_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: document_entity_links_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.document_entity_links_id_seq OWNED BY public.document_entity_links.id;


--
-- Name: entity_registry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entity_registry (
    id integer NOT NULL,
    fuseki_uri text NOT NULL,
    entity_text text NOT NULL,
    entity_type text NOT NULL,
    normalized_text text NOT NULL,
    embedding public.vector(1536),
    first_seen_at timestamp without time zone DEFAULT now(),
    last_seen_at timestamp without time zone DEFAULT now(),
    occurrence_count integer DEFAULT 1,
    metadata jsonb DEFAULT '{}'::jsonb,
    ledger_id character varying(50),
    metadata_iri text,
    admin_address character varying(100),
    aliases text[] DEFAULT '{}'::text[],
    jurisdiction character varying(50),
    class_id character varying(50),
    source character varying(50),
    vault_rid text,
    created_at timestamp with time zone DEFAULT now(),
    node_private boolean DEFAULT false,
    first_seen_rid text,
    phonetic_code text,
    wallet_address text
);


--
-- Name: entity_registry_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.entity_registry_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entity_registry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.entity_registry_id_seq OWNED BY public.entity_registry.id;


--
-- Name: entity_relationships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entity_relationships (
    id integer NOT NULL,
    subject_uri text NOT NULL,
    predicate text NOT NULL,
    object_uri text NOT NULL,
    confidence double precision DEFAULT 1.0,
    source text DEFAULT 'vault'::text,
    source_rid text,
    source_field text,
    raw_value text,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    CONSTRAINT entity_relationships_check CHECK ((subject_uri <> object_uri)),
    CONSTRAINT entity_relationships_predicate_check CHECK ((predicate ~ '^[a-z][a-z0-9_]*$'::text))
);


--
-- Name: entity_relationships_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.entity_relationships_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entity_relationships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.entity_relationships_id_seq OWNED BY public.entity_relationships.id;


--
-- Name: entity_rid_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entity_rid_mappings (
    id integer NOT NULL,
    vault_rid text NOT NULL,
    vault_path text NOT NULL,
    canonical_uri text NOT NULL,
    entity_type text,
    name text,
    content_hash text,
    sync_status text DEFAULT 'linked'::text,
    last_synced timestamp without time zone DEFAULT now(),
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT valid_sync_status CHECK ((sync_status = ANY (ARRAY['linked'::text, 'local_only'::text, 'pending_sync'::text, 'conflict'::text])))
);


--
-- Name: entity_rid_mappings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.entity_rid_mappings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entity_rid_mappings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.entity_rid_mappings_id_seq OWNED BY public.entity_rid_mappings.id;


--
-- Name: user_feedback; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_feedback (
    id integer NOT NULL,
    rating integer NOT NULL,
    category character varying(50) NOT NULL,
    task_description text,
    notes text NOT NULL,
    session_context jsonb DEFAULT '{}'::jsonb,
    user_email character varying(255) DEFAULT 'anonymous'::character varying,
    client_version character varying(50),
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT user_feedback_rating_check CHECK (((rating >= 1) AND (rating <= 5))),
    CONSTRAINT valid_category CHECK (((category)::text = ANY ((ARRAY['success'::character varying, 'partial'::character varying, 'bug'::character varying, 'suggestion'::character varying, 'question'::character varying, 'other'::character varying])::text[])))
);


--
-- Name: koi_kg_extractions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.koi_kg_extractions (
    id integer NOT NULL,
    memory_rid character varying(500) NOT NULL,
    extraction_rid character varying(500) NOT NULL,
    extraction_type character varying(50) NOT NULL,
    entities jsonb DEFAULT '[]'::jsonb,
    statements jsonb DEFAULT '[]'::jsonb,
    relations jsonb DEFAULT '[]'::jsonb,
    nanopubs jsonb DEFAULT '[]'::jsonb,
    confidence_score double precision,
    ontology_version character varying(20) DEFAULT 'op-v1.1'::character varying,
    extractor_version character varying(50),
    tokens_consumed integer DEFAULT 0,
    cost_usd numeric(10,6) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT koi_kg_extractions_confidence_score_check CHECK (((confidence_score >= (0)::double precision) AND (confidence_score <= (1)::double precision))),
    CONSTRAINT koi_kg_extractions_extraction_type_check CHECK (((extraction_type)::text = ANY (ARRAY[('passA'::character varying)::text, ('passB'::character varying)::text, ('entity_resolution'::character varying)::text, ('nanopub_creation'::character varying)::text, ('contradiction_detection'::character varying)::text])))
);


--
-- Name: koi_adaptive_extractions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.koi_adaptive_extractions (
    id integer NOT NULL,
    query_log_id text,
    document_rid text,
    extraction_type text,
    extraction_result jsonb,
    confidence_improvement double precision,
    extraction_timestamp timestamp with time zone DEFAULT now(),
    receipt_rid text,
    created_at timestamp with time zone DEFAULT now(),
    cat_receipt_rid text,
    extracted_content jsonb,
    triples_generated integer DEFAULT 0,
    entities_extracted integer DEFAULT 0,
    relationships_extracted integer DEFAULT 0,
    extraction_cost_usd double precision DEFAULT 0.0
);


--
-- Name: koi_adaptive_extractions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.koi_adaptive_extractions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: koi_adaptive_extractions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.koi_adaptive_extractions_id_seq OWNED BY public.koi_adaptive_extractions.id;


--
-- Name: koi_content; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.koi_content (
    rid character varying NOT NULL,
    source_rid character varying,
    content_hash character varying NOT NULL,
    url character varying,
    title character varying,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    raw_content text,
    content_type character varying(50),
    scraped_at timestamp without time zone DEFAULT now(),
    extracted_at timestamp without time zone,
    extraction_version character varying(20) DEFAULT 'v1'::character varying,
    jena_artifact_uri character varying,
    jena_provenance_graph character varying
);


--
-- Name: koi_embeddings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.koi_embeddings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: koi_embeddings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.koi_embeddings_id_seq OWNED BY public.koi_embeddings.id;


--
-- Name: koi_entity_chunk_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.koi_entity_chunk_links (
    id integer NOT NULL,
    entity_name text NOT NULL,
    entity_name_lower text NOT NULL,
    entity_type text NOT NULL,
    entity_uri text,
    chunk_rid text NOT NULL,
    chunk_index integer,
    document_rid text NOT NULL,
    char_offset integer,
    confidence double precision DEFAULT 0.8,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: koi_entity_chunk_links_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.koi_entity_chunk_links_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: koi_entity_chunk_links_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.koi_entity_chunk_links_id_seq OWNED BY public.koi_entity_chunk_links.id;


--
-- Name: koi_kg_extractions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.koi_kg_extractions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: koi_kg_extractions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.koi_kg_extractions_id_seq OWNED BY public.koi_kg_extractions.id;


--
-- Name: koi_memory_chunks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.koi_memory_chunks (
    id integer NOT NULL,
    chunk_rid character varying NOT NULL,
    document_rid character varying NOT NULL,
    source_content_rid character varying,
    chunk_index integer NOT NULL,
    total_chunks integer NOT NULL,
    content jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp without time zone DEFAULT now(),
    jena_chunk_uri character varying,
    embedding public.vector(1536)
);


--
-- Name: koi_memory_chunks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.koi_memory_chunks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: koi_memory_chunks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.koi_memory_chunks_id_seq OWNED BY public.koi_memory_chunks.id;


--
-- Name: koi_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.koi_migrations (
    migration_id text NOT NULL,
    applied_at timestamp with time zone DEFAULT now(),
    checksum text NOT NULL
);


--
-- Name: koi_query_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.koi_query_log (
    id text NOT NULL,
    query_text text,
    user_id text,
    agent_id text,
    confidence_score double precision,
    triggered_extraction boolean,
    created_at timestamp without time zone DEFAULT now(),
    extraction_receipt_rid text,
    result_count integer,
    response_time_ms integer,
    top_result_score double precision,
    query_embedding public.vector(1536)
);


--
-- Name: koi_query_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.koi_query_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: koi_query_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.koi_query_log_id_seq OWNED BY public.koi_query_log.id;


--
-- Name: koi_relationships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.koi_relationships (
    id bigint NOT NULL,
    subject_entity_id integer NOT NULL,
    predicate text NOT NULL,
    object_entity_id integer NOT NULL,
    confidence real,
    last_doc_rid text,
    last_run_id text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    occurrence_count integer DEFAULT 1 NOT NULL,
    first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT koi_relationships_no_self CHECK ((subject_entity_id <> object_entity_id)),
    CONSTRAINT koi_relationships_predicate_format CHECK ((predicate ~ '^[a-z0-9_]+$'::text))
);


--
-- Name: koi_relationships_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.koi_relationships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: koi_relationships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.koi_relationships_id_seq OWNED BY public.koi_relationships.id;


--
-- Name: koi_sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.koi_sources (
    rid character varying NOT NULL,
    type character varying NOT NULL,
    name character varying NOT NULL,
    url character varying,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: metadata_derivations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metadata_derivations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metadata_derivations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metadata_derivations_id_seq OWNED BY public.metadata_derivations.id;


--
-- Name: oauth_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_tokens (
    user_email character varying(255) NOT NULL,
    access_token text NOT NULL,
    refresh_token text,
    token_expiry timestamp with time zone,
    scope text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: pending_relationships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pending_relationships (
    id integer NOT NULL,
    subject_uri text,
    object_uri text,
    predicate text NOT NULL,
    raw_unknown_label text NOT NULL,
    unknown_side text NOT NULL,
    target_type_hint text,
    source text DEFAULT 'vault'::text,
    source_rid text,
    source_field text,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT pending_relationships_check CHECK ((((subject_uri IS NOT NULL) AND (object_uri IS NULL)) OR ((subject_uri IS NULL) AND (object_uri IS NOT NULL)))),
    CONSTRAINT pending_relationships_check1 CHECK ((((unknown_side = 'subject'::text) AND (subject_uri IS NULL) AND (object_uri IS NOT NULL)) OR ((unknown_side = 'object'::text) AND (object_uri IS NULL) AND (subject_uri IS NOT NULL)))),
    CONSTRAINT pending_relationships_unknown_side_check CHECK ((unknown_side = ANY (ARRAY['subject'::text, 'object'::text])))
);


--
-- Name: pending_relationships_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pending_relationships_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pending_relationships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pending_relationships_id_seq OWNED BY public.pending_relationships.id;


--
-- Name: quality_reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quality_reviews (
    review_id uuid DEFAULT gen_random_uuid() NOT NULL,
    content_id character varying(255) NOT NULL,
    content_type character varying(50) NOT NULL,
    content_data jsonb NOT NULL,
    style_score double precision NOT NULL,
    validation_score double precision NOT NULL,
    quality_issues jsonb,
    approval_status character varying(50) NOT NULL,
    reviewer_notes text,
    reviewed_by character varying(100),
    auto_publish_eligible boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    reviewed_at timestamp with time zone,
    published_at timestamp with time zone,
    rolled_back_at timestamp with time zone,
    provenance jsonb DEFAULT '{}'::jsonb
);


--
-- Name: session_chunks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.session_chunks (
    id integer NOT NULL,
    session_rid text NOT NULL,
    session_id text NOT NULL,
    chunk_index integer NOT NULL,
    chunk_text text NOT NULL,
    role text,
    "timestamp" timestamp without time zone,
    embedding public.vector(1536),
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: session_chunks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.session_chunks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: session_chunks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.session_chunks_id_seq OWNED BY public.session_chunks.id;


--
-- Name: session_ingestion_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.session_ingestion_log (
    session_id text NOT NULL,
    transcript_path text NOT NULL,
    project_path text,
    summary text,
    first_prompt text,
    message_count integer DEFAULT 0,
    chunk_count integer DEFAULT 0,
    file_mtime double precision,
    last_ingested_at timestamp without time zone DEFAULT now(),
    created_at timestamp without time zone DEFAULT now(),
    tools_used text[],
    tool_counts jsonb,
    mcp_servers text[],
    files_accessed text[],
    model text,
    cwd text,
    git_branch text
);


--
-- Name: session_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.session_tokens (
    id integer NOT NULL,
    user_email character varying(255) NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    expires_at timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone,
    client_info text,
    token_hash character varying(64)
);


--
-- Name: session_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.session_tokens_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: session_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.session_tokens_id_seq OWNED BY public.session_tokens.id;


--
-- Name: session_tool_usage; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.session_tool_usage (
    id integer NOT NULL,
    session_id text NOT NULL,
    tool_name text NOT NULL,
    call_count integer DEFAULT 1,
    is_mcp boolean DEFAULT false,
    mcp_server text,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: session_tool_usage_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.session_tool_usage_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: session_tool_usage_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.session_tool_usage_id_seq OWNED BY public.session_tool_usage.id;


--
-- Name: task_registry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_registry (
    id integer NOT NULL,
    task_key text NOT NULL,
    uuid text,
    title text NOT NULL,
    status text DEFAULT 'inbox'::text NOT NULL,
    priority text DEFAULT 'medium'::text,
    due_date date,
    start_date date,
    wait_until date,
    context text,
    effort text,
    owner_uri text,
    project_uri text,
    collaborator_uris text[] DEFAULT '{}'::text[],
    blocked_by text[] DEFAULT '{}'::text[],
    source_note text,
    source_type text DEFAULT 'meeting'::text,
    vault_path text,
    tags text[] DEFAULT '{}'::text[],
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    completed_at timestamp without time zone,
    started_at timestamp without time zone,
    triaged_at timestamp without time zone,
    CONSTRAINT task_registry_status_check CHECK ((status = ANY (ARRAY['inbox'::text, 'open'::text, 'in-progress'::text, 'waiting'::text, 'done'::text, 'cancelled'::text])))
);


--
-- Name: task_registry_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.task_registry_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: task_registry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.task_registry_id_seq OWNED BY public.task_registry.id;


--
-- Name: user_feedback_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_feedback_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_feedback_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_feedback_id_seq OWNED BY public.user_feedback.id;


--
-- Name: user_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_profiles (
    id integer NOT NULL,
    email character varying(255) NOT NULL,
    experience_level character varying(20) DEFAULT 'mid'::character varying,
    role character varying(50),
    preferences jsonb DEFAULT '{}'::jsonb,
    managed_by character varying(255),
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    CONSTRAINT valid_experience_level CHECK (((experience_level)::text = ANY ((ARRAY['junior'::character varying, 'mid'::character varying, 'senior'::character varying, 'staff'::character varying, 'principal'::character varying])::text[])))
);


--
-- Name: user_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_profiles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_profiles_id_seq OWNED BY public.user_profiles.id;


--
-- Name: anchored_metadata_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anchored_metadata_records ALTER COLUMN id SET DEFAULT nextval('public.anchored_metadata_records_id_seq'::regclass);


--
-- Name: auth_requests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_requests ALTER COLUMN id SET DEFAULT nextval('public.auth_requests_id_seq'::regclass);


--
-- Name: canonical_source_mappings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.canonical_source_mappings ALTER COLUMN id SET DEFAULT nextval('public.canonical_source_mappings_id_seq'::regclass);


--
-- Name: claim_attestations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_attestations ALTER COLUMN id SET DEFAULT nextval('public.claim_attestations_id_seq'::regclass);


--
-- Name: claim_state_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_state_log ALTER COLUMN id SET DEFAULT nextval('public.claim_state_log_id_seq'::regclass);


--
-- Name: claims id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claims ALTER COLUMN id SET DEFAULT nextval('public.claims_id_seq'::regclass);


--
-- Name: derivation_allowlist id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derivation_allowlist ALTER COLUMN id SET DEFAULT nextval('public.derivation_allowlist_id_seq'::regclass);


--
-- Name: document_entity_links id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_entity_links ALTER COLUMN id SET DEFAULT nextval('public.document_entity_links_id_seq'::regclass);


--
-- Name: entity_registry id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_registry ALTER COLUMN id SET DEFAULT nextval('public.entity_registry_id_seq'::regclass);


--
-- Name: entity_relationships id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_relationships ALTER COLUMN id SET DEFAULT nextval('public.entity_relationships_id_seq'::regclass);


--
-- Name: entity_rid_mappings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_rid_mappings ALTER COLUMN id SET DEFAULT nextval('public.entity_rid_mappings_id_seq'::regclass);


--
-- Name: koi_adaptive_extractions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_adaptive_extractions ALTER COLUMN id SET DEFAULT nextval('public.koi_adaptive_extractions_id_seq'::regclass);


--
-- Name: koi_embeddings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_embeddings ALTER COLUMN id SET DEFAULT nextval('public.koi_embeddings_id_seq'::regclass);


--
-- Name: koi_entity_chunk_links id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_entity_chunk_links ALTER COLUMN id SET DEFAULT nextval('public.koi_entity_chunk_links_id_seq'::regclass);


--
-- Name: koi_kg_extractions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_kg_extractions ALTER COLUMN id SET DEFAULT nextval('public.koi_kg_extractions_id_seq'::regclass);


--
-- Name: koi_memory_chunks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_memory_chunks ALTER COLUMN id SET DEFAULT nextval('public.koi_memory_chunks_id_seq'::regclass);


--
-- Name: koi_query_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_query_log ALTER COLUMN id SET DEFAULT nextval('public.koi_query_log_id_seq'::regclass);


--
-- Name: koi_relationships id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_relationships ALTER COLUMN id SET DEFAULT nextval('public.koi_relationships_id_seq'::regclass);


--
-- Name: metadata_derivations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_derivations ALTER COLUMN id SET DEFAULT nextval('public.metadata_derivations_id_seq'::regclass);


--
-- Name: pending_relationships id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pending_relationships ALTER COLUMN id SET DEFAULT nextval('public.pending_relationships_id_seq'::regclass);


--
-- Name: session_chunks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_chunks ALTER COLUMN id SET DEFAULT nextval('public.session_chunks_id_seq'::regclass);


--
-- Name: session_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_tokens ALTER COLUMN id SET DEFAULT nextval('public.session_tokens_id_seq'::regclass);


--
-- Name: session_tool_usage id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_tool_usage ALTER COLUMN id SET DEFAULT nextval('public.session_tool_usage_id_seq'::regclass);


--
-- Name: task_registry id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_registry ALTER COLUMN id SET DEFAULT nextval('public.task_registry_id_seq'::regclass);


--
-- Name: user_feedback id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_feedback ALTER COLUMN id SET DEFAULT nextval('public.user_feedback_id_seq'::regclass);


--
-- Name: user_profiles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profiles ALTER COLUMN id SET DEFAULT nextval('public.user_profiles_id_seq'::regclass);


--
-- Name: allowed_predicates allowed_predicates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.allowed_predicates
    ADD CONSTRAINT allowed_predicates_pkey PRIMARY KEY (predicate);


--
-- Name: anchored_metadata_records anchored_metadata_records_iri_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anchored_metadata_records
    ADD CONSTRAINT anchored_metadata_records_iri_key UNIQUE (iri);


--
-- Name: anchored_metadata_records anchored_metadata_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anchored_metadata_records
    ADD CONSTRAINT anchored_metadata_records_pkey PRIMARY KEY (id);


--
-- Name: approval_history approval_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_history
    ADD CONSTRAINT approval_history_pkey PRIMARY KEY (history_id);


--
-- Name: auth_requests auth_requests_device_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_requests
    ADD CONSTRAINT auth_requests_device_code_key UNIQUE (device_code);


--
-- Name: auth_requests auth_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_requests
    ADD CONSTRAINT auth_requests_pkey PRIMARY KEY (id);


--
-- Name: canonical_source_mappings canonical_source_mappings_entity_uri_source_url_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.canonical_source_mappings
    ADD CONSTRAINT canonical_source_mappings_entity_uri_source_url_key UNIQUE (entity_uri, source_url);


--
-- Name: canonical_source_mappings canonical_source_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.canonical_source_mappings
    ADD CONSTRAINT canonical_source_mappings_pkey PRIMARY KEY (id);


--
-- Name: cat_receipts cat_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cat_receipts
    ADD CONSTRAINT cat_receipts_pkey PRIMARY KEY (rid);


--
-- Name: claim_attestations claim_attestations_attestation_rid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_attestations
    ADD CONSTRAINT claim_attestations_attestation_rid_key UNIQUE (attestation_rid);


--
-- Name: claim_attestations claim_attestations_claim_rid_reviewer_uri_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_attestations
    ADD CONSTRAINT claim_attestations_claim_rid_reviewer_uri_key UNIQUE (claim_rid, reviewer_uri);


--
-- Name: claim_attestations claim_attestations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_attestations
    ADD CONSTRAINT claim_attestations_pkey PRIMARY KEY (id);


--
-- Name: claim_state_log claim_state_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_state_log
    ADD CONSTRAINT claim_state_log_pkey PRIMARY KEY (id);


--
-- Name: claims claims_claim_rid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claims
    ADD CONSTRAINT claims_claim_rid_key UNIQUE (claim_rid);


--
-- Name: claims claims_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claims
    ADD CONSTRAINT claims_pkey PRIMARY KEY (id);


--
-- Name: derivation_allowlist derivation_allowlist_metric_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derivation_allowlist
    ADD CONSTRAINT derivation_allowlist_metric_id_key UNIQUE (metric_id);


--
-- Name: derivation_allowlist derivation_allowlist_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derivation_allowlist
    ADD CONSTRAINT derivation_allowlist_pkey PRIMARY KEY (id);


--
-- Name: document_entity_links document_entity_links_document_rid_entity_uri_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_entity_links
    ADD CONSTRAINT document_entity_links_document_rid_entity_uri_key UNIQUE (document_rid, entity_uri);


--
-- Name: document_entity_links document_entity_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_entity_links
    ADD CONSTRAINT document_entity_links_pkey PRIMARY KEY (id);


--
-- Name: entity_registry entity_registry_fuseki_uri_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_registry
    ADD CONSTRAINT entity_registry_fuseki_uri_key UNIQUE (fuseki_uri);


--
-- Name: entity_registry entity_registry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_registry
    ADD CONSTRAINT entity_registry_pkey PRIMARY KEY (id);


--
-- Name: entity_registry entity_registry_text_type_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_registry
    ADD CONSTRAINT entity_registry_text_type_key UNIQUE (normalized_text, entity_type);


--
-- Name: entity_relationships entity_relationships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_relationships
    ADD CONSTRAINT entity_relationships_pkey PRIMARY KEY (id);


--
-- Name: entity_relationships entity_relationships_subject_uri_predicate_object_uri_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_relationships
    ADD CONSTRAINT entity_relationships_subject_uri_predicate_object_uri_key UNIQUE (subject_uri, predicate, object_uri);


--
-- Name: entity_rid_mappings entity_rid_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_rid_mappings
    ADD CONSTRAINT entity_rid_mappings_pkey PRIMARY KEY (id);


--
-- Name: entity_rid_mappings entity_rid_mappings_vault_rid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_rid_mappings
    ADD CONSTRAINT entity_rid_mappings_vault_rid_key UNIQUE (vault_rid);


--
-- Name: koi_adaptive_extractions koi_adaptive_extractions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_adaptive_extractions
    ADD CONSTRAINT koi_adaptive_extractions_pkey PRIMARY KEY (id);


--
-- Name: koi_content koi_content_content_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_content
    ADD CONSTRAINT koi_content_content_hash_key UNIQUE (content_hash);


--
-- Name: koi_content koi_content_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_content
    ADD CONSTRAINT koi_content_pkey PRIMARY KEY (rid);


--
-- Name: koi_embeddings koi_embeddings_memory_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_embeddings
    ADD CONSTRAINT koi_embeddings_memory_id_key UNIQUE (memory_id);


--
-- Name: koi_embeddings koi_embeddings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_embeddings
    ADD CONSTRAINT koi_embeddings_pkey PRIMARY KEY (id);


--
-- Name: koi_entity_chunk_links koi_entity_chunk_links_entity_name_lower_chunk_rid_char_off_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_entity_chunk_links
    ADD CONSTRAINT koi_entity_chunk_links_entity_name_lower_chunk_rid_char_off_key UNIQUE (entity_name_lower, chunk_rid, char_offset);


--
-- Name: koi_entity_chunk_links koi_entity_chunk_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_entity_chunk_links
    ADD CONSTRAINT koi_entity_chunk_links_pkey PRIMARY KEY (id);


--
-- Name: koi_kg_extractions koi_kg_extractions_extraction_rid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_kg_extractions
    ADD CONSTRAINT koi_kg_extractions_extraction_rid_key UNIQUE (extraction_rid);


--
-- Name: koi_kg_extractions koi_kg_extractions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_kg_extractions
    ADD CONSTRAINT koi_kg_extractions_pkey PRIMARY KEY (id);


--
-- Name: koi_memories koi_memories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_memories
    ADD CONSTRAINT koi_memories_pkey PRIMARY KEY (id);


--
-- Name: koi_memories koi_memories_rid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_memories
    ADD CONSTRAINT koi_memories_rid_key UNIQUE (rid);


--
-- Name: koi_memories koi_memories_rid_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_memories
    ADD CONSTRAINT koi_memories_rid_version_key UNIQUE (rid, version);


--
-- Name: koi_memory_chunks koi_memory_chunks_chunk_rid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_memory_chunks
    ADD CONSTRAINT koi_memory_chunks_chunk_rid_key UNIQUE (chunk_rid);


--
-- Name: koi_memory_chunks koi_memory_chunks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_memory_chunks
    ADD CONSTRAINT koi_memory_chunks_pkey PRIMARY KEY (id);


--
-- Name: koi_migrations koi_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_migrations
    ADD CONSTRAINT koi_migrations_pkey PRIMARY KEY (migration_id);


--
-- Name: koi_query_log koi_query_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_query_log
    ADD CONSTRAINT koi_query_log_pkey PRIMARY KEY (id);


--
-- Name: koi_relationships koi_relationships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_relationships
    ADD CONSTRAINT koi_relationships_pkey PRIMARY KEY (id);


--
-- Name: koi_relationships koi_relationships_triple_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_relationships
    ADD CONSTRAINT koi_relationships_triple_uniq UNIQUE (subject_entity_id, predicate, object_entity_id);


--
-- Name: koi_sources koi_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_sources
    ADD CONSTRAINT koi_sources_pkey PRIMARY KEY (rid);


--
-- Name: koi_transformation_receipts koi_transformation_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_transformation_receipts
    ADD CONSTRAINT koi_transformation_receipts_pkey PRIMARY KEY (receipt_id);


--
-- Name: metadata_derivations metadata_derivations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_derivations
    ADD CONSTRAINT metadata_derivations_pkey PRIMARY KEY (id);


--
-- Name: oauth_tokens oauth_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_tokens
    ADD CONSTRAINT oauth_tokens_pkey PRIMARY KEY (user_email);


--
-- Name: pending_relationships pending_relationships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pending_relationships
    ADD CONSTRAINT pending_relationships_pkey PRIMARY KEY (id);


--
-- Name: quality_reviews quality_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quality_reviews
    ADD CONSTRAINT quality_reviews_pkey PRIMARY KEY (review_id);


--
-- Name: session_chunks session_chunks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_chunks
    ADD CONSTRAINT session_chunks_pkey PRIMARY KEY (id);


--
-- Name: session_chunks session_chunks_session_id_chunk_index_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_chunks
    ADD CONSTRAINT session_chunks_session_id_chunk_index_key UNIQUE (session_id, chunk_index);


--
-- Name: session_ingestion_log session_ingestion_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_ingestion_log
    ADD CONSTRAINT session_ingestion_log_pkey PRIMARY KEY (session_id);


--
-- Name: session_tokens session_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_tokens
    ADD CONSTRAINT session_tokens_pkey PRIMARY KEY (id);


--
-- Name: session_tool_usage session_tool_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_tool_usage
    ADD CONSTRAINT session_tool_usage_pkey PRIMARY KEY (id);


--
-- Name: session_tool_usage session_tool_usage_session_id_tool_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_tool_usage
    ADD CONSTRAINT session_tool_usage_session_id_tool_name_key UNIQUE (session_id, tool_name);


--
-- Name: task_registry task_registry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_registry
    ADD CONSTRAINT task_registry_pkey PRIMARY KEY (id);


--
-- Name: task_registry task_registry_task_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_registry
    ADD CONSTRAINT task_registry_task_key_key UNIQUE (task_key);


--
-- Name: metadata_derivations unique_metric_per_record; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_derivations
    ADD CONSTRAINT unique_metric_per_record UNIQUE (metadata_record_id, metric_id);


--
-- Name: user_feedback user_feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_feedback
    ADD CONSTRAINT user_feedback_pkey PRIMARY KEY (id);


--
-- Name: user_profiles user_profiles_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_email_key UNIQUE (email);


--
-- Name: user_profiles user_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_pkey PRIMARY KEY (id);


--
-- Name: entity_registry_metadata_code_uri_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX entity_registry_metadata_code_uri_idx ON public.entity_registry USING btree (((metadata ->> 'code_uri'::text)));


--
-- Name: idx_anchored_metadata_content_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_anchored_metadata_content_hash ON public.anchored_metadata_records USING btree (content_hash);


--
-- Name: idx_anchored_metadata_iri; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_anchored_metadata_iri ON public.anchored_metadata_records USING btree (iri);


--
-- Name: idx_anchored_metadata_resolved_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_anchored_metadata_resolved_at ON public.anchored_metadata_records USING btree (resolved_at DESC);


--
-- Name: idx_attestations_claim; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attestations_claim ON public.claim_attestations USING btree (claim_rid);


--
-- Name: idx_attestations_reviewer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attestations_reviewer ON public.claim_attestations USING btree (reviewer_uri);


--
-- Name: idx_attestations_verdict; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attestations_verdict ON public.claim_attestations USING btree (verdict);


--
-- Name: idx_auth_requests_device_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_requests_device_code ON public.auth_requests USING btree (device_code);


--
-- Name: idx_auth_requests_expires; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_requests_expires ON public.auth_requests USING btree (expires_at);


--
-- Name: idx_auth_requests_state_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_requests_state_id ON public.auth_requests USING btree (state_id);


--
-- Name: idx_auth_requests_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_requests_status ON public.auth_requests USING btree (status);


--
-- Name: idx_auth_requests_user_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_requests_user_code ON public.auth_requests USING btree (user_code);


--
-- Name: idx_cat_content_cid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cat_content_cid ON public.cat_receipts USING btree (content_cid);


--
-- Name: idx_cat_parent_rid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cat_parent_rid ON public.cat_receipts USING btree (parent_rid);


--
-- Name: idx_cat_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cat_timestamp ON public.cat_receipts USING btree ("timestamp");


--
-- Name: idx_cat_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cat_type ON public.cat_receipts USING btree (type);


--
-- Name: idx_chunks_content_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chunks_content_source ON public.koi_memory_chunks USING btree (source_content_rid);


--
-- Name: idx_chunks_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chunks_created ON public.koi_memory_chunks USING btree (created_at DESC);


--
-- Name: idx_chunks_document; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chunks_document ON public.koi_memory_chunks USING btree (document_rid);


--
-- Name: idx_claim_state_log_rid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claim_state_log_rid ON public.claim_state_log USING btree (claim_rid);


--
-- Name: idx_claims_claimant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claims_claimant ON public.claims USING btree (claimant_uri);


--
-- Name: idx_claims_credit_class; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claims_credit_class ON public.claims USING btree (credit_class_id) WHERE (credit_class_id IS NOT NULL);


--
-- Name: idx_claims_data_iri; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_claims_data_iri ON public.claims USING btree (data_iri) WHERE (data_iri IS NOT NULL);


--
-- Name: idx_claims_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claims_entity ON public.claims USING btree (entity_uri);


--
-- Name: idx_claims_rid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claims_rid ON public.claims USING btree (claim_rid);


--
-- Name: idx_claims_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claims_type ON public.claims USING btree (claim_type);


--
-- Name: idx_claims_verification; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claims_verification ON public.claims USING btree (verification);


--
-- Name: idx_csm_entity_uri; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_csm_entity_uri ON public.canonical_source_mappings USING btree (entity_uri);


--
-- Name: idx_csm_one_canonical_per_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_csm_one_canonical_per_entity ON public.canonical_source_mappings USING btree (entity_uri) WHERE (is_canonical = true);


--
-- Name: idx_derivations_is_valid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_derivations_is_valid ON public.metadata_derivations USING btree (is_valid) WHERE (is_valid = true);


--
-- Name: idx_derivations_metadata_record; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_derivations_metadata_record ON public.metadata_derivations USING btree (metadata_record_id);


--
-- Name: idx_derivations_metric_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_derivations_metric_id ON public.metadata_derivations USING btree (metric_id);


--
-- Name: idx_entity_aliases_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entity_aliases_gin ON public.entity_registry USING gin (aliases);


--
-- Name: idx_entity_exact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entity_exact ON public.entity_registry USING btree (normalized_text, entity_type);


--
-- Name: idx_entity_first_seen; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entity_first_seen ON public.entity_registry USING btree (first_seen_at DESC);


--
-- Name: idx_entity_links_chunk; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entity_links_chunk ON public.koi_entity_chunk_links USING btree (chunk_rid);


--
-- Name: idx_entity_links_document; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entity_links_document ON public.koi_entity_chunk_links USING btree (document_rid);


--
-- Name: idx_entity_links_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entity_links_name ON public.koi_entity_chunk_links USING btree (entity_name_lower);


--
-- Name: idx_entity_links_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entity_links_type ON public.koi_entity_chunk_links USING btree (entity_type);


--
-- Name: idx_entity_links_uri; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entity_links_uri ON public.koi_entity_chunk_links USING btree (entity_uri);


--
-- Name: idx_entity_registry_admin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entity_registry_admin ON public.entity_registry USING btree (admin_address) WHERE (admin_address IS NOT NULL);


--
-- Name: idx_entity_registry_class_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entity_registry_class_id ON public.entity_registry USING btree (class_id) WHERE (class_id IS NOT NULL);


--
-- Name: idx_entity_registry_ledger_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entity_registry_ledger_id ON public.entity_registry USING btree (ledger_id) WHERE (ledger_id IS NOT NULL);


--
-- Name: idx_entity_registry_normalized; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entity_registry_normalized ON public.entity_registry USING btree (normalized_text);


--
-- Name: idx_entity_registry_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entity_registry_source ON public.entity_registry USING btree (source) WHERE (source IS NOT NULL);


--
-- Name: idx_entity_registry_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entity_registry_type ON public.entity_registry USING btree (entity_type);


--
-- Name: idx_entity_uri; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entity_uri ON public.entity_registry USING btree (fuseki_uri);


--
-- Name: idx_entity_vector; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entity_vector ON public.entity_registry USING hnsw (embedding public.vector_cosine_ops) WITH (m='16', ef_construction='64');


--
-- Name: idx_entity_wallet; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_entity_wallet ON public.entity_registry USING btree (wallet_address) WHERE (wallet_address IS NOT NULL);


--
-- Name: idx_extraction_cat_receipt; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_extraction_cat_receipt ON public.koi_adaptive_extractions USING btree (cat_receipt_rid) WHERE (cat_receipt_rid IS NOT NULL);


--
-- Name: idx_extraction_document; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_extraction_document ON public.koi_adaptive_extractions USING btree (document_rid);


--
-- Name: idx_extraction_query; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_extraction_query ON public.koi_adaptive_extractions USING btree (query_log_id);


--
-- Name: idx_extraction_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_extraction_timestamp ON public.koi_adaptive_extractions USING btree (extraction_timestamp DESC);


--
-- Name: idx_feedback_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_feedback_category ON public.user_feedback USING btree (category);


--
-- Name: idx_feedback_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_feedback_created_at ON public.user_feedback USING btree (created_at DESC);


--
-- Name: idx_feedback_rating; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_feedback_rating ON public.user_feedback USING btree (rating);


--
-- Name: idx_kg_confidence; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kg_confidence ON public.koi_kg_extractions USING btree (confidence_score DESC);


--
-- Name: idx_kg_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kg_created_at ON public.koi_kg_extractions USING btree (created_at DESC);


--
-- Name: idx_kg_entities_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kg_entities_gin ON public.koi_kg_extractions USING gin (entities);


--
-- Name: idx_kg_extraction_rid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kg_extraction_rid ON public.koi_kg_extractions USING btree (extraction_rid);


--
-- Name: idx_kg_extraction_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kg_extraction_type ON public.koi_kg_extractions USING btree (extraction_type);


--
-- Name: idx_kg_memory_rid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kg_memory_rid ON public.koi_kg_extractions USING btree (memory_rid);


--
-- Name: idx_kg_nanopubs_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kg_nanopubs_gin ON public.koi_kg_extractions USING gin (nanopubs);


--
-- Name: idx_kg_ontology_version; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kg_ontology_version ON public.koi_kg_extractions USING btree (ontology_version);


--
-- Name: idx_kg_relations_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kg_relations_gin ON public.koi_kg_extractions USING gin (relations);


--
-- Name: idx_kg_statements_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kg_statements_gin ON public.koi_kg_extractions USING gin (statements);


--
-- Name: idx_koi_content_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_content_hash ON public.koi_content USING btree (content_hash);


--
-- Name: idx_koi_content_scraped; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_content_scraped ON public.koi_content USING btree (scraped_at);


--
-- Name: idx_koi_content_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_content_source ON public.koi_content USING btree (source_rid);


--
-- Name: idx_koi_content_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_content_type ON public.koi_content USING btree (content_type);


--
-- Name: idx_koi_embeddings_dim_1024; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_embeddings_dim_1024 ON public.koi_embeddings USING hnsw (dim_1024 public.vector_cosine_ops) WITH (m='16', ef_construction='64');


--
-- Name: idx_koi_embeddings_dim_1536; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_embeddings_dim_1536 ON public.koi_embeddings USING ivfflat (dim_1536 public.vector_cosine_ops) WITH (lists='100');


--
-- Name: idx_koi_embeddings_dim_768; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_embeddings_dim_768 ON public.koi_embeddings USING ivfflat (dim_768 public.vector_cosine_ops) WITH (lists='100');


--
-- Name: idx_koi_memories_access_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_memories_access_source ON public.koi_memories USING btree (access_source);


--
-- Name: idx_koi_memories_active_privacy; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_memories_active_privacy ON public.koi_memories USING btree (superseded_at, is_private) WHERE (superseded_at IS NULL);


--
-- Name: idx_koi_memories_agent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_memories_agent_id ON public.koi_memories USING btree (agent_id);


--
-- Name: idx_koi_memories_cid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_memories_cid ON public.koi_memories USING btree (cid);


--
-- Name: idx_koi_memories_content_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_memories_content_hash ON public.koi_memories USING btree (content_hash) WHERE (content_hash IS NOT NULL);


--
-- Name: idx_koi_memories_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_memories_created_at ON public.koi_memories USING btree (created_at DESC);


--
-- Name: idx_koi_memories_daily_curator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_memories_daily_curator ON public.koi_memories USING btree (published_at DESC, source_sensor, event_type) WHERE ((published_at IS NOT NULL) AND (superseded_at IS NULL));


--
-- Name: idx_koi_memories_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_memories_event_type ON public.koi_memories USING btree (event_type);


--
-- Name: idx_koi_memories_is_private; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_memories_is_private ON public.koi_memories USING btree (is_private);


--
-- Name: idx_koi_memories_published_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_memories_published_at ON public.koi_memories USING btree (published_at DESC) WHERE (published_at IS NOT NULL);


--
-- Name: idx_koi_memories_rid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_memories_rid ON public.koi_memories USING btree (rid);


--
-- Name: idx_koi_memories_source_sensor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_memories_source_sensor ON public.koi_memories USING btree (source_sensor);


--
-- Name: idx_koi_memories_superseded; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_memories_superseded ON public.koi_memories USING btree (superseded_at) WHERE (superseded_at IS NOT NULL);


--
-- Name: idx_koi_memories_version; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_memories_version ON public.koi_memories USING btree (rid, version DESC);


--
-- Name: idx_koi_receipts_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_receipts_created_at ON public.koi_transformation_receipts USING btree (created_at DESC);


--
-- Name: idx_koi_receipts_input_rid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_receipts_input_rid ON public.koi_transformation_receipts USING btree (input_rid);


--
-- Name: idx_koi_receipts_output_rid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_receipts_output_rid ON public.koi_transformation_receipts USING btree (output_rid);


--
-- Name: idx_koi_receipts_transformation_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_receipts_transformation_type ON public.koi_transformation_receipts USING btree (transformation_type);


--
-- Name: idx_koi_sources_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_koi_sources_type ON public.koi_sources USING btree (type);


--
-- Name: idx_memories_content_hash_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memories_content_hash_active ON public.koi_memories USING btree (content_hash) WHERE ((superseded_at IS NULL) AND (content_hash IS NOT NULL));


--
-- Name: idx_memories_jena_sync; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memories_jena_sync ON public.koi_memories USING btree (jena_sync_status);


--
-- Name: idx_memories_jena_uri; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memories_jena_uri ON public.koi_memories USING btree (jena_uri);


--
-- Name: idx_oauth_tokens_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_oauth_tokens_email ON public.oauth_tokens USING btree (user_email);


--
-- Name: idx_pending_source_rid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pending_source_rid ON public.pending_relationships USING btree (source_rid);


--
-- Name: idx_pending_unique_edge; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_pending_unique_edge ON public.pending_relationships USING btree (COALESCE(subject_uri, ''::text), COALESCE(object_uri, ''::text), predicate, raw_unknown_label, unknown_side);


--
-- Name: idx_pending_unknown_label; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pending_unknown_label ON public.pending_relationships USING btree (raw_unknown_label);


--
-- Name: idx_pending_unknown_label_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pending_unknown_label_trgm ON public.pending_relationships USING gin (raw_unknown_label public.gin_trgm_ops);


--
-- Name: idx_query_agent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_query_agent ON public.koi_query_log USING btree (agent_id);


--
-- Name: idx_query_confidence; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_query_confidence ON public.koi_query_log USING btree (confidence_score);


--
-- Name: idx_query_extraction; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_query_extraction ON public.koi_query_log USING btree (triggered_extraction) WHERE (triggered_extraction = true);


--
-- Name: idx_query_low_confidence; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_query_low_confidence ON public.koi_query_log USING btree (confidence_score) WHERE (confidence_score < (0.7)::double precision);


--
-- Name: idx_query_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_query_user ON public.koi_query_log USING btree (user_id);


--
-- Name: idx_receipts_jena; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_receipts_jena ON public.koi_transformation_receipts USING btree (jena_receipt_uri);


--
-- Name: idx_rel_object; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rel_object ON public.entity_relationships USING btree (object_uri);


--
-- Name: idx_rel_object_predicate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rel_object_predicate ON public.entity_relationships USING btree (object_uri, predicate);


--
-- Name: idx_rel_source_rid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rel_source_rid ON public.entity_relationships USING btree (source_rid);


--
-- Name: idx_rel_subject; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rel_subject ON public.entity_relationships USING btree (subject_uri);


--
-- Name: idx_rel_subject_predicate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rel_subject_predicate ON public.entity_relationships USING btree (subject_uri, predicate);


--
-- Name: idx_reviews_content; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reviews_content ON public.quality_reviews USING btree (content_id);


--
-- Name: idx_reviews_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reviews_date ON public.quality_reviews USING btree (created_at);


--
-- Name: idx_reviews_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reviews_status ON public.quality_reviews USING btree (approval_status);


--
-- Name: idx_rid_mappings_canonical; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rid_mappings_canonical ON public.entity_rid_mappings USING btree (canonical_uri);


--
-- Name: idx_rid_mappings_sync_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rid_mappings_sync_status ON public.entity_rid_mappings USING btree (sync_status);


--
-- Name: idx_rid_mappings_vault_path; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rid_mappings_vault_path ON public.entity_rid_mappings USING btree (vault_path);


--
-- Name: idx_session_chunks_embedding; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_chunks_embedding ON public.session_chunks USING hnsw (embedding public.vector_cosine_ops);


--
-- Name: idx_session_chunks_rid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_chunks_rid ON public.session_chunks USING btree (session_rid);


--
-- Name: idx_session_chunks_session_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_chunks_session_id ON public.session_chunks USING btree (session_id);


--
-- Name: idx_session_tokens_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_tokens_email ON public.session_tokens USING btree (user_email);


--
-- Name: idx_session_tokens_expires; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_tokens_expires ON public.session_tokens USING btree (expires_at);


--
-- Name: idx_session_tokens_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_tokens_hash ON public.session_tokens USING btree (token_hash);


--
-- Name: idx_session_tool_usage_mcp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_tool_usage_mcp ON public.session_tool_usage USING btree (mcp_server) WHERE (mcp_server IS NOT NULL);


--
-- Name: idx_session_tool_usage_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_tool_usage_session ON public.session_tool_usage USING btree (session_id);


--
-- Name: idx_session_tool_usage_tool; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_tool_usage_tool ON public.session_tool_usage USING btree (tool_name);


--
-- Name: idx_task_due_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_due_date ON public.task_registry USING btree (due_date);


--
-- Name: idx_task_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_owner ON public.task_registry USING btree (owner_uri);


--
-- Name: idx_task_project; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_project ON public.task_registry USING btree (project_uri);


--
-- Name: idx_task_source_note; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_source_note ON public.task_registry USING btree (source_note);


--
-- Name: idx_task_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_status ON public.task_registry USING btree (status);


--
-- Name: idx_transform_receipts_code_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transform_receipts_code_entity ON public.koi_transformation_receipts USING btree (transformation_type) WHERE ((transformation_type)::text = 'github_to_code_entity'::text);


--
-- Name: idx_transform_receipts_code_relationship; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transform_receipts_code_relationship ON public.koi_transformation_receipts USING btree (transformation_type) WHERE ((transformation_type)::text = 'code_entity_to_relationship'::text);


--
-- Name: idx_transform_receipts_commit; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transform_receipts_commit ON public.koi_transformation_receipts USING btree (input_cid) WHERE ((transformation_type)::text = 'github_to_code_entity'::text);


--
-- Name: idx_transform_receipts_file; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transform_receipts_file ON public.koi_transformation_receipts USING btree (((metadata ->> 'file_path'::text))) WHERE ((transformation_type)::text = 'github_to_code_entity'::text);


--
-- Name: idx_transform_receipts_metadata_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transform_receipts_metadata_gin ON public.koi_transformation_receipts USING gin (metadata);


--
-- Name: idx_transform_receipts_repo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transform_receipts_repo ON public.koi_transformation_receipts USING btree (((metadata ->> 'repo'::text))) WHERE ((transformation_type)::text = 'github_to_code_entity'::text);


--
-- Name: idx_user_profiles_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_profiles_email ON public.user_profiles USING btree (email);


--
-- Name: idx_user_profiles_managed_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_profiles_managed_by ON public.user_profiles USING btree (managed_by);


--
-- Name: koi_memories_content_tsv_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX koi_memories_content_tsv_idx ON public.koi_memories USING gin (content_tsv);


--
-- Name: koi_relationships_last_doc_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX koi_relationships_last_doc_idx ON public.koi_relationships USING btree (last_doc_rid);


--
-- Name: koi_relationships_object_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX koi_relationships_object_idx ON public.koi_relationships USING btree (object_entity_id);


--
-- Name: koi_relationships_pred_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX koi_relationships_pred_idx ON public.koi_relationships USING btree (predicate);


--
-- Name: koi_relationships_subject_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX koi_relationships_subject_idx ON public.koi_relationships USING btree (subject_entity_id);


--
-- Name: anchored_metadata_records anchored_metadata_updated_at_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER anchored_metadata_updated_at_trigger BEFORE UPDATE ON public.anchored_metadata_records FOR EACH ROW EXECUTE FUNCTION public.update_anchored_metadata_updated_at();


--
-- Name: derivation_allowlist derivation_allowlist_updated_at_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER derivation_allowlist_updated_at_trigger BEFORE UPDATE ON public.derivation_allowlist FOR EACH ROW EXECUTE FUNCTION public.update_anchored_metadata_updated_at();


--
-- Name: koi_memories koi_memories_content_tsv_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER koi_memories_content_tsv_update BEFORE INSERT OR UPDATE ON public.koi_memories FOR EACH ROW EXECUTE FUNCTION public.koi_memories_content_tsv_trigger();


--
-- Name: user_profiles trigger_user_profiles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_user_profiles_updated_at BEFORE UPDATE ON public.user_profiles FOR EACH ROW EXECUTE FUNCTION public.update_user_profiles_updated_at();


--
-- Name: approval_history approval_history_review_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_history
    ADD CONSTRAINT approval_history_review_id_fkey FOREIGN KEY (review_id) REFERENCES public.quality_reviews(review_id);


--
-- Name: cat_receipts cat_receipts_parent_rid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cat_receipts
    ADD CONSTRAINT cat_receipts_parent_rid_fkey FOREIGN KEY (parent_rid) REFERENCES public.cat_receipts(rid);


--
-- Name: claim_attestations claim_attestations_claim_rid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_attestations
    ADD CONSTRAINT claim_attestations_claim_rid_fkey FOREIGN KEY (claim_rid) REFERENCES public.claims(claim_rid);


--
-- Name: claim_attestations claim_attestations_reviewer_uri_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_attestations
    ADD CONSTRAINT claim_attestations_reviewer_uri_fkey FOREIGN KEY (reviewer_uri) REFERENCES public.entity_registry(fuseki_uri);


--
-- Name: claims claims_operator_uri_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claims
    ADD CONSTRAINT claims_operator_uri_fkey FOREIGN KEY (operator_uri) REFERENCES public.entity_registry(fuseki_uri);


--
-- Name: koi_memory_chunks fk_document_rid; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_memory_chunks
    ADD CONSTRAINT fk_document_rid FOREIGN KEY (document_rid) REFERENCES public.koi_memories(rid) ON DELETE CASCADE;


--
-- Name: pending_relationships fk_pending_object; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pending_relationships
    ADD CONSTRAINT fk_pending_object FOREIGN KEY (object_uri) REFERENCES public.entity_registry(fuseki_uri) ON DELETE CASCADE;


--
-- Name: pending_relationships fk_pending_predicate; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pending_relationships
    ADD CONSTRAINT fk_pending_predicate FOREIGN KEY (predicate) REFERENCES public.allowed_predicates(predicate);


--
-- Name: pending_relationships fk_pending_subject; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pending_relationships
    ADD CONSTRAINT fk_pending_subject FOREIGN KEY (subject_uri) REFERENCES public.entity_registry(fuseki_uri) ON DELETE CASCADE;


--
-- Name: entity_relationships fk_rel_object; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_relationships
    ADD CONSTRAINT fk_rel_object FOREIGN KEY (object_uri) REFERENCES public.entity_registry(fuseki_uri) ON DELETE CASCADE;


--
-- Name: entity_relationships fk_rel_predicate; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_relationships
    ADD CONSTRAINT fk_rel_predicate FOREIGN KEY (predicate) REFERENCES public.allowed_predicates(predicate);


--
-- Name: entity_relationships fk_rel_subject; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_relationships
    ADD CONSTRAINT fk_rel_subject FOREIGN KEY (subject_uri) REFERENCES public.entity_registry(fuseki_uri) ON DELETE CASCADE;


--
-- Name: koi_adaptive_extractions koi_adaptive_extractions_query_log_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_adaptive_extractions
    ADD CONSTRAINT koi_adaptive_extractions_query_log_id_fkey FOREIGN KEY (query_log_id) REFERENCES public.koi_query_log(id);


--
-- Name: koi_content koi_content_source_rid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_content
    ADD CONSTRAINT koi_content_source_rid_fkey FOREIGN KEY (source_rid) REFERENCES public.koi_sources(rid) ON DELETE CASCADE;


--
-- Name: koi_embeddings koi_embeddings_memory_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_embeddings
    ADD CONSTRAINT koi_embeddings_memory_id_fkey FOREIGN KEY (memory_id) REFERENCES public.koi_memories(id) ON DELETE CASCADE;


--
-- Name: koi_memories koi_memories_parent_document_rid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_memories
    ADD CONSTRAINT koi_memories_parent_document_rid_fkey FOREIGN KEY (parent_document_rid) REFERENCES public.koi_memories(rid);


--
-- Name: koi_memories koi_memories_previous_version_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_memories
    ADD CONSTRAINT koi_memories_previous_version_id_fkey FOREIGN KEY (previous_version_id) REFERENCES public.koi_memories(id);


--
-- Name: koi_memories koi_memories_source_content_rid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_memories
    ADD CONSTRAINT koi_memories_source_content_rid_fkey FOREIGN KEY (source_content_rid) REFERENCES public.koi_content(rid);


--
-- Name: koi_memory_chunks koi_memory_chunks_source_content_rid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_memory_chunks
    ADD CONSTRAINT koi_memory_chunks_source_content_rid_fkey FOREIGN KEY (source_content_rid) REFERENCES public.koi_content(rid);


--
-- Name: koi_relationships koi_relationships_object_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_relationships
    ADD CONSTRAINT koi_relationships_object_entity_id_fkey FOREIGN KEY (object_entity_id) REFERENCES public.entity_registry(id) ON DELETE CASCADE;


--
-- Name: koi_relationships koi_relationships_subject_entity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.koi_relationships
    ADD CONSTRAINT koi_relationships_subject_entity_id_fkey FOREIGN KEY (subject_entity_id) REFERENCES public.entity_registry(id) ON DELETE CASCADE;


--
-- Name: metadata_derivations metadata_derivations_metadata_record_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_derivations
    ADD CONSTRAINT metadata_derivations_metadata_record_id_fkey FOREIGN KEY (metadata_record_id) REFERENCES public.anchored_metadata_records(id) ON DELETE CASCADE;


--
-- Name: session_tool_usage session_tool_usage_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_tool_usage
    ADD CONSTRAINT session_tool_usage_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.session_ingestion_log(session_id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--
