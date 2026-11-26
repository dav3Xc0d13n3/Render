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
      
      git clone --depth 1 "https://${GIT_SNAPSHOT_TOKEN}@github.com/${GIT_SNAPSHOT_REPO}.git" "$LOOP_DIR" 2>/dev/null || {
        mkdir -p "$LOOP_DIR/root"
        cd "$LOOP_DIR" && git init -b main
        git remote add origin "https://${GIT_SNAPSHOT_TOKEN}@github.com/${GIT_SNAPSHOT_REPO}.git"
      }
      
      mkdir -p "$LOOP_DIR/root"
      rsync -a --delete --exclude 'storage' /root/ "$LOOP_DIR/root/"
      
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

  # 3. BIG FILE WATCHER (Every 2 minutes, finds files > 45MB and chunks them)
  (
    while true; do
      sleep 120
      
      # Find files over 45MB, ignoring the storage folder and cache
      while IFS= read -r -d '' BIG_FILE; do
        FILENAME=$(basename "$BIG_FILE")
        TARGET_DIR="/root/storage/chunks_${FILENAME}"
        mkdir -p "$TARGET_DIR"
        
        echo "Detected big file: $FILENAME. Splitting..."
        split -b 45M "$BIG_FILE" "${TARGET_DIR}/${FILENAME}.part_"
        
        # Push the chunks to GitHub
        LOOP_DIR=$(mktemp -d)
        git clone --depth 1 "https://${GIT_SNAPSHOT_TOKEN}@github.com/${GIT_SNAPSHOT_REPO}.git" "$LOOP_DIR" 2>/dev/null || {
          mkdir -p "$LOOP_DIR/storage"
          cd "$LOOP_DIR" && git init -b main
          git remote add origin "https://${GIT_SNAPSHOT_TOKEN}@github.com/${GIT_SNAPSHOT_REPO}.git"
        }
        
        mkdir -p "$LOOP_DIR/storage"
        rsync -a "$TARGET_DIR" "$LOOP_DIR/storage/"
        
        cd "$LOOP_DIR"
        git add -A
        git commit -m "auto big upload: $FILENAME $(date +%s)"
        git push origin main 2>/dev/null || true
        cd /root
        
        # Clean up local disk
        rm -rf "$LOOP_DIR" "$TARGET_DIR"
        rm -f "$BIG_FILE"
        echo "Chunked and uploaded $FILENAME. Original deleted."
        
      done < <(find /root -maxdepth 1 -type f -size +45M -print0)
      
    done
  ) &
fi

# ---- run setup script ----
if [[ -f /root/setup.sh ]]; then
  (bash /root/setup.sh > /root/setup.log 2>&1) &
fi

wait $SSHD_PID
