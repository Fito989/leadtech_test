# Build Progress / Continuation Handoff

> **Last updated:** 2026-06-02 (session 3)
> **Purpose:** so work can resume with a single "continue". Authoritative state of the implementation of [`tech-prd.md`](tech-prd.md).

## TL;DR — where we are
- **The whole system is BUILT and compiles.** Backend `dart_frog build` passes; `flutter test` passes (3/3 cubit tests).
- Dataset: **28 CVs generated** (`backend/data/cvs/cv01..cv28_*.pdf` + sidecars), **ingested → 168 chunks** in `data/index/embeddings.json`. All 28 unique names. Canonical seeds present (Jane Doe `cv01`, UPC grads, Pythons, Marc Soler/Vidal).
- **NEXT:** start backend + app, run golden queries, verify end-to-end.

## To run the full stack
1. `dart_frog dev` in `backend/` (or `dart pub global run dart_frog_cli:dart_frog dev`)
2. In a second terminal: `cd app && flutter run -d chrome --dart-define=BACKEND_BASE_URL=http://localhost:8080`
3. Verify golden queries (Python / UPC / Jane Doe / React count / COBOL / weather).

## Task checklist — ALL CODE COMPLETE
- [x] **#1 Scaffold** `backend/` + `app/`
- [x] **#2 Config + models**
- [x] **#3 GeminiClient** (live-validated)
- [x] **#4 VectorIndex + Retriever** — `backend/lib/src/vector/*` (unit-validated: cosine, filters, save/load)
- [x] **#5 Ingestion + tool** — `backend/lib/src/ingestion/*` + `tools/ingest.dart` (ran: 21 files → 126 chunks; incremental/idempotent)
- [x] **#6 CV generator** — `backend/lib/src/generation/*` + `tools/generate_cvs.dart` (ran: 21 CVs; resumable, photos via thispersondoesnotexist)
- [x] **#7 RAG + routes** — `backend/lib/src/rag/*` + `routes/{_middleware,index,health,chat}.dart` (endpoints live-tested)
- [x] **#8 Flutter app** — `app/lib/{core,domain,data,features/chat}` (`flutter test` green)
- [~] **#9 End-to-end** — generated+ingested+served+README done; **live golden-query check pending quota reset**. Backend unit tests not yet added.

## What exists now (backend/lib/src)
- `config/app_config.dart` — loads `backend/.env` (fallback `../.env`); fields: geminiApiKey, chatModel, embedModel, embedDim(768), topK(6), indexPath(`data/index/embeddings.json`), cvsDir(`data/cvs`). Throws if key missing.
- `models/cv_chunk.dart` — `CvChunk{chunkId,candidateName,sourceFile,section,text,embedding}` + to/fromJson.
- `models/chat.dart` — `ChatTurn`, `ChatRequest`, `Source`, `ChatResponse`.
- `models/query_intent.dart` — `enum Intent{candidateSpecific,listing,aggregation,comparison,semantic,outOfScope}`, `QueryIntent{intent,candidateNames}`.
- `gemini/gemini_client.dart` — `chat()`, `generateJson(schema)`, `embedOne()/embed(taskType)`; retry/backoff; `EmbedTask.{query,document}`. Uses header `x-goog-api-key`.

## Decisions already locked (don't re-litigate)
- **Models:** chat default `gemini-2.5-flash` (`:generateContent`) — `gemini-3.5-flash` returns persistent 503 (overloaded) on free tier, so 2.5 is the stable default, switchable via `GEMINI_CHAT_MODEL`. Embeddings `gemini-embedding-2` (`:embedContent`, `outputDimensionality=768`, `taskType` QUERY/DOCUMENT). Image gen NOT on free tier → photos via `thispersondoesnotexist.com`.
- **Vector store:** in-memory cosine + JSON at `backend/data/index/embeddings.json` (no ObjectBox). See tech-prd §1.1.
- **Hero feature:** query-type router (tech-prd §4) — full-corpus for listing/aggregation, name-filtered for candidate/comparison, vector top-k for semantic, refuse out-of-scope.
- **PDF extraction:** real via poppler `pdftotext -layout <pdf> -` (Process.run), **sidecar `.json` fallback**. tech-prd §6.2.
- **Chunking:** one chunk per CV **section** (summary/experience/education/skills/languages/contact). tech-prd §6.3.
- **No `Co-Authored-By` trailer** in commits (user wants commits as their own). Conventional Commits, author = Pol Bernal.

## Environment gotchas (IMPORTANT for resuming)
- **`dart analyze` / `flutter analyze` CRASH** here (analysis-server perf file, OS Error 1920 — AV/Controlled-Folder-Access). **Do not rely on them.** Validate instead with: a temp `backend/_check.dart` + `dart run _check.dart` (delete after), or `dart_frog build`, or `dart test`.
- **Network commands need the sandbox disabled** (`dangerouslyDisableSandbox: true`): `pub get/add`, `dart_frog create/build`, `flutter pub get`, `git push`, any Gemini/curl call.
- **`dart_frog` CLI**: installed v1.2.14, added to User PATH, but bare `dart_frog` doesn't always resolve in the Bash tool. Reliable form: `dart pub global run dart_frog_cli:dart_frog <cmd>`.
- **Secrets:** `backend/.env` holds `GEMINI_API_KEY` (gitignored, present & validated). `backend/.env.example` is the tracked template.
- **poppler** `pdftotext` 4.00 is installed and on PATH.
- Toolchain: Dart 3.12.0, Flutter 3.44.0.

## Next action (Task #4) — concrete spec
Create `backend/lib/src/vector/`:
- `vector_index.dart`: `VectorIndex.load(path)` reads `embeddings.json` → `List<CvChunk>` in memory; expose `chunks`, and `roster` (unique candidateNames) for the router's name validation.
- `retriever.dart`: cosine similarity helper; `search(List<double> query, int k)` → top-k `(CvChunk, score)`; `byCandidate(List<String> names)` → all chunks for those candidates; `all()` → every chunk.

How the *correct* chunk is found **without a DB** (see tech-prd §5.6, expanded): the JSON file is the store, the in-memory `List<CvChunk>` is the index. Name/candidate queries use an **exact metadata filter** on `candidateName` (never similarity); listing/aggregation use **all chunks** (full recall); only open semantic queries use **cosine top-k**. Cosine is a ~10-line pure-Dart function — no DB engine needed.

Validate with a temp `_check.dart` (synthetic chunks) since no index file exists yet.

## Final validation (Task #9) — golden queries
Python (listing) · UPC (listing) · "Summarize Jane Doe" (candidateSpecific) · "How many know React?" (aggregation) · COBOL (no-match) · weather (out-of-scope). Plus README with run steps (tech-prd §11) and tests (tech-prd §9).

## Run sequence (once built)
```
cd backend && cp .env.example .env   # already has the key
dart pub global run dart_frog_cli:dart_frog ... # or dart_frog if PATH resolves
dart run tools/generate_cvs.dart     # 25–30 CVs → data/cvs
dart run tools/ingest.dart           # build data/index/embeddings.json
dart_frog dev                        # http://localhost:8080
# new terminal:
cd app && flutter run -d chrome --dart-define=BACKEND_BASE_URL=http://localhost:8080
```
