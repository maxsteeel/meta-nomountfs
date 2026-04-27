#!/system/bin/sh
# boot-completed.sh — NoMountFS post-boot mount registration
#
# This script runs after boot is complete and registers all nomountfs
# mount points with the kernel umount manager.
#
# Usage: Called by service.sh after boot_completed
#
# Flow:
#   1. metamount.sh writes mount points to /dev/nomountfs_state/pending_mounts
#   2. Communicates directly with the kernel and updates persistent storage
#      without spawning child shell processes.

STATE_DIR="/dev/nomountfs_state"
PENDING_FILE="$STATE_DIR/pending_mounts"
NOMOUNT_PROC="/proc/nomountfs"
NOMOUNT_UMOUNT_LIST="/data/adb/nomountfs_umount_list"

log() {
    echo "[nomountfs-boot] $*" >> /dev/kmsg 2>/dev/null || true
}

[ -f "$PENDING_FILE" ] || exit 0

log "Starting post-boot mount registration..."

mkdir -p "${NOMOUNT_UMOUNT_LIST%/*}" 2>/dev/null || true

while IFS= read -r path || [ -n "$path" ]; do
    [ -z "$path" ] && continue
    log "Registering mount point with kernel umount: $path"
    echo "$path" > "$NOMOUNT_PROC/umount_add" 2>/dev/null || true
    if ! grep -qxF "$path" "$NOMOUNT_UMOUNT_LIST" 2>/dev/null; then
        echo "$path" >> "$NOMOUNT_UMOUNT_LIST"
    fi
done < "$PENDING_FILE"

rm -f "$PENDING_FILE"
log "Post-boot registration complete."
