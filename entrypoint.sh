#!/usr/bin/env bash
set -euo pipefail

# ---- ssh key from Render env ----
if [[ -n "${SSH_PUBLIC_KEY:-}" ]]; then
  echo "$SSH_PUBLIC_KEY" > /home/ollie/.ssh/authorized_keys
  chown ollie:ollie /home/ollie/.ssh/authorized_keys
  chmod 600 /home/ollie/.ssh/authorized_keys
else
  echo "warn: SSH_PUBLIC_KEY not set — key auth will fail" >&2
fi

# ---- restore snapshot before sshd starts ----
if [[ -n "${GIT_SNAPSHOT_REPO:-}" && -n "${GIT_SNAPSHOT_TOKEN:-}" ]]; then
  git config --global user.email "ollie@bench.local"
  git config --global user.name "ollie"
  SNAP_DIR=$(mktemp -d)
  git clone --depth 1 "https://x-access-token:${GIT_SNAPSHOT_TOKEN}@github.com/${GIT_SNAPSHOT_REPO}.git" "$SNAP_DIR" 2>/dev/null || true
  if [[ -d "$SNAP_DIR/home" ]]; then
    rsync -a --delete "$SNAP_DIR/home/" /home/ollie/
  fi
  rm -rf "$SNAP_DIR"
fi

# ---- start sshd ----
mkdir -p /run/sshd
/usr/sbin/sshd -D &
SSHD_PID=$!

# ---- start chisel reverse tunnel on Render's PORT ----
# Termux connects: chisel client https://<service>.onrender.com R:2222:localhost:22
chisel server --port "${PORT:-8080}" --reverse --socks5 &

# ---- periodic snapshot loop (every 5 min) ----
if [[ -n "${GIT_SNAPSHOT_REPO:-}" && -n "${GIT_SNAPSHOT_TOKEN:-}" ]]; then
  while sleep 300; do
    SNAP_DIR=$(mktemp -d)
    git clone --depth 1 "https://x-access-token:${GIT_SNAPSHOT_TOKEN}@github.com/${GIT_SNAPSHOT_REPO}.git" "$SNAP_DIR" 2>/dev/null || {
      mkdir -p "$SNAP_DIR/home"
      cd "$SNAP_DIR" && git init -b main
    }
    rsync -a --delete /home/ollie/ "$SNAP_DIR/home/"
    cd "$SNAP_DIR"
    git add -A
    git diff --cached --quiet || git commit -m "snapshot $(date -u +%FT%TZ)"
    git push "https://x-access-token:${GIT_SNAPSHOT_TOKEN}@github.com/${GIT_SNAPSHOT_REPO}.git" main 2>/dev/null || true
    rm -rf "$SNAP_DIR"
  done &
fi

wait $SSHD_PID
