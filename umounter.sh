#!/system/bin/sh
# nomount-umount.sh — NoMountFS kernel umount list management
#
# This script manages the NoMountFS kernel-level umount list,
# allowing you to add or remove paths that should be automatically
# unmounted for new app processes.
#
# Usage:
#   nomount-umount.sh add <path>    - Add a path to the umount list
#   nomount-umount.sh del <path>    - Remove a path from the umount list
#   nomount-umount.sh list          - List all paths in the umount list
#   nomount-umount.sh clear         - Clear all paths from the umount list
#   nomount-umount.sh enable        - Enable kernel umount
#   nomount-umount.sh disable       - Disable kernel umount
#   nomount-umount.sh status        - Show current status

set -e

NOMOUNT_PROC="/proc/nomountfs"
NOMOUNT_UMOUNT_LIST="/data/adb/nomountfs_umount_list"
LOG_TAG="NoMountFS-umount"

log() {
    echo "[$LOG_TAG] $*"
    echo "[$LOG_TAG] $*" >> /dev/kmsg 2>/dev/null || true
}

# Check if NoMountFS kernel module is loaded
check_module() {
    if ! grep -q "nomountfs" /proc/filesystems 2>/dev/null; then
        log "ERROR: NoMountFS module is not loaded"
        exit 1
    fi
}

# Add a path to the umount list
cmd_add() {
    local path="$1"
    [ -z "$path" ] && { log "ERROR: path required"; exit 1; }
    mkdir -p "${NOMOUNT_UMOUNT_LIST%/*}"
    if ! grep -qxF "$path" "$NOMOUNT_UMOUNT_LIST" 2>/dev/null; then
        echo "$path" >> "$NOMOUNT_UMOUNT_LIST"
        log "Added to umount list: $path"
    fi
    echo "$path" > "$NOMOUNT_PROC/umount_add" 2>/dev/null || true
}

# Remove a path from the umount list
cmd_del() {
    local path="$1"
    [ -z "$path" ] && { log "ERROR: path required"; exit 1; }
    [ -f "$NOMOUNT_UMOUNT_LIST" ] && sed -i "\|^$path\$|d" "$NOMOUNT_UMOUNT_LIST" 2>/dev/null
    log "Removed from umount list: $path"
    echo "$path" > "$NOMOUNT_PROC/umount_del" 2>/dev/null || true
}

# List all paths in the umount list
cmd_list() {
    [ -f "$NOMOUNT_PROC/umount_list" ] && {
        echo "=== NoMountFS Kernel Umount List ==="
        cat "$NOMOUNT_PROC/umount_list"
    }
}

# Clear all paths from the umount list
cmd_clear() {
    rm -f "$NOMOUNT_UMOUNT_LIST"
    log "Cleared umount list"
    echo "1" > "$NOMOUNT_PROC/umount_clear" 2>/dev/null || true
}

# Enable kernel umount
cmd_enable() {
    echo "1" > "$NOMOUNT_PROC/umount_enabled" 2>/dev/null && log "Kernel umount enabled" || log "Kernel interface not found"
}

# Disable kernel umount
cmd_disable() {
    echo "0" > "$NOMOUNT_PROC/umount_enabled" 2>/dev/null && log "Kernel umount disabled" || log "Kernel interface not found"
}

# Show current status
cmd_status() {
    echo "=== NoMountFS Status ==="
    [ -d "$NOMOUNT_PROC" ] && echo "Module: loaded" || echo "Module: not loaded"
    
    local count=0
    [ -f "$NOMOUNT_UMOUNT_LIST" ] && count=$(grep -c . "$NOMOUNT_UMOUNT_LIST" 2>/dev/null || echo 0)
    echo "Persistent umount entries: $count"

    # Check kernel umount status
    if [ -f "$NOMOUNT_PROC/umount_enabled" ]; then
        [ "$(cat "$NOMOUNT_PROC/umount_enabled" 2>/dev/null)" = "1" ] && echo "Kernel umount: enabled"
         || echo "Kernel umount: disabled"
    else
        echo "Kernel umount: not available"
    fi

    echo ""
    echo "=== Active NoMountFS Mounts ==="
    grep " nomountfs " /proc/mounts | cut -d' ' -f2 2>/dev/null || echo "(none)"
}

restore_list() {
    [ -f "$NOMOUNT_UMOUNT_LIST" ] || return 0
    [ -f "$NOMOUNT_PROC/umount_add" ] || return 0

    log "Restoring umount list from persistent storage..."
    while IFS= read -r path; do
        [ -n "$path" ] && echo "$path" > "$NOMOUNT_PROC/umount_add" 2>/dev/null || true
    done < "$NOMOUNT_UMOUNT_LIST"
    log "Umount list restored"
}

# Main
case "${1:-}" in
    add)
        check_module
        cmd_add "$2"
        ;;
    del)
        check_module
        cmd_del "$2"
        ;;
    list)
        cmd_list
        ;;
    clear)
        cmd_clear
        ;;
    enable)
        cmd_enable
        ;;
    disable)
        cmd_disable
        ;;
    status)
        cmd_status
        ;;
    restore)
        restore_list
        ;;
    *)
        echo "NoMountFS Kernel Umount Manager"
        echo ""
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  add <path>     Add a path to the umount list"
        echo "  del <path>     Remove a path from the umount list"
        echo "  list           List all paths in the umount list"
        echo "  clear          Clear all paths from the umount list"
        echo "  enable         Enable kernel umount"
        echo "  disable        Disable kernel umount"
        echo "  status         Show current status"
        echo ""
        echo "Examples:"
        echo "  $0 add /system"
        echo "  $0 add /vendor"
        echo "  $0 list"
        echo "  $0 del /system"
        ;;
esac
