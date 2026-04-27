#!/system/bin/sh
# metamount.sh — NoMountFS Metamodule mount script
#
# Features:
#   1. Passes module paths directly to the kernel. No copying or chcon loops.
#   2. Issues exactly ONE nomountfs mount per partition.
#   3. Layer stacking via $MODDIR/mount_order:
#        - One module ID per line, top = lowest priority, bottom = highest.
#        - Bottom entry mounts last → wins on file collision.
#        - Modules not listed in mount_order are appended after listed ones,
#          sorted alphabetically (so they layer above listed modules by default,
#          unless you explicitly place them in mount_order).
#        - If mount_order is absent, all modules are processed alphabetically
#          with the last letter winning on collision.
#
# Mount model:
#   mount -t nomountfs none <DEST>
#         -o upperdir=<MERGED_TREE>,lowerdir=<DEST>

MODDIR="${0%/*}"
MODULES_DIR="/data/adb/modules"
PARTITIONS="system vendor product system_ext odm oem"
ORDER_FILE="$MODDIR/mount_order"

STATE_DIR="/dev/nomountfs_state"
mkdir -p "$STATE_DIR"

# --- helpers ---
log() {
    local msg="[meta-nomountfs] $*"
    echo "$msg" >> /dev/kmsg 2>/dev/null
    echo "$msg" >> "$STATE_DIR/mount.log" 2>/dev/null
}

wait_for_fs() {
    local retries=10
    while [ $retries -gt 0 ]; do
        grep -q "nomountfs" /proc/filesystems 2>/dev/null && return 0
        retries=$((retries - 1))
        sleep 1
    done
    return 1
}

# --- Module List Builder ---
# Returns list ordered from Lowest priority to Highest priority
build_module_list() {
    MODULE_LIST=""
    local ALPHA_LIST=""
    local LISTED=""

    # 1. Alphabetical pass (fast native globbing)
    for MOD in "$MODULES_DIR"/*; do
        [ -d "$MOD" ] || continue
        local MODID="${MOD##*/}"
        [ "$MODID" = "meta-nomountfs" ] && continue
        [ -f "$MOD/disable" ] || [ -f "$MOD/skip_mount" ] && continue
        ALPHA_LIST="$ALPHA_LIST $MODID"
    done
    ALPHA_LIST="$(echo "$ALPHA_LIST" | tr ' ' '\n' | grep -v '^$' | sort | tr '\n' ' ')"

    # 2. Ordered pass from file
    if [ -f "$ORDER_FILE" ]; then
        while IFS= read -r LINE || [ -n "$LINE" ]; do
            LINE="$(echo "$LINE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            [ -z "$LINE" ] && continue
            case "$LINE" in '#'*) continue ;; esac

            local MOD="$MODULES_DIR/$LINE"
            [ -d "$MOD" ] || continue
            [ -f "$MOD/disable" ] || [ -f "$MOD/skip_mount" ] && continue

            MODULE_LIST="$MODULE_LIST $MOD"
            LISTED="$LISTED $LINE"
        done < "$ORDER_FILE"
    fi

    # 3. Append unlisted modules
    for MODID in $ALPHA_LIST; do
        local already=0
        for L in $LISTED; do
            [ "$L" = "$MODID" ] && { already=1; break; }
        done
        [ $already -eq 1 ] && continue
        MODULE_LIST="$MODULE_LIST $MODULES_DIR/$MODID"
    done
}

# --- Mount Execution ---
mount_partition() {
    local PART="$1"
    local DEST="$2"

    [ -d "$DEST" ] || return 0
    grep -q " $DEST nomountfs " /proc/mounts 2>/dev/null && return 0

    # Build the lowerdir string (Highest priority first for the kernel stack)
    # The kernel evaluates left-to-right, so we must reverse the MODULE_LIST
    local BRANCHES=""
    
    # Reverse iteration trick in bash
    local REV_LIST=""
    for MOD in $MODULE_LIST; do
        REV_LIST="$MOD $REV_LIST"
    done

    for MOD in $REV_LIST; do
        local SRC="$MOD/$PART"
        if [ -d "$SRC" ]; then
            if [ -z "$BRANCHES" ]; then
                BRANCHES="$SRC"
            else
                BRANCHES="$BRANCHES:$SRC"
            fi
        fi
    done

    # If no modules affect this partition, skip
    [ -z "$BRANCHES" ] && return 0

    # Append the real physical partition at the very bottom
    BRANCHES="$BRANCHES:$DEST"

    log "Mounting $PART with branches: $BRANCHES"

    # Fast native mount with no copying or chcon loops. The kernel will handle everything.
    mount -t nomountfs none "$DEST" -o "lowerdir=$BRANCHES" 2>>"$STATE_DIR/mount.log"
    local rc=$?
    
    if [ $rc -eq 0 ]; then
        log "OK: $PART -> $DEST"
        echo "$DEST" >> "$STATE_DIR/active_mounts"
        echo "$DEST" >> "$STATE_DIR/pending_mounts"
    else
        log "FAIL (rc=$rc): $PART -> $DEST"
    fi
    return $rc
}

# --- Main ---
if ! wait_for_fs; then
    log "FATAL: nomountfs missing. Aborting."
    exit 1
fi

build_module_list

for PART in $PARTITIONS; do
    TARGET="/$PART"
    [ "$PART" = "system_ext" ] && TARGET="/system_ext" # Catch special cases if any
    mount_partition "$PART" "$TARGET"
done

log "Mount pass complete."
