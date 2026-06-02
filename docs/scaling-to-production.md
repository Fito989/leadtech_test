# Scaling to Production

This prototype is intentionally right-sized for the task: ~25–30 CVs, an in-memory vector index, a single local backend, synthetic data, and free-tier models. This document describes what would change to run it as a **massive, real-world product** — screening millions of real CVs for many organisations — and why.

The format is **current (prototype) → at scale**, so the trade-offs are explicit.

---

## 1. Retrieval & vector store
**Current:** all section embeddings in a JSON file, loaded into memory, brute-force cosine in Dart.

**At scale:**
- Move to a **dedicated vector database** with ANN indexing (HNSW/IVF) — e.g. **Qdrant, Pinecone, Weaviate, Milvus**, or **Postgres + pgvector** if you want one datastore. Brute-force is fine for hundreds of vectors; it's hopeless at hundreds of millions.
- **Hybrid search**: combine dense (embedding) retrieval with sparse keyword/BM25 retrieval, then fuse (e.g. Reciprocal Rank Fusion). Pure vector search misses exact terms ("AWS Lambda", a specific certification); hybrid is markedly better for recruiting.
- **Reranking**: add a cross-encoder reranker (e.g. Cohere Rerank, bge-reranker) over the top-N candidates to sharply improve precision before the LLM sees them.
- **Metadata filtering at the DB layer**: push candidate/role/location/skill filters into the vector query so the router's "name-filtered" and attribute strategies scale to millions of records instead of scanning memory.

### Postgres + pgvector — a pragmatic first "real DB"
Before reaching for a specialised vector database, a single **PostgreSQL** instance with the **pgvector** extension can be the entire datastore — operationally simple and surprisingly powerful:

- **One database, three jobs:** relational tables for candidates/metadata/audit, a `vector` column (pgvector with an HNSW index) for embeddings, and a `tsvector` column for the keyword half of hybrid search.
- **The router's strategies become plain SQL.** "Listing"/"aggregation" intents map to real `WHERE` / `COUNT` / `GROUP BY` over indexed columns instead of stuffing the whole corpus into the prompt — correct and cheap at any size. "Name-filtered" is `WHERE candidate_id = …`. "Semantic" is `ORDER BY embedding <=> $query LIMIT k` (cosine via pgvector). Hybrid = blend the `tsvector` rank with the vector distance.
- **Transactional integrity & familiar ops:** backups, migrations, and **row-level security** (excellent for multi-tenant isolation) — with no extra service to run.
- **When to graduate:** pgvector comfortably handles millions of vectors; beyond that, or when you need very high QPS or advanced ANN tuning, move the embeddings to a dedicated vector DB (Qdrant/Pinecone/Milvus) while keeping Postgres as the system of record.

Example shape:
```sql
CREATE TABLE candidates (
  id uuid PRIMARY KEY,
  name text,
  location text,
  tenant_id uuid           -- per-organisation isolation
);

CREATE TABLE cv_chunks (
  id uuid PRIMARY KEY,
  candidate_id uuid REFERENCES candidates(id),
  section text,            -- summary | experience | skills | ...
  content text,
  content_tsv tsvector,    -- keyword search (hybrid)
  embedding vector(768)    -- pgvector
);

CREATE INDEX ON cv_chunks USING hnsw (embedding vector_cosine_ops);  -- ANN
CREATE INDEX ON cv_chunks USING gin (content_tsv);                   -- full-text
```

This is the cleanest evolution of the prototype's in-memory index: same data model (chunk + metadata + vector), just backed by a database that also gives you SQL aggregation, hybrid search, and tenant isolation. It directly powers the query router (§3) from the data layer instead of in memory.

---

## 2. Ingestion pipeline
**Current:** a CLI loops over local PDFs, extracts with poppler, embeds inline, writes one JSON.

**At scale:**
- **Asynchronous, queue-driven ingestion** (e.g. a worker pool consuming from SQS/Kafka/Cloud Tasks). Uploading a CV enqueues a job; workers extract, chunk, embed, and upsert.
- **Robust document parsing**: real CVs are messy — scanned images, multi-column layouts, tables, DOCX, ODT. Add OCR (Textract/Document AI/Tesseract), layout-aware parsing, and language detection.
- **Embedding at scale**: batch embedding calls, backpressure, and a dead-letter queue for failures. Cache embeddings by content hash to avoid re-embedding identical text.
- **Idempotency & versioning**: content-hashed chunk IDs (already the idea here), plus document versioning so re-uploads and edits don't duplicate or orphan data.
- **Incremental & re-embedding**: when you change the embedding model, you need a backfill/migration strategy (dual-write, shadow index, cutover).

---

## 3. The query router (the hero feature) at scale
**Current:** one Gemini JSON call classifies intent, validated against an in-memory roster, with heuristic fallback.

**At scale:**
- **Cheaper/faster classification**: a small fine-tuned classifier or a distilled model instead of a full LLM call per query — classification is a hot path and should be cheap and ~instant.
- **Cache** classifications for repeated/similar queries.
- **Structured filters**: for listing/aggregation, translate the question into structured DB queries (skill = X, school = Y, years > N) against indexed metadata rather than stuffing the whole corpus into context — "full corpus" doesn't scale past a few hundred CVs.
- **Aggregation via the data layer**: counts, rankings and "top N" should be computed by the database/search engine and then *summarised* by the LLM, not counted by the LLM. This is both correct and cheap at scale.
- **Confidence & clarification**: when classification or name resolution is ambiguous, ask the user — important when many candidates share names.

---

## 4. LLM usage: cost, latency, reliability
**Current:** direct REST calls to a single Gemini model; tiny free-tier quota; retry/backoff.

**At scale:**
- **Model tiering**: a small/cheap model for routing and simple answers; a larger model only for complex synthesis. Route by difficulty.
- **Prompt caching** for the stable system prompt and shared context to cut cost/latency.
- **Streaming responses** to the UI for perceived speed.
- **Multi-provider abstraction & fallback**: provider-agnostic client (Gemini / OpenAI / Anthropic / open-weights on your own GPUs) with automatic failover — exactly the lesson from this prototype hitting 503/429s.
- **Rate-limit & quota management**: token buckets, per-tenant quotas, request prioritisation, graceful degradation.
- **Cost controls**: per-request and per-tenant budgets, token accounting, alerting.

---

## 5. Backend architecture
**Current:** single Dart Frog process, singletons built at startup, local files.

**At scale:**
- **Stateless, horizontally scalable services** behind a load balancer/API gateway; no in-process singletons holding data — state lives in shared datastores.
- **Separate services**: ingestion workers, retrieval/RAG API, and the classifier can scale independently.
- **Caching layer** (Redis) for embeddings, classifications, hot answers, and session/conversation state.
- **Datastores**: object storage (S3/GCS) for the original PDFs, a relational DB (Postgres) for candidates/metadata/audit, the vector DB for embeddings.
- **Containerised & orchestrated** (Docker + Kubernetes/Cloud Run), with autoscaling on queue depth and request load.

---

## 6. Multi-tenancy & access control
A real product serves many organisations.
- **Tenant isolation**: partition vectors, documents and metadata per organisation; never let one tenant's query retrieve another's CVs (namespace/collection per tenant, or row-level security).
- **AuthN/AuthZ**: SSO/OAuth/OIDC, RBAC (recruiter vs admin), and per-resource permissions.
- **Audit logging**: who asked what, which CVs were surfaced — essential for trust and compliance.

---

## 7. Security
- **Secrets**: a managed secret store (Vault, AWS/GCP Secret Manager), not `.env` files; rotation; no keys in client code.
- **Prompt injection at scale**: CV content is untrusted input. Beyond delimiting/labelling (done here), add input sanitisation, output validation, and guardrail models — a malicious CV could try to manipulate the screener.
- **Transport & storage encryption**, dependency scanning, and rate limiting/WAF at the edge.

---

## 8. Privacy, compliance & responsible AI (critical for hiring)
This is the part that turns a demo into a defensible product — and it's especially serious because the domain is **recruiting on real personal data**.

- **Real PII / GDPR / CCPA**: CVs are sensitive personal data. You need lawful basis/consent, data minimisation, configurable **retention** and **right-to-erasure** (including purging embeddings and cached context, not just the source file), and **data residency** controls.
- **Anti-discrimination & fairness**: automated candidate screening is legally regulated (e.g. EU AI Act treats hiring as **high-risk**; NYC Local Law 144 requires bias audits). The system must avoid using or inferring protected attributes, undergo **bias/fairness audits**, and document its logic.
- **Explainability & human-in-the-loop**: screening decisions should be explainable (the source attribution here is a start) and must keep a human in the loop — the tool *assists*, it doesn't auto-reject.
- **Grounding & hallucination control**: at scale, wrong/invented claims about a candidate are a real harm. Strengthen with reranking, citations to the exact passage, and answer-verification checks.

---

## 9. Quality & evaluation
**Current:** a manual "golden question" set.

**At scale:**
- **Offline eval harness**: a labelled set measuring retrieval **recall/precision** and answer faithfulness; run it in CI to catch regressions when prompts, models, or chunking change.
- **RAG-specific metrics**: context relevance, groundedness/faithfulness, answer completeness (e.g. RAGAS-style).
- **Online feedback**: thumbs up/down, and capture disagreements for continuous improvement.
- **LLM-as-judge** for scalable grading, spot-checked by humans.

---

## 10. Observability & operations
- **Structured logging + distributed tracing** (OpenTelemetry) across ingestion → retrieval → LLM.
- **Metrics & dashboards**: latency (p50/p95), error rates, retrieval hit quality, token/cost per query, quota usage.
- **Alerting & SLOs**; cost anomaly detection.
- **Replayable traces** of a query through routing/retrieval/generation for debugging.

---

## 11. Frontend at scale
- **Auth, conversation history persistence, pagination** of long candidate lists.
- **Streaming UI** for token-by-token answers.
- **Accessibility & i18n** (the recruiting market is global).
- **Source previews**: click a citation to open the exact CV passage.

---

## 12. Delivery & infrastructure
- **Infrastructure as Code** (Terraform/Pulumi), multiple environments (dev/staging/prod).
- **CI/CD** with automated tests, the eval harness as a gate, and safe rollouts (canary/blue-green) for prompt and model changes.
- **Versioning everything**: prompts, models, embedding model, and the index are all versioned and rollback-able.

---

## Summary: what stays vs what changes
The **architecture's shape stays** — generate/ingest → chunk → embed → **route by intent** → retrieve → ground → answer. The router concept in particular becomes *more* valuable at scale, where "retrieve everything" stops working and intent must drive structured queries, metadata filters, and DB-side aggregation. What changes is the **engineering around it**: managed vector search with reranking, async ingestion, multi-provider LLM access with caching and budgets, multi-tenant security, and — for hiring specifically — the privacy, fairness, and explainability obligations that make automated screening lawful and trustworthy.
