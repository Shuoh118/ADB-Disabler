#!/system/bin/sh
# ADB Disabler — boot-time hardening (Magisk / KernelSU / APatch).
#
# Every run appends to /data/adb/adbdisabler/service.log so the WebUI can show
# what happened, and records the completion time in .../last_run. Pass --now to
# skip the boot-completed wait when the WebUI triggers a manual re-seal.

LOG_DIR=/data/adb/adbdisabler
LOG_FILE="$LOG_DIR/service.log"

if [ "$1" = "--now" ]; then
  MODE=manual
else
  MODE=boot
fi

mkdir -p "$LOG_DIR" 2>/dev/null

log() {
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$MODE" "$*" >> "$LOG_FILE" 2>/dev/null
}

# Keep the audit trail bounded; the WebUI only reads the last 200 lines.
if [ -f "$LOG_FILE" ]; then
  _lines=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')
  if [ "${_lines:-0}" -gt 400 ] 2>/dev/null; then
    tail -n 300 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE" 2>/dev/null
  fi
fi

RESETPROP_BIN="$(command -v resetprop 2>/dev/null)"
if [ -z "$RESETPROP_BIN" ]; then
  if [ -x /data/adb/ksu/bin/resetprop ]; then
    RESETPROP_BIN=/data/adb/ksu/bin/resetprop
  elif [ -x /data/adb/magisk/resetprop ]; then
    RESETPROP_BIN=/data/adb/magisk/resetprop
  elif [ -x /data/adb/ap/bin/resetprop ]; then
    RESETPROP_BIN=/data/adb/ap/bin/resetprop
  fi
fi
if [ -z "$RESETPROP_BIN" ]; then
  log "fatal: resetprop not found"
  exit 1
fi

SETTINGS_BIN=/system/bin/settings
[ -x "$SETTINGS_BIN" ] || SETTINGS_BIN=settings
GETPROP_BIN=/system/bin/getprop
[ -x "$GETPROP_BIN" ] || GETPROP_BIN=getprop

log "start resetprop=$RESETPROP_BIN"

if [ "$MODE" = "boot" ]; then
  for _i in $(seq 1 30); do
    [ "$("$RESETPROP_BIN" sys.boot_completed 2>/dev/null)" = "1" ] && break
    sleep 2
  done
fi

"$SETTINGS_BIN" put global development_settings_enabled 0 2>/dev/null
"$RESETPROP_BIN" -n persist.sys.development_settings_enabled 0
"$RESETPROP_BIN" -n ro.debuggable 0
"$RESETPROP_BIN" -n ro.force.debuggable 0
"$SETTINGS_BIN" put global adb_enabled 0 2>/dev/null
"$RESETPROP_BIN" -n ro.adb.secure 1
setprop persist.sys.usb.config mtp
setprop sys.usb.config mtp
setprop ctl.stop adbd 2>/dev/null
stop adbd 2>/dev/null
"$RESETPROP_BIN" -n service.adb.root 0
"$RESETPROP_BIN" -n init.svc.adbd stopped
"$RESETPROP_BIN" -n init.svc_debug_pid.adbd ""
"$RESETPROP_BIN" "sys.usb.adb.disabled" " "
"$RESETPROP_BIN" -n sys.oem_unlock_allowed 0
"$RESETPROP_BIN" -n ro.oem_unlock_supported 0

_ADB=$("$SETTINGS_BIN" get global adb_enabled 2>/dev/null)
_DEV=$("$SETTINGS_BIN" get global development_settings_enabled 2>/dev/null)
_OEM=$("$GETPROP_BIN" sys.oem_unlock_allowed 2>/dev/null)
_ADBD=$("$GETPROP_BIN" init.svc.adbd 2>/dev/null)

log "done adb=$_ADB dev=$_DEV oem=$_OEM adbd=$_ADBD"
date +%s > "$LOG_DIR/last_run" 2>/dev/null

exit 0
