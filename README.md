# AI-Powered CV Screener

A chat application that answers natural-language questions about a collection of CVs, grounded in their content via a Retrieval-Augmented Generation (RAG) pipeline.

- **`app/`** — Flutter chat UI (Cubits / `flutter_bloc`)
- **`backend/`** — Dart Frog API + offline tools (CV generation, ingestion)
- **`docs/`** — [product PRD](docs/prd.md), [technical PRD](docs/tech-prd.md), [build progress](docs/build-progress.md)

The backend generates ~25–30 fake CV PDFs (text via Gemini, AI photos), extracts and embeds them into a local JSON vector index, and answers questions with a **query-type router** that picks the best retrieval strategy per question (full-corpus for listing/counting, name-filtered for candidate questions, vector search for open semantic queries).

## Prerequisites

- Dart SDK ≥ 3.12, Flutter ≥ 3.44
- [`poppler`](https://poppler.freedesktop.org/) for `pdftotext` (`choco install poppler` on Windows, `brew install poppler` on macOS, `apt install poppler-utils` on Linux)
- Dart Frog CLI: `dart pub global activate dart_frog_cli`
- A Gemini API key — free at https://aistudio.google.com/apikey

## Setup

```bash
cd backend
cp .env.example .env        # then put your GEMINI_API_KEY in .env
dart pub get
```

## Run (one command)

After setup, one command generates CVs (if none), builds the index (if missing), starts the backend, and launches the app.

**Windows — Android emulator** (copy-paste, then Enter):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_all.ps1 -Device emulator-5554
```

**Windows — Chrome (web):**

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_all.ps1
```

**Git Bash / macOS / Linux:**

```bash
bash scripts/run_all.sh                 # DEVICE=chrome bash scripts/run_all.sh for web
```

> Run from the repository root. For the emulator, make sure it's booted (`flutter devices`); the app is wired to reach the backend at `http://10.0.2.2:8080`.

## Run (manual steps)

```bash
# 1) Generate the CV dataset (writes data/cvs/*.pdf + *.json). Resumable.
dart run tools/generate_cvs.dart            # or --count N for fewer

# 2) Build the vector index (writes data/index/embeddings.json)
dart run tools/ingest.dart

# 3) Start the API
dart_frog dev                               # http://localhost:8080

# 4) In another terminal, run the app
cd ../app
flutter run -d chrome --dart-define=BACKEND_BASE_URL=http://localhost:8080
```

## API

- `GET /` — service info (model, chunk/candidate counts)
- `GET /health` — readiness (is the index loaded?)
- `POST /chat` — `{ "message": "...", "history": [{ "role": "...", "content": "..." }] }`
  → `{ "answer", "intent", "sources": [{candidate, file, score}], "matched" }`

## Sample questions

- "Who has experience with Python?"
- "Which candidate graduated from UPC?"
- "Summarize the profile of Jane Doe."
- "How many candidates know React?"
- "Compare Jane Doe and Marc Soler."

## Models & free-tier note

Configurable via `backend/.env`. Chat uses a Gemini Flash model; embeddings use `gemini-embedding-2` (768-dim). The free tier is rate/quota-limited per model — if a model returns `503`/`429`, switch `GEMINI_CHAT_MODEL` to another (e.g. `gemini-2.5-flash-lite`) or wait for the daily reset. Profile photos come from `thispersondoesnotexist.com` (image generation is not on the free tier).

## Tests

```bash
cd backend && dart test
cd app && flutter test
```
