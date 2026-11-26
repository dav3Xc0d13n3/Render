#!/usr/bin/env bash
set -euo pipefail

# ---- start sshd ----
mkdir -p /run/sshd
/usr/sbin/sshd -D &
SSHD_PID=$!

# ---- start Python WebSocket bridge ----
python3 /proxy.py &

# ---- snapshot sync (restore on boot, save every 60s) ----
if [[ -n "${GIT_SNAPSHOT_REPO:-}" && -n "${GIT_SNAPSHOT_TOKEN:-}" ]]; then
  git config --global user.email "ollie@bench.local"
  git config --global user.name "ollie"
  
  # 1. RESTORE ON BOOT
  echo "Restoring snapshot..."
  SNAP_DIR=$(mktemp -d)
  git clone --depth 1 "https://${GIT_SNAPSHOT_TOKEN}@github.com/${GIT_SNAPSHOT_REPO}.git" "$SNAP_DIR" 2>/dev/null || true
  if [[ -d "$SNAP_DIR/root" ]]; then
    rsync -a --delete "$SNAP_DIR/root/" /root/
  fi
  rm -rf "$SNAP_DIR"
  echo "Restore complete."

  # 2. AUTO-SAVE LOOP (Every 60 seconds)
  (
    while true; do
      sleep 60
      LOOP_DIR=$(mktemp -d)
      
      # Clone or init repo
      git clone --depth 1 "https://${GIT_SNAPSHOT_TOKEN}@github.com/${GIT_SNAPSHOT_REPO}.git" "$LOOP_DIR" 2>/dev/null || {
        mkdir -p "$LOOP_DIR/root"
        cd "$LOOP_DIR" && git init -b main
        git remote add origin "https://${GIT_SNAPSHOT_TOKEN}@github.com/${GIT_SNAPSHOT_REPO}.git"
      }
      
      # Sync files (EXCLUDING the storage folder so big chunks don't crash the loop)
      mkdir -p "$LOOP_DIR/root"
      rsync -a --delete --exclude 'storage' /root/ "$LOOP_DIR/root/"
      
      # Commit and push
      cd "$LOOP_DIR"
      git add -A
      if ! git diff --cached --quiet; then
        git commit -m "auto snapshot $(date -u +%FT%TZ)"
        git push origin main 2>/dev/null || true
      fi
      
      rm -rf "$LOOP_DIR"
      cd /root
    done
  ) &
fi

# ---- run setup script if it exists (in background so it doesn't block boot) ----
if [[ -f /root/setup.sh ]]; then
  (bash /root/setup.sh > /root/setup.log 2>&1) &
fi

wait $SSHD_PID
