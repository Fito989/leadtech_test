# Technical PRD: AI-Powered CV Screener

| | |
|---|---|
| **Document** | Technical PRD — AI-Powered CV Screener |
| **Status** | Ready for implementation |
| **Companion docs** | [`prd.md`](prd.md) (product), [`requirements.pdf`](requirements.pdf) (source brief) |
| **Stack** | Flutter (app) · Dart Frog (backend) · in-memory cosine + JSON (vector store) · Google Gemini (LLM + embeddings) |

> Defines **how** the product in [`prd.md`](prd.md) is built. Requirement IDs (CV-xx, ING-xx, RAG-xx, UI-xx, NFR-xx, ERR-xx, UC-xx) trace back to that PRD.

---

## 1. Technology Decisions

| Concern | Decision | Rationale |
|---------|----------|-----------|
| Frontend | **Flutter** (Chrome/web for local run) | Single codebase, fast UI |
| State management | **`flutter_bloc` with Cubits** | Simple, testable, explicit state for a small app |
| Backend | **Dart Frog** | Lightweight, file-based routing, pure Dart |
| Language | **Dart end-to-end** (app, backend, tooling) | One language across the repo |
| LLM | **`gemini-3.5-flash`** (REST) | Current GA Gemini Flash (May 2026); free tier; fast; good instruction following |
| Embeddings | **`gemini-embedding-2`**, output dim **768**, `taskType`-aware (REST) | Current GA embedding model (Apr 2026); same provider; MRL-truncated from 3072→768 to keep cosine cheap |
| Vector store | **In-memory cosine** + **JSON persistence** | Pure Dart, no native deps; brute-force is sub-ms at this scale (§1.1) |
| **Retrieval strategy** | **Query-type router** (hero feature, §4) | Routes each query to full-corpus / name-filtered / vector retrieval to maximize recall *and* precision |
| PDF generation | **`pdf`** package (DavBfr) | Pure-Dart PDF rendering for the generator |
| PDF text extraction | **`pdftotext` (poppler) via `Process.run`**, sidecar JSON fallback | Real extraction from the PDFs (ING-01); sidecar guarantees robustness (§6.2) |
| Image generation | Gemini image generation / Imagen API | AI profile photos (CV-02) |
| HTTP | `dio` (app), `package:http` (backend/tools) | Standard clients |

### 1.1 Vector store: why in-memory cosine
25–30 CVs produce a few hundred section-level vectors. A **brute-force cosine scan is sub-millisecond** at that size, so an ANN index (e.g. ObjectBox HNSW) adds setup cost — including a native library that must be installed manually on the host — for zero practical benefit. In-memory cosine is pure Dart, has no native dependency, behaves identically in the ingest CLI and the server, and is trivially portable.

The ingest tool writes `data/index/embeddings.json` (chunks + vectors + metadata); the backend loads it into memory at startup behind a `VectorIndex` interface. That interface can later be backed by Hive or ObjectBox without touching `Retriever` or `RagService`.

---

## 2. Repository Structure

Two independent Dart projects plus shared docs:

```
leadthech_test/
├── app/                         # Flutter chat application
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/
│   │   │   ├── config/          # base URL, constants
│   │   │   ├── di/              # dependency injection
│   │   │   ├── network/         # dio client
│   │   │   └── theme/
│   │   ├── data/
│   │   │   ├── dtos/            # ChatRequestDto, ChatResponseDto, SourceDto
│   │   │   └── repositories/    # ChatRepositoryImpl
│   │   ├── domain/
│   │   │   ├── entities/        # ChatMessage, Source
│   │   │   └── repositories/    # ChatRepository (interface)
│   │   └── features/
│   │       └── chat/
│   │           ├── cubit/      # chat_cubit.dart, chat_state.dart
│   │           ├── view/       # chat_page.dart
│   │           └── widgets/    # message_bubble, source_chip, chat_input, typing_indicator
│   ├── test/
│   └── pubspec.yaml
│
├── backend/                     # Dart Frog API + tooling
│   ├── routes/
│   │   ├── _middleware.dart     # CORS, logging, error handling, DI
│   │   ├── index.dart           # GET /  -> service info
│   │   ├── health.dart          # GET /health
│   │   └── chat.dart            # POST /chat
│   ├── lib/
│   │   └── src/
│   │       ├── config/          # AppConfig (env)
│   │       ├── models/          # CvChunk, Candidate, ChatRequest/Response, Source, QueryIntent
│   │       ├── gemini/          # GeminiClient (chat + embeddings + classify)
│   │       ├── vector/          # VectorIndex (load JSON), Retriever (cosine + name filter)
│   │       ├── ingestion/       # PdfExtractor, Chunker, IngestionPipeline
│   │       └── rag/             # RagService, QueryRouter, PromptBuilder, Guardrails
│   ├── tools/
│   │   ├── generate_cvs.dart    # CLI: generate 25–30 CV PDFs + sidecar JSON
│   │   └── ingest.dart          # CLI: build data/index/embeddings.json
│   ├── data/
│   │   ├── cvs/                 # <slug>.pdf + <slug>.json (committed)
│   │   └── index/              # embeddings.json
│   ├── test/
│   └── pubspec.yaml
│
├── docs/
│   ├── prd.md
│   ├── tech-prd.md
│   └── requirements.pdf
├── .env.example                 # GEMINI_API_KEY=...
└── README.md
```

A Flutter project currently sits at the repo **root**; the first step moves it into `app/`. The `backend/` project is created with `dart_frog create backend`.

---

## 3. High-Level Architecture

```
                ┌──────────────────────────────────────────┐
                │            Flutter App (app/)             │
                │  ChatPage ── ChatCubit ── ChatRepository  │
                │            (dio HTTP client)              │
                └───────────────────┬──────────────────────┘
                                    │  POST /chat (JSON)
                                    ▼
                ┌──────────────────────────────────────────┐
                │         Dart Frog Backend (backend/)      │
                │  _middleware (CORS, log, errors, DI)      │
                │                  │                        │
                │                  ▼                        │
                │            RagService                     │
                │   1. QueryRouter.classify ── Gemini ──────┼─► Gemini (classify)
                │   2. select context strategy:             │
                │      • full-corpus  (listing/count/cmp)   │
                │      • name-filtered (candidate-specific) │
                │      • vector top-k (semantic) ── Gemini ──┼─► Gemini (embed query)
                │                       └─ VectorIndex (cosine, in-mem)
                │   3. PromptBuilder (grounding + injection)│
                │   4. generate answer ──── Gemini ─────────┼─► Gemini (chat)
                │   5. attach sources                       │
                └──────────────────────────────────────────┘

   OFFLINE (one-time, CLI tools)
   ┌─────────────────────────┐     ┌──────────────────────────────────┐
   │ tools/generate_cvs.dart │     │ tools/ingest.dart                │
   │ Gemini text + image API │ ──► │ pdftotext extract → section chunk │
   │ → PDF + sidecar JSON     │ PDFs│ → embed → data/index/embeddings.json
   └─────────────────────────┘     └──────────────────────────────────┘
```

---

## 4. Query-Type Router (hero feature)

Naive top-k retrieval breaks the most common recruiter questions: *listing* ("who knows Python?") and *counting* ("how many know React?") under-retrieve (wrong, confident answers), and *name* queries ("summarize Jane Doe") don't reliably retrieve the right person by vector similarity. The router fixes all three by choosing a context strategy per query. This is the centerpiece of the solution and demonstrates that grounding requires **recall**, not just precision.

### 4.1 Classification
`QueryRouter.classify(message, history)` returns a `QueryIntent`:
```dart
enum Intent { candidateSpecific, listing, aggregation, comparison, semantic, outOfScope }
class QueryIntent { Intent intent; List<String> candidateNames; }
```
- **Primary:** a single Gemini call with a strict JSON schema returns the intent plus any candidate names mentioned. Candidate names are validated against the known roster (we generated the CVs, so the roster is authoritative — robust name matching, no guessing).
- **Fast path / fallback:** cheap heuristics (e.g. `how many`/`count` → aggregation; `compare` → comparison; roster-name match → candidateSpecific) so the system degrades gracefully if the classify call fails.
- **Ambiguous names:** if a partial name matches multiple roster entries (e.g. several "John"s), all matches are passed as `candidateNames`; the answer either lists them or asks the user to disambiguate (UC-24, ERR-10).

### 4.2 Strategy per intent
| Intent | Context strategy | Why |
|--------|------------------|-----|
| `listing` | **Full-corpus**: all CV section-chunks | Guarantees every matching candidate is considered (recall) — UC-01–06, incl. combined/negation criteria UC-11/13 |
| `aggregation` | **Full-corpus** | Counts/rankings must span the whole corpus — UC-12/14/15/16, RAG-08 |
| `comparison` | **Name-filtered** (named candidates) or full-corpus | Pulls exactly the compared candidates — UC-17/18 |
| `candidateSpecific` | **Name-filtered**: all chunks for the named candidate(s) | Guarantees the right person's CV — UC-08/09/10 |
| `semantic` | **Vector top-k** (cosine over `VectorIndex`) | Open-ended semantic match; classic RAG, demonstrates the pipeline |
| `outOfScope` | **None** → guardrail refusal | UC-21 |

At this corpus size, full-corpus context fits comfortably in the Gemini context window, so completeness-sensitive queries trade a few thousand tokens for correctness. The mandatory RAG pipeline (extract → chunk → embed → vector store → retrieve) is genuinely exercised by the `semantic` branch.

---

## 5. Backend — Dart Frog

### 5.1 Routes (API contract)
| Method | Route | Purpose | Maps to |
|--------|-------|---------|---------|
| `GET` | `/` | Service metadata (name, model) | — |
| `GET` | `/health` | Liveness + index-loaded check | ERR-07 |
| `POST` | `/chat` | RAG query endpoint | RAG-06 |

**`POST /chat`** request:
```json
{ "message": "Who has experience with Python?",
  "history": [{ "role": "user", "content": "..." }] }
```
Response:
```json
{ "answer": "Three candidates mention Python: ...",
  "intent": "listing",
  "sources": [{ "candidate": "Jane Doe", "file": "jane_doe.pdf", "score": 0.82 }],
  "matched": true }
```
- `matched: false` → no relevant content / out of scope; `answer` explains (UC-21/22, ERR-04).
- Error envelope: `{ "error": { "code": "RATE_LIMITED", "message": "..." } }`.

### 5.2 `_middleware.dart`
- **CORS** (Flutter web is a different origin).
- **Request logging** — method, path, latency, intent, context size (NFR-10).
- **Error handling** — exceptions → error envelope; no stack traces leaked (ERR-01/02/05).
- **DI** — `provider<RagService>(...)`, `provider<AppConfig>(...)`, `provider<VectorIndex>(...)` (index loaded once at startup).

### 5.3 `RagService` flow
1. **Validate** input — reject empty/oversized (ERR-03, ERR-08).
2. **Classify** via `QueryRouter` (§4).
3. **Assemble context** per strategy (full-corpus / name-filtered / vector top-k).
4. **Build prompt** via `PromptBuilder` (grounding + injection defense + history, RAG-07).
5. **Generate** via `GeminiClient.chat()`.
6. **Attach sources** — candidates/files contributing to the context (RAG-05, UI-04).

### 5.4 Grounding & "no match" — without a brittle threshold (#5 fix)
Raw cosine cutoffs are uncalibrated, so we **do not** gate answers on an absolute similarity number. Instead:
- **Out-of-scope** is caught at **routing** (`Intent.outOfScope`) → deterministic refusal (UC-21).
- **No-match within scope** is enforced at **generation**: the system prompt instructs the model to answer **only** from the provided CV context and to reply *"I couldn't find that in the CVs"* when the context doesn't support an answer (UC-22, ERR-04). The LLM judges relevance against actual content far more reliably than a fixed cosine threshold.
- For the `semantic` branch only, a **relative** signal (top score vs. the rest) can flag low-confidence retrieval for logging — diagnostic, not a hard gate.

### 5.5 `PromptBuilder` & injection defense
System prompt enforces: answer only from provided CV context; say so when unknown; never invent candidates/facts; only answer questions about the CVs; no subjective/discriminatory judgments (UC-25). Retrieved CV text is wrapped in delimited blocks **labeled as untrusted data**, with an instruction to ignore any instructions inside it (RAG-09 / ERR-09).

### 5.6 `VectorIndex` + `Retriever`
- `VectorIndex.load()` reads `embeddings.json` into memory at startup.
- `Retriever.byCandidate(names)` → metadata filter on `candidateName` (name-filtered strategy, #3).
- `Retriever.all()` → every chunk (full-corpus strategy).
- `Retriever.search(queryVec, k)` → cosine rank, top-k (semantic strategy; default k=6, NFR-09).

### 5.7 `GeminiClient`
- `classify(message) → QueryIntent` (JSON-mode chat call).
- `embed(texts, taskType) → vectors` — `taskType: RETRIEVAL_DOCUMENT` at ingest, `RETRIEVAL_QUERY` at query time (#6); batched (NFR-08).
- `chat(systemPrompt, messages) → String`.
- Timeout + retry/backoff on 429/5xx (ERR-01); fail fast if `GEMINI_API_KEY` missing/invalid (ERR-02).

---

## 6. Backend Data Models & Ingestion

### 6.1 Models
```dart
class CvChunk {
  String chunkId;          // stable hash (idempotency, ING-06)
  String candidateName;    // enables name filtering (#3)
  String sourceFile;       // e.g. "jane_doe.pdf"
  String section;          // summary | experience | education | skills | languages | contact
  String text;
  List<double> embedding;  // 768-dim (gemini-embedding-2, MRL-truncated)
}
class Source { String candidate; String file; double score; }
class ChatRequest { String message; List<ChatTurn> history; }
class ChatResponse { String answer; String intent; List<Source> sources; bool matched; }
```

### 6.2 PDF text extraction (#4 — real extraction via poppler)
Pure-Dart PDF text extraction is immature (the mature libraries need Flutter and won't run in a Dart Frog/CLI process). To genuinely satisfy ING-01 we extract with **`pdftotext` (poppler-utils)** invoked via `Process.run`:
```
pdftotext -layout data/cvs/<slug>.pdf -    # text to stdout
```
- **poppler is a required local dependency** (install: `choco install poppler` on Windows; `brew install poppler` / `apt install poppler-utils` elsewhere). Documented in the README.
- **Sidecar fallback:** the generator also writes `<slug>.json`. If `pdftotext` is unavailable or yields too little text, ingestion falls back to the sidecar so no candidate is ever lost (NFR-04, ERR-06).

### 6.3 Chunking — section-based, and why (#7 justification)
We chunk **one chunk per CV section** (summary, experience, education, skills, languages, contact), **not** fixed-size sliding windows. Justification:
- A CV section is a **semantically coherent unit** and the natural granularity for the use cases ("Jane's *education*" → the education chunk).
- Section tags give clean **metadata for routing/filtering** (#3) — name + section retrieval is precise.
- At CV length (~one page) there is **no recall benefit** to overlapping token windows; section chunks keep retrieval interpretable and sources meaningful.
- A candidate's full CV is reconstructed by concatenating their section chunks (name-filtered / summary queries).

### 6.4 `tools/ingest.dart` (ING-01…07)
Enumerate `data/cvs/*.pdf` → extract (poppler, sidecar fallback) → section-chunk with `candidateName`/`section` metadata → embed in batches (`RETRIEVAL_DOCUMENT`) → write `data/index/embeddings.json` keyed by `chunkId` (idempotent) → print per-file status (success/skipped/failed).

### 6.5 `tools/generate_cvs.dart` (CV-01…10)
25–30 diverse profiles (roles, seniorities, languages) → **seed canonical entities** (a "Jane Doe", a UPC graduate, several Python candidates) → Gemini structured CV text → image API photo → render PDF (`pdf` package) → write `<slug>.pdf` + `<slug>.json`. Seeded RNG for reproducibility; some shared skills/schools (meaningful filters); ≥1 duplicate first name (disambiguation, UC-24).

---

## 7. Frontend — Flutter (Cubits)

- **domain/** — `ChatMessage`, `Source`; `ChatRepository` interface.
- **data/** — DTOs + `ChatRepositoryImpl` (dio) → `POST /chat`.
- **features/chat/cubit/** — `ChatCubit` + `ChatState`.

```dart
sealed class ChatState {}
class ChatInitial extends ChatState {}
class ChatLoaded extends ChatState { List<ChatMessage> messages; }
class ChatSending extends ChatState { List<ChatMessage> messages; }   // UI-03
class ChatError  extends ChatState { List<ChatMessage> messages; String error; } // UI-06
```

`ChatCubit.sendMessage(text)`: guard empty (UI-07/ERR-03) → append user msg, emit `ChatSending` → call repo with history → success: append assistant msg + sources, emit `ChatLoaded` → failure: emit `ChatError`. `clearConversation()` resets (UI-08). In-session history passed to the backend for follow-ups (UC-19/20, RAG-07).

| Widget | Responsibility | Maps to |
|--------|----------------|---------|
| `ChatPage` | Scaffold, message list, input; `BlocBuilder` | UI-01 |
| `MessageBubble` | User/assistant message (markdown) | UI-02 |
| `SourceChip` | Source candidate/file under answers | UI-04 |
| `TypingIndicator` | Shown during `ChatSending` | UI-03 |
| `ChatInput` | Text field; Enter-to-send; disabled while sending | UI-07/UI-10 |

---

## 8. Configuration & Secrets

| Variable | Used by | Purpose |
|----------|---------|---------|
| `GEMINI_API_KEY` | backend, tools | Gemini auth (NFR-11) |
| `GEMINI_CHAT_MODEL` | backend, tools | default `gemini-3.5-flash` |
| `GEMINI_EMBED_MODEL` | backend, tools | default `gemini-embedding-2` |
| `EMBED_DIM` | backend, tools | embedding output dim (default 768) |
| `TOP_K` | backend | semantic retrieval depth (default 6) (NFR-09) |
| `INDEX_PATH` | backend, tools | path to `data/index/embeddings.json` |
| `CVS_DIR` | tools | path to `data/cvs` |
| `BACKEND_BASE_URL` | app | API base (e.g. `http://localhost:8080`) |

`.env` is gitignored; `.env.example` is committed (NFR-11). App reads `BACKEND_BASE_URL` via `--dart-define`.

---

## 9. Testing Strategy

| Level | Target | Tooling |
|-------|--------|---------|
| Backend unit | `QueryRouter` classification (incl. heuristic fallback), section Chunker, PromptBuilder, cosine ranking, name filter | `package:test` |
| Backend unit | `GeminiClient` (mocked HTTP) — retry/backoff, error mapping | `mocktail` |
| Backend integration | `POST /chat` with stubbed Gemini + seeded in-memory index, per intent | `dart_frog` test utils |
| Ingestion | extract → section-chunk → index produces expected chunk count/metadata | `package:test` |
| App | `ChatCubit` transitions | `bloc_test` |
| App | `ChatPage` renders messages/loading/error/sources | `flutter_test` |
| Golden set | Python (listing) · UPC (listing) · summarize Jane Doe (candidateSpecific) · how many know React (aggregation) · COBOL (no-match) · weather (out-of-scope) | scripted |

---

## 10. Technical Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| poppler not installed | Extraction fails | Sidecar JSON fallback (§6.2); documented install step |
| Router misclassifies a query | Wrong context strategy | Heuristic fallback; safe default to full-corpus when uncertain |
| Listing/count under-recall | Confidently wrong answers | Full-corpus strategy for listing/aggregation (§4.2) |
| Name query retrieves wrong person | Wrong summary | Name-metadata filter, not vector similarity (§5.6) |
| Gemini rate limits | Failures | Batch embeddings at ingest; retry/backoff; cache |
| Image-gen quota/cost | Incomplete CVs | Cache photos; stock AI-face fallback |
| Prompt injection via CV text | Compromised answers | Delimit + label CV text as untrusted (§5.5) |

---

## 11. Local Run Sequence

```bash
# 0. One-time: move root Flutter project into app/, create backend, install poppler
dart_frog create backend
choco install poppler            # Windows (brew/apt elsewhere)

# 1. Secrets
cp .env.example .env             # add GEMINI_API_KEY

# 2. Generate the CV dataset (25–30 PDFs + sidecars)
cd backend && dart run tools/generate_cvs.dart

# 3. Build the vector index (data/index/embeddings.json)
dart run tools/ingest.dart

# 4. Run the backend
dart_frog dev                    # http://localhost:8080

# 5. Run the app (new terminal)
cd ../app
flutter run -d chrome --dart-define=BACKEND_BASE_URL=http://localhost:8080
```

---

## 12. Confirmed Defaults
- **Run target:** Chrome (web) for the local run.
- **Dataset:** generated PDFs + sidecars are **committed** so the app runs without an image-API key (regeneration available via the tool).
- **Models:** `gemini-3.5-flash` (chat) + `gemini-embedding-2` @ 768 dims (embeddings).
- **Hero feature:** the query-type router (§4).
