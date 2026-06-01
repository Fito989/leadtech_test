#!/usr/bin/env bash
# One-command runner for the CV Screener (Git Bash / macOS / Linux).
#   ./scripts/run_all.sh                 # generate (if empty) + ingest (if missing) + run
#   COUNT=6 ./scripts/run_all.sh         # generate fewer CVs
#   SKIP_GENERATE=1 SKIP_INGEST=1 ./scripts/run_all.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$ROOT/backend"
APP="$ROOT/app"
BACKEND_URL="${BACKEND_URL:-http://localhost:8080}"   # host-side health check
DEVICE="${DEVICE:-emulator-5554}"                      # e.g. chrome | emulator-5554
FROG="dart pub global run dart_frog_cli:dart_frog"

# From inside an Android emulator, the host's localhost is 10.0.2.2.
case "$DEVICE" in
  *emulator*|*android*) APP_URL="http://10.0.2.2:8080" ;;
  *) APP_URL="$BACKEND_URL" ;;
esac

# Kill any process still listening on the given TCP port (cross-platform).
free_port() {
  local port="$1"
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)   # Windows (Git Bash)
      local pids
      pids=$(netstat -ano 2>/dev/null | grep -E ":${port}[[:space:]]" | grep -i LISTENING | awk '{print $NF}' | sort -u || true)
      for pid in $pids; do MSYS_NO_PATHCONV=1 taskkill /PID "$pid" /F >/dev/null 2>&1 || true; done
      ;;
    *)                      # macOS / Linux
      if command -v lsof >/dev/null 2>&1; then
        lsof -ti:"$port" 2>/dev/null | xargs -r kill -9 2>/dev/null || true
      elif command -v fuser >/dev/null 2>&1; then
        fuser -k "${port}/tcp" 2>/dev/null || true
      fi
      ;;
  esac
}

# 1. Secrets check
if [ ! -f "$BACKEND/.env" ]; then
  echo "ERROR: backend/.env not found. Run: cp backend/.env.example backend/.env  then add GEMINI_API_KEY." >&2
  exit 1
fi

# 2. Generate CVs only if none exist
if [ "${SKIP_GENERATE:-0}" != "1" ] && ! ls "$BACKEND"/data/cvs/*.pdf >/dev/null 2>&1; then
  echo "==> Generating CVs..."
  if [ -n "${COUNT:-}" ]; then (cd "$BACKEND" && dart run tools/generate_cvs.dart --count "$COUNT");
  else (cd "$BACKEND" && dart run tools/generate_cvs.dart); fi
else
  echo "==> Skipping CV generation."
fi

# 3. Build the vector index only if missing
if [ "${SKIP_INGEST:-0}" != "1" ] && [ ! -f "$BACKEND/data/index/embeddings.json" ]; then
  echo "==> Ingesting CVs -> vector index..."
  (cd "$BACKEND" && dart run tools/ingest.dart)
else
  echo "==> Skipping ingest."
fi

# Clear a stale backend from a previous run so the port is free.
PORT="${BACKEND_URL##*:}"
echo "==> Clearing anything on port $PORT ..."
free_port "$PORT"

# 4. Start the backend in the background; stop it on exit
echo "==> Starting backend ($BACKEND_URL)..."
(cd "$BACKEND" && $FROG dev) &
BACK_PID=$!
trap 'kill "$BACK_PID" 2>/dev/null || true' EXIT

# 5. Wait for health
echo "==> Waiting for backend health..."
for _ in $(seq 1 30); do
  if curl -sf "$BACKEND_URL/health" >/dev/null 2>&1; then echo "    backend is up."; break; fi
  sleep 2
done

# 6. Launch the Flutter app (foreground)
echo "==> Launching Flutter app on '$DEVICE' (backend $APP_URL)..."
(cd "$APP" && flutter run -d "$DEVICE" --dart-define=BACKEND_BASE_URL="$APP_URL")
