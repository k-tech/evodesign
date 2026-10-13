#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
USER_HOME="${HOME:-}"
STATE_DIR="${EVODESIGN_STATE_DIR:-${XDG_STATE_HOME:-${USER_HOME:-/tmp}/.local/state}/evodesign}"
TIMEZONE="America/Los_Angeles"
REMOTE="origin"
BRANCH="main"
CODEX_MODEL="${EVODESIGN_CODEX_MODEL:-gpt-5.5}"

mkdir -p "$STATE_DIR"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
EXTERNAL_LOG="$STATE_DIR/run-${RUN_ID}.log"
exec > >(tee -a "$EXTERNAL_LOG") 2>&1

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
fail() { log "ABORT: $*"; exit 1; }

resolve_command() { command -v "$1" 2>/dev/null || true; }

BASH_PATH="$(resolve_command bash)"
GIT_PATH="$(resolve_command git)"
PYTHON_PATH="$(resolve_command python3)"
[[ -n "$PYTHON_PATH" ]] || PYTHON_PATH="$(resolve_command python)"
CODEX_PATH="$(resolve_command codex)"
FLOCK_PATH="$(resolve_command flock)"

log "Repository: $ROOT_DIR"
log "Bash path: ${BASH_PATH:-NOT_FOUND}"
log "Git path: ${GIT_PATH:-NOT_FOUND}"
log "Python path: ${PYTHON_PATH:-NOT_FOUND}"
log "Codex path: ${CODEX_PATH:-NOT_FOUND}"
log "Codex model: $CODEX_MODEL"
log "Timezone: $TIMEZONE"
log "External log: $EXTERNAL_LOG"

[[ -n "$GIT_PATH" ]] || fail "GIT_NOT_FOUND"
[[ -n "$PYTHON_PATH" ]] || fail "PYTHON_NOT_FOUND"

LOCK_DIR="$STATE_DIR/lock"
LOCK_FILE="$STATE_DIR/evolution.lock"
LOCK_MODE=""
LOCK_FD=""
acquire_lock() {
  if [[ -n "$FLOCK_PATH" ]]; then
    eval "exec 9>\"$LOCK_FILE\""
    if ! "$FLOCK_PATH" -n 9; then
      log "RUN_ALREADY_IN_PROGRESS"
      exit 0
    fi
    LOCK_MODE="flock"
    LOCK_FD=9
    log "Run lock acquired with flock: $LOCK_FILE"
  else
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
      log "RUN_ALREADY_IN_PROGRESS"
      exit 0
    fi
    LOCK_MODE="mkdir"
    trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
    log "Run lock acquired with lock directory: $LOCK_DIR"
  fi
}

release_lock() {
  if [[ "$LOCK_MODE" == "flock" && -n "$LOCK_FD" ]]; then
    eval "exec ${LOCK_FD}>&-" || true
  elif [[ "$LOCK_MODE" == "mkdir" ]]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}

require_repo() {
  [[ -d "$ROOT_DIR/.git" ]] || fail "REPOSITORY_NOT_FOUND"
  cd "$ROOT_DIR"
  [[ -n "$(git rev-parse --show-toplevel 2>/dev/null)" ]] || fail "WRONG_REPOSITORY_ROOT"
  [[ "$(git branch --show-current)" == "$BRANCH" ]] || fail "BRANCH_MUST_BE_MAIN"
}

required_files() {
  local file
  for file in index.html styles.css script.js README.md AGENTS.md prompts/current.md prompts/evolve.md rsi-status.json .github/workflows/deploy-cloudflare.yml; do
    [[ -f "$file" ]] || fail "MISSING_REQUIRED_FILE:$file"
  done
}

require_clean() { [[ -z "$(git status --porcelain)" ]] || fail "DIRTY_WORKTREE"; }
current_remote_ref() { git rev-parse "$REMOTE/$BRANCH" 2>/dev/null || true; }
current_local_ref() { git rev-parse "$BRANCH" 2>/dev/null || true; }

sync_git() {
  log "Fetching $REMOTE/$BRANCH"
  git fetch "$REMOTE" "$BRANCH" || fail "GIT_FETCH_FAILED"
  local local_ref remote_ref base
  local_ref="$(current_local_ref)"
  remote_ref="$(current_remote_ref)"
  [[ -n "$local_ref" && -n "$remote_ref" ]] || fail "MISSING_LOCAL_OR_REMOTE_MAIN"
  base="$(git merge-base "$BRANCH" "$REMOTE/$BRANCH")" || fail "GIT_MERGE_BASE_FAILED"
  if [[ "$local_ref" == "$remote_ref" ]]; then
    log "Git state synchronized: $local_ref"
  elif [[ "$base" == "$local_ref" ]]; then
    log "Local main is behind origin/main; fast-forwarding"
    git pull --ff-only "$REMOTE" "$BRANCH" || fail "GIT_FAST_FORWARD_FAILED"
  elif [[ "$base" == "$remote_ref" ]]; then
    log "Local main is ahead of origin/main; attempting to push previous run"
    git push "$REMOTE" "$BRANCH" || fail "LOCAL_AHEAD_PUSH_FAILED"
    git fetch "$REMOTE" "$BRANCH" || fail "GIT_FETCH_AFTER_PUSH_FAILED"
    [[ "$(current_local_ref)" == "$(current_remote_ref)" ]] || fail "LOCAL_REMOTE_STILL_UNSYNCED"
  else
    fail "DIVERGED_LOCAL_REMOTE"
  fi
  require_clean
}

generation_number() {
  local path name number
  local highest=0
  shopt -s nullglob
  shopt -s extglob
  for path in generations/gen-*.json; do
    name="$(basename "$path")"
    if [[ "$name" =~ ^gen-([0-9]+)\.json$ ]]; then
      number="${BASH_REMATCH[1]}"
      number="${number##+(0)}"
      [[ -n "$number" ]] || number=0
      (( number > highest )) && highest=$number
    fi
  done
  shopt -u nullglob
  shopt -u extglob
  printf '%d' "$highest"
}

prompt_version() { sed -nE 's/^Version:[[:space:]]*(v[0-9]+\.[0-9]+).*$/\1/p' prompts/current.md | head -n 1; }

pacific_timestamp() {
  "$PYTHON_PATH" - "$TIMEZONE" <<'PY'
import sys
from datetime import datetime
from zoneinfo import ZoneInfo
print(datetime.now(ZoneInfo(sys.argv[1])).isoformat(timespec="seconds"))
PY
}

python_prompt_version() {
  "$PYTHON_PATH" - "$1" <<'PY'
import json, sys
print(json.loads(open(sys.argv[1], encoding="utf-8").read())["promptVersionAfter"])
PY
}

no_change_streak() {
  "$PYTHON_PATH" <<'PY'
import glob, json
records = []
for filename in glob.glob("generations/gen-*.json"):
    try:
        data = json.load(open(filename, encoding="utf-8"))
        records.append((int(data.get("generation", 0)), data.get("decision")))
    except (OSError, ValueError, TypeError):
        pass
streak = 0
for _, decision in sorted(records, reverse=True):
    if decision != "NO_CHANGE":
        break
    streak += 1
print(streak)
PY
}

write_status_file() {
  local generation_file="$1"
  "$PYTHON_PATH" - "$generation_file" <<'PY'
import glob, json, sys
from datetime import datetime, timezone
from pathlib import Path

generation_file = Path(sys.argv[1])
current = json.loads(generation_file.read_text(encoding="utf-8"))
records = []
for filename in glob.glob("generations/gen-*.json"):
    try:
        data = json.loads(Path(filename).read_text(encoding="utf-8"))
        records.append((int(data["generation"]), data))
    except (OSError, ValueError, KeyError, TypeError):
        continue
records.sort(key=lambda item: item[0], reverse=True)
streak = 0
for _, data in records:
    if data.get("decision") != "NO_CHANGE":
        break
    streak += 1
generation = int(current["generation"])
date = current["date"]
next_padded = f"{generation:03d}"
status = {
    "schemaVersion": 1,
    "project": "EvoDesign",
    "repository": "https://github.com/k-tech/evodesign",
    "productionUrl": "https://evodesign.pages.dev/",
    "currentGeneration": generation,
    "nextGeneration": generation + 1,
    "promptVersion": current.get("promptVersionAfter"),
    "scheduler": {
        "provider": "Codex Automation",
        "automationId": "evodesign-daily-evolution",
        "schedule": "daily at 09:00",
        "timezone": "America/Los_Angeles",
        "status": "ACTIVE",
    },
    "lastRun": {
        "generation": generation,
        "previousGeneration": int(current["previousGeneration"]),
        "date": date,
        "timestamp": current.get("timestamp", current.get("startedAt")),
        "decision": current.get("decision"),
        "status": "success",
        "evidence": {
            "reflection": f"reflections/{date}-gen-{next_padded}.md",
            "generation": f"generations/gen-{next_padded}.json",
            "log": f"logs/{date}-gen-{next_padded}.log",
        },
    },
    "consecutiveNoChange": streak,
    "updatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
}
Path("rsi-status.json").write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

validate_generation_json() {
  local file="$1" expected="$2" previous="$3" run_date="$4" prompt_before="$5"
  "$PYTHON_PATH" - "$file" "$expected" "$previous" "$run_date" "$prompt_before" <<'PY'
import json, sys
from pathlib import Path
file, expected, previous, run_date, prompt_before = sys.argv[1:]
data = json.loads(Path(file).read_text(encoding="utf-8"))
checks = {"generation": int(expected), "previousGeneration": int(previous), "date": run_date, "promptVersionBefore": prompt_before, "status": "completed"}
for key, value in checks.items():
    actual = data.get(key)
    if key in {"generation", "previousGeneration"}:
        try:
            actual = int(actual)
        except (TypeError, ValueError):
            pass
    if actual != value:
        raise SystemExit(f"{file}: {key} must equal {value!r}")
if data.get("decision") not in {"CHANGE", "NO_CHANGE"}:
    raise SystemExit(f"{file}: decision must be CHANGE or NO_CHANGE")
if not data.get("timestamp", data.get("startedAt")):
    raise SystemExit(f"{file}: timestamp is required")
if not data.get("promptVersionAfter"):
    raise SystemExit(f"{file}: promptVersionAfter is required")
PY
}

validate_evidence() {
  local current="$1" next="$2" date_value="$3" timestamp="$4" prompt_before="$5"
  local current_pad next_pad reflection generation evidence_log
  current_pad="$(printf '%03d' "$current")"
  next_pad="$(printf '%03d' "$next")"
  reflection="reflections/${date_value}-gen-${next_pad}.md"
  generation="generations/gen-${next_pad}.json"
  evidence_log="logs/${date_value}-gen-${next_pad}.log"
  [[ -f "$reflection" ]] || fail "MISSING_REFLECTION:$reflection"
  [[ -f "$generation" ]] || fail "MISSING_GENERATION_JSON:$generation"
  [[ -f "$evidence_log" ]] || fail "MISSING_EVOLUTION_LOG:$evidence_log"
  [[ -s "$reflection" && -s "$evidence_log" ]] || fail "EMPTY_EVIDENCE"
  validate_generation_json "$generation" "$next" "$current" "$date_value" "$prompt_before" || fail "INVALID_GENERATION_JSON"
  grep -q "Generation: ${next_pad}" "$reflection" || fail "REFLECTION_GENERATION_MISMATCH"
  grep -qE '^Decision: (CHANGE|NO_CHANGE)$' "$reflection" || fail "REFLECTION_DECISION_MISSING"
  [[ -f index.html && -f styles.css && -f script.js ]] || fail "REQUIRED_SITE_FILE_MISSING"
  [[ "$(prompt_version)" == "$(python_prompt_version "$generation")" ]] || fail "PROMPT_VERSION_AFTER_MISMATCH"
  log "Evidence validation passed for generation $next_pad (previous $current_pad, timestamp $timestamp)"
}

validate_changes() {
  local status_line path code
  while IFS= read -r status_line; do
    [[ -n "$status_line" ]] || continue
    code="${status_line:0:2}"
    path="${status_line:3}"
    [[ "$path" == "index.html" || "$path" == "styles.css" || "$path" == "script.js" || "$path" == "README.md" || "$path" == "rsi-status.json" || "$path" == prompts/* || "$path" == reflections/* || "$path" == generations/* || "$path" == logs/* ]] || fail "REVIEW_REQUIRED:PROTECTED_FILE:$path"
    [[ "$code" != *D* ]] || fail "REVIEW_REQUIRED:DELETED_FILE:$path"
  done < <(git status --porcelain)
}

codex_command() {
  if [[ "$CODEX_PATH" == *.ps1 ]]; then
    local native_path="$CODEX_PATH"
    if command -v cygpath >/dev/null 2>&1; then native_path="$(cygpath -w "$CODEX_PATH")"; fi
    printf '%s\0' powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$native_path"
  else
    printf '%s\0' "$CODEX_PATH"
  fi
}

codex_login_status() {
  if [[ -n "${CODEX_ACCESS_TOKEN:-}" || -n "${OPENAI_API_KEY:-}" ]]; then
    return 0
  fi
  local -a invoke
  mapfile -d '' -t invoke < <(codex_command)
  "${invoke[@]}" login status
}

run_codex() {
  [[ -n "$CODEX_PATH" ]] || fail "CODEX_NOT_FOUND"
  local next_pad
  next_pad="$(printf '%03d' "$(( $(generation_number) + 1 ))")"
  local codex_log="$STATE_DIR/codex-${RUN_DATE}-gen-${next_pad}.log"
  local -a invoke
  mapfile -d '' -t invoke < <(codex_command)
  log "Starting Codex with workspace-write; output: $codex_log"
  cat "$STATE_DIR/run-context-${RUN_DATE}-gen-${next_pad}.txt" | "${invoke[@]}" exec --model "$CODEX_MODEL" --approve-for-me --cd "$ROOT_DIR" - | tee "$codex_log"
}

preflight() {
  log "PREFLIGHT_START"
  require_repo
  required_files
  require_clean
  git ls-remote "$REMOTE" "refs/heads/$BRANCH" >/dev/null || fail "GIT_CREDENTIALS_OR_REMOTE_UNAVAILABLE"
  local current next current_pad next_pad
  current="$(generation_number)"
  (( current >= 1 )) || fail "NO_GENERATION_RECORD"
  next=$((current + 1))
  current_pad="$(printf '%03d' "$current")"
  next_pad="$(printf '%03d' "$next")"
  [[ -f "generations/gen-${current_pad}.json" ]] || fail "CURRENT_GENERATION_FILE_MISSING"
  [[ ! -e "generations/gen-${next_pad}.json" ]] || fail "NEXT_GENERATION_ALREADY_EXISTS"
  [[ -n "$CODEX_PATH" ]] || fail "CODEX_NOT_FOUND"
  [[ -n "$CODEX_MODEL" ]] || fail "CODEX_MODEL_NOT_FOUND"
  codex_login_status >/dev/null 2>&1 || fail "CODEX_AUTH_UNAVAILABLE"
  [[ -n "$LOCK_MODE" ]] || fail "LOCK_UNAVAILABLE"
  log "PASS repository=$ROOT_DIR"
  log "PASS branch=$BRANCH"
  log "PASS worktree=clean"
  log "PASS origin/main=available"
  log "PASS current_generation=$current_pad"
  log "PASS next_generation=$next_pad"
  log "PASS codex=$CODEX_PATH"
  log "PASS codex_model=$CODEX_MODEL"
  log "PASS codex_auth=usable"
  log "PASS required_prompts_and_rules=present"
  log "PASS git_credentials=usable"
  log "PASS lock=${FLOCK_PATH:-mkdir-fallback}"
  log "PASS workflow=.github/workflows/deploy-cloudflare.yml"
  log "PREFLIGHT_PASS"
}

main() {
  acquire_lock
  trap release_lock EXIT
  if [[ "${1:-}" == "--preflight" ]]; then
    preflight
    return 0
  fi
  require_repo
  required_files
  require_clean
  [[ -n "$CODEX_MODEL" ]] || fail "CODEX_MODEL_NOT_FOUND"
  sync_git
  local current next current_pad next_pad timestamp
  current="$(generation_number)"
  next=$((current + 1))
  current_pad="$(printf '%03d' "$current")"
  next_pad="$(printf '%03d' "$next")"
  [[ ! -e "generations/gen-${next_pad}.json" ]] || fail "NEXT_GENERATION_ALREADY_EXISTS"
  RUN_TIMESTAMP="$(pacific_timestamp)"
  RUN_DATE="${RUN_TIMESTAMP%%T*}"
  PROMPT_VERSION="$(prompt_version)"
  [[ -n "$PROMPT_VERSION" ]] || fail "PROMPT_VERSION_NOT_FOUND"
  NO_CHANGE_STREAK="$(no_change_streak)"
  timestamp="$RUN_TIMESTAMP"
  cat > "$STATE_DIR/run-context-${RUN_DATE}-gen-${next_pad}.txt" <<EOF
RUN CONTEXT (authoritative; copy these values into evidence)
Generation: ${next_pad}
Previous Generation: ${current_pad}
Date: ${RUN_DATE}
Timestamp: ${RUN_TIMESTAMP}
Prompt Version: ${PROMPT_VERSION}
Timezone: ${TIMEZONE}
Recent NO_CHANGE streak: ${NO_CHANGE_STREAK}

Follow AGENTS.md and prompts/evolve.md. Always produce these evidence files:
reflections/${RUN_DATE}-gen-${next_pad}.md
generations/gen-${next_pad}.json
logs/${RUN_DATE}-gen-${next_pad}.log
If the reflection supports CHANGE, also implement the smallest useful change in the allowed files. The evidence list is not a restriction on website implementation. The runner owns rsi-status.json; do not edit it directly.
If the recent NO_CHANGE streak is two or more, do not repeat the same contract-based NO_CHANGE reason; either make a justified minimal change or document a new concrete evidence gap.
Do not commit or push. The runner owns Git operations.
Do not modify protected files, credentials, secrets, .git, .github/workflows, or Cloudflare configuration.
EOF
  log "RUN_CONTEXT current=$current_pad next=$next_pad date=$RUN_DATE timestamp=$RUN_TIMESTAMP prompt=$PROMPT_VERSION no_change_streak=$NO_CHANGE_STREAK"
  run_codex
  validate_changes
  validate_evidence "$current" "$next" "$RUN_DATE" "$timestamp" "$PROMPT_VERSION"
  write_status_file "generations/gen-${next_pad}.json"
  git add -- index.html styles.css script.js README.md rsi-status.json prompts reflections generations logs
  validate_changes
  git diff --cached --quiet && fail "NO_EVOLUTION_CHANGES_STAGED"
  git commit -m "evolution: generation ${next_pad}"
  git push "$REMOTE" "$BRANCH"
  log "EVOLUTION_COMPLETE generation=$next_pad"
}

main "$@"
