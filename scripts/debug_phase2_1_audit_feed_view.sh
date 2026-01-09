#!/usr/bin/env bash
set -euo pipefail

TARGET="scripts/phase2_1_audit_feed_view_run.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: $TARGET not found."
  exit 3
fi

echo "==> Showing $TARGET (lines 100-140)"
nl -ba "$TARGET" | sed -n '100,140p'

echo
echo "==> Re-running with bash trace to capture the failing command"
# -x prints commands; pipe to tee so you keep a log
bash -x "$TARGET" 2>&1 | tee /tmp/phase2_1_audit_feed_view_trace.log

echo
echo "==> Trace log written to: /tmp/phase2_1_audit_feed_view_trace.log"
