#!/system/bin/sh
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
[ -n "$RESETPROP_BIN" ] || exit 1
SETTINGS_BIN=/system/bin/settings
[ -x "$SETTINGS_BIN" ] || SETTINGS_BIN=settings
for _i in $(seq 1 30); do
  [ "$("$RESETPROP_BIN" sys.boot_completed 2>/dev/null)" = "1" ] && break
  sleep 2
done
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
