#!/system/bin/sh
# metauninstall.sh — NoMountFS Metamodule uninstall hook (Extreme Optimization)
#
# Called by KernelSU before a module's directory is removed.
# $1 = MODULE_ID of the module being uninstalled.
#
# Actions:
#   1. Remove the module's ID from mount_order.
#   2. Build the new lowerdir string excluding the uninstalled module.
#   3. Unmount the current nomountfs overlay.
#   4. Re-mount instantly using the new lowerdir string (if modules remain).

MODULE_ID="$1"
META_DIR="/data/adb/modules/meta-nomountfs"
ORDER_FILE="$META_DIR/mount_order"
STATE_DIR="/dev/nomountfs_state"
MODULES_DIR="/data/adb/modules"
PARTITIONS="system vendor product system_ext odm oem"

log() {
    local msg="[meta-nomountfs] metauninstall: $*"
    echo "$msg" >> /dev/kmsg 2>/dev/null
    echo "$msg" >> "$STATE_DIR/mount.log" 2>/dev/null
}

is_nomountfs() {
    grep -q " $1 nomountfs " /proc/mounts 2>/dev/null
}

if [ -z "$MODULE_ID" ]; then
    log "ERROR: no MODULE_ID passed. Aborting."
    exit 1
fi

log "Uninstalling module: $MODULE_ID"

# ─── Step 1: remove from mount_order ─────────────────────────────────────────

if [ -f "$ORDER_FILE" ]; then
    TMP_ORDER="$STATE_DIR/mount_order_tmp_$$"
    grep -vx "$MODULE_ID" "$ORDER_FILE" > "$TMP_ORDER" 2>/dev/null
    mv -f "$TMP_ORDER" "$ORDER_FILE"
    log "Removed $MODULE_ID from mount_order."
fi

# ─── Step 2: rebuild module list (excluding the removed module) ──────────────

build_module_list_except() {
    local EXCLUDE="$1"
    MODULE_LIST=""
    local ALPHA_LIST=""
    local LISTED=""

    for MOD in "$MODULES_DIR"/*; do
        [ -d "$MOD" ] || continue
        local MODID="${MOD##*/}"
        [ "$MODID" = "meta-nomountfs" ] && continue
        [ "$MODID" = "$EXCLUDE" ] && continue
        [ -f "$MOD/disable" ] || [ -f "$MOD/skip_mount" ] && continue
        ALPHA_LIST="$ALPHA_LIST $MODID"
    done
    ALPHA_LIST="$(echo "$ALPHA_LIST" | tr ' ' '\n' | grep -v '^$' | sort | tr '\n' ' ')"

    if [ -f "$ORDER_FILE" ]; then
        while IFS= read -r LINE || [ -n "$LINE" ]; do
            LINE="$(echo "$LINE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            [ -z "$LINE" ] && continue
            case "$LINE" in '#'*) continue ;; esac
            [ "$LINE" = "$EXCLUDE" ] && continue

            local MOD="$MODULES_DIR/$LINE"
            [ -d "$MOD" ] || continue
            [ -f "$MOD/disable" ] || [ -f "$MOD/skip_mount" ] && continue

            MODULE_LIST="$MODULE_LIST $MOD"
            LISTED="$LISTED $LINE"
        done < "$ORDER_FILE"
    fi

    for MODID in $ALPHA_LIST; do
        local already=0
        for L in $LISTED; do
            [ "$L" = "$MODID" ] && { already=1; break; }
        done
        [ $already -eq 1 ] && continue
        MODULE_LIST="$MODULE_LIST $MODULES_DIR/$MODID"
    done
}

# ─── Step 3: Unmount & Remount instantly ─────────────────────────────────────

build_module_list_except "$MODULE_ID"
log "Remaining module order:$MODULE_LIST"

# Reverse the list to respect the priority of the VFS (Left = High priority)
REV_LIST=""
for MOD in $MODULE_LIST; do
    REV_LIST="$MOD $REV_LIST"
done

for PART in $PARTITIONS; do
    TARGET="/$PART"
    [ "$PART" = "system_ext" ] && TARGET="/system_ext"

    is_nomountfs "$TARGET" || continue
    log "Unmounting $TARGET for rebuild..."

    if ! umount "$TARGET" 2>/dev/null; then
        umount -l "$TARGET" 2>/dev/null \
            && log "  lazy unmount: $TARGET" \
            || { log "  FAIL to unmount $TARGET — skipping"; continue; }
    fi

    # Build the lowerdir chain excluding the uninstalled module. 
    # The kernel will handle the remount with 0 overhead.
    BRANCHES=""
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

    if [ -z "$BRANCHES" ]; then
        log "  No remaining modules for $PART — leaving unmounted."
        continue
    fi

    # Append the physical partition at the end
    BRANCHES="$BRANCHES:$TARGET"

    mount -t nomountfs none "$TARGET" -o "lowerdir=$BRANCHES" 2>>"$STATE_DIR/mount.log"
    if [ $? -eq 0 ]; then
        log "  Re-mounted $PART -> $TARGET"
    else
        log "  FAIL to re-mount $PART -> $TARGET"
    fi
done

# ─── Step 4: Sync active mounts state ────────────────────────────────────────

if [ -f "$STATE_DIR/active_mounts" ]; then
    TMP="$STATE_DIR/active_mounts_tmp_$$"
    while IFS= read -r MNT; do
        is_nomountfs "$MNT" && echo "$MNT"
    done < "$STATE_DIR/active_mounts" > "$TMP"
    mv -f "$TMP" "$STATE_DIR/active_mounts"
fi

log "Done."
