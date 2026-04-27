#!/system/bin/sh
# metainstall.sh — NoMountFS Metamodule installation hook
# Sourced during regular module installation (NOT the metamodule itself).
# Inherits all variables and functions from KernelSU's built-in install.sh.

META_DIR="/data/adb/modules/meta-nomountfs"
ORDER_FILE="$META_DIR/mount_order"

# 1. MODPATH fallback
# We use a native glob loop instead of the very slow 'find -exec'
if [ -z "$MODPATH" ]; then
    for dir in /data/adb/modules_update/*; do
        if [ -f "$dir/module.prop" ]; then
            MODPATH="$dir"
            break
        fi
    done
fi

# Clean end bars and extract the ID
MODPATH="${MODPATH%/}"
INSTALL_ID="${MODPATH##*/}"

ui_print "- [meta-nomountfs] Validating NoMountFS environment..."

# Check 1: VFS Registration
if grep -q "nomountfs" /proc/filesystems 2>/dev/null; then
    ui_print "  ✓ nomountfs found in /proc/filesystems"
else
    ui_print "  ! nomountfs NOT in /proc/filesystems"
    ui_print "    Ensure the NoMountFS .ko is loaded before next reboot."
fi

# Check 2: Conflict Warning
for OTHER_META in /data/adb/modules/*/metamount.sh; do
    [ -f "$OTHER_META" ] || continue
    OTHER_DIR="${OTHER_META%/*}"
    OTHER_ID="${OTHER_DIR##*/}"
    [ "$OTHER_ID" = "meta-nomountfs" ] && continue
    if [ ! -f "$OTHER_DIR/disable" ]; then
        ui_print "  ! WARNING: Another mount metamodule is active: $OTHER_ID"
        ui_print "    This may conflict. Disable one of them."
    fi
done

# Check 3: Partition Validation & mount_order Registration
if [ -n "$INSTALL_ID" ] && [ -d "$META_DIR" ]; then
    HAS_PART=0
    for PART in system vendor product system_ext odm oem; do
        if [ -d "$MODPATH/$PART" ]; then
            HAS_PART=1
            break
        fi
    done

    if [ $HAS_PART -eq 0 ]; then
        ui_print "  = $INSTALL_ID has no partition folders — skipping mount_order"
    elif grep -qxF "$INSTALL_ID" "$ORDER_FILE" 2>/dev/null; then
        ui_print "  = $INSTALL_ID already in mount_order — order unchanged"
    else
        echo "$INSTALL_ID" >> "$ORDER_FILE"
        ui_print "  + Registered $INSTALL_ID in mount_order (position: bottom)"
    fi
else
    ui_print "  ! Could not register in mount_order: META_DIR missing or empty ID"
fi

ui_print "- [meta-nomountfs] Running standard module installation..."
install_module
ui_print "- [meta-nomountfs] Module installed successfully."
