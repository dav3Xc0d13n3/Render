#!/usr/bin/env bash
set -euo pipefail

# ---- restore snapshot before anything starts ----
if [[ -n "${GIT_SNAPSHOT_REPO:-}" && -n "${GIT_SNAPSHOT_TOKEN:-}" ]]; then
  git config --global user.email "ollie@bench.local"
  git config --global user.name "ollie"
  SNAP_DIR=$(mktemp -d)
  git clone --depth 1 "https://x-access-token:${GIT_SNAPSHOT_TOKEN}@github.com/${GIT_SNAPSHOT_REPO}.git" "$SNAP_DIR" 2>/dev/null || true
  if [[ -d "$SNAP_DIR/root" ]]; then
    rsync -a --delete "$SNAP_DIR/root/" /root/
  fi
  rm -rf "$SNAP_DIR"
fi

# ---- start sshd ----
mkdir -p /run/sshd
/usr/sbin/sshd -D &
SSHD_PID=$!

# ---- start Python WebSocket bridge ----
python3 /proxy.py &

# ---- periodic snapshot loop (every 5 min) ----
if [[ -n "${GIT_SNAPSHOT_REPO:-}" && -n "${GIT_SNAPSHOT_TOKEN:-}" ]]; then
  while sleep 300; do
    SNAP_DIR=$(mktemp -d)
    git clone --depth 1 "https://x-access-token:${GIT_SNAPSHOT_TOKEN}@github.com/${GIT_SNAPSHOT_REPO}.git" "$SNAP_DIR" 2>/dev/null || {
      mkdir -p "$SNAP_DIR/root"
      cd "$SNAP_DIR" && git init -b main
    }
    rsync -a --delete /root/ "$SNAP_DIR/root/"
    cd "$SNAP_DIR"
    git add -A
    git diff --cached --quiet || git commit -m "snapshot $(date -u +%FT%TZ)"
    git push "https://x-access-token:${GIT_SNAPSHOT_TOKEN}@github.com/${GIT_SNAPSHOT_REPO}.git" main 2>/dev/null || true
    rm -rf "$SNAP_DIR"
  done &
fi

wait $SSHD_PID
