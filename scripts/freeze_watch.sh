#!/usr/bin/env bash
# EvoDesign Freeze Watch (read-only)
#
# Runs scripts/evolve.sh --preflight as a passive observer and converts its
# freeze-watch signal into a structured exit code:
#   0  preflight OK and freeze_watch is `ok ...`           -> QUIET
#   1  preflight OK but freeze_watch is FREEZE_RECOVERY    -> NOTIFY (suspected freeze)
#   2  preflight aborted                                   -> NOTIFY (drift / infra problem)
#   3  freeze_watch line missing or unparseable             -> NOTIFY (probe broke)
#
# The script never modifies files, never commits, never pushes. It exists so
# a separate Codex heartbeat automation can run preflight out-of-band and
# notify within ~one scheduler window if the real runner has frozen.

set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"

log_file="$(mktemp 2>/dev/null || mktemp -t evodesign)"
trap 'rm -f "$log_file"' EXIT

# Capture preflight exit without tripping set -e.
bash scripts/evolve.sh --preflight >"$log_file" 2>&1 || preflight_rc=$?
preflight_rc="${preflight_rc:-0}"

emit() { printf '%s\n' "$1"; }

if (( preflight_rc != 0 )); then
  emit "RESULT=preflight_aborted rc=$preflight_rc"
  tail -n 8 "$log_file" | sed 's/^/  /'
  exit 2
fi

freeze_line="$(grep -E '^\[[0-9TZ:.-]+\] PASS freeze_watch=' "$log_file" | tail -n1 || true)"

if [[ -z "$freeze_line" ]]; then
  emit "RESULT=freeze_watch_line_missing"
  tail -n 8 "$log_file" | sed 's/^/  /'
  exit 3
fi

note="${freeze_line##*PASS freeze_watch=}"
case "$note" in
  ok*)
    emit "RESULT=ok detail='$note'"
    exit 0
    ;;
  FREEZE_RECOVERY*)
    emit "RESULT=freeze_suspected detail='$note'"
    exit 1
    ;;
  *)
    emit "RESULT=freeze_watch_unrecognized detail='$note'"
    exit 3
    ;;
esac
